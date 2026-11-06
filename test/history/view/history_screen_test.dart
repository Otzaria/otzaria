import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';
import '../../helpers/memory_settings_cache.dart';

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _RecordingTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {
  final sent = <TabsEvent>[];

  @override
  void add(TabsEvent event) => sent.add(event);
}

class _RecordingNavigationBloc
    extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  @override
  void add(NavigationEvent event) {}
}

class _HistoryFileSystem implements FileSystemData {
  @override
  Future<Library> getLibrary() async => Library(categories: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Bookmark _searchBookmark(
  String ref, {
  required String query,
  SearchConfiguration? configuration,
}) {
  return Bookmark(
    ref: ref,
    book: TextBook(title: query),
    index: 0,
    isSearch: true,
    searchConfiguration: configuration?.toMap(),
  );
}

Bookmark _bookmark(String ref, {String? workspaceName}) {
  return Bookmark(
    ref: ref,
    book: TextBook(title: ref),
    index: 0,
    workspaceName: workspaceName,
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // בניית כותרת עשירה עם אפשרויות מפצלת מילים דרך המנוע; מדולג כשאין build.
  final engineReady = await tryInitSearchEngine();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  group('שחזור תחום וסינון מההיסטוריה', () {
    late Directory temp;
    late TantivyDataProvider provider;
    setUpAll(() async {
      if (!engineReady) return;
      FileSystemData.instance = _HistoryFileSystem();
      temp = await Directory.systemTemp.createTemp('history-search-');
      final engine = await SearchEngine.newInstance(path: temp.path);
      // A tab closes with an unawaited cancellation request. Prepare its native
      // handle in the real async zone, before any widget FakeAsync can own it.
      await RustSearchEngineOperations.prepareCancellation(engine);
      // Assign the test provider without first reading the production singleton,
      // whose constructor starts loading real library/index sources.
      provider = TantivyDataProvider.forTesting(Future.value(engine));
      TantivyDataProvider.instance = provider;
      await provider.engine;
    });
    setUp(() {
      DataRepository.instance.library = Future.value(
        Library(categories: []),
      );
    });
    tearDownAll(() async {
      if (!engineReady) return;
      await provider.dispose();
      DataRepository.instance.invalidateLibraryCache();
      if (!Platform.isWindows) await temp.delete(recursive: true);
    });

    Future<void> pumpUntil(
      WidgetTester tester,
      bool Function() done,
    ) async {
      // Native replies need the real event loop; Bloc events and continuations
      // belong to FakeAsync and must also be pumped. Awaiting close solely in
      // runAsync leaves those queued continuations unable to finish.
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'The isolated search must finish');
    }

    for (final (scope, filter) in <(List<String>, List<String>?)>[
      (['/scope'], null),
      (['/scope'], []),
      (['/scope'], ['/scope/רשבא']),
      ([], null),
    ]) {
      final legacyEmptyScope = scope.isEmpty;
      final restoredScope = legacyEmptyScope ? const ['/'] : scope;
      final testName = legacyEmptyScope
          ? 'פתיחת חיפוש ישן עם תחום ריק משחזרת את כל הספרייה'
          : 'פתיחת חיפוש משחזרת את הסינון $filter בתוך התחום';
      testWidgets(testName, (tester) async {
        final history = MockHistoryBloc();
        final tabs = _RecordingTabsBloc();
        final navigation = _RecordingNavigationBloc();
        SearchingTab? tab;
        try {
          whenListen(
            history,
            const Stream<HistoryState>.empty(),
            initialState: HistoryLoaded([
              Bookmark(
                ref: 'ממון מזיק',
                book: TextBook(title: 'ממון מזיק'),
                index: 0,
                isSearch: true,
                searchScopeFacets: scope,
                searchFilterFacets: filter,
              ),
            ]),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MultiBlocProvider(
                  providers: [
                    BlocProvider<HistoryBloc>.value(value: history),
                    BlocProvider<TabsBloc>.value(value: tabs),
                    BlocProvider<NavigationBloc>.value(value: navigation),
                  ],
                  child: const HistoryView(),
                ),
              ),
            ),
          );
          if (legacyEmptyScope) {
            expect(
              find.text('ללא ספרים מסומנים'),
              findsNothing,
              reason: 'Legacy empty scope restores the whole library',
            );
            expect(find.textContaining('בקטגוריות:'), findsNothing);
          } else {
            expect(
              find.text(
                filter == null
                    ? 'בקטגוריות: scope'
                    : filter.isEmpty
                    ? 'ללא ספרים מסומנים'
                    : 'בקטגוריות: רשבא',
              ),
              findsOneWidget,
            );
          }
          await tester.tap(find.text('ממון מזיק'));
          tab = (tabs.sent.single as AddTab).tab as SearchingTab;
          final search = tab.searchBloc;
          expect(search.state.currentFacets, filter ?? restoredScope);
          expect(search.state.searchScopeFacets, restoredScope);
          await pumpUntil(
            tester,
            () =>
                search.state.searchQuery == 'ממון מזיק' &&
                !search.state.isLoading &&
                !search.state.isCounting,
          );
          expect(search.state.errorMessage, isNull);
          expect(search.state.currentFacets, filter ?? restoredScope);
          expect(search.state.searchScopeFacets, restoredScope);
        } finally {
          final createdTab = tab;
          try {
            if (createdTab != null) {
              var closed = false;
              final closing = createdTab.searchBloc.close().whenComplete(
                () => closed = true,
              );
              await pumpUntil(tester, () => closed);
              await closing;
            }
          } finally {
            createdTab?.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
            await history.close();
            await tabs.close();
            await navigation.close();
          }
        }
      }, skip: !engineReady);
    }
  });

  for (final slot in <String?>[null, 'selected-place']) {
    testWidgets('לחיצה על מקום בהיסטוריה מבקשת התאמת slot ($slot)', (
      tester,
    ) async {
      final history = MockHistoryBloc();
      final tabs = _RecordingTabsBloc();
      final navigation = _RecordingNavigationBloc();
      whenListen(
        history,
        const Stream<HistoryState>.empty(),
        initialState: HistoryLoaded([
          Bookmark(
            ref: 'ספר פרק א',
            book: TextBook(id: 7, title: 'ספר'),
            index: 50,
            historySlot: slot,
          ),
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<HistoryBloc>.value(value: history),
                BlocProvider<TabsBloc>.value(value: tabs),
                BlocProvider<NavigationBloc>.value(value: navigation),
              ],
              child: const HistoryView(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ספר'));
      await tester.pump();
      final event = tabs.sent.single as OpenOrFocusTab;
      addTearDown(event.tab.dispose);
      expect(event.matchHistorySlot, isTrue);
      expect(event.tab.historySlot, slot);
      await tester.pumpWidget(const SizedBox.shrink());
      await history.close();
      await tabs.close();
      await navigation.close();
    });
  }

  testWidgets('חיפוש בהיסטוריה מוצא ספר לפי כינוי', (tester) async {
    AcronymsCache.instance.setAcronymsForTesting({
      7: ['רמבם'],
    });
    addTearDown(AcronymsCache.instance.clear);
    final history = MockHistoryBloc();
    whenListen(
      history,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([
        Bookmark(
          ref: 'משנה תורה, הלכות שבת',
          book: TextBook(id: 7, title: 'משנה תורה'),
          index: 3,
        ),
        _bookmark('ברכות ב.'),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<HistoryBloc>.value(
            value: history,
            child: const HistoryView(),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'רמבם');
    await tester.pump();

    expect(find.text('משנה תורה'), findsOneWidget);
    expect(find.text('ברכות ב.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await history.close();
  });

  group('HistoryView - workspace filter chips', () {
    late MockHistoryBloc historyBloc;
    late StreamController<HistoryState> stateController;

    setUp(() {
      historyBloc = MockHistoryBloc();
      stateController = StreamController<HistoryState>.broadcast();
      whenListen(
        historyBloc,
        stateController.stream,
        initialState: HistoryLoaded([]),
      );
    });

    tearDown(() async {
      await stateController.close();
    });

    Widget buildWidget() {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<HistoryBloc>.value(
            value: historyBloc,
            child: const HistoryView(),
          ),
        ),
      );
    }

    testWidgets('לא מציג צ\'יפים כשכל הפריטים שייכים ל-workspace אחד', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('ברכות ב.', workspaceName: 'גמרא'),
        ]),
      );
      await tester.pump();

      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('לא מציג צ\'יפים כשאין workspaceName בפריטים', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:'),
          _bookmark('ברכות ב.'),
        ]),
      );
      await tester.pump();

      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('מציג צ\'יפים עם שמות ה-workspaces כשיש 2+', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      expect(find.byType(FilterChip), findsNWidgets(2));
      expect(find.widgetWithText(FilterChip, 'גמרא'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'הלכה'), findsOneWidget);
    });

    testWidgets('לחיצה על צ\'יפ מסננת את הרשימה לאותו workspace', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('ברכות ב.', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    testWidgets('לחיצה שנייה על צ\'יפ שנבחר מבטלת את הסינון', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      // בחר גמרא
      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();
      expect(find.text('הלכות שבת'), findsNothing);

      // בטל בחירה
      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();
      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsOneWidget);
    });

    testWidgets(
      'workspace שנבחר ונמחק מההיסטוריה - הסינון מתבטל אוטומטית (P1 regression)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildWidget());
        stateController.add(
          HistoryLoaded([
            _bookmark('שבת עד:', workspaceName: 'גמרא'),
            _bookmark('הלכות שבת', workspaceName: 'הלכה'),
          ]),
        );
        await tester.pump();

        // בחר workspace 'גמרא'
        await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
        await tester.pump();
        expect(find.text('שבת עד:'), findsOneWidget);
        expect(find.text('הלכות שבת'), findsNothing);

        // state חדש - workspace 'גמרא' נעלם
        stateController.add(
          HistoryLoaded([
            _bookmark('הלכות שבת', workspaceName: 'הלכה'),
          ]),
        );
        await tester.pump();

        // אין צ'יפים (workspace יחיד)
        expect(find.byType(FilterChip), findsNothing);
        // הפריט הנותר מוצג - סינון לא תקוע
        expect(find.text('הלכות שבת'), findsOneWidget);
      },
    );

    testWidgets('חיפוש טקסט מוצא פריטים לפי שם workspace', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      // חפש לפי שם workspace
      await tester.enterText(find.byType(TextField).first, 'גמרא');
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    testWidgets('צ\'יפ וחיפוש טקסט פועלים ביחד', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('ברכות ב.', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      // סנן לגמרא
      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();

      // חיפוש על גבי הסינון
      await tester.enterText(find.byType(TextField).first, 'שבת');
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsNothing);
      expect(find.text('הלכות שבת'), findsNothing);
    });
  });

  group('HistoryView - חיווי הגדרות חיפוש בפריט', () {
    late MockHistoryBloc historyBloc;
    late StreamController<HistoryState> stateController;

    setUp(() {
      historyBloc = MockHistoryBloc();
      stateController = StreamController<HistoryState>.broadcast();
      whenListen(
        historyBloc,
        stateController.stream,
        initialState: HistoryLoaded([]),
      );
    });

    tearDown(() async {
      await stateController.close();
    });

    Widget buildWidget() {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<HistoryBloc>.value(
            value: historyBloc,
            child: const HistoryView(),
          ),
        ),
      );
    }

    testWidgets('הכותרת מציגה את השאילתה וההגדרות יורדות לכותרת המשנה', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _searchBookmark(
            'כדאי + הוא + בית',
            query: 'כדאי הוא בית',
            configuration: const SearchConfiguration(distance: 5),
          ),
        ]),
      );
      await tester.pump();

      // הכותרת — השאילתה המפורמטת (ה-ref), בלי ההגדרות.
      expect(find.text('כדאי + הוא + בית'), findsOneWidget);
      // כותרת המשנה — ההגדרות עם תווית ברורה.
      expect(find.text('הגדרות: מרחק 5'), findsOneWidget);
    });

    testWidgets('חיפוש ברירת מחדל אינו מציג חיווי הגדרות', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _searchBookmark(
            'שבת',
            query: 'שבת',
            configuration: const SearchConfiguration(),
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('שבת'), findsOneWidget);
      expect(find.textContaining('הגדרות:'), findsNothing);
    });

    testWidgets(
      'אפשרויות מילה מוצגות בכותרת בגופן קטן ובגוון הנושא',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildWidget());
        stateController.add(
          HistoryLoaded([
            Bookmark(
              ref: '(קד)שלום + עולם',
              book: TextBook(title: 'שלום עולם'),
              index: 0,
              isSearch: true,
              searchOptions: {
                'שלום_0': {'קידומות דקדוקיות': true},
              },
            ),
          ]),
        );
        await tester.pump();

        // הכותרת מרונדרת כטקסט עשיר; הטקסט המלא זהה לשאילתה המפורמטת.
        final title = tester.widget<Text>(find.text('(קד)שלום + עולם'));
        expect(title.textSpan, isNotNull);

        // מקטע האפשרות "(קד)" מובחן — גופן קטן יותר, לא מודגש, בצבע הנושא.
        final optionSpans = <TextSpan>[];
        title.textSpan!.visitChildren((span) {
          if (span is TextSpan && span.text == '(קד)') optionSpans.add(span);
          return true;
        });
        expect(optionSpans, hasLength(1));
        expect(optionSpans.first.style?.fontSize, 13);
        expect(optionSpans.first.style?.fontWeight, FontWeight.normal);
        expect(optionSpans.first.style?.color, isNotNull);
      },
      skip: !engineReady,
    );
  });
}
