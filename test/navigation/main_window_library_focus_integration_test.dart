import 'dart:async';
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_role.dart';
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
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/legacy.dart' show TitleBarStyle;
import '../test_helpers/memory_cache_provider.dart';

void main() {
  tz.initializeTimeZones();
  late Directory dataRoot;
  setUpAll(() async {
    dataRoot = await Directory.systemTemp.createTemp('main-window-focus-test-');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
  });
  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });
  final platforms = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.android,
  });
  for (final start in [Screen.reading, Screen.settings]) {
    testWidgets(
      'מעבר מ${start.name} לספרייה ממקד את החיפוש במסך הראשי (issue #1723)',
      (tester) async {
        await Settings.init(cacheProvider: MemoryCacheProvider());
        // כמו חלון שאינו בעל התהליך: בלי ניקוז הפעלות חיצוניות.
        if (ProcessDuties.current.isProcessOwner) {
          ProcessDuties.debugOverride = ProcessDuties(
            isProcessOwner: () => false,
          );
          addTearDown(() => ProcessDuties.debugOverride = null);
        }
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        final navigation = _NavigationBloc();
        final changes = StreamController<NavigationState>.broadcast();
        whenListen(
          navigation,
          changes.stream,
          initialState: const NavigationState(currentScreen: Screen.reading),
        );
        final focus = FocusRepository();
        focus.librarySearchController.text = 'בראשית';
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
        final library = _LibraryBloc();
        whenListen(
          library,
          const Stream<LibraryState>.empty(),
          initialState: LibraryState(library: Library(categories: [])),
        );
        final tabs = _TabsBloc();
        whenListen(
          tabs,
          const Stream<TabsState>.empty(),
          initialState: TabsState.initial(),
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
          await changes.close();
          for (final bloc in [
            navigation,
            settings,
            indexing,
            history,
            library,
            tabs,
            workspace,
            pluginSystem,
            libraryUpdate,
            workStatus,
          ]) {
            await bloc.close();
          }
          focus.librarySearchFocusNode.unfocus();
          focus.librarySearchController.clear();
          await tester.binding.setSurfaceSize(null);
        });
        const window = _FakeWindow(AppWindowId('test-window'));
        await tester.pumpWidget(
          AppWindowScope(
            controller: window,
            geometry: window,
            role: const AppWindowRole(
              isPrimaryView: false,
              openedWithTab: true,
            ),
            child: RepositoryProvider<FocusRepository>.value(
              value: focus,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<NavigationBloc>.value(value: navigation),
                  BlocProvider<WorkStatusCubit>.value(value: workStatus),
                  BlocProvider<SettingsBloc>.value(value: settings),
                  BlocProvider<WindowFullscreenCubit>(
                    create: (_) => WindowFullscreenCubit(
                      initial: false,
                      persist: (_) async {},
                    ),
                  ),
                  BlocProvider<IndexingBloc>.value(value: indexing),
                  BlocProvider<HistoryBloc>.value(value: history),
                  BlocProvider<LibraryBloc>.value(value: library),
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
                  child: const MaterialApp(home: MainWindowScreen()),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (start == Screen.settings) {
          final rootContext = tester.element(find.byType(MainWindowScreen));
          final shortcuts = tester.widget<KeyboardShortcuts>(
            find.byType(KeyboardShortcuts),
          );
          for (final open in [
            shortcuts.onFindRefRequested,
            shortcuts.onNewSearchRequested!,
          ]) {
            showDialog<void>(
              context: rootContext,
              builder: (_) => const PopScope(
                canPop: false,
                child: AlertDialog(title: Text('התקנה פעילה')),
              ),
            );
            await tester.pumpAndSettle();
            showDialog<void>(
              context: rootContext,
              builder: (_) => const AlertDialog(title: Text('שכבה נוספת')),
            );
            await tester.pumpAndSettle();
            open();
            await tester.pumpAndSettle();
            expect(find.text('שכבה נוספת'), findsNothing);
            expect(find.text('התקנה פעילה'), findsOneWidget);
            Navigator.of(rootContext).pop();
            await tester.pumpAndSettle();
          }
        }
        Future<void> navigate(Screen screen) async {
          changes.add(NavigationState(currentScreen: screen));
          await tester.pump();
          await tester.pumpAndSettle();
          await tester.pump();
        }

        // בכניסה הראשונה השדה עצמו עושה autofocus; הבאג מופיע בחזרה אליו.
        await navigate(Screen.library);
        await navigate(start);
        expect(focus.librarySearchFocusNode.hasFocus, isFalse);
        await navigate(Screen.library);
        expect(tester.takeException(), isNull);
        final desktop = defaultTargetPlatform == TargetPlatform.windows;
        expect(focus.librarySearchFocusNode.hasFocus, desktop);
        if (!desktop) return;
        expect(
          focus.librarySearchController.selection,
          const TextSelection(baseOffset: 0, extentOffset: 6),
        );
        tester.testTextInput.enterText('משנה');
        await tester.pump();
        expect(focus.librarySearchController.text, 'משנה');
      },
      variant: platforms,
    );
  }
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
    implements LibraryBloc {}

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
