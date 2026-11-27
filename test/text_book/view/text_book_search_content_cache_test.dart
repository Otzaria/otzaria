import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

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
    bool useSearchWorker = false,
  }) async {
    final textBookBloc = StubTextBookBloc(_loadedState());
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
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
                    lines: LineScrollController(),
                    focusNode: focusNode,
                    closeLeftPaneCallback: () {},
                    initialQuery: '',
                    simpleSearchRunner: useSearchWorker
                        ? null
                        : simpleSearchRunner ?? _noResultsSearchRunner,
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

  testWidgets(
    'תוכן שנטען לרגקס אחרי שינוי הספר זמין גם לחיפוש ליטרלי',
    (tester) async {
      addTearDown(resetSectionSearchWorkerForTesting);
      var book = const ['אברהם'];
      var loads = 0;
      final harness = await pumpSearchView(
        tester,
        useSearchWorker: true,
        contentLoader: () async {
          loads++;
          return book;
        },
      );
      await harness.search('אברהם');
      await harness.settle();
      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      await harness.setVisible(false);
      book = const ['משה'];
      await harness.setVisible(true);
      await harness.search('/משה/');
      await harness.settle();
      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      expect(loads, 2);
      await harness.search('משה');
      await harness.settle();
      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      expect(loads, 2);
    },
    skip: !engineReady,
  );

  testWidgets(
    'חיפוש ליטרלי אחרי חזרה מהרקע רואה שינוי בתוכן הספר',
    (tester) async {
      addTearDown(resetSectionSearchWorkerForTesting);
      var book = const ['אברהם'];
      var loads = 0;
      final harness = await pumpSearchView(
        tester,
        useSearchWorker: true,
        contentLoader: () async {
          loads++;
          return book;
        },
      );
      await harness.search('אברהם');
      await harness.settle();
      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      await harness.setVisible(false);
      book = const ['משה'];
      await harness.setVisible(true);
      await harness.search('משה');
      await harness.settle();
      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      expect(loads, 2);
    },
    skip: !engineReady,
  );

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
        reason: 'הקאש שוחרר ברקע, ומסלול שצריך עותק ב-isolate הראשי טוען מחדש',
      );
    });

    testWidgets(
      'חיפוש ב-worker אחרי חזרה מהרקע טוען תוכן עדכני',
      (tester) async {
        addTearDown(resetSectionSearchWorkerForTesting);
        var loadCount = 0;
        final harness = await pumpSearchView(
          tester,
          useSearchWorker: true,
          contentLoader: () async {
            loadCount++;
            return const ['אב אברהם', 'יצחק'];
          },
        );

        await harness.search('אברהם');
        await harness.settle();
        expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
        expect(loadCount, 1);

        await harness.setVisible(false);
        await harness.setVisible(true);
        await harness.search('יצחק');
        await harness.settle();

        expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
        expect(
          loadCount,
          2,
          reason: 'טעינה חוזרת מבטיחה שה-worker מקבל את התוכן העדכני',
        );
      },
      skip: !engineReady,
    );

    testWidgets(
      'טעינה ישנה שמסתיימת אחרי החדשה אינה מבטלת את החיפוש הפעיל',
      (tester) async {
        addTearDown(resetSectionSearchWorkerForTesting);
        // ספר גדול מגודל ה-chunk, כדי שהסריקה תיעצר להודעה שמגיעה אחריה.
        final book = List.generate(50000, (i) => i == 40000 ? 'אברהם' : 'שורה');
        final loaders = <Completer<List<String>>>[];
        final harness = await pumpSearchView(
          tester,
          useSearchWorker: true,
          contentLoader: () {
            final completer = Completer<List<String>>();
            loaders.add(completer);
            return completer.future;
          },
        );

        await harness.search('שורה');
        expect(loaders, hasLength(1));
        await harness.setVisible(false);
        await harness.setVisible(true);
        await harness.search('אברהם');
        expect(loaders, hasLength(2));

        loaders.last.complete(book);
        loaders.first.complete(const ['תוכן ישן']);
        await tester.pump();
        await harness.settle();

        expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
      },
      skip: !engineReady,
    );

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
    await tester.pump(kSearchFieldDebounce + const Duration(milliseconds: 50));
  }

  Future<void> search(String query) async {
    await type(query);
    await tester.pump();
    await tester.pump();
  }

  /// מאפשר ל-isolate של החיפוש לענות; ה-pump לבדו אינו מריץ אירועים אמיתיים.
  Future<void> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (tester
            .widget<SearchPaneBase>(find.byType(SearchPaneBase))
            .progressWidget !=
        null) {
      if (DateTime.now().isAfter(deadline)) {
        fail('החיפוש לא הסתיים בתוך חמש שניות');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
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
    searchText: '',
  );
}
