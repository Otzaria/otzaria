import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// חלונית החיפוש בטאב שיורד לרקע: התוצאות נשמרות, ועותק שורות הספר משוחרר.
///
/// הרקע מדומה דרך [TickerMode], כמו ב-`ReadingScreen`. הצגת תוצאות מאצילה את
/// ההדגשה למנוע הנייטיבי, ולכן טסטים שמציגים תוצאות מדולגים בלי build זמין.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    // בלי ספרייה מדומה, אתחול החלונית ניגש למסד הנתונים האמיתי.
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });

  /// בונה את חלונית החיפוש בתוך [TickerMode] שניתן לכבות.
  ///
  /// [simpleSearchRunner] ברירת המחדל אינו מחזיר תוצאות, כדי שהטסט לא יהיה
  /// תלוי במנוע הנייטיבי שמדגיש אותן.
  Future<_Harness> pumpSearchView(
    WidgetTester tester, {
    required Future<List<String>> Function() contentLoader,
    Future<List<TextSearchResult>> Function(List<String>, String)?
    simpleSearchRunner,
  }) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await settingsBloc.close();
      focusNode.dispose();
    });

    late StateSetter setHostState;
    var isVisible = true;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Scaffold(
                body: TickerMode(
                  enabled: isVisible,
                  child: TextBookSearchView(
                    contentLoader: contentLoader,
                    scrollControler: ItemScrollController(),
                    focusNode: focusNode,
                    closeLeftPaneCallback: () {},
                    initialQuery: '',
                    simpleSearchRunner:
                        simpleSearchRunner ?? _noResultsSearchRunner,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    return _Harness(
      tester: tester,
      setVisibility: (value) => setHostState(() => isVisible = value),
    );
  }

  group('קאש שורות הספר', () {
    testWidgets('חיפוש טוען את שורות הספר פעם אחת בלבד', (tester) async {
      var loadCount = 0;
      final harness = await pumpSearchView(
        tester,
        contentLoader: () async {
          loadCount++;
          return const ['אב אברהם', 'יצחק'];
        },
      );

      await harness.search('אב');
      expect(loadCount, 1);

      await harness.search('יצחק');
      expect(loadCount, 1, reason: 'תוכן הספר כבר בקאש — אין לטעון שוב');
    });

    testWidgets('מעבר לרקע משחרר את עותק שורות הספר', (tester) async {
      var loadCount = 0;
      final harness = await pumpSearchView(
        tester,
        contentLoader: () async {
          loadCount++;
          return const ['אב אברהם', 'יצחק'];
        },
      );

      await harness.search('אב');
      expect(loadCount, 1);

      await harness.setVisible(false);
      await harness.setVisible(true);
      await harness.search('יצחק');

      expect(
        loadCount,
        2,
        reason: 'הקאש שוחרר ברקע, ולכן החיפוש הבא טוען את הספר מחדש',
      );
    });

    testWidgets('שהייה ברקע בלי חיפוש חדש אינה טוענת את הספר', (tester) async {
      var loadCount = 0;
      final harness = await pumpSearchView(
        tester,
        contentLoader: () async {
          loadCount++;
          return const ['אב אברהם'];
        },
      );

      await harness.search('אב');
      await harness.setVisible(false);
      await harness.setVisible(true);

      expect(loadCount, 1, reason: 'שחרור קאש אינו טעינה מחדש');
    });

    testWidgets('מעבר לרקע בזמן טעינת התוכן לא מחזיר את הקאש', (tester) async {
      var loadCount = 0;
      final loaders = <Completer<List<String>>>[];
      final harness = await pumpSearchView(
        tester,
        contentLoader: () {
          loadCount++;
          final completer = Completer<List<String>>();
          loaders.add(completer);
          return completer.future;
        },
      );

      await harness.type('אב');
      expect(loaders, hasLength(1));

      // הטאב יורד לרקע בעוד הטעינה באוויר, ורק אחר-כך היא מסתיימת.
      await harness.setVisible(false);
      loaders.first.complete(const ['אב אברהם', 'יצחק']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await harness.setVisible(true);
      await harness.search('יצחק');

      expect(
        loadCount,
        2,
        reason: 'תוצאת טעינה שהגיעה אחרי השחרור אינה אמורה לחזור לקאש',
      );
    });

    testWidgets('כשל טעינה מאפשר ניסיון חוזר בחיפוש הבא', (tester) async {
      var loadCount = 0;
      final harness = await pumpSearchView(
        tester,
        contentLoader: () async {
          loadCount++;
          if (loadCount == 1) throw StateError('טעינה נכשלה');
          return const ['אב אברהם'];
        },
      );

      await harness.search('אב');
      await harness.search('אברהם');

      expect(loadCount, 2);
    });
  });

  group('שימור תוצאות במעבר טאב', () {
    testWidgets('חזרה מהרקע אינה מריצה את החיפוש מחדש', (tester) async {
      var searchCount = 0;
      final harness = await pumpSearchView(
        tester,
        contentLoader: () async => const ['אב אברהם'],
        simpleSearchRunner: (content, query) async {
          searchCount++;
          return const [];
        },
      );

      await harness.search('אב');
      expect(searchCount, 1);

      await harness.setVisible(false);
      await harness.setVisible(true);

      expect(
        searchCount,
        1,
        reason: 'חזרה לטאב אינה חיפוש חדש — התוצאות אמורות להיות בזיכרון',
      );
    });

    testWidgets(
      'התוצאות שעל המסך נשמרות במעבר לרקע וחזרה',
      (tester) async {
        var searchCount = 0;
        final harness = await pumpSearchView(
          tester,
          contentLoader: () async => const ['אב אברהם'],
          simpleSearchRunner: (content, query) async {
            searchCount++;
            return _resultsFor(query);
          },
        );

        await harness.search('אב');
        expect(find.text('כתובת-אב'), findsOneWidget);
        expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);

        await harness.setVisible(false);
        await harness.setVisible(true);

        expect(find.text('כתובת-אב'), findsOneWidget);
        expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
        expect(searchCount, 1);
      },
      skip: !engineReady,
    );

    testWidgets(
      'חיפוש חדש אחרי חזרה מהרקע מציג את התוצאות החדשות',
      (tester) async {
        final harness = await pumpSearchView(
          tester,
          contentLoader: () async => const ['אב אברהם', 'יצחק'],
          simpleSearchRunner: (content, query) async => _resultsFor(query),
        );

        await harness.search('אב');
        expect(find.text('כתובת-אב'), findsOneWidget);

        await harness.setVisible(false);
        await harness.setVisible(true);
        await harness.search('יצחק');

        expect(find.text('כתובת-יצחק'), findsOneWidget);
        expect(find.text('כתובת-אב'), findsNothing);
      },
      skip: !engineReady,
    );
  });
}

class _Harness {
  _Harness({required this.tester, required this.setVisibility});

  final WidgetTester tester;
  final void Function(bool) setVisibility;

  /// מקליד שאילתה וממתין לחלוף ה-debounce של שדה החיפוש (200ms), אבל לא
  /// לסיום החיפוש עצמו.
  Future<void> type(String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> search(String query) async {
    await type(query);
    await tester.pump();
    await tester.pump();
  }

  Future<void> setVisible(bool value) async {
    setVisibility(value);
    await tester.pump();
  }
}

Future<List<TextSearchResult>> _noResultsSearchRunner(
  List<String> content,
  String query,
) async => const [];

List<TextSearchResult> _resultsFor(String query) {
  return [
    TextSearchResult(
      snippet: 'תוצאה עבור $query',
      index: 0,
      query: query,
      address: 'כתובת-$query',
    ),
  ];
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: true,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
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
