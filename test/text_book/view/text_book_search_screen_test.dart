import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/models/text_search_range.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('תו בודד אינו מריץ חיפוש בהתאמה חלקית', (tester) async {
    await InBookSearchPreferences.saveWholeWord(false);
    addTearDown(() => InBookSearchPreferences.saveWholeWord(false));

    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    final queries = <String>[];
    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
      TextSearchRange? range,
    ) async {
      queries.add(query);
      return const [];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => ['את השמים ואת הארץ'],
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: '',
              simpleSearchRunner: simpleSearchRunner,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ש');
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));

    expect(queries, isEmpty);
    // אין "אין תוצאות" על שאילתה שלא רצה בכלל.
    expect(find.text('אין תוצאות'), findsNothing);
    // הספר אינו מודגש על תו בודד.
    expect(
      textBookBloc.events.whereType<UpdateSearchText>().last.text,
      isEmpty,
    );

    await tester.enterText(find.byType(TextField).first, 'שמ');
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));

    expect(queries, ['שמ']);
  });

  testWidgets('מתג "מילים שלמות" מריץ את החיפוש מחדש ומעדכן את ההדגשה', (
    tester,
  ) async {
    await InBookSearchPreferences.saveWholeWord(false);
    addTearDown(() => InBookSearchPreferences.saveWholeWord(false));

    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    var searchRuns = 0;
    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
      TextSearchRange? range,
    ) async {
      searchRuns++;
      return const [];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => ['את השמים ואת הארץ'],
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: 'שמים',
              simpleSearchRunner: simpleSearchRunner,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ההעדפה כבויה — המתג מתחיל במצב "חצאי מילים".
    expect(
      find.byIcon(FluentIcons.text_whole_word_20_regular),
      findsOneWidget,
    );
    final runsBeforeToggle = searchRuns;

    await tester.tap(find.byIcon(FluentIcons.text_whole_word_20_regular));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.text_whole_word_20_filled), findsOneWidget);
    expect(searchRuns, greaterThan(runsBeforeToggle));
    expect(InBookSearchPreferences.loadWholeWord(), isTrue);

    final lastUpdate = textBookBloc.events.whereType<UpdateSearchText>().last;
    expect(lastUpdate.searchWholeWord, isTrue);
  });

  testWidgets('איפוס initialQuery חיצוני מנקה תוצאות חיפוש קיימות', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
      TextSearchRange? range,
    ) async {
      if (query.isEmpty) return const [];
      return [
        TextSearchResult(
          snippet: 'תוצאה עבור $query',
          index: 0,
          query: query,
          address: 'כתובת-$query',
        ),
      ];
    }

    String queryProp = '';
    late StateSetter outerSetState;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              outerSetState = setState;
              return Scaffold(
                body: TextBookSearchView(
                  contentLoader: () async => ['אב אברהם'],
                  scrollControler: ItemScrollController(),
                  focusNode: focusNode,
                  closeLeftPaneCallback: () {},
                  initialQuery: queryProp,
                  simpleSearchRunner: simpleSearchRunner,
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pump();

    // ההורה מחיל חיפוש דרך initialQuery
    outerSetState(() {
      queryProp = 'אב';
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('כתובת-אב'), findsOneWidget);

    // ההורה מאפס את initialQuery לריק — צריך לנקות תוצאות
    outerSetState(() {
      queryProp = '';
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('כתובת-אב'), findsNothing);
  }, skip: !engineReady);

  testWidgets('כשל טעינת תוכן בחיפוש פשוט מציג שגיאה ולא "אין תוצאות"', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => throw Exception('טעינה נכשלה'),
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: '',
              simpleSearchRunner: (content, query, range) async => const [],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.enterText(find.byType(TextField), 'אב');
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(TextBookMessages.searchContentLoadFailed), findsWidgets);
    expect(find.text('אין תוצאות'), findsNothing);
  });

  testWidgets(
    'didUpdateWidget מונע חיפוש כפול בהד הקלדה אך מריץ על שינוי חיצוני',
    (tester) async {
      final textBookBloc = _TestTextBookBloc(_loadedState());
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final focusNode = FocusNode();

      addTearDown(textBookBloc.close);
      addTearDown(settingsBloc.close);
      addTearDown(focusNode.dispose);
      addTearDown(resetSectionSearchWorkerForTesting);

      int runnerCalls = 0;
      final List<String> queriesSeen = [];
      Future<List<TextSearchResult>> simpleSearchRunner(
        List<String> content,
        String query,
        TextSearchRange? range,
      ) async {
        runnerCalls++;
        queriesSeen.add(query);
        if (query.isEmpty) return const [];
        return [
          TextSearchResult(
            snippet: 'תוצאה עבור $query',
            index: 0,
            query: query,
            address: 'כתובת-$query',
          ),
        ];
      }

      String queryProp = '';
      late StateSetter outerSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: StatefulBuilder(
              builder: (context, setState) {
                outerSetState = setState;
                return Scaffold(
                  body: TextBookSearchView(
                    contentLoader: () async => ['אב אברהם'],
                    scrollControler: ItemScrollController(),
                    focusNode: focusNode,
                    closeLeftPaneCallback: () {},
                    initialQuery: queryProp,
                    simpleSearchRunner: simpleSearchRunner,
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // הקלדה אמיתית → onSearchTextChanged מריץ חיפוש פעם אחת.
      // ההמתנה ארוכה מ-debounce שדה החיפוש (200ms).
      await tester.enterText(find.byType(TextField), 'אב');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      final callsAfterTyping = runnerCalls;
      expect(callsAfterTyping, greaterThan(0));

      // ההורה בונה מחדש עם initialQuery == controller.text — הד ה-roundtrip של
      // ההקלדה דרך ה-bloc. שינוי שכבר משוקף ב-controller אסור שיריץ חיפוש נוסף.
      outerSetState(() => queryProp = 'אב');
      await tester.pump();
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      expect(
        runnerCalls,
        callsAfterTyping,
        reason: 'הד הקלדה (controller מסונכרן) לא אמור להריץ חיפוש כפול',
      );

      // שינוי חיצוני אמיתי: ה-query שונה מתוכן ה-controller → חיפוש כן רץ.
      outerSetState(() => queryProp = 'אברהם');
      await tester.pump();
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      expect(
        runnerCalls,
        callsAfterTyping + 1,
        reason: 'שינוי query חיצוני אמור להריץ חיפוש פעם אחת בלבד',
      );
      expect(queriesSeen.last, 'אברהם');
    },
    skip: !engineReady,
  );

  testWidgets('חיפוש ישן לא דורס תוצאות של חיפוש חדש יותר', (tester) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
      TextSearchRange? range,
    ) async {
      if (query == 'אב') {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } else if (query == 'אברהם') {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      return [
        TextSearchResult(
          snippet: 'תוצאה עבור $query',
          index: 0,
          query: query,
          address: query == 'אב' ? 'ישן' : 'חדש',
        ),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => ['אב אברהם'],
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: '',
              simpleSearchRunner: simpleSearchRunner,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final textField = find.byType(TextField);

    await tester.enterText(textField, 'אב');
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));

    await tester.enterText(textField, 'אברהם');
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('חדש'), findsOneWidget);
    expect(find.text('ישן'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('חדש'), findsOneWidget);
    expect(find.text('ישן'), findsNothing);
  }, skip: !engineReady);

  Future<void> pumpSearchWithResults({
    required WidgetTester tester,
    required List<int> visibleIndices,
    required List<TextSearchResult> results,
  }) async {
    final textBookBloc = _TestTextBookBloc(
      _loadedState(visibleIndices: visibleIndices),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
      TextSearchRange? range,
    ) async {
      if (query.isEmpty) return const [];
      return results;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => ['שורה'],
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: '',
              simpleSearchRunner: simpleSearchRunner,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.enterText(find.byType(TextField), 'xa');
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'גלילה לתוצאה האחרונה כשהמיקום הנוכחי אחרי כל התוצאות',
    (tester) async {
      // visibleIndices = [1000] — אחרי כל התוצאות (0, 5, 10).
      // לפני התיקון: לא הייתה גלילה בכלל ו-_selectedSearchResultIndex
      // נשאר null. הציפייה: התוצאה האחרונה (index 2) נבחרת.
      await pumpSearchWithResults(
        tester: tester,
        visibleIndices: const [1000],
        results: [
          TextSearchResult(
            snippet: 'מוקדם',
            index: 0,
            query: 'xa',
            address: 'א',
          ),
          TextSearchResult(
            snippet: 'אמצע',
            index: 5,
            query: 'xa',
            address: 'ב',
          ),
          TextSearchResult(
            snippet: 'מאוחר',
            index: 10,
            query: 'xa',
            address: 'ג',
          ),
        ],
      );

      // אימות שכפתור "התוצאה הבאה" מנוטרל — כלומר _selectedSearchResultIndex
      // מצביע על התוצאה האחרונה.
      final nextInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('התוצאה הבאה'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        nextInkWell.onTap,
        isNull,
        reason: 'התוצאה הנבחרת אמורה להיות האחרונה',
      );

      final prevInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('התוצאה הקודמת'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        prevInkWell.onTap,
        isNotNull,
        reason: 'אמורות להיות לפחות 2 תוצאות לפני הנבחרת',
      );
    },
    skip: !engineReady,
  );

  testWidgets(
    'גלילה לתוצאה הראשונה מהמיקום הנוכחי והלאה',
    (tester) async {
      // visibleIndices = [6] — באמצע. התוצאה ב-index 10 היא הראשונה
      // מהשורה הנוכחית והלאה. כלומר _selectedSearchResultIndex == 2.
      await pumpSearchWithResults(
        tester: tester,
        visibleIndices: const [6],
        results: [
          TextSearchResult(snippet: 'a', index: 0, query: 'xa', address: 'א'),
          TextSearchResult(snippet: 'b', index: 5, query: 'xa', address: 'ב'),
          TextSearchResult(snippet: 'c', index: 10, query: 'xa', address: 'ג'),
        ],
      );

      final nextInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('התוצאה הבאה'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        nextInkWell.onTap,
        isNull,
        reason: 'התוצאה הנבחרת היא האחרונה (index 10 >= currentLine 6)',
      );
    },
    skip: !engineReady,
  );

  testWidgets(
    'שמירת בחירה לפי שורה בספר כשהשאילתה משתנה',
    (tester) async {
      // משתמש בוחר תוצאה ב-line=50. לאחר עידכון שאילתה, התוצאות החדשות
      // מכילות תוצאה אחרת ב-line=50. הציפייה: הבחירה תועבר לאינדקס
      // החדש של אותה שורה (לפי זהות), לא תיתקע על האינדקס הסידורי הישן.
      final textBookBloc = _TestTextBookBloc(
        _loadedState(visibleIndices: const [0]),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final focusNode = FocusNode();

      addTearDown(textBookBloc.close);
      addTearDown(settingsBloc.close);
      addTearDown(focusNode.dispose);
      addTearDown(resetSectionSearchWorkerForTesting);

      Future<List<TextSearchResult>> simpleSearchRunner(
        List<String> content,
        String query,
        TextSearchRange? range,
      ) async {
        if (query == 'xa') {
          // 3 תוצאות, line=50 באינדקס 1.
          return [
            TextSearchResult(
              snippet: 'a',
              index: 10,
              query: 'xa',
              address: 'א',
            ),
            TextSearchResult(
              snippet: 'b',
              index: 50,
              query: 'xa',
              address: 'ב',
            ),
            TextSearchResult(
              snippet: 'c',
              index: 100,
              query: 'xa',
              address: 'ג',
            ),
          ];
        }
        if (query == 'xy') {
          // 2 תוצאות, line=50 באינדקס 0 — אותה שורה במיקום סידורי אחר.
          return [
            TextSearchResult(
              snippet: 'b',
              index: 50,
              query: 'xy',
              address: 'ב',
            ),
            TextSearchResult(
              snippet: 'd',
              index: 200,
              query: 'xy',
              address: 'ד',
            ),
          ];
        }
        return const [];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: TextBookSearchView(
                contentLoader: () async => ['שורה'],
                scrollControler: ItemScrollController(),
                focusNode: focusNode,
                closeLeftPaneCallback: () {},
                initialQuery: '',
                simpleSearchRunner: simpleSearchRunner,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.enterText(find.byType(TextField), 'xa');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // ניווט לתוצאה האמצעית (index 1, line=50) דרך כפתור החץ למטה.
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      await tester.pump();
      // ה-ItemScrollController של הספר אינו מחובר לרשימה אמיתית בטסט;
      // ה-assertion שזורק scrollControler.scrollTo מנוטרל כאן בכוונה.
      tester.takeException();

      // עידכון השאילתה ל-'xy' — תוצאות חדשות שבהן line=50 נמצא ב-index 0.
      await tester.enterText(find.byType(TextField), 'xy');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // התוצאה הנבחרת היא הראשונה (line=50 שנשמרה). כפתור "הקודם" מנוטרל,
      // כפתור "הבא" מאופשר.
      final prevInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('התוצאה הקודמת'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        prevInkWell.onTap,
        isNull,
        reason: 'הבחירה אמורה לעבור לאינדקס 0 של תוצאות xy (line=50)',
      );
    },
    skip: !engineReady,
  );

  testWidgets(
    'ניווט בחצים גולל את רשימת התוצאות כשהתוצאה הנבחרת יוצאת מהאזור הגלוי',
    (tester) async {
      // הרבה תוצאות עם כתובות ייחודיות, כך שתוצאה רחוקה לא תהיה ברנדור
      // ההתחלתי של ה-ScrollablePositionedList. ללא התיקון לחיצה על "הבא"
      // הייתה משאירה את הרשימה במקומה והתוצאה הנבחרת הייתה נשארת מחוץ
      // לאזור הגלוי.
      final results = List.generate(
        40,
        (i) => TextSearchResult(
          snippet: 'snippet $i',
          index: i,
          query: 'xa',
          address: 'קטע_$i',
        ),
      );

      await pumpSearchWithResults(
        tester: tester,
        visibleIndices: const [0],
        results: results,
      );

      // מצב התחלתי: תוצאה מרוחקת לא ברנדור.
      expect(
        find.text('קטע_30'),
        findsNothing,
        reason: 'תוצאה מרוחקת לא אמורה להיות מורנדרת בתחילה',
      );

      // ניווט קדימה עד שהבחירה מגיעה לתוצאה 30.
      final nextButton = find.byTooltip('התוצאה הבאה');
      for (var i = 0; i < 30; i++) {
        await tester.tap(nextButton);
        await tester.pump();
        // ה-ItemScrollController של הספר אינו מחובר לרשימה אמיתית בטסט.
        tester.takeException();
      }
      await tester.pump();

      // אחרי הניווט — הרשימה גוללה ותוצאה 30 גלויה.
      expect(
        find.text('קטע_30'),
        findsOneWidget,
        reason: 'הרשימה צריכה לגלול כדי שהתוצאה הנבחרת תהיה גלויה',
      );
    },
  );

  testWidgets(
    'ניווט בחצים בין תוצאות סמוכות לא מזיז את הרשימה כשהיעד כבר גלוי',
    (tester) async {
      // מעט תוצאות שכולן נכנסות לאזור הגלוי. ניווט קדימה לא אמור לקפוץ —
      // הכותרת הראשונה צריכה להישאר ברנדור באותו מיקום וויזואלי.
      final results = List.generate(
        4,
        (i) => TextSearchResult(
          snippet: 'snippet $i',
          index: i,
          query: 'xa',
          address: 'כתובת_$i',
        ),
      );

      await pumpSearchWithResults(
        tester: tester,
        visibleIndices: const [0],
        results: results,
      );

      final firstHeader = find.text('כתובת_0');
      expect(firstHeader, findsOneWidget);
      final initialTopLeft = tester.getTopLeft(firstHeader);

      await tester.tap(find.byTooltip('התוצאה הבאה'));
      await tester.pump();
      tester.takeException();
      await tester.pump();

      expect(
        find.text('כתובת_0'),
        findsOneWidget,
        reason: 'הכותרת הראשונה אמורה להישאר גלויה כשכל התוצאות בתוך הוויופורט',
      );
      expect(
        tester.getTopLeft(find.text('כתובת_0')),
        initialTopLeft,
        reason: 'אסור לגלול את רשימת התוצאות אם היעד כבר גלוי',
      );
    },
    skip: !engineReady,
  );

  testWidgets(
    'חיצים מהמקלדת מדפדפים בין התוצאות בלי לעזוב את שדה החיפוש',
    (tester) async {
      // visibleIndices = [0] → התוצאה הראשונה נבחרת אוטומטית.
      await pumpSearchWithResults(
        tester: tester,
        visibleIndices: const [0],
        results: [
          TextSearchResult(snippet: 'a', index: 0, query: 'xa', address: 'א'),
          TextSearchResult(snippet: 'b', index: 5, query: 'xa', address: 'ב'),
          TextSearchResult(snippet: 'c', index: 10, query: 'xa', address: 'ג'),
        ],
      );

      InkWell buttonInkWell(String tooltip) => tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(InkWell),
        ),
      );

      // הפוקוס נשאר בשדה מההקלדה; שני חיצים למטה מגיעים לתוצאה האחרונה.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      tester.takeException();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      tester.takeException();

      expect(
        buttonInkWell('התוצאה הבאה').onTap,
        isNull,
        reason: 'אחרי שני חיצים למטה הבחירה על התוצאה האחרונה',
      );

      // חץ למעלה חוזר אחורה — הכפתור "הבאה" שב להיות פעיל.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      tester.takeException();
      expect(buttonInkWell('התוצאה הבאה').onTap, isNotNull);

      // הפוקוס לא יצא מהשדה — אפשר להמשיך להקליד.
      expect(
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>(),
        isNotNull,
      );
    },
    skip: !engineReady,
  );

  testWidgets(
    'שימור בחירה מבחין בין הופעות באותה שורה לפי matchOffset',
    (tester) async {
      final textBookBloc = _TestTextBookBloc(_loadedState());
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final focusNode = FocusNode();

      addTearDown(textBookBloc.close);
      addTearDown(settingsBloc.close);
      addTearDown(focusNode.dispose);
      addTearDown(resetSectionSearchWorkerForTesting);

      Future<List<TextSearchResult>> simpleSearchRunner(
        List<String> content,
        String query,
        TextSearchRange? range,
      ) async {
        if (query == 'xa') {
          // שתי הופעות באותה שורה (50) והופעה נוספת לפניהן.
          return [
            TextSearchResult(
              snippet: 'a',
              index: 10,
              query: 'xa',
              address: 'א',
            ),
            TextSearchResult(
              snippet: 'b1',
              index: 50,
              query: 'xa',
              address: 'ב',
              matchOffset: 0,
            ),
            TextSearchResult(
              snippet: 'b2',
              index: 50,
              query: 'xa',
              address: 'ב',
              matchOffset: 30,
            ),
          ];
        }
        if (query == 'xy') {
          // רק שתי ההופעות של שורה 50 — הנבחרת (offset 30) עכשיו אחרונה.
          return [
            TextSearchResult(
              snippet: 'b1',
              index: 50,
              query: 'xy',
              address: 'ב',
              matchOffset: 0,
            ),
            TextSearchResult(
              snippet: 'b2',
              index: 50,
              query: 'xy',
              address: 'ב',
              matchOffset: 30,
            ),
          ];
        }
        return const [];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: TextBookSearchView(
                contentLoader: () async => ['שורה'],
                scrollControler: ItemScrollController(),
                focusNode: focusNode,
                closeLeftPaneCallback: () {},
                initialQuery: '',
                simpleSearchRunner: simpleSearchRunner,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.enterText(find.byType(TextField), 'xa');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // ניווט להופעה השנייה בשורה 50 (אינדקס 2).
      final nextButton = find.byTooltip('התוצאה הבאה');
      await tester.tap(nextButton);
      await tester.pump();
      tester.takeException();
      await tester.tap(nextButton);
      await tester.pump();
      tester.takeException();

      await tester.enterText(find.byType(TextField), 'xy');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // הבחירה נשמרה על ההופעה עם offset 30 — האחרונה — ולכן "הבא" מנוטרל.
      // שימור לפי שורה בלבד היה בוחר את ההופעה הראשונה ומאפשר את "הבא".
      final nextInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('התוצאה הבאה'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        nextInkWell.onTap,
        isNull,
        reason: 'הבחירה אמורה להישמר על ההופעה עם matchOffset=30',
      );
    },
    skip: !engineReady,
  );

  testWidgets(
    'נפילה ל-closestIndex כשהשורה הנבחרת לא קיימת בתוצאות החדשות',
    (tester) async {
      // line=50 נבחר. שאילתה חדשה לא מכילה line=50 — נפילה ל-closestIndex.
      final textBookBloc = _TestTextBookBloc(
        _loadedState(visibleIndices: const [1000]),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final focusNode = FocusNode();

      addTearDown(textBookBloc.close);
      addTearDown(settingsBloc.close);
      addTearDown(focusNode.dispose);
      addTearDown(resetSectionSearchWorkerForTesting);

      Future<List<TextSearchResult>> simpleSearchRunner(
        List<String> content,
        String query,
        TextSearchRange? range,
      ) async {
        if (query == 'xa') {
          return [
            TextSearchResult(
              snippet: 'a',
              index: 10,
              query: 'xa',
              address: 'א',
            ),
            TextSearchResult(
              snippet: 'b',
              index: 50,
              query: 'xa',
              address: 'ב',
            ),
          ];
        }
        if (query == 'xy') {
          // אין line=50. visibleIndices=[1000] → fallback לאחרון.
          return [
            TextSearchResult(
              snippet: 'p',
              index: 20,
              query: 'xy',
              address: 'א',
            ),
            TextSearchResult(
              snippet: 'q',
              index: 80,
              query: 'xy',
              address: 'ב',
            ),
          ];
        }
        return const [];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: TextBookSearchView(
                contentLoader: () async => ['שורה'],
                scrollControler: ItemScrollController(),
                focusNode: focusNode,
                closeLeftPaneCallback: () {},
                initialQuery: '',
                simpleSearchRunner: simpleSearchRunner,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.enterText(find.byType(TextField), 'xa');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // ניווט ל-line=50 (אינדקס 1).
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      await tester.pump();
      tester.takeException();

      await tester.enterText(find.byType(TextField), 'xy');
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // line=50 לא קיים בתוצאות xy. visibleIndices=[1000] → fallback
      // לאחרון (אינדקס 1, line=80). "הבא" מנוטרל, "הקודם" מאופשר.
      final nextInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('התוצאה הבאה'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        nextInkWell.onTap,
        isNull,
        reason: 'הבחירה נפלה ל-closestIndex (אחרון) כי line=50 לא קיים',
      );
    },
    skip: !engineReady,
  );
  testWidgets('הגבלת החיפוש לטווח כותרות מועברת למסלול הפשוט ומוצגת כתווית', (
    tester,
  ) async {
    final book = TocEntry(text: 'ספר בדיקה', index: 0, level: 1);
    final chapterA = TocEntry(text: 'פרק א', index: 1, level: 2, parent: book);
    final chapterB = TocEntry(text: 'פרק ב', index: 3, level: 2, parent: book);
    final chapterC = TocEntry(text: 'פרק ג', index: 6, level: 2, parent: book);
    book.children = [chapterA, chapterB, chapterC];

    final textBookBloc = _TestTextBookBloc(
      _loadedState(tableOfContents: [book]),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    final ranges = <TextSearchRange?>[];
    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
      TextSearchRange? range,
    ) async {
      ranges.add(range);
      return const [];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => const [
                '<h1>ספר בדיקה</h1>',
                '<h2>פרק א</h2>',
                'שמים',
                '<h2>פרק ב</h2>',
                'שמים',
                'שמים',
                '<h2>פרק ג</h2>',
                'שמים',
              ],
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: 'שמים',
              simpleSearchRunner: simpleSearchRunner,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ranges, [isNull], reason: 'ללא טווח — החיפוש הראשון על כל הספר');

    await tester.tap(find.byTooltip('הגבל את החיפוש לטווח בספר'));
    await tester.pumpAndSettle();
    expect(find.text('תחילת הטווח'), findsOneWidget);
    await tester.tap(find.text('פרק ב'));
    await tester.pumpAndSettle();
    expect(find.text('סוף הטווח'), findsOneWidget);
    await tester.tap(find.text('"פרק ב" בלבד'));
    await tester.pumpAndSettle();

    expect(ranges.length, 2);
    expect(ranges.last!.startLine, 3);
    expect(ranges.last!.endLine, 6, reason: 'עד "פרק ג" (לא כולל)');
    expect(find.text('טווח: פרק ב'), findsOneWidget);

    // הסרת הצ'יפ מחזירה את החיפוש לכל הספר.
    await tester.tap(find.byTooltip('חפש בכל הספר'));
    await tester.pumpAndSettle();
    expect(ranges.length, 3);
    expect(ranges.last, isNull);
    expect(find.text('טווח: פרק ב'), findsNothing);
  });
}

TextBookLoaded _loadedState({
  List<int> visibleIndices = const [0],
  List<TocEntry> tableOfContents = const [],
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: tableOfContents,
    removeNikud: false,
    visibleIndices: visibleIndices,
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  final List<TextBookEvent> events = [];

  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => events.add(event));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
