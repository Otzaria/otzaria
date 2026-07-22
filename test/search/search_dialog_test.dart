import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

/// LibraryBloc מדומה עם ספרייה ריקה — מספיק ל-parseCategoryQuery בדיאלוג.
MockLibraryBloc _stubLibraryBloc() {
  final bloc = MockLibraryBloc();
  whenListen(
    bloc,
    const Stream<LibraryState>.empty(),
    initialState: const LibraryState(),
  );
  return bloc;
}

Widget _buildDialogHarness({
  required ThemeData theme,
  required HistoryBloc historyBloc,
  required IndexingBloc indexingBloc,
  required NavigationBloc navigationBloc,
  required SearchDialog dialog,
}) {
  return MaterialApp(
    theme: theme,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<HistoryBloc>.value(value: historyBloc),
        BlocProvider<IndexingBloc>.value(value: indexingBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
        BlocProvider<LibraryBloc>.value(value: _stubLibraryBloc()),
      ],
      child: Scaffold(body: dialog),
    ),
  );
}

Future<void> main() async {
  // הווידג'טים הנבדקים קוראים ל-sanitizeQuery/splitQueryWords שמאצילים למנוע
  // ה-Rust; הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('תפריט ההיסטוריה משתמש ברקע של הדיאלוג',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB85C38),
      ),
    );

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([
        Bookmark(
          ref: 'משה',
          book: TextBook(title: 'משה'),
          index: 0,
          isSearch: true,
        ),
      ]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));

    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));

    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(FluentIcons.history_24_regular));
    await tester.tap(find.byIcon(FluentIcons.history_24_regular));
    await tester.pumpAndSettle();

    final historyMenuAnchor = find.byWidgetPredicate(
      (widget) => widget is MenuAnchor && widget.controller != null,
    );
    final menuAnchor = tester.widget<MenuAnchor>(historyMenuAnchor);
    expect(
      menuAnchor.style!.backgroundColor!.resolve({}),
      theme.colorScheme.surfaceContainerHigh,
    );
    expect(find.byKey(const ValueKey('search-history-menu')), findsOneWidget);
    expect(find.text('משה'), findsWidgets);
  });

  testWidgets('בורר היקף החיפוש נשאר מוצג בכל סוגי החיפוש',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScopeMenuButton), findsOneWidget);

    for (final mode in ['מתקדם', 'מקורב', 'מדויק']) {
      await tester.ensureVisible(find.text(mode).first);
      await tester.tap(find.text(mode).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'המעבר אל $mode נכשל');
      expect(find.byType(SearchScopeMenuButton), findsOneWidget);
    }
  });

  testWidgets(
      'פתיחה מחדש בתוך ספר: אפשרות פר-מילה משוחזרת מוצגת מסומנת במצב מתקדם',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    // מדמה את ה-tempTab שבונה מסך החיפוש בתוך הספר בפתיחה חוזרת: מפת פר-מילה
    // עם האפשרות שנבחרה, ו-useGlobalSearchOptions=false (התיקון).
    final tab = SearchingTab('חיפוש', 'חכמה');
    tab.searchOptions.addAll({
      'חכמה_0': {'קידומות דקדוקיות': true},
    });
    tab.useGlobalSearchOptions.value = false;
    tab.searchBloc.add(SetSearchMode(SearchMode.advanced));

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        bookTitle: 'ספר',
        returnResultOnSubmit: true,
      ),
    ));
    await tester.pumpAndSettle();

    final chipFinder = find.byWidgetPredicate((widget) =>
        widget is FilterChip &&
        (widget.label as Text).data == 'קידומות דקדוקיות');
    expect(chipFinder, findsOneWidget);
    expect(tester.widget<FilterChip>(chipFinder).selected, isTrue,
        reason: 'אפשרות פר-מילה משוחזרת חייבת להופיע מסומנת בפתיחה מחדש');
  }, skip: !engineReady);

  testWidgets('onSearch לא מעביר פרמטרים מתקדמים במצב exact',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    // "קידומות דקדוקיות" נתמכת ברגיל ועוברת; "קידומות" הכללית בלעדית
    // למתקדם ומסוננת.
    tab.searchOptions.addAll({
      'חכמה_0': {'קידומות דקדוקיות': true, 'קידומות': true}
    });
    // אפשרויות פר-מילה נלקחות בחשבון רק כשמצב האפשרויות אינו גלובלי
    tab.useGlobalSearchOptions.value = false;
    tab.alternativeWords.addAll({
      0: ['דעת']
    });
    tab.spacingValues.addAll({'0-1': '5'});
    tab.searchBloc.add(SetSearchMode(SearchMode.exact));

    Map<String, Map<String, bool>>? capturedSearchOptions;
    Map<int, List<String>>? capturedAlternativeWords;
    Map<String, String>? capturedSpacingValues;
    SearchMode? capturedSearchMode;

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        onSearch: (
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          searchMode,
          distance,
        ) {
          capturedSearchOptions = searchOptions;
          capturedAlternativeWords = alternativeWords;
          capturedSpacingValues = spacingValues;
          capturedSearchMode = searchMode;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedSearchMode, SearchMode.exact);
    // רק אפשרויות המילה של המצב הרגיל (exactWordOptionKeys) עוברות;
    // "קידומות" הכללית, מילים חלופיות ומרווחים ידניים נשארים בלעדיים
    // למצב המתקדם.
    expect(capturedSearchOptions, {
      'חכמה_0': {'קידומות דקדוקיות': true},
    });
    expect(capturedAlternativeWords, isEmpty);
    expect(capturedSpacingValues, isEmpty);
  }, skip: !engineReady);

  testWidgets('onSearch לא מעביר פרמטרים מתקדמים במצב fuzzy',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchOptions.addAll({
      'חכמה_0': {'קידומות': true}
    });
    tab.alternativeWords.addAll({
      0: ['דעת']
    });
    tab.spacingValues.addAll({'0-1': '5'});
    tab.searchBloc.add(SetSearchMode(SearchMode.fuzzy));

    Map<String, Map<String, bool>>? capturedSearchOptions;
    Map<int, List<String>>? capturedAlternativeWords;
    Map<String, String>? capturedSpacingValues;
    SearchMode? capturedSearchMode;

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        onSearch: (
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          searchMode,
          distance,
        ) {
          capturedSearchOptions = searchOptions;
          capturedAlternativeWords = alternativeWords;
          capturedSpacingValues = spacingValues;
          capturedSearchMode = searchMode;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedSearchMode, SearchMode.fuzzy);
    expect(capturedSearchOptions, isEmpty);
    expect(capturedAlternativeWords, isEmpty);
    expect(capturedSpacingValues, isEmpty);
  }, skip: !engineReady);

  testWidgets('בדיאלוג צר בתוך ספר אין overflow כששדה המרחק מוצג',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchBloc.add(SetSearchMode(SearchMode.exact));

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(520, 740));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        bookTitle: 'ספר',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('מרווח בין מילים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter בשדה מרווח בין מילים לא מפעיל onSearch',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchBloc.add(SetSearchMode(SearchMode.advanced));

    var onSearchCalls = 0;

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: SearchDialog(
        existingTab: tab,
        bookTitle: 'ספר',
        onSearch: (
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          searchMode,
          distance,
        ) {
          onSearchCalls++;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SpinBox));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(onSearchCalls, 0);
    expect(find.byType(SearchDialog), findsOneWidget);
  }, skip: !engineReady);

  testWidgets('returnResultOnSubmit מחזיר תוצאת חיפוש אחרי סגירת הדיאלוג',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');

    SearchDialogResult? capturedResult;

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<IndexingBloc>.value(value: indexingBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<LibraryBloc>.value(value: _stubLibraryBloc()),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    capturedResult = await showDialog<SearchDialogResult>(
                      context: context,
                      builder: (_) => SearchDialog(
                        existingTab: tab,
                        bookTitle: 'ספר',
                        returnResultOnSubmit: true,
                      ),
                    );
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedResult, isNotNull);
    expect(capturedResult!.query, 'חכמה בינה');
    expect(find.byType(SearchDialog), findsNothing);
  }, skip: !engineReady);

  testWidgets('דיאלוג החיפוש מציג tooltip למצבי החיפוש והסבר למרחק',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('מרווח בין מילים'), findsOneWidget);

    await tester.longPress(find.text('מקורב').first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'חיפוש מקורב מרשה התאמות דומות ושיבושי כתיב קלים לפי מרחק החיפוש.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('סימון אפשרות בחיפוש רגיל נשמר לסשן ומוצג בפתיחה מחדש',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));

    final typoChipFinder = find.byWidgetPredicate((widget) =>
        widget is FilterChip && (widget.label as Text).data == 'שגיאות כתיב');
    FilterChip typoChip() => tester.widget<FilterChip>(typoChipFinder);

    // דיאלוג ראשון: מצב מדויק (ברירת המחדל), מסמנים "שגיאות כתיב" וסוגרים.
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));
    await tester.pumpAndSettle();

    expect(typoChip().selected, isFalse);
    await tester.ensureVisible(typoChipFinder);
    await tester.tap(typoChipFinder);
    await tester.pumpAndSettle();
    expect(typoChip().selected, isTrue);

    // סגירת הדיאלוג (unmount ⇒ dispose ⇒ זכירת סשן)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // הזכירה עצמה: הסשן חייב להכיל את האפשרות שסומנה.
    expect(
        SearchDefaults.initialExactOptionsForNewSearch()['שגיאות כתיב'], isTrue,
        reason: 'סגירת הדיאלוג צריכה לזכור את האפשרויות לסשן');

    // דיאלוג שני: הסימון מהסשן צריך להופיע מסומן.
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));
    await tester.pumpAndSettle();

    expect(typoChip().selected, isTrue,
        reason: 'אפשרות שסומנה בסשן הנוכחי צריכה להישאר מסומנת בדיאלוג חדש');
  });

  testWidgets('חיפוש רגיל מציג רק קידומות/סיומות דקדוקיות',
      (WidgetTester tester) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_buildDialogHarness(
      theme: theme,
      historyBloc: historyBloc,
      indexingBloc: indexingBloc,
      navigationBloc: navigationBloc,
      dialog: const SearchDialog(),
    ));
    await tester.pumpAndSettle();

    Finder chip(String label) => find.byWidgetPredicate((widget) =>
        widget is FilterChip && (widget.label as Text).data == label);

    expect(chip('קידומות דקדוקיות'), findsOneWidget);
    expect(chip('סיומות דקדוקיות'), findsOneWidget);
    expect(chip('קידומות'), findsNothing,
        reason: 'קידומות כלליות בלעדיות למצב המתקדם');
    expect(chip('סיומות'), findsNothing,
        reason: 'סיומות כלליות בלעדיות למצב המתקדם');
  });
}
