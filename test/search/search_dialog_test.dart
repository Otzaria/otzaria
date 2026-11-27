import 'dart:math' as math;

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/controls/toggle_pill.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/plugins/services/plugin_search_selection_preferences.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/active_lexical_searches.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder, SearchScope, WordMatchMode;

import '../support/golden_fonts.dart';
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
MockLibraryBloc _stubLibraryBloc({Library? library}) {
  final bloc = MockLibraryBloc();
  whenListen(
    bloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(library: library),
  );
  return bloc;
}

Widget _buildDialogHarness({
  required ThemeData theme,
  required HistoryBloc historyBloc,
  required IndexingBloc indexingBloc,
  required NavigationBloc navigationBloc,
  required SearchDialog dialog,
  Library? library,
}) {
  return MaterialApp(
    theme: theme,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<HistoryBloc>.value(value: historyBloc),
        BlocProvider<IndexingBloc>.value(value: indexingBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
        BlocProvider<LibraryBloc>.value(
          value: _stubLibraryBloc(library: library),
        ),
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

  // טיימר התקיעות של חיפוש שנשאר פתוח בסוף הטסט נחשב טיימר תלוי.
  setUp(() {
    ActiveLexicalSearches.instance = ActiveLexicalSearches(
      stallThreshold: null,
    );
  });

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
      expect(tester.widget<FilterChip>(contribution).selected, isTrue);

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

  testWidgets('בחירת שורת תוסף נזכרת בדיאלוג הבא', (WidgetTester tester) async {
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
    expect(tester.widget<FilterChip>(contribution).selected, isTrue);

    await tester.ensureVisible(contribution);
    await tester.tap(contribution);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(contribution).selected, isFalse);

    // בחירה ששונה מברירת המחדל פותחת את "אפשרויות נוספות" מעצמה.
    await pumpDialog(const ValueKey('second'));
    expect(tester.widget<FilterChip>(contribution).selected, isFalse);
  });

  group('שורות תוסף בדיאלוג', () {
    late MockHistoryBloc historyBloc;
    late MockIndexingBloc indexingBloc;
    late MockNavigationBloc navigationBloc;
    late PluginSearchDialogRegistry registry;

    setUp(() {
      historyBloc = MockHistoryBloc();
      indexingBloc = MockIndexingBloc();
      navigationBloc = MockNavigationBloc();
      registry = PluginSearchDialogRegistry.forTesting();
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
    });

    Future<void> pumpDialog(
      WidgetTester tester,
      Key key, {
      Library? library,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _buildDialogHarness(
          theme: ThemeData(useMaterial3: true),
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          library: library,
          dialog: SearchDialog(
            key: key,
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: registry,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder row(String id) =>
        find.byKey(ValueKey('plugin-search-dialog-test.plugin-$id'));

    testWidgets(
      'פריט switch מוצג כ-AppTogglePill, ושורה עם persist:false אינה נשמרת',
      (tester) async {
        registry.registerPayload('test.plugin', {
          'id': 'sw',
          'type': 'switch',
          'title': 'מתג',
          'visibleInModes': ['exact'],
        });
        registry.registerPayload('test.plugin', {
          'id': 'tmp',
          'type': 'checkbox',
          'title': 'זמני',
          'persist': false,
          'visibleInModes': ['exact'],
        });
        addTearDown(registry.dispose);

        await pumpDialog(tester, const ValueKey('first'));
        await _openMoreOptions(tester);
        expect(tester.widget<AppTogglePill>(row('sw')).value, isFalse);
        expect(row('tmp'), findsOneWidget);
        expect(tester.widget<FilterChip>(row('tmp')).selected, isFalse);

        // ב־AppTogglePill המתג הוא הפקד; בשבב — השבב כולו.
        for (final target in [
          find.descendant(of: row('sw'), matching: find.byType(Switch)),
          row('tmp'),
        ]) {
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }
        expect(tester.widget<AppTogglePill>(row('sw')).value, isTrue);
        expect(tester.widget<FilterChip>(row('tmp')).selected, isTrue);
        expect(PluginSearchSelectionPreferences.load(), {
          'test.plugin/sw': true,
        });

        await pumpDialog(tester, const ValueKey('second'));
        expect(tester.widget<AppTogglePill>(row('sw')).value, isTrue);
        expect(tester.widget<FilterChip>(row('tmp')).selected, isFalse);
      },
    );

    testWidgets('הקשר לכפתור תוסף בשדה: בקשת החיפוש הנוכחית ובחירות השורות', (
      tester,
    ) async {
      registry.registerPayload('test.plugin', {
        'id': 'include-external',
        'type': 'checkbox',
        'title': 'חפש גם במקור חיצוני',
        'defaultValue': true,
        'visibleInModes': ['exact'],
      });
      addTearDown(registry.dispose);

      await pumpDialog(tester, const ValueKey('first'));
      await tester.enterText(find.byType(EditableText).first, 'שלום עולם');
      await tester.pump();

      final actions = tester.widget<PluginSearchFieldActions>(
        find.byType(PluginSearchFieldActions),
      );
      final context = actions.invocationContext!();
      final request =
          context[PluginSearchFieldContext.requestKey] as Map<String, dynamic>;
      expect(request['query'], 'שלום עולם');
      expect(request['mode'], 'exact');
      expect(request['facets'], ['/']);
      expect(context[PluginSearchFieldContext.pluginSelectionsKey], {
        'test.plugin/include-external': true,
      });
    });

    testWidgets(
      'הכתבה אחרי לחיצת עכבר מחליפה את הטקסט המסומן (issue #3878)',
      (tester) async {
        final actions = PluginSearchFieldActionsRegistry.instance;
        addTearDown(() => actions.removeAll('voice'));
        actions.registerPayload('voice', {
          'id': 'dictate',
          'title': 'חיפוש בדיבור',
          'icon': 'mic_24_regular',
          'fields': ['fullText'],
        });
        await pumpDialog(tester, const ValueKey('first'));
        final field = find.byType(EditableText).first;
        await tester.enterText(field, 'שלום עולם');
        await tester.pump();
        final controller = tester.widget<EditableText>(field).controller;
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 9,
        );

        // לחיצת עכבר אמיתית ארוכה מ-kPressTimeout, ואז השדה כבר מגיב ל-tap down.
        final gesture = await tester.startGesture(
          tester.getCenter(find.byTooltip('חיפוש בדיבור')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(kPressTimeout * 2);
        await gesture.up();
        await tester.pump();

        final sessions = PluginSearchFieldSessionService.instance;
        final binding =
            tester.state(
                  find.byType(PluginSearchFieldActions),
                )
                as PluginSearchFieldBinding;
        final session = sessions.sessionFor(binding, 'voice', 'dictate')!;
        sessions.setFieldText('voice', session.id, 'אהבת חסד');
        expect(controller.text, 'אהבת חסד');
      },
      variant: TargetPlatformVariant.desktop(),
      skip: !engineReady,
    );

    testWidgets('הקשר לכפתור תוסף מפענח את צמצום @קטגוריה כמו השליחה', (
      tester,
    ) async {
      final category = Category(
        title: 'רשי',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: const [],
        books: const [],
        parent: null,
      );
      await pumpDialog(
        tester,
        const ValueKey('first'),
        library: Library(categories: [category]),
      );

      Map<String, dynamic> currentRequest() {
        final actions = tester.widget<PluginSearchFieldActions>(
          find.byType(PluginSearchFieldActions),
        );
        return actions.invocationContext!()[PluginSearchFieldContext.requestKey]
            as Map<String, dynamic>;
      }

      await tester.enterText(find.byType(EditableText).first, 'שלום@רשי');
      await tester.pump();
      var request = currentRequest();
      expect(request['query'], 'שלום');
      expect(request['facets'], [category.path]);

      await tester.enterText(find.byType(EditableText).first, 'שלום@אין');
      await tester.pump();
      request = currentRequest();
      expect(request['query'], 'שלום');
      expect(request['facets'], ['/']);
    });
  });

  testWidgets('אישור שורת תוסף מנתב אליו payload מלא במקום לפתוח טאב חיפוש', (
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
  }, skip: !engineReady);

  testWidgets('תפריט ההיסטוריה משתמש ברקע של הדיאלוג', (
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
      (widget) =>
          widget is MenuAnchor &&
          widget.controller != null &&
          widget.style?.backgroundColor != null,
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
      // מדמה את הטאב ש-createInBookSearchDialogTab בונה בפתיחה חוזרת: מפת פר-מילה
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
        dialog: SearchDialog(existingTab: tab, bookTitle: 'ספר'),
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

  for (final scenario in [
    (globalOptions: null, manual: false),
    (globalOptions: false, manual: false),
    (globalOptions: true, manual: false),
    (globalOptions: true, manual: true),
  ]) {
    final globalOptions = scenario.globalOptions;
    final manual = scenario.manual;
    testWidgets(
      globalOptions == null
          ? 'returnResultOnSubmit מחזיר תוצאת חיפוש אחרי סגירת הדיאלוג'
          : 'אישור דיאלוג משמר תבנית, מדיניות וחלופות: global=$globalOptions manual=$manual',
      (WidgetTester tester) async {
        final historyBloc = MockHistoryBloc();
        final indexingBloc = MockIndexingBloc();
        final navigationBloc = MockNavigationBloc();
        final theme = ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
        );
        final tab = globalOptions == null
            ? SearchingTab('חיפוש', 'חכמה בינה')
            : createInBookSearchDialogTab(
                query: manual ? 'חכמה בינה' : 'חכמה',
                searchMode: SearchMode.advanced,
                distance: 0,
                matchPolicy: const SearchMatchPolicy(anyOrder: true),
                searchOptions: const {
                  'חכמה_0': {'קידומות דקדוקיות': true},
                },
                alternativeWords: manual
                    ? const {
                        0: ['חכימה'],
                      }
                    : const {},
                spacingValues: manual ? const {'0-1': '5'} : const {},
                optionsForEveryWord: globalOptions
                    ? const {'קידומות דקדוקיות': true}
                    : null,
              );

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
        expect(
          capturedResult!.query,
          globalOptions == null || manual ? 'חכמה בינה' : 'חכמה',
        );
        if (globalOptions != null) {
          expect(capturedResult!.matchPolicy.anyOrder, isFalse);
          if (manual) {
            expect(capturedResult!.alternativeWords, {
              0: ['חכימה'],
            });
            expect(capturedResult!.spacingValues, {'0-1': '5'});
          }
          final settings = InBookSearchSettings.fromDialogResult(
            capturedResult!,
          );
          expect(settings.alternativeWords, capturedResult!.alternativeWords);
          expect(settings.spacingValues, capturedResult!.spacingValues);
          expect(settings.matchPolicy.anyOrder, isFalse);
          expect(settings.requestedMatchPolicy.anyOrder, !manual);
          expect(
            settings.optionsForEveryWord,
            globalOptions ? {'קידומות דקדוקיות': true} : null,
          );
          final twoWords = settings.forQuery('חכמה בינה');
          expect(twoWords.matchPolicy.anyOrder, !manual);
          expect(twoWords.searchOptions.containsKey('בינה_1'), globalOptions);
        }
        expect(find.byType(SearchDialog), findsNothing);
      },
      skip: !engineReady,
    );
  }

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
    expect(find.text('בחר שאילתה, סוג חיפוש והיקף'), findsOneWidget);
  });

  // סקירה שלישית של 4.11, q-ss7: 2×2 רק כשתווית נחתכת גם בלי אייקונים.
  testWidgets('בורר המצבים בשתי שורות רק כשתווית נחתכת, והבחירה עובדת בהן', (
    WidgetTester tester,
  ) async {
    final historyBloc = MockHistoryBloc();
    final indexingBloc = MockIndexingBloc();
    final navigationBloc = MockNavigationBloc();
    final tab = SearchingTab('חיפוש', '');
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
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tab.dispose();
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });
    final modeRows = find.descendant(
      of: find.byType(SearchDialog),
      matching: find.byWidgetPredicate((w) => w is SegmentedButton),
    );
    Future<void> pump(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        _buildDialogHarness(
          theme: ThemeData(useMaterial3: true),
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(existingTab: tab),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(const Size(1400, 900));
    expect(modeRows, findsOneWidget);

    // בגופן הבדיקות כל אות 14: ב-300 "מתקדם" (70) לא נכנס גם בלי אייקון.
    await pump(const Size(300, 640));
    expect(modeRows, findsNWidgets(2));
    // ב-300 בגופן הבדיקות שורה אחרת בדיאלוג גולשת, גם בלי השינוי הזה.
    tester.takeException();
    await tester.tap(find.text('מקורב'));
    await tester.pumpAndSettle();
    expect(tab.searchBloc.state.configuration.searchMode, SearchMode.fuzzy);
  });

  testWidgets('כותרת החיפוש בתוך ספר לא מבטיחה היקף', (
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
        dialog: const SearchDialog(bookTitle: 'ספר'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('בחר שאילתה וסוג חיפוש'), findsOneWidget);
    expect(find.text('בחר שאילתה, סוג חיפוש והיקף'), findsNothing);
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

  group(
    'קביעת מצב ברירת מחדל שומרת גם את האפשרויות הנוכחיות (issue #5185)',
    () {
      late SearchingTab tab;

      Future<void> pumpWithTab(WidgetTester tester, SearchMode mode) async {
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
        tab = SearchingTab.newSearch('חיפוש', '', mode: mode);
        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
          // השמירה מעדכנת גם את הסשן — בלי איפוס היא מזליגה לטסטים הבאים.
          SearchDefaults.rememberSessionMode(SearchMode.exact);
          SearchDefaults.rememberSessionExactOptions(const {});
          SearchDefaults.rememberSessionOptions(const {});
          SearchDefaults.rememberSessionDistance(0, SearchMode.exact);
          SearchDefaults.rememberSessionDistance(0, SearchMode.advanced);
          SearchDefaults.saveDistanceDefault(0, mode: SearchMode.exact);
          SearchDefaults.saveDistanceDefault(0, mode: SearchMode.advanced);
          SearchDefaults.rememberSessionAnyOrder(false);
          SearchDefaults.rememberSessionMatchPolicy(SearchMatchPolicy.standard);
          tab.dispose();
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
            dialog: SearchDialog(existingTab: tab),
          ),
        );
        await tester.pumpAndSettle();
        // מה שהמשתמש סימן בחלונית: קידומות וסיומות, מרווח 5, בכל סדר.
        tab.globalSearchOptions
          ..clear()
          ..addAll({'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true});
        tab.searchBloc
          ..add(UpdateDistanceWithoutSearch(5))
          ..add(UpdateWordOrderWithoutSearch(true));
        await tester.pumpAndSettle();
      }

      Future<void> openDefaultMode(WidgetTester tester) async {
        await tester.tap(
          find.byKey(const ValueKey('search-dialog-defaults-menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('search-dialog-default-mode')),
        );
        await tester.pumpAndSettle();
      }

      final includeOptions = find.text('כולל האפשרויות הנוכחיות');

      testWidgets('חיפוש רגיל: אישור שומר את המצב, האפשרויות, המרווח והסדר', (
        tester,
      ) async {
        await pumpWithTab(tester, SearchMode.exact);
        await openDefaultMode(tester);
        expect(includeOptions, findsOneWidget);
        await tester.tap(find.text('קבע כברירת מחדל'));
        await tester.pumpAndSettle();

        expect(SearchDefaults.loadModeDefault(), SearchMode.exact);
        expect(SearchDefaults.loadExactDefaults(), {
          'קידומות דקדוקיות': true,
          'סיומות דקדוקיות': true,
        });
        expect(SearchDefaults.loadDistanceDefault(SearchMode.exact), 5);
        expect(SearchDefaults.loadAnyOrderDefault(), isTrue);
      });

      testWidgets('חיפוש מתקדם: נשמר גם טווח הקרבה', (tester) async {
        await pumpWithTab(tester, SearchMode.advanced);
        tab.searchBloc.add(
          UpdateProximityScopeWithoutSearch(SearchScope.sameParagraph),
        );
        await tester.pumpAndSettle();
        await openDefaultMode(tester);
        await tester.tap(find.text('קבע כברירת מחדל'));
        await tester.pumpAndSettle();

        expect(SearchDefaults.loadModeDefault(), SearchMode.advanced);
        expect(SearchDefaults.loadDefaults(), {
          'קידומות דקדוקיות': true,
          'סיומות דקדוקיות': true,
        });
        expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 5);
        expect(
          SearchDefaults.loadMatchPolicyDefault().proximityScope,
          SearchScope.sameParagraph,
        );
      });

      testWidgets('מתקדם פר-מילה: ברירת המחדל של האפשרויות אינה נדרסת', (
        tester,
      ) async {
        SearchDefaults.saveDefaults(const {'קידומות דקדוקיות': true});
        await pumpWithTab(tester, SearchMode.advanced);
        // "זהה לכל המילים" כבוי (כמו אחרי שחזור מההיסטוריה): המפה הגלובלית
        // אינה מה שמוצג בחלונית.
        tab.useGlobalSearchOptions.value = false;
        tab.globalSearchOptions.clear();
        await openDefaultMode(tester);
        await tester.tap(find.text('קבע כברירת מחדל'));
        await tester.pumpAndSettle();

        expect(SearchDefaults.loadDefaults(), {'קידומות דקדוקיות': true});
        expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 5);
      });

      testWidgets(
        'מתקדם פר-מילה: האישור אינו מבטיח את האפשרויות שאינן נשמרות',
        (
          tester,
        ) async {
          SearchDefaults.saveDefaults(const {'קידומות דקדוקיות': true});
          await pumpWithTab(tester, SearchMode.advanced);
          tab.useGlobalSearchOptions.value = false;
          tab.globalSearchOptions.clear();
          tab.searchBloc.add(
            UpdateProximityScopeWithoutSearch(SearchScope.sameParagraph),
          );
          await tester.pumpAndSettle();
          await openDefaultMode(tester);

          expect(includeOptions, findsNothing);
          expect(find.text('כולל המרווח וסדר המילים הנוכחיים'), findsOneWidget);
          await tester.tap(find.text('קבע כברירת מחדל'));
          await tester.pumpAndSettle();

          // חיפוש חדש: האפשרויות הן ברירת המחדל הקודמת, המרווח והסדר מהחלונית.
          final next = SearchingTab.newSearch('חיפוש', '');
          addTearDown(next.dispose);
          expect(
            next.searchBloc.state.configuration.searchMode,
            SearchMode.advanced,
          );
          expect(next.globalSearchOptions, {'קידומות דקדוקיות': true});
          expect(next.searchBloc.state.distance, 5);
          expect(next.searchBloc.state.anyOrder, isTrue);
          expect(
            next.searchBloc.state.configuration.matchPolicy.proximityScope,
            SearchScope.wordDistance,
          );
        },
      );

      testWidgets('בלי הסימון נשמר המצב בלבד', (tester) async {
        await pumpWithTab(tester, SearchMode.advanced);
        await openDefaultMode(tester);
        await tester.tap(includeOptions);
        await tester.pumpAndSettle();
        await tester.tap(find.text('קבע כברירת מחדל'));
        await tester.pumpAndSettle();

        expect(SearchDefaults.loadModeDefault(), SearchMode.advanced);
        expect(SearchDefaults.loadDefaults(), isEmpty);
        expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 0);
        expect(SearchDefaults.loadAnyOrderDefault(), isFalse);
      });

      testWidgets('ביטול אינו שומר דבר', (tester) async {
        await pumpWithTab(tester, SearchMode.advanced);
        await openDefaultMode(tester);
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();

        expect(SearchDefaults.loadModeDefault(), SearchMode.exact);
        expect(SearchDefaults.loadDefaults(), isEmpty);
        expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 0);
      });

      testWidgets('במקורב אין אפשרויות מילה — אין סימון', (tester) async {
        await pumpWithTab(tester, SearchMode.fuzzy);
        await openDefaultMode(tester);
        expect(includeOptions, findsNothing);
        await tester.tap(find.text('קבע כברירת מחדל'));
        await tester.pumpAndSettle();
        expect(SearchDefaults.loadModeDefault(), SearchMode.fuzzy);
        expect(SearchDefaults.loadDistanceDefault(SearchMode.exact), 0);
      });
    },
  );

  testWidgets('תפריט ברירות המחדל של המתקדם שומר ומחזיר את המרווח (#2360)', (
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
      SearchDefaults.saveDistanceDefault(0, mode: SearchMode.advanced);
      SearchDefaults.rememberSessionMode(SearchMode.exact);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
    });

    SearchDefaults.saveDistanceDefault(2, mode: SearchMode.advanced);
    SearchDefaults.rememberSessionDistance(4, SearchMode.advanced);
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

    Future<void> openAdvancedDefaults() async {
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-defaults-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('קביעת ברירת מחדל לחיפוש מתקדם'));
      await tester.pumpAndSettle();
    }

    // חזרה לברירת מחדל מחזירה גם את המרווח השמור.
    await tester.tap(find.byKey(const ValueKey('search-dialog-defaults-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('חזרה לברירת מחדל'));
    await tester.pumpAndSettle();
    await openAdvancedDefaults();
    final saveDistance = find.text('קבע את המרווח הנוכחי (2) כברירת מחדל');
    expect(saveDistance, findsOneWidget);

    Settings.setValue<int>('key-search-default-distance-advanced', 5);
    await tester.tap(saveDistance);
    await tester.pumpAndSettle();
    expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 2);
  });

  testWidgets(
    'מרווח ברירת מחדל נפרד לחיפוש הרגיל ולמתקדם, גם במעבר מצב (issue #5758)',
    (WidgetTester tester) async {
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
      Settings.setValue<int>('key-search-default-distance', 0);
      SearchDefaults.rememberSessionMode(SearchMode.exact);
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        // סגירת הדיאלוג שומרת לסשן — מאפסים אחריה כדי לא להזליג לטסטים הבאים.
        await tester.pumpWidget(const SizedBox());
        SearchDefaults.saveDistanceDefault(0, mode: SearchMode.exact);
        SearchDefaults.saveDistanceDefault(0, mode: SearchMode.advanced);
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
      final bloc = BlocProvider.of<SearchBloc>(
        tester.element(find.text('מדויק')),
        listen: false,
      );

      Future<void> saveDistance(String submenu, int distance) async {
        await tester.tap(
          find.byKey(const ValueKey('search-dialog-defaults-menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(submenu));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('קבע את המרווח הנוכחי ($distance) כברירת מחדל'),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }

      // מתקדם: מרווח 3 נשמר כברירת מחדל.
      bloc.add(UpdateDistanceWithoutSearch(3));
      await tester.pumpAndSettle();
      await saveDistance('קביעת ברירת מחדל לחיפוש מתקדם', 3);

      // מעבר לרגיל טוען את המרווח שלו, ולא גורר את המרווח של המתקדם.
      await tester.tap(find.text('מדויק'));
      await tester.pumpAndSettle();
      expect(bloc.state.distance, 0);
      await saveDistance('קביעת ברירת מחדל לחיפוש רגיל', 0);

      // וחזרה למתקדם מחזירה את המרווח שלו.
      await tester.tap(find.text('מתקדם'));
      await tester.pumpAndSettle();
      expect(bloc.state.distance, 3);

      // חיפוש חדש בכל מצב נפתח עם ברירת המחדל שלו.
      final advanced = SearchingTab.newSearch(
        'חיפוש',
        '',
        mode: SearchMode.advanced,
      );
      final exact = SearchingTab.newSearch(
        'חיפוש',
        'בראשית',
        mode: SearchMode.exact,
      );
      addTearDown(advanced.dispose);
      addTearDown(exact.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      expect(advanced.searchBloc.state.distance, 3);
      expect(exact.searchBloc.state.distance, 0);

      // חיפוש מהספרייה או מאיתור נפתח עם טאב זמני שנושא את השאילתה.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _buildDialogHarness(
          theme: ThemeData(useMaterial3: true),
          historyBloc: historyBloc,
          indexingBloc: indexingBloc,
          navigationBloc: navigationBloc,
          dialog: SearchDialog(existingTab: exact),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('מתקדם'));
      await tester.pumpAndSettle();
      expect(exact.searchBloc.state.distance, 3);

      exact.searchBloc.add(UpdateDistanceWithoutSearch(4));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(
        SearchDefaults.initialDistanceForNewSearch(SearchMode.advanced),
        4,
      );
      expect(SearchDefaults.loadDistanceDefault(SearchMode.advanced), 3);
    },
  );

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
  testWidgets('טאב שנפתח מהדיאלוג נושא את המיון והאיחוד השמורים', (
    WidgetTester tester,
  ) async {
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

    expect(tab.searchBloc.state.resultGrouping, ResultGroupingMode.sameSection);
    expect(tab.searchBloc.state.sortBy, ResultsOrder.relevance);
    // העטיפה מוסיפה להעדפות ואינה מחליפה את מה שנבחר בדיאלוג.
    expect(tab.searchBloc.state.currentFacets, isNotEmpty);
  }, skip: !engineReady);

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

    testWidgets('Enter בשדה מחיל את השאילתה על כותרת הטאב הנערך', (
      WidgetTester tester,
    ) async {
      await openEditDialog(tester);
      await tester.enterText(queryField, 'צדיק גאולה');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(SearchDialog), findsNothing);
      expect(editedTab.title, 'חיפוש: צדיק גאולה');
      expect(editedTab.titleNotifier.value, 'חיפוש: צדיק גאולה');
    }, skip: !engineReady);
    Future<void> pickWordDistanceMode(
      WidgetTester tester,
      WordMatchMode mode,
    ) async {
      await tester.tap(find.byIcon(OtzariaIcons.apps_list_24_regular));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<(SearchScope, WordMatchMode)>),
          matching: find.text(SearchScope.wordDistance.label),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode.label).last);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'עריכה מחילה על הטאב מצב התאמה חלקית שנבחר בדיאלוג (issue #2006)',
      (WidgetTester tester) async {
        await openEditDialog(tester);
        await pickWordDistanceMode(tester, WordMatchMode.mostWords);
        expect(editedTab.searchBloc.state.wordMatchMode, WordMatchMode.all);

        await tester.tap(find.byTooltip('חפש'));
        await tester.pumpAndSettle();
        expect(
          editedTab.searchBloc.state.wordMatchMode,
          WordMatchMode.mostWords,
        );
      },
      skip: !engineReady,
    );

    testWidgets('עריכה מחילה על הטאב את סדר המילים (issue #2006)', (
      WidgetTester tester,
    ) async {
      await openEditDialog(tester);
      await tester.tap(
        find.byKey(const ValueKey('search-word-order-checkbox')),
      );
      await tester.pumpAndSettle();
      expect(editedTab.searchBloc.state.anyOrder, isFalse);

      await tester.tap(find.byTooltip('חפש'));
      await tester.pumpAndSettle();
      expect(editedTab.searchBloc.state.anyOrder, isTrue);
    }, skip: !engineReady);
  });

  group('טווח הקרבה וסדר המילים בדיאלוג (issue #2006)', () {
    late MockTabsBloc tabsBloc;

    Future<void> openDialog(
      WidgetTester tester, {
      SearchMode mode = SearchMode.advanced,
    }) async {
      final historyBloc = MockHistoryBloc();
      final indexingBloc = MockIndexingBloc();
      final navigationBloc = MockNavigationBloc();
      tabsBloc = MockTabsBloc();
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
        SearchDefaults.saveMatchPolicyDefault(SearchMatchPolicy.standard);
        SearchDefaults.saveAnyOrderDefault(false);
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
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => SearchDialog(initialSearchMode: mode),
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
    }

    Future<void> openDefaultsMenu(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-defaults-menu')),
      );
      await tester.pumpAndSettle();
    }

    SearchBloc dialogBloc(WidgetTester tester) => BlocProvider.of<SearchBloc>(
      tester.element(find.byType(WordOrderCheckbox)),
    );

    bool dialogKeepsOrder(WidgetTester tester) => tester
        .widget<Checkbox>(
          find.descendant(
            of: find.byKey(const ValueKey('search-word-order-checkbox')),
            matching: find.byType(Checkbox),
          ),
        )
        .value!;

    testWidgets('טאב חדש נושא את כל מדיניות ההתאמה שבדיאלוג', (
      WidgetTester tester,
    ) async {
      SearchDefaults.rememberSessionMatchPolicy(
        const SearchMatchPolicy(
          wordMatchMode: WordMatchMode.atLeast,
          wordMatchCount: 3,
        ),
      );
      SearchDefaults.rememberSessionAnyOrder(true);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField).first, 'חכמה בינה');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('חפש'));
      await tester.pumpAndSettle();

      final captured = verify(() => tabsBloc.add(captureAny())).captured;
      final tab = captured.whereType<AddTab>().single.tab as SearchingTab;
      addTearDown(tab.dispose);
      final config = tab.searchBloc.state.configuration;
      expect(config.wordMatchMode, WordMatchMode.atLeast);
      expect(config.wordMatchCount, 3);
      expect(config.anyOrder, isTrue);
    }, skip: !engineReady);

    testWidgets('בחיפוש רגיל הסדר הוא צ\'יפ תחת "אפשרויות נוספות"', (
      WidgetTester tester,
    ) async {
      SearchDefaults.rememberSessionAnyOrder(false);
      await openDialog(tester, mode: SearchMode.exact);
      final chip = find.byKey(const ValueKey('search-word-order-chip'));
      expect(chip, findsNothing);
      expect(
        find.byKey(const ValueKey('search-word-order-checkbox')),
        findsNothing,
      );

      await _openMoreOptions(tester);
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isFalse);

      await tester.enterText(find.byType(TextField).first, 'חכמה בינה');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('חפש'));
      await tester.pumpAndSettle();
      final captured = verify(() => tabsBloc.add(captureAny())).captured;
      final tab = captured.whereType<AddTab>().single.tab as SearchingTab;
      addTearDown(tab.dispose);
      expect(tab.searchBloc.state.configuration.searchMode, SearchMode.exact);
      expect(tab.searchBloc.state.anyOrder, isTrue);
    }, skip: !engineReady);

    testWidgets('צ\'יפ "בכל סדר" פעיל פותח את "אפשרויות נוספות" מעצמו', (
      WidgetTester tester,
    ) async {
      SearchDefaults.rememberSessionAnyOrder(true);
      await openDialog(tester, mode: SearchMode.exact);
      final chip = find.byKey(const ValueKey('search-word-order-chip'));
      expect(chip, findsOneWidget);
      expect(tester.widget<FilterChip>(chip).selected, isFalse);
    }, skip: !engineReady);

    testWidgets(
      'ברירות המחדל נפתחות בתת־תפריט ו־Escape משאיר את הדיאלוג פתוח',
      (WidgetTester tester) async {
        await openDialog(tester);
        final proximity = find.byKey(
          const ValueKey('search-dialog-default-proximity'),
        );

        await openDefaultsMenu(tester);
        expect(find.byType(SubmenuButton), findsOneWidget);
        expect(proximity, findsNothing, reason: 'הקבוצה סגורה בפתיחה');

        await tester.tap(find.text('קביעת ברירת מחדל לחיפוש מתקדם'));
        await tester.pumpAndSettle();
        expect(proximity, findsOneWidget);
        expect(find.byType(SubmenuButton), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(proximity, findsNothing);
        expect(find.byType(SubmenuButton), findsNothing);
        expect(find.byType(SearchDialog), findsOneWidget);
        await openDefaultsMenu(tester);
        expect(proximity, findsNothing);
      },
      skip: !engineReady,
    );

    testWidgets('תפריט ברירות המחדל שומר את הטווח ואת הסדר ומחזיר אותם', (
      WidgetTester tester,
    ) async {
      SearchDefaults.rememberSessionMatchPolicy(
        const SearchMatchPolicy(proximityScope: SearchScope.sameParagraph),
      );
      SearchDefaults.rememberSessionAnyOrder(false);
      await openDialog(tester);
      expect(dialogKeepsOrder(tester), isTrue);

      await openDefaultsMenu(tester);
      await tester.tap(find.text('קביעת ברירת מחדל לחיפוש מתקדם'));
      await tester.pumpAndSettle();
      // בחלון נמוך הפריט האחרון בתת־התפריט עשוי לדרוש גלילה.
      await tester.ensureVisible(
        find.byKey(const ValueKey('search-dialog-default-proximity')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-default-proximity')),
      );
      await tester.pumpAndSettle();
      expect(
        SearchDefaults.loadMatchPolicyDefault().proximityScope,
        SearchScope.sameParagraph,
      );

      // תיבת ברירת המחדל משקפת את השמור, ושינויה מוחל גם על הדיאלוג.
      // CheckboxMenuButton מעביר את המפתח גם ל-MenuItemButton הפנימי.
      final defaultOrder = find.byWidgetPredicate(
        (widget) =>
            widget is CheckboxMenuButton &&
            widget.key == const ValueKey('search-dialog-default-word-order'),
      );
      expect(tester.widget<CheckboxMenuButton>(defaultOrder).value, isTrue);
      await tester.tap(defaultOrder);
      await tester.pumpAndSettle();
      expect(SearchDefaults.loadAnyOrderDefault(), isTrue);
      expect(tester.widget<CheckboxMenuButton>(defaultOrder).value, isFalse);
      // הפוקוס נשאר בשדה: handler הדיאלוג סוגר קודם את התפריט הפתוח.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dialogBloc(tester).state.anyOrder, isTrue);
      // בטווח פסקה הסדר אינו חל, ולכן התיבה המושבתת מוצגת "שמור".
      expect(dialogKeepsOrder(tester), isTrue);

      // חזרה לברירת המחדל מחזירה את מה ששמור כעת.
      Settings.setValue<bool>('key-search-default-any-order', false);
      Settings.setValue<String>(
        'key-search-default-proximity-scope',
        'wordDistance',
      );
      await openDefaultsMenu(tester);
      await tester.tap(find.text('חזרה לברירת מחדל'));
      await tester.pumpAndSettle();
      expect(dialogBloc(tester).state.anyOrder, isFalse);
      expect(dialogBloc(tester).state.proximityScope, SearchScope.wordDistance);
      expect(dialogKeepsOrder(tester), isTrue);
      expect(
        find.textContaining(SearchScope.sameParagraph.label),
        findsNothing,
      );
    }, skip: !engineReady);
  });

  group('Escape סוגר קודם תפריט פתוח ורק אחר כך את הדיאלוג (#2528)', () {
    Future<void> openDialog(WidgetTester tester) async {
      final historyBloc = MockHistoryBloc();
      final indexingBloc = MockIndexingBloc();
      final navigationBloc = MockNavigationBloc();
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
        MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryBloc>.value(value: _stubLibraryBloc()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SearchDialog(
                        initialSearchMode: SearchMode.advanced,
                      ),
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
    }

    bool queryFieldHasFocus(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byType(EnhancedSearchField),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;

    Future<void> expectEscapeClosesMenuThenDialog(
      WidgetTester tester,
      Finder menuContent,
    ) async {
      expect(menuContent, findsOneWidget);
      expect(queryFieldHasFocus(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menuContent, findsNothing);
      expect(find.byType(SearchDialog), findsOneWidget);
      expect(queryFieldHasFocus(tester), isTrue, reason: 'ההקלדה נמשכת');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchDialog), findsNothing);
    }

    testWidgets('תפריט ההיסטוריה', (WidgetTester tester) async {
      await openDialog(tester);
      await tester.tap(find.byIcon(FluentIcons.history_24_regular));
      await tester.pumpAndSettle();
      await expectEscapeClosesMenuThenDialog(
        tester,
        find.byKey(const ValueKey('search-history-menu')),
      );
    });

    testWidgets('תפריט ברירות המחדל', (WidgetTester tester) async {
      await openDialog(tester);
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-defaults-menu')),
      );
      await tester.pumpAndSettle();
      await expectEscapeClosesMenuThenDialog(
        tester,
        find.byKey(const ValueKey('search-dialog-default-mode')),
      );
    });
  });

  // תפריט ברירות המחדל נפתח מתחתית הדיאלוג, ותת־התפריט שבו ארוך (כ-636 פיקסלים
  // בתפריטים הרגילים, כ-500 בצפופים). ב-RTL, בערכת הנושא האמיתית ובגופני
  // ה-goldens: כשיש מקום בצד הוא נפתח לצד השורה ותחתיתו בגובה תחתיתה, ובחלון
  // צר, כשאין מקום בצד, צמוד מעל השורה ומיושר לקצה ימין שלה.
  group('מיקום תת־התפריט של ברירות המחדל', () {
    const rowLabel = 'קביעת ברירת מחדל לחיפוש מתקדם';
    const proximityKey = ValueKey('search-dialog-default-proximity');
    // AppMenuMetrics.menuPadding: אנכי 8, אופקי 0.
    const menuPadding = 8.0;
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    // רוחב הטקסט קובע אם יש מקום בצד; בלי גופן אמיתי כל אות היא ריבוע.
    setUpAll(loadGoldenFonts);

    final row = find.byType(SubmenuButton);
    final proximity = find.byKey(proximityKey);
    final defaultOrder = find.byWidgetPredicate(
      (widget) =>
          widget is CheckboxMenuButton &&
          widget.key == const ValueKey('search-dialog-default-word-order'),
    );

    Future<void> openDialog(
      WidgetTester tester,
      Size size, {
      bool compact = false,
      TextDirection direction = TextDirection.rtl,
      double textScale = 1,
      double bottomInset = 0,
    }) async {
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
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
      addTearDown(() async {
        tester.view.reset();
        await historyBloc.close();
        await indexingBloc.close();
        await navigationBloc.close();
      });

      // נבנית בתוך הבדיקה, כדי ש-visualDensity והתפריטים יחושבו ל-Windows.
      final theme = AppThemeData.light(
        AppThemeData.createColorScheme(
          AppSeedColors.defaultLight,
          Brightness.light,
        ),
        compactMenuMode: compact,
      );
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
            builder: (context, app) => Directionality(
              textDirection: direction,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: app!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SearchDialog(
                        initialSearchMode: SearchMode.advanced,
                      ),
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
    }

    Future<void> openDefaultsMenu(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-defaults-menu')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openSubmenu(WidgetTester tester) async {
      await openDefaultsMenu(tester);
      await tester.tap(find.text(rowLabel));
      await tester.pumpAndSettle();
      expect(proximity, findsOneWidget);
    }

    /// הלוח הגלוי של תת־התפריט (ה-Material הקרוב ביותר מעל פריט בו).
    Rect submenuRect(WidgetTester tester) => tester.getRect(
      find.ancestor(of: proximity, matching: find.byType(Material)).first,
    );

    bool besideRow(Rect panel, Rect rowRect) =>
        panel.right <= rowRect.left + 0.5 || panel.left >= rowRect.right - 0.5;

    bool inOffstage(Element element) {
      var offstage = false;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is Offstage && widget.offstage) {
          offstage = true;
          return false;
        }
        return true;
      });
      return offstage;
    }

    String sizeName(Size size) =>
        '${size.width.toInt()}x${size.height.toInt()}';

    for (final (size, compact) in const [
      (Size(1100, 700), true),
      (Size(1366, 768), true),
      (Size(1366, 900), false),
    ]) {
      testWidgets(
        'חלון רחב ${sizeName(size)}${compact ? ' (תפריטים צפופים)' : ''}: '
        'תת־התפריט לצד השורה ותחתיתו בגובה תחתיתה',
        (WidgetTester tester) async {
          await openDialog(tester, size, compact: compact);
          await openSubmenu(tester);

          final rowRect = tester.getRect(row);
          final panel = submenuRect(tester);
          expect(rowRect.deflate(0.5).overlaps(panel), isFalse);
          expect(besideRow(panel, rowRect), isTrue, reason: '$panel $rowRect');
          expect(panel.top, lessThan(rowRect.top));
          expect(
            panel.bottom,
            moreOrLessEquals(rowRect.bottom + menuPadding, epsilon: 1),
          );
        },
        variant: windows,
      );
    }

    // תת־התפריט גבוה מהמקום שמעל תחתית השורה: Flutter מצמיד אותו לראש החלון.
    for (final size in const [Size(1100, 700), Size(1366, 768)]) {
      testWidgets(
        'חלון רחב ${sizeName(size)} נמוך מתת־התפריט: לצד השורה וצמוד לראש החלון',
        (WidgetTester tester) async {
          await openDialog(tester, size);
          await openSubmenu(tester);

          final rowRect = tester.getRect(row);
          final panel = submenuRect(tester);
          expect(panel.height, greaterThan(rowRect.bottom + menuPadding));
          expect(rowRect.deflate(0.5).overlaps(panel), isFalse);
          expect(besideRow(panel, rowRect), isTrue, reason: '$panel $rowRect');
          expect(panel.top, moreOrLessEquals(0, epsilon: 1));
        },
        variant: windows,
      );
    }

    for (final (size, compact) in const [
      (Size(480, 760), true),
      (Size(480, 820), false),
    ]) {
      testWidgets(
        'חלון צר ${sizeName(size)}${compact ? ' (תפריטים צפופים)' : ''}: '
        'תת־התפריט צמוד מעל השורה ומיושר לקצה ימין שלה',
        (WidgetTester tester) async {
          await openDialog(tester, size, compact: compact);
          await openSubmenu(tester);

          final rowRect = tester.getRect(row);
          final panel = submenuRect(tester);
          // התרחיש: אין מקום לתת־התפריט לא משמאל לשורה ולא מימין לה.
          expect(
            panel.width,
            greaterThan(
              math.max(rowRect.left, size.width - rowRect.right),
            ),
          );
          expect(rowRect.deflate(0.5).overlaps(panel), isFalse);
          expect(panel.bottom, moreOrLessEquals(rowRect.top, epsilon: 1));
          expect(panel.right, moreOrLessEquals(rowRect.right, epsilon: 1));
        },
        variant: windows,
      );
    }

    // אין מקום לא בצד ולא מעל השורה: הלוח מוגבל לגובה שמעל השורה ונגלל,
    // במקום ש-Flutter יצמיד אותו לראש החלון ויכסה את השורה.
    for (final size in const [
      Size(700, 700),
      Size(480, 760),
      Size(450, 700),
    ]) {
      testWidgets(
        'חלון צר ונמוך ${sizeName(size)}: תת־התפריט מעל השורה, נגלל ולא מכסה אותה',
        (WidgetTester tester) async {
          await openDialog(tester, size);
          await openSubmenu(tester);
          final rowRect = tester.getRect(row);
          final panel = submenuRect(tester);
          expect(rowRect.deflate(0.5).overlaps(panel), isFalse);
          expect(panel.bottom, moreOrLessEquals(rowRect.top, epsilon: 1));
          expect(panel.right, moreOrLessEquals(rowRect.right, epsilon: 1));
          expect(panel.top, greaterThanOrEqualTo(-0.5));

          // הלוח נגלל: יש מה לגלול, והפריטים האחרונים מגיעים לתוך הלוח.
          final scrollable = find
              .ancestor(of: proximity, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          expect(position.maxScrollExtent, greaterThan(0));
          expect(position.pixels, 0);
          await tester.ensureVisible(proximity);
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(0));
          final last = tester.getRect(proximity);
          expect(last.top, greaterThanOrEqualTo(panel.top - 0.5));
          expect(last.bottom, lessThanOrEqualTo(panel.bottom + 0.5));
          expect(submenuRect(tester), panel, reason: 'הלוח לא זז בגלילה');

          // הפריט האחרון עם תיבה ניתן לסימון אחרי הגלילה.
          final before = SearchDefaults.loadAnyOrderDefault();
          await tester.tap(defaultOrder);
          await tester.pumpAndSettle();
          expect(SearchDefaults.loadAnyOrderDefault(), !before);
          expect(proximity, findsOneWidget, reason: 'closeOnActivate: false');
        },
        variant: windows,
      );
    }

    for (final direction in TextDirection.values) {
      testWidgets(
        'חלון צר עם כיוון $direction וטקסט מוגדל',
        (tester) async {
          await openDialog(
            tester,
            const Size(360, 640),
            direction: direction,
            textScale: 1.3,
          );
          await openSubmenu(tester);
          final rowRect = tester.getRect(row);
          final panel = submenuRect(tester);
          expect(rowRect.deflate(0.5).overlaps(panel), isFalse);
        },
        variant: windows,
      );
    }

    testWidgets(
      'תת־התפריט נגיש בחלון אופקי עם מקלדת המסך פתוחה',
      (tester) async {
        await openDialog(tester, const Size(640, 400), bottomInset: 145);
        await openSubmenu(tester);
        final rowRect = tester.getRect(row);
        final panel = submenuRect(tester);
        expect(
          rowRect.deflate(0.5).overlaps(panel),
          isFalse,
          reason: '$panel $rowRect',
        );
        expect(panel.bottom, moreOrLessEquals(rowRect.top, epsilon: 1));
        expect(panel.top, greaterThanOrEqualTo(-0.5));

        await tester.ensureVisible(proximity);
        await tester.pumpAndSettle();
        expect(
          panel.deflate(0.5).contains(tester.getCenter(proximity)),
          isTrue,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    for (final size in const [Size(1366, 768), Size(480, 820)]) {
      testWidgets(
        'חלון ${sizeName(size)}: תת־התפריט לא קופץ אחרי שהוצג',
        (WidgetTester tester) async {
          await openDialog(tester, size);
          // פתיחה מהירה: פריים אחד בלבד בין פתיחת התפריט לפתיחת תת־התפריט.
          await tester.tap(
            find.byKey(const ValueKey('search-dialog-defaults-menu')),
          );
          await tester.pump();
          await tester.tap(find.text(rowLabel));
          Rect? first;
          for (var i = 0; i < 10 && first == null; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (proximity.evaluate().isNotEmpty) first = submenuRect(tester);
          }
          expect(first, isNotNull);
          await tester.pumpAndSettle();
          expect(submenuRect(tester), first);

          // גם בפתיחה בריחוף, בתפריט שנפתח מחדש.
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(proximity, findsNothing);
          await openDefaultsMenu(tester);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(row));
          first = null;
          for (var i = 0; i < 10 && first == null; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (proximity.evaluate().isNotEmpty) first = submenuRect(tester);
          }
          expect(first, isNotNull);
          await tester.pumpAndSettle();
          expect(submenuRect(tester), first);
        },
        variant: windows,
      );
    }

    for (final size in const [Size(1366, 900), Size(480, 820)]) {
      testWidgets(
        'חלון ${sizeName(size)}: העכבר עובר מהשורה אל תת־התפריט ומסמן בו תיבה',
        (WidgetTester tester) async {
          await openDialog(tester, size);
          await openDefaultsMenu(tester);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          var at = tester.getCenter(row);
          await mouse.moveTo(at);
          await tester.pumpAndSettle();
          expect(proximity, findsOneWidget);

          final rowRect = tester.getRect(row);
          final panel = submenuRect(tester);
          final target = tester.getRect(defaultOrder);
          Future<void> moveTowards(Offset to) async {
            while ((to - at).distance > 0.5) {
              final step = to - at;
              at += step.distance <= 4 ? step : step / step.distance * 4;
              await mouse.moveTo(at);
              await tester.pump(const Duration(milliseconds: 8));
              expect(proximity, findsOneWidget, reason: 'נסגר ב-$at');
            }
          }

          if (besideRow(panel, rowRect)) {
            // לצד השורה: אופקית אל תוך הלוח, ואז בתוכו אל התיבה.
            final x = (panel.left + panel.right) / 2;
            await moveTowards(Offset(x, at.dy));
            await moveTowards(Offset(x, target.center.dy));
          } else {
            // מעל השורה: עולים ישר למעלה, בקו אנכי שבתוך השורה ובתוך התיבה.
            expect(panel.bottom, moreOrLessEquals(rowRect.top, epsilon: 1));
            final x =
                (math.max(rowRect.left, target.left) +
                    math.min(rowRect.right, target.right)) /
                2;
            await moveTowards(Offset(x, at.dy));
            await moveTowards(Offset(x, target.center.dy));
          }
          await tester.pumpAndSettle();
          expect(proximity, findsOneWidget);
          expect(target.contains(at), isTrue);

          final before = SearchDefaults.loadAnyOrderDefault();
          await mouse.down(at);
          await tester.pump();
          await mouse.up();
          await tester.pumpAndSettle();
          expect(SearchDefaults.loadAnyOrderDefault(), !before);
          expect(proximity, findsOneWidget, reason: 'closeOnActivate: false');
        },
        variant: windows,
      );
    }

    testWidgets(
      'מקלדת: חץ שמאלה נכנס לתת־התפריט, ו-Esc סוגר את התפריטים ולא את הדיאלוג',
      (WidgetTester tester) async {
        await openDialog(tester, const Size(1366, 900));
        await openDefaultsMenu(tester);
        final defaultMode = find.byKey(
          const ValueKey('search-dialog-default-mode'),
        );

        // פוקוס על השורה פותח את תת־התפריט (התנהגות SubmenuButton).
        Focus.of(tester.element(find.text(rowLabel))).requestFocus();
        await tester.pumpAndSettle();
        expect(proximity, findsOneWidget);

        Element submenuPanel() {
          late Element panel;
          tester.element(proximity).visitAncestorElements((ancestor) {
            if (ancestor.widget.runtimeType.toString() == '_MenuPanel') {
              panel = ancestor;
              return false;
            }
            return true;
          });
          return panel;
        }

        bool focusInSubmenu() {
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused is! Element) return false;
          final panel = submenuPanel();
          var inside = false;
          focused.visitAncestorElements((ancestor) {
            inside = identical(ancestor, panel);
            return !inside;
          });
          return inside;
        }

        // ב-RTL תת־התפריט משמאל: חץ שמאלה מעביר אליו את הפוקוס.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(focusInSubmenu(), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusInSubmenu(), isTrue);
        final focused = FocusManager.instance.primaryFocus!.context! as Element;
        expect(inOffstage(focused), isFalse);

        // DismissMenuAction של Flutter סוגר את כל עץ התפריטים (root), ולכן
        // Esc ראשון סוגר את תת־התפריט ואת התפריט הראשי, והדיאלוג נשאר.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(proximity, findsNothing);
        expect(defaultMode, findsNothing);
        expect(find.byType(SearchDialog), findsOneWidget);
      },
      variant: windows,
    );

    testWidgets(
      'העותק הנסתר למדידה: לא נמצא, לא מקבל פוקוס, לא נלחץ ולא בסמנטיקה',
      (WidgetTester tester) async {
        final semantics = tester.ensureSemantics();
        await openDialog(tester, const Size(1366, 900));
        await openDefaultsMenu(tester);

        // קיים בעץ אבל מחוץ לבמה: המאתרים הרגילים לא רואים אותו.
        expect(proximity, findsNothing);
        final hidden = find.byKey(proximityKey, skipOffstage: false);
        expect(hidden, findsOneWidget);
        expect(inOffstage(tester.element(hidden)), isTrue);
        expect(find.byType(SubmenuButton), findsOneWidget);
        expect(find.semantics.byLabel(RegExp('טווח הקרבה')), findsNothing);

        // פוקוס: לא ניתן לבקש, וגם מעבר בחצים וב-Tab לא מגיע אליו.
        final hiddenNode = Focus.of(
          tester.element(
            find
                .descendant(
                  of: hidden,
                  matching: find.byType(Text, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          ),
        );
        expect(hiddenNode.canRequestFocus, isFalse);
        hiddenNode.requestFocus();
        await tester.pump();
        expect(hiddenNode.hasFocus, isFalse);
        Focus.of(tester.element(find.text(rowLabel))).requestFocus();
        await tester.pump();
        for (final key in [
          for (var i = 0; i < 6; i++) LogicalKeyboardKey.arrowDown,
          for (var i = 0; i < 6; i++) LogicalKeyboardKey.arrowUp,
          for (var i = 0; i < 6; i++) LogicalKeyboardKey.tab,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused is Element) {
            expect(inOffstage(focused), isFalse, reason: '$key');
          }
        }

        // לחיצה: מרכז העותק לא פוגע בו (הוא מונח מעל השורה ומתחתיה).
        await tester.pumpAndSettle();
        if (find.byType(SubmenuButton).evaluate().isEmpty) {
          await openDefaultsMenu(tester);
        }
        final hiddenBox = tester.renderObject<RenderBox>(hidden);
        final point = hiddenBox.localToGlobal(
          hiddenBox.size.center(Offset.zero),
        );
        final hiddenObjects =
            tester
                .renderObjectList(
                  find.descendant(
                    of: hidden,
                    matching: find.byWidgetPredicate(
                      (_) => true,
                      skipOffstage: false,
                    ),
                    skipOffstage: false,
                  ),
                )
                .toSet()
              ..add(hiddenBox);
        final hit = tester.hitTestOnBinding(point);
        expect(
          hit.path.where((entry) => hiddenObjects.contains(entry.target)),
          isEmpty,
        );
        semantics.dispose();
      },
      variant: windows,
    );
  });
}
