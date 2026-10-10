import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_selection_preferences.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder;

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

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

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

final _moreOptionsButton = find.byKey(
  const ValueKey('search-dialog-more-options'),
);

Future<void> _openMoreOptions(WidgetTester tester) async {
  await tester.ensureVisible(_moreOptionsButton);
  await tester.tap(_moreOptionsButton);
  await tester.pumpAndSettle();
}

Future<void> main() async {
  // הווידג'טים הנבדקים קוראים ל-sanitizeQuery/splitQueryWords שמאצילים למנוע
  // ה-Rust; הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  setUpAll(() => registerFallbackValue(_FakeTabsEvent()));

  // מחסן טרי לכל טסט: טסט ששומר העדפת תצוגת תוצאות אחרת מזליג אותה לכל
  // טאב חיפוש שייבנה אחריו בקובץ.
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // בחירת שורת תוסף נשמרת בין דיאלוגים — בלי איפוס, טסט אחד מזליג לשני.
  setUp(() async {
    await PluginSearchSelectionPreferences.save(const {});
  });

  testWidgets(
    'תרומה סטטית של תוסף מופיעה רק במצבים המותרים ומשביתה אפשרויות שהוגדרו',
    (WidgetTester tester) async {
      final historyBloc = MockHistoryBloc();
      final indexingBloc = MockIndexingBloc();
      final navigationBloc = MockNavigationBloc();
      final registry = PluginSearchDialogRegistry.forTesting();
      registry.registerPayload('test.plugin', {
        'id': 'include-external',
        'type': 'checkbox',
        'title': 'חפש גם במקור חיצוני',
        'defaultValue': true,
        'visibleInModes': ['exact', 'advanced'],
        'disabledSearchOptions': {
          'advanced': ['word.partial'],
        },
      });
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
        registry.dispose();
        await historyBloc.close();
        await indexingBloc.close();
        await navigationBloc.close();
      });

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(
        _buildDialogHarness(
          theme: theme,
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: registry,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final contribution = find.byKey(
        const ValueKey('plugin-search-dialog-test.plugin-include-external'),
      );
      await _openMoreOptions(tester);
      expect(contribution, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(contribution).value, isTrue);

      await tester.tap(find.text('מתקדם').first);
      await tester.pumpAndSettle();
      await _openMoreOptions(tester);
      expect(contribution, findsOneWidget);

      final partialChip = find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip && (widget.label as Text).data == 'חלק ממילה',
      );
      expect(tester.widget<FilterChip>(partialChip).onSelected, isNull);

      await tester.ensureVisible(contribution);
      await tester.tap(contribution);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(partialChip).onSelected, isNotNull);

      final fuzzyMode = find.text('מקורב').first;
      await tester.ensureVisible(fuzzyMode);
      await tester.tap(fuzzyMode);
      await tester.pumpAndSettle();
      expect(contribution, findsNothing);
      expect(_moreOptionsButton, findsNothing);

      await tester.pumpWidget(
        _buildDialogHarness(
          theme: theme,
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: registry,
            onSearch: (_, _, _, _, _, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(contribution, findsNothing);
    },
  );

  testWidgets('שורת תוסף מקופלת תחת "אפשרויות נוספות" כשהיא בברירת המחדל', (
    WidgetTester tester,
  ) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final registry = PluginSearchDialogRegistry.forTesting();
    registry.registerPayload('test.plugin', {
      'id': 'include-external',
      'type': 'checkbox',
      'title': 'חפש גם במקור חיצוני',
      'visibleInModes': ['exact'],
    });

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
      registry.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: ThemeData(useMaterial3: true),
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: SearchDialog(
          initialSearchMode: SearchMode.exact,
          pluginSearchDialogRegistry: registry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contribution = find.byKey(
      const ValueKey('plugin-search-dialog-test.plugin-include-external'),
    );
    expect(contribution, findsNothing);

    await _openMoreOptions(tester);
    expect(contribution, findsOneWidget);
  });

  testWidgets('בחירת שורת תוסף נזכרת בדיאלוג הבא', (
    WidgetTester tester,
  ) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final registry = PluginSearchDialogRegistry.forTesting();
    registry.registerPayload('test.plugin', {
      'id': 'include-external',
      'type': 'checkbox',
      'title': 'חפש גם במקור חיצוני',
      'defaultValue': true,
      'visibleInModes': ['exact'],
    });

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
      registry.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    Future<void> pumpDialog(Key key) async {
      await tester.pumpWidget(
        _buildDialogHarness(
          theme: ThemeData(useMaterial3: true),
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(
            key: key,
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: registry,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await pumpDialog(const ValueKey('first'));

    final contribution = find.byKey(
      const ValueKey('plugin-search-dialog-test.plugin-include-external'),
    );
    await _openMoreOptions(tester);
    expect(tester.widget<CheckboxListTile>(contribution).value, isTrue);

    await tester.ensureVisible(contribution);
    await tester.tap(contribution);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(contribution).value, isFalse);

    // בחירה ששונה מברירת המחדל פותחת את "אפשרויות נוספות" מעצמה.
    await pumpDialog(const ValueKey('second'));
    expect(tester.widget<CheckboxListTile>(contribution).value, isFalse);
  });

  testWidgets(
    'אישור שורת תוסף מנתב אליו payload מלא במקום לפתוח טאב חיפוש',
    (
      WidgetTester tester,
    ) async {
      final historyBloc = MockHistoryBloc();
      final indexingBloc = MockIndexingBloc();
      final navigationBloc = MockNavigationBloc();
      final registry = PluginSearchDialogRegistry.forTesting();
      final tab = SearchingTab(
        'חיפוש',
        'חכמה בינה',
        initialConfiguration: const SearchConfiguration(
          searchMode: SearchMode.exact,
          distance: 4,
        ),
      );
      tab.globalSearchOptions['קידומות דקדוקיות'] = true;
      final launches = <(String, Map<String, dynamic>)>[];

      registry.registerPayload('test.plugin', {
        'id': 'include-external',
        'type': 'checkbox',
        'title': 'חפש גם במקור חיצוני',
        'defaultValue': true,
        'openPluginOnSubmit': true,
        'visibleInModes': ['exact'],
      });
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
        registry.dispose();
        tab.dispose();
        await historyBloc.close();
        await indexingBloc.close();
        await navigationBloc.close();
      });

      await tester.pumpWidget(
        _buildDialogHarness(
          theme: ThemeData(useMaterial3: true),
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(
            existingTab: tab,
            pluginSearchDialogRegistry: registry,
            pluginSearchSubmitLauncher: (pluginId, payload) {
              launches.add((pluginId, payload));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('חפש'));
      await tester.pump();

      expect(launches, hasLength(1));
      expect(launches.single.$1, 'test.plugin');
      expect(launches.single.$2['itemId'], 'include-external');
      final request = launches.single.$2['request'] as Map<String, dynamic>;
      expect(request['query'], 'חכמה בינה');
      expect(request['mode'], 'exact');
      expect(request['distance'], 4);
      expect(request['facets'], ['/']);
      expect(request['wordOptions'], {
        'חכמה_0': {'קידומות דקדוקיות': true},
        'בינה_1': {'קידומות דקדוקיות': true},
      });
    },
    skip: !engineReady,
  );

  testWidgets('תפריט ההיסטוריה משתמש ברקע של הדיאלוג', (
    WidgetTester tester,
  ) async {
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

    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(),
      ),
    );

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

  testWidgets('בורר היקף החיפוש נשאר מוצג בכל סוגי החיפוש', (
    WidgetTester tester,
  ) async {
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(),
      ),
    );
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
      await tester.pumpWidget(
        _buildDialogHarness(
          theme: theme,
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(
            existingTab: tab,
            bookTitle: 'ספר',
            returnResultOnSubmit: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip &&
            (widget.label as Text).data == 'קידומות דקדוקיות',
      );
      expect(chipFinder, findsOneWidget);
      expect(
        tester.widget<FilterChip>(chipFinder).selected,
        isTrue,
        reason: 'אפשרות פר-מילה משוחזרת חייבת להופיע מסומנת בפתיחה מחדש',
      );
    },
    skip: !engineReady,
  );

  testWidgets('onSearch לא מעביר פרמטרים מתקדמים במצב exact', (
    WidgetTester tester,
  ) async {
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
      'חכמה_0': {'קידומות דקדוקיות': true, 'קידומות': true},
    });
    // אפשרויות פר-מילה נלקחות בחשבון רק כשמצב האפשרויות אינו גלובלי
    tab.useGlobalSearchOptions.value = false;
    tab.alternativeWords.addAll({
      0: ['דעת'],
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: SearchDialog(
          existingTab: tab,
          onSearch:
              (
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
      ),
    );
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

  testWidgets('onSearch לא מעביר פרמטרים מתקדמים במצב fuzzy', (
    WidgetTester tester,
  ) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
    );
    final tab = SearchingTab('חיפוש', 'חכמה בינה');
    tab.searchOptions.addAll({
      'חכמה_0': {'קידומות': true},
    });
    tab.alternativeWords.addAll({
      0: ['דעת'],
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: SearchDialog(
          existingTab: tab,
          onSearch:
              (
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('חפש'));
    await tester.pumpAndSettle();

    expect(capturedSearchMode, SearchMode.fuzzy);
    expect(capturedSearchOptions, isEmpty);
    expect(capturedAlternativeWords, isEmpty);
    expect(capturedSpacingValues, isEmpty);
  }, skip: !engineReady);

  testWidgets('בדיאלוג צר בתוך ספר אין overflow כששדה המרחק מוצג', (
    WidgetTester tester,
  ) async {
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: SearchDialog(
          existingTab: tab,
          bookTitle: 'ספר',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('מרווח בין מילים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter בשדה מרווח בין מילים לא מפעיל onSearch', (
    WidgetTester tester,
  ) async {
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: SearchDialog(
          existingTab: tab,
          bookTitle: 'ספר',
          onSearch:
              (
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SpinBox));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(onSearchCalls, 0);
    expect(find.byType(SearchDialog), findsOneWidget);
  }, skip: !engineReady);

  testWidgets(
    'returnResultOnSubmit מחזיר תוצאת חיפוש אחרי סגירת הדיאלוג',
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
    },
    skip: !engineReady,
  );

  testWidgets('דיאלוג החיפוש מציג tooltip למצבי החיפוש והסבר למרחק', (
    WidgetTester tester,
  ) async {
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(),
      ),
    );
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

  testWidgets('סימון אפשרות בחיפוש רגיל נשמר לסשן ומוצג בפתיחה מחדש', (
    WidgetTester tester,
  ) async {
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

    final typoChipFinder = find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip && (widget.label as Text).data == 'שגיאות כתיב',
    );
    FilterChip typoChip() => tester.widget<FilterChip>(typoChipFinder);

    // דיאלוג ראשון: מצב מדויק (ברירת המחדל), מסמנים "שגיאות כתיב" וסוגרים.
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(),
      ),
    );
    await tester.pumpAndSettle();

    await _openMoreOptions(tester);
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
      SearchDefaults.initialExactOptionsForNewSearch()['שגיאות כתיב'],
      isTrue,
      reason: 'סגירת הדיאלוג צריכה לזכור את האפשרויות לסשן',
    );

    // דיאלוג שני: הסימון מהסשן צריך להופיע מסומן.
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      typoChip().selected,
      isTrue,
      reason: 'אפשרות שסומנה בסשן הנוכחי צריכה להישאר מסומנת בדיאלוג חדש',
    );
  });

  testWidgets('במסך קטן כל החיפוש הרגיל נכנס בלי גלילה', (
    WidgetTester tester,
  ) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();

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

    // טסט קודם זוכר לסשן אפשרות נסתרת פעילה, שהייתה פותחת את "אפשרויות נוספות".
    SearchDefaults.rememberSessionExactOptions(const {});
    tester.view.physicalSize = const Size(800, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.pumpWidget(
      _buildDialogHarness(
        theme: ThemeData(useMaterial3: true),
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(initialSearchMode: SearchMode.exact),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SearchDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(_moreOptionsButton.hitTestable(), findsOneWidget);
    expect(find.byTooltip('חפש').hitTestable(), findsOneWidget);
  });

  testWidgets('קביעת מצב ברירת המחדל נשמרת רק אחרי אישור', (
    WidgetTester tester,
  ) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();

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
      // השמירה מעדכנת גם את מצב הסשן — בלי איפוס הוא מזליג לטסטים הבאים.
      SearchDefaults.rememberSessionMode(SearchMode.exact);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: ThemeData(useMaterial3: true),
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(initialSearchMode: SearchMode.advanced),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openDefaultMode() async {
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-defaults-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-default-mode')),
      );
      await tester.pumpAndSettle();
    }

    // ביטול — שום דבר לא נשמר.
    await openDefaultMode();
    expect(
      find.text(
        'כל חיפוש חדש ייפתח מעכשיו במצב "מתקדם". ניתן לשנות זאת שוב בכל עת.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(SearchDefaults.loadModeDefault(), SearchMode.exact);

    // אישור — נשמר.
    await openDefaultMode();
    await tester.tap(find.text('קבע כברירת מחדל'));
    await tester.pumpAndSettle();
    expect(SearchDefaults.loadModeDefault(), SearchMode.advanced);
  });

  testWidgets('חיפוש רגיל מציג רק קידומות/סיומות דקדוקיות', (
    WidgetTester tester,
  ) async {
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
    await tester.pumpWidget(
      _buildDialogHarness(
        theme: theme,
        historyBloc: historyBloc,
        indexingBloc: indexingBloc,
        navigationBloc: navigationBloc,
        dialog: const SearchDialog(),
      ),
    );
    await tester.pumpAndSettle();

    Finder chip(String label) => find.byWidgetPredicate(
      (widget) => widget is FilterChip && (widget.label as Text).data == label,
    );

    expect(chip('קידומות דקדוקיות'), findsOneWidget);
    expect(chip('סיומות דקדוקיות'), findsOneWidget);
    expect(
      chip('קידומות'),
      findsNothing,
      reason: 'קידומות כלליות בלעדיות למצב המתקדם',
    );
    expect(
      chip('סיומות'),
      findsNothing,
      reason: 'סיומות כלליות בלעדיות למצב המתקדם',
    );
  });

  // המסלול הראשי של המשתמש: דיאלוג → "חפש" → טאב חדש. הטאב נבנה כאן עם
  // configuration מפורשת, ולכן העדפות תצוגת התוצאות חייבות להיות מוזרקות בו
  // במפורש — ברירת המחדל של הבנאי אינה חלה על מסלול זה.
  testWidgets(
    'טאב שנפתח מהדיאלוג נושא את המיון והאיחוד השמורים',
    (WidgetTester tester) async {
      final historyBloc = MockHistoryBloc();
      final indexingBloc = MockIndexingBloc();
      final navigationBloc = MockNavigationBloc();
      final tabsBloc = MockTabsBloc();
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
      whenListen(
        tabsBloc,
        const Stream<TabsState>.empty(),
        initialState: const TabsState(tabs: [], currentTabIndex: 0),
      );

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await historyBloc.close();
        await indexingBloc.close();
        await navigationBloc.close();
        await tabsBloc.close();
      });

      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.sameSection);
      SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryBloc>.value(value: _stubLibraryBloc()),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SearchDialog(),
                    ),
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
      await tester.enterText(find.byType(TextField).first, 'חכמה בינה');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('חפש'));
      await tester.pumpAndSettle();

      final captured = verify(() => tabsBloc.add(captureAny())).captured;
      final addedTabs = captured.whereType<AddTab>().toList();
      expect(addedTabs, hasLength(1));
      final tab = addedTabs.single.tab as SearchingTab;
      addTearDown(tab.dispose);

      expect(
        tab.searchBloc.state.resultGrouping,
        ResultGroupingMode.sameSection,
      );
      expect(tab.searchBloc.state.sortBy, ResultsOrder.relevance);
      // העטיפה מוסיפה להעדפות ואינה מחליפה את מה שנבחר בדיאלוג.
      expect(tab.searchBloc.state.currentFacets, isNotEmpty);
    },
    skip: !engineReady,
  );

  group('Enter על פקד בתוך שדה החיפוש של עריכת החיפוש (issue #1910)', () {
    late SearchingTab editedTab;
    late _PopCounter popCounter;

    /// דף "בית" ומעליו דיאלוג "עריכת חיפוש" במצב מתקדם, כמו במסך התוצאות.
    Future<void> openEditDialog(WidgetTester tester) async {
      final historyBloc = MockHistoryBloc();
      final indexingBloc = MockIndexingBloc();
      final navigationBloc = MockNavigationBloc();
      final tabsBloc = MockTabsBloc();
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
      whenListen(
        tabsBloc,
        const Stream<TabsState>.empty(),
        initialState: const TabsState(tabs: [], currentTabIndex: 0),
      );
      editedTab = SearchingTab('חיפוש', 'חכמה');
      editedTab.searchBloc.add(SetSearchMode(SearchMode.advanced));
      popCounter = _PopCounter();
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        editedTab.dispose();
        await historyBloc.close();
        await indexingBloc.close();
        await navigationBloc.close();
        await tabsBloc.close();
      });

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryBloc>.value(value: _stubLibraryBloc()),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: MaterialApp(
            navigatorObservers: [popCounter],
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => SearchDialog(editTab: editedTab),
                    ),
                    child: const Text('דף הבית'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('דף הבית'));
      await tester.pumpAndSettle();
    }

    final queryField = find.descendant(
      of: find.byType(EnhancedSearchField),
      matching: find.byType(TextField),
    );

    testWidgets(
      'Tab להצעת המקלדת ו-Enter מחילים אותה — הדיאלוג והדף שמתחתיו נשארים',
      (WidgetTester tester) async {
        await openEditDialog(tester);
        // "דוד" הוקלד במקלדת אנגלית.
        await tester.enterText(queryField, 'SUS');
        await tester.pumpAndSettle();
        expect(find.textContaining('האם התכוונת'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'layout-fix-suggestion',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(popCounter.pops, 0, reason: 'Enter על ההצעה אינו מגיש חיפוש');
        expect(find.text('דף הבית'), findsOneWidget);
        expect(find.byType(SearchDialog), findsOneWidget);
        expect(tester.widget<TextField>(queryField).controller!.text, 'דוד');
        expect(tester.takeException(), isNull);
      },
      skip: !engineReady,
    );

    testWidgets(
      'Enter על כפתור בתוך השדה מגיש פעם אחת — הדף שמתחת לדיאלוג נשאר',
      (WidgetTester tester) async {
        await openEditDialog(tester);
        await tester.enterText(queryField, 'חכמה בינה');
        await tester.pumpAndSettle();

        final clearButton = find.descendant(
          of: find.byType(EnhancedSearchField),
          matching: find.byIcon(FluentIcons.dismiss_24_regular),
        );
        Focus.of(tester.element(clearButton)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(popCounter.pops, 1, reason: 'רק הדיאלוג נסגר');
        expect(find.byType(SearchDialog), findsNothing);
        expect(find.text('דף הבית'), findsOneWidget);
        expect(editedTab.queryController.text, 'חכמה בינה');
      },
      skip: !engineReady,
    );
  });
}
