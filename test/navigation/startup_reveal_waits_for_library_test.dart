import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/external_activation_service.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
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
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart' show TitleBarStyle;

import '../test_helpers/memory_cache_provider.dart';

/// עלייה למסך הספרייה: החלון נחשף פעם אחת, כשהקטלוג זמין — לא חלון ריק ואחריו
/// מחוון טעינה נפרד של הספרייה (issue #2838).
void main() {
  tz.initializeTimeZones();
  late Directory dataRoot;
  setUpAll(() async {
    dataRoot = await Directory.systemTemp.createTemp('library-reveal-test-');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    await QueryLoader.initialize();
  });
  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  group('single startup loading phase on library screen (issue #2838)', () {
    testWidgets('החלון אינו נחשף לפני שהקטלוג נטען', (tester) async {
      final harness = await _pumpMainWindow(tester);
      expect(harness.calls, isNot(contains('show')));

      harness.libraryChanges.add(
        LibraryState(library: Library(categories: [])),
      );
      await tester.pump();
      await tester.pump();
      expect(harness.calls, contains('show'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('שגיאת טעינת הספרייה חושפת מיד את מצב השגיאה', (tester) async {
      final catalog = Completer<Library>();
      final library = LibraryBloc(
        repository: _FailingRepository(catalog.future),
      );
      final harness = await _pumpMainWindow(tester, realLibrary: library);
      expect(harness.calls, isNot(contains('show')));

      catalog.completeError(StateError('כשל קטלוג'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      await tester.pump();
      await tester.pump();
      expect(harness.calls, containsAllInOrder(['show', 'splash:close']));
      expect(library.state.error, contains('כשל קטלוג'));
      expect(find.byType(OtzariaErrorState), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ספרייה חסרה חושפת את מסך ההגדרה בזמן הטעינה', (tester) async {
      final harness = await _pumpMainWindow(tester);
      expect(harness.calls, isNot(contains('show')));

      harness.navigationChanges.add(
        const NavigationState(
          currentScreen: Screen.library,
          hasCheckedLibrary: true,
          isLibraryEmpty: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(harness.calls, contains('show'));
      expect(find.byType(LibrarySetupView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('מעבר לחיפוש משחרר את ההמתנה לקטלוג', (tester) async {
      final harness = await _pumpMainWindow(tester);
      expect(harness.calls, isNot(contains('show')));

      harness.navigationChanges.add(
        const NavigationState(currentScreen: Screen.search),
      );
      await tester.pump();
      await tester.pump();
      expect(harness.calls, contains('show'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('קטלוג שלא נטען — רשת הביטחון הקיימת חושפת', (tester) async {
      final harness = await _pumpMainWindow(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(harness.calls, isNot(contains('show')));

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump();
      expect(harness.calls, contains('show'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('קטלוג שכבר נטען — חשיפה מיידית', (tester) async {
      final harness = await _pumpMainWindow(
        tester,
        initialLibrary: LibraryState(library: Library(categories: [])),
      );
      expect(harness.calls, contains('show'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('בלי מסך פתיחה נייטיבי אין המתנה לקטלוג', (tester) async {
      final harness = await _pumpMainWindow(tester, nativeSplashActive: false);
      expect(harness.calls, contains('show'));
      expect(tester.takeException(), isNull);
    });
  });
}

class _FailingRepository extends Fake implements DataRepository {
  _FailingRepository(this.library);

  @override
  final Future<Library> library;
}

class _Harness {
  _Harness(this.calls, this.libraryChanges, this.navigationChanges);

  final List<String> calls;
  final StreamController<LibraryState> libraryChanges;
  final StreamController<NavigationState> navigationChanges;
}

Future<_Harness> _pumpMainWindow(
  WidgetTester tester, {
  LibraryState? initialLibrary,
  LibraryBloc? realLibrary,
  bool nativeSplashActive = true,
}) async {
  await Settings.init(cacheProvider: MemoryCacheProvider());
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  WindowPersistence.splashMode = nativeSplashActive;
  // כמו חלון שאינו בעל התהליך: בלי ניקוז הפעלות חיצוניות ועבודות רקע.
  if (ProcessDuties.current.isProcessOwner) {
    ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
    addTearDown(() => ProcessDuties.debugOverride = null);
  }
  final calls = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
    call,
  ) async {
    calls.add(call.method);
    if (call.method == 'isVisible') return true;
    if (call.method.startsWith('is')) return false;
    return null;
  });
  messenger.setMockMethodCallHandler(const MethodChannel('otzaria/splash'), (
    call,
  ) async {
    calls.add('splash:${call.method}');
    return null;
  });
  final navigation = _NavigationBloc();
  final navigationChanges = StreamController<NavigationState>.broadcast();
  whenListen(
    navigation,
    navigationChanges.stream,
    initialState: const NavigationState(currentScreen: Screen.library),
  );
  final focus = FocusRepository();
  final workStatus = WorkStatusCubit();
  final settings = _SettingsBloc();
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(isOfflineMode: true),
  );
  final indexing = _IndexingBloc();
  whenListen(
    indexing,
    const Stream<IndexingState>.empty(),
    initialState: IndexingInitial(),
  );
  final history = _HistoryBloc();
  whenListen(
    history,
    const Stream<HistoryState>.empty(),
    initialState: HistoryLoaded([]),
  );
  final libraryChanges = StreamController<LibraryState>.broadcast();
  final library = realLibrary ?? _LibraryBloc();
  if (realLibrary == null) {
    whenListen(
      library,
      libraryChanges.stream,
      initialState: initialLibrary ?? LibraryState.initial(),
    );
  }
  final tabs = _TabsBloc();
  whenListen(
    tabs,
    const Stream<TabsState>.empty(),
    initialState: const TabsState(tabs: [], currentTabIndex: 0),
  );
  final workspace = _WorkspaceBloc();
  whenListen(
    workspace,
    const Stream<WorkspaceState>.empty(),
    initialState: const WorkspaceState(workspaces: []),
  );
  final pluginSystem = _PluginSystemBloc();
  whenListen(
    pluginSystem,
    const Stream<PluginSystemState>.empty(),
    initialState: const PluginSystemLoaded([]),
  );
  final libraryUpdate = _LibraryUpdateBloc();
  whenListen(
    libraryUpdate,
    const Stream<LibraryUpdateState>.empty(),
    initialState: const LibraryUpdateState(),
  );

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await libraryChanges.close();
    await navigationChanges.close();
    for (final bloc in [
      navigation,
      settings,
      indexing,
      history,
      if (realLibrary == null) library,
      tabs,
      workspace,
      pluginSystem,
      libraryUpdate,
      workStatus,
    ]) {
      await bloc.close();
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('otzaria/splash'),
      null,
    );
    WindowPersistence.splashMode = false;
    await tester.binding.setSurfaceSize(null);
  });
  const window = _FakeWindow(AppWindowId('test-window'));
  await tester.pumpWidget(
    AppWindowScope(
      controller: window,
      geometry: window,
      child: RepositoryProvider<FocusRepository>.value(
        value: focus,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<NavigationBloc>.value(value: navigation),
            BlocProvider<WorkStatusCubit>.value(value: workStatus),
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<WindowFullscreenCubit>(
              create: (_) =>
                  WindowFullscreenCubit(initial: false, persist: (_) async {}),
            ),
            BlocProvider<IndexingBloc>.value(value: indexing),
            BlocProvider<HistoryBloc>.value(value: history),
            if (realLibrary == null)
              BlocProvider<LibraryBloc>.value(value: library)
            else
              BlocProvider<LibraryBloc>(create: (_) => realLibrary),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<WorkspaceBloc>.value(value: workspace),
            BlocProvider<PluginSystemBloc>.value(value: pluginSystem),
            BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdate),
            BlocProvider<CustomFoldersBloc>(
              create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
            ),
          ],
          child: RepositoryProvider<SettingsRepository>(
            create: (_) => SettingsRepository(),
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<ShamorZachorDataProvider>(
                  create: (_) => _ShamorData(),
                ),
                ChangeNotifierProvider<ShamorZachorProgressProvider>(
                  create: (_) => _ShamorProgress(),
                ),
                Provider<ExternalActivationService>(
                  create: (_) => ExternalActivationService(),
                  dispose: (_, service) => service.dispose(),
                ),
              ],
              child: const MaterialApp(home: MainWindowScreen()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  return _Harness(calls, libraryChanges, navigationChanges);
}

class _ShamorData extends ShamorZachorDataProvider {
  @override
  Future<void> ensureLoaded() async {}
}

class _ShamorProgress extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}
}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _IndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

class _TabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _WorkspaceBloc extends MockBloc<WorkspaceEvent, WorkspaceState>
    implements WorkspaceBloc {}

class _PluginSystemBloc extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

class _LibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _FakeWindow implements AppWindowController, AppWindowGeometry {
  const _FakeWindow(this.id);

  @override
  final AppWindowId id;

  @override
  Future<void> center() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> quitApplication() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<Rect> getBounds() async => Rect.zero;
  @override
  Future<bool> isFullScreen() async => false;
  @override
  Listenable get stateChanges => Listenable.merge(const []);
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<bool> isVisible() async => true;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setBounds(Rect bounds) async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setProgressBar(double progress) async {}
  @override
  Future<void> setSize(Size size) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}
