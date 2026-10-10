import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';

import '../helpers/seforim_fixture_db.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart' show TitleBarStyle;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  tz.initializeTimeZones();
  late Directory dataRoot;
  setUpAll(() async {
    dataRoot = await Directory.systemTemp.createTemp('attached-reveal-test-');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    await QueryLoader.initialize();
  });
  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });
  for (final source in [
    BookSource.attached('a'),
    BookSource.official,
    BookSource.user,
  ]) {
    testWidgets(
      'חשיפת ספר ${source.identitySuffix} משחררת את שער SQLite אחרי הציור',
      (tester) async {
        await Settings.init(cacheProvider: MemoryCacheProvider());
        final oldSecondary = WindowRole.isSecondary;
        final oldOpenedWithTab = WindowRole.openedWithTab;
        WindowRole.isSecondary = false;
        WindowRole.openedWithTab = false;
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        final book = TextBook(
          id: SeforimFixtureIds.bereshitId,
          title: 'בראשית',
          source: source,
        );
        final bookChanges = StreamController<TextBookState>.broadcast();
        final bookBloc = _TextBookBloc();
        whenListen(
          bookBloc,
          bookChanges.stream,
          initialState: TextBookLoading(book, 0, false, const []),
        );
        final tab = TextBookTab(book: book, index: 0, blocOverride: bookBloc)
          ..currentTitle.value = 'בראשית פרק א';
        final gate = Completer<void>();
        final nativeClose = Completer<void>();
        final previousGate = AttachedLibraryRegistry.startupGate;
        AttachedLibraryRegistry.startupGate = () => gate.future;
        final dbDir = Directory.systemTemp.createTempSync(
          'attached-reveal-db-',
        );
        final path = SeforimFixtureDb.create(dbDir, SeforimFixtureVariant.full);
        final registry = AttachedLibraryRegistry(idleTimeout: null)
          ..update([
            AttachedLibrary(
              slug: 'a',
              displayName: 'ספרייה',
              path: path,
              priority: 0,
              hidden: false,
              status: AttachedLibraryStatus.ok,
              addedAt: DateTime(2026),
            ),
          ]);
        var opened = false;
        late Future<SeforimRepository?> pending;
        await tester.runAsync(() async {
          pending = registry.repositoryFor('a').then((repository) {
            opened = true;
            return repository;
          });
        });
        final calls = <String>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async {
            calls.add(call.method);
            if (call.method == 'isVisible') return true;
            if (call.method.startsWith('is')) return false;
            return null;
          },
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('otzaria/splash'),
          (call) async {
            calls.add('splash:${call.method}');
            if (call.method == 'close') {
              expect(opened, isFalse);
              expect(registry.isOpen('a'), isFalse);
              await nativeClose.future;
              gate.complete();
            }
            return null;
          },
        );
        final navigation = _NavigationBloc();
        final changes = StreamController<NavigationState>.broadcast();
        whenListen(
          navigation,
          changes.stream,
          initialState: const NavigationState(currentScreen: Screen.reading),
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
          initialState: TabsState(tabs: [tab], currentTabIndex: 0),
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
          tab.dispose();
          await bookChanges.close();
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
          if (!nativeClose.isCompleted) nativeClose.complete();
          if (!gate.isCompleted) gate.complete();
          await tester.pump();
          await tester.runAsync(() async {
            await pending;
            await registry.closeAll();
          });
          AttachedLibraryRegistry.startupGate = previousGate;
          messenger.setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          );
          messenger.setMockMethodCallHandler(
            const MethodChannel('otzaria/splash'),
            null,
          );
          WindowRole.isSecondary = oldSecondary;
          WindowRole.openedWithTab = oldOpenedWithTab;
          await tester.binding.setSurfaceSize(null);
          dbDir.deleteSync(recursive: true);
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
                  BlocProvider<IndexingBloc>.value(value: indexing),
                  BlocProvider<HistoryBloc>.value(value: history),
                  BlocProvider<LibraryBloc>.value(value: library),
                  BlocProvider<TabsBloc>.value(value: tabs),
                  BlocProvider<WorkspaceBloc>.value(value: workspace),
                  BlocProvider<PluginSystemBloc>.value(value: pluginSystem),
                  BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdate),
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
        if (!source.isAttached) {
          expect(calls, isNot(contains('show')));
          expect(gate.isCompleted, isFalse);
          expect(opened, isFalse);
          bookChanges.add(
            TextBookError('שגיאת טעינה', book, 0, false, const []),
          );
          await tester.pump();
          await tester.pump();
        }
        expect(calls, contains('show'));
        expect(calls, contains('splash:close'));
        expect(gate.isCompleted, isFalse);
        expect(opened, isFalse);
        nativeClose.complete();
        await tester.pump();
        expect(gate.isCompleted, isTrue);
        final repository = await tester.runAsync(() => pending);
        expect(repository, isNotNull);
        expect(
          await tester.runAsync(() => repository!.getBookToc(book.id!)),
          isNotEmpty,
        );
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _TextBookBloc extends MockBloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  @override
  bool get isClosed => false;
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
