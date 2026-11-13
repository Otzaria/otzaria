import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockPluginRegistryRepository extends Mock
    implements PluginRegistryRepository {}

class _Tabs extends Cubit<TabsState> implements TabsBloc {
  _Tabs(super.initialState);
  @override
  void add(TabsEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Nav extends Cubit<NavigationState> implements NavigationBloc {
  _Nav() : super(const NavigationState(currentScreen: Screen.reading));
  @override
  void add(NavigationEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History extends Cubit<HistoryState> implements HistoryBloc {
  _History() : super(HistoryInitial());
  @override
  void add(HistoryEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _Settings() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '0.9.99',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'צפייה',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _throwsError(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

/// `ui.setFullscreen`: מסך מלא של האפליקציה מתוסף. כניסה רק מפעולת משתמש,
/// ויציאה (Escape, "חזור", false) תמיד.
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('אינה דורשת הרשאת manifest', () {
    expect(
      PluginBridgeHandler.methodPermissions['ui.setFullscreen'],
      PluginBridgeHandler.noManifestPermission,
    );
  });

  PluginBridgeAdapter adapterFor({
    BuildContext? windowContext,
    required TabsBloc tabsBloc,
    required NavigationBloc navigationBloc,
    required Future<bool> Function() gesture,
    Future<void> Function(bool fullscreen)? setAppFullscreen,
  }) => PluginBridgeAdapter(
    _plugin(),
    instanceId: 'tab-1',
    dependencies: PluginBridgeDependencies(
      windowContext: windowContext,
      historyBloc: _History(),
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: _MockWorkspaceBloc(),
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
      hasUserActivation: (_, _) => gesture(),
      setAppFullscreen: setAppFullscreen,
    ),
    pluginRepository: _MockPluginRegistryRepository(),
  );

  group('ui.setFullscreen', () {
    late List<bool> calls;
    late bool gesture;
    late PluginBridgeAdapter adapter;

    setUp(() {
      calls = [];
      gesture = true;
      adapter = adapterFor(
        tabsBloc: _Tabs(TabsState(tabs: const [], currentTabIndex: 0)),
        navigationBloc: _Nav(),
        gesture: () async => gesture,
        setAppFullscreen: (value) async => calls.add(value),
      );
    });

    test('fullscreen שאינו בוליאני נדחה כ-invalid_params', () {
      expect(
        () => adapter.execute('ui', 'setFullscreen', {'fullscreen': 'yes'}),
        _throwsError('error.invalid_params'),
      );
      expect(
        () => adapter.execute('ui', 'setFullscreen', const {}),
        _throwsError('error.invalid_params'),
      );
      expect(calls, isEmpty);
    });

    test('כניסה בלי פעולת משתמש נדחית ב-forbidden', () async {
      gesture = false;
      await expectLater(
        adapter.execute('ui', 'setFullscreen', {'fullscreen': true}),
        _throwsError('error.forbidden'),
      );
      expect(calls, isEmpty);
    });

    test('כניסה מפעולת משתמש, ויציאה גם בלי פעולה', () async {
      expect(
        await adapter.execute('ui', 'setFullscreen', {'fullscreen': true}),
        isTrue,
      );
      gesture = false;
      expect(
        await adapter.execute('ui', 'setFullscreen', {'fullscreen': false}),
        isTrue,
      );
      expect(calls, [true, false]);
    });
  });

  testWidgets(
    'בחלון אמיתי: התוסף נכנס, Escape יוצא בלי לשאול אותו, והוא אינו חוזר '
    'בלי פעולת משתמש',
    (tester) async {
      final fullscreen = WindowFullscreenCubit(
        initial: false,
        persist: (_) async {},
      );
      final tab = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
      final tabs = _Tabs(TabsState(tabs: [tab], currentTabIndex: 0));
      final navigation = _Nav();
      final history = _History();
      final settings = _Settings();
      addTearDown(() async {
        await fullscreen.close();
        await tabs.close();
        await navigation.close();
        await history.close();
        await settings.close();
        tab.dispose();
      });

      late BuildContext windowContext;
      await tester.pumpWidget(
        AppWindowScope(
          controller: const WindowManagerAppWindowController(),
          geometry: const WindowManagerAppWindowController(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<WindowFullscreenCubit>.value(value: fullscreen),
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<NavigationBloc>.value(value: navigation),
              BlocProvider<HistoryBloc>.value(value: history),
              BlocProvider<SettingsBloc>.value(value: settings),
              Provider<FocusRepository>.value(value: FocusRepository()),
            ],
            child: MaterialApp(
              home: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: Builder(
                  builder: (context) {
                    windowContext = context;
                    return const Scaffold(body: SizedBox.expand());
                  },
                ),
              ),
            ),
          ),
        ),
      );

      var gesture = false;
      final adapter = adapterFor(
        windowContext: windowContext,
        tabsBloc: tabs,
        navigationBloc: navigation,
        gesture: () async => gesture,
      );

      await tester.runAsync(
        () => expectLater(
          adapter.execute('ui', 'setFullscreen', {'fullscreen': true}),
          _throwsError('error.forbidden'),
        ),
      );
      expect(fullscreen.state, isFalse);

      gesture = true;
      await tester.runAsync(
        () => adapter.execute('ui', 'setFullscreen', {'fullscreen': true}),
      );
      await tester.pump();
      expect(fullscreen.state, isTrue);

      // Escape של האפליקציה יוצא ממסך מלא; התוסף אינו יכול לחסום.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fullscreen.state, isFalse);

      // לא דביק: בלי פעולת משתמש חדשה התוסף לא מחזיר את המסך המלא.
      gesture = false;
      await tester.runAsync(
        () => expectLater(
          adapter.execute('ui', 'setFullscreen', {'fullscreen': true}),
          _throwsError('error.forbidden'),
        ),
      );
      expect(fullscreen.state, isFalse);
      adapter.dispose();
    },
  );
}
