import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
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
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/navigation/view/vertical_reading_tab_strip.dart';
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
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
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
    registerFallbackValue(DropOrphanedIndexEntries(Library(categories: [])));
    dataRoot = await Directory.systemTemp.createTemp('main-window-load-test-');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
  });
  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  testWidgets('טעינת ספרייה שנכשלה אינה מפילה שגיאה לא מטופלת (#2469)', (
    tester,
  ) async {
    final catalog = Completer<Library>();
    final harness = await _pumpMainWindow(tester, catalog.future);
    harness.libraryChanges.add(
      harness.initialState.copyWith(isLoading: false, error: 'load failed'),
    );
    await tester.pump();
    catalog.completeError(StateError('catalog build failed'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verifyNever(() => harness.indexing.add(any()));
  });

  testWidgets('טעינת ספרייה שהצליחה מפעילה את החלטת האינדוקס', (tester) async {
    final harness = await _pumpMainWindow(
      tester,
      Future.value(Library(categories: [])),
    );
    harness.libraryChanges.add(harness.initialState.copyWith(isLoading: false));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verify(() => harness.indexing.add(any(that: isA<ReconcileHiddenIndex>())))
        .called(1);
  });

  testWidgets('החלטת האינדוקס בעלייה שואלת את ProcessDuties', (tester) async {
    // לפני הבנייה: המסך קורא את ProcessDuties פעם אחת, ב-initState.
    ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
    addTearDown(() => ProcessDuties.debugOverride = null);
    final harness = await _pumpMainWindow(
      tester,
      Future.value(Library(categories: [])),
    );
    harness.libraryChanges.add(harness.initialState.copyWith(isLoading: false));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verify(() => harness.indexing.add(any(that: isA<CheckIndexStatus>())))
        .called(1);
  });

  testWidgets('סוף רצף העלייה מכבה את סימון ההמתנה כשהאינדוקס מתחיל (#2646)', (
    tester,
  ) async {
    final deferred = TantivyDataProvider.instance.isIndexingDeferred;
    addTearDown(() => deferred.value = false);
    final indexingStates = StreamController<IndexingState>.broadcast();
    addTearDown(indexingStates.close);
    final harness = await _pumpMainWindow(
      tester,
      Future.value(Library(categories: [])),
      indexingStates: indexingStates.stream,
    );
    deferred.value = true;
    harness.libraryChanges.add(harness.initialState.copyWith(isLoading: false));
    await tester.pump();
    await tester.pump();
    expect(deferred.value, isTrue);

    indexingStates.add(const IndexingInProgress(booksProcessed: 0));
    await tester.pump();
    expect(deferred.value, isFalse);
  });

  testWidgets('רענון ספרייה שנכשל אינו מפיל שגיאה לא מטופלת', (tester) async {
    final catalog = Completer<Library>();
    final harness = await _pumpMainWindow(
      tester,
      catalog.future,
      isLoading: false,
    );
    harness.libraryChanges.add(
      harness.initialState.copyWith(
        error: 'refresh failed',
        failedRefreshRequestIds: {7},
      ),
    );
    await tester.pump();
    catalog.completeError(StateError('catalog build failed'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verifyNever(() => harness.indexing.add(any()));
  });

  group('כרטיסיות בצד מוצגות לפי כיוון אחד לכל החלון (issue #3180)', () {
    // הרצועה נקבעת לפי רוחב החלון (DD-15, MIG-21) ולא לפי הכיוון: 1000×1030
    // הוא חלון לאורך אבל לא צר, ולכן הכרטיסיות בצד. #3180 עצמו: תמיד רצועה
    // אחת. רק חלון צר (מתחת ל-600) מחזיר אותן לשורה שמתחת לסרגל.
    for (final (size, onSide) in [
      (const Size(1000, 1030), true),
      (const Size(1400, 900), true),
      (const Size(560, 900), false),
    ]) {
      testWidgets('חלון ${size.width.toInt()}×${size.height.toInt()}', (
        tester,
      ) async {
        await _pumpMainWindow(
          tester,
          Future.value(Library(categories: [])),
          isLoading: false,
          size: size,
          tabsPlacement: SettingsRepository.readingTabsPlacementSide,
          openTabs: [_StubTab('ספר א')],
        );
        await tester.pumpAndSettle();

        // רצועת כרטיסיות אחת בלבד: בצד, או בשורה שמתחת לסרגל הכותרת.
        expect(
          find.byType(VerticalReadingTabStrip).hitTestable(),
          onSide ? findsOneWidget : findsNothing,
        );
        expect(
          find
              .descendant(
                of: find.byType(CustomTitleBar),
                matching: find.byType(ReadingTabStrip),
              )
              .hitTestable(),
          onSide ? findsNothing : findsOneWidget,
        );
      });
    }
  });

  testWidgets(
    'מעבר לעיון וחזרה אינו מזיז את פס הגלילה של הספרייה (issue #4173)',
    (tester) async {
      final folder = Category(
        title: 'תיקייה',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [for (var i = 0; i < 300; i++) TextBook(title: 'ספר $i')],
        parent: null,
      );
      final library = Library(categories: [folder]);
      folder.parent = library;
      final harness = await _pumpMainWindow(
        tester,
        Future.value(library),
        isLoading: false,
        size: const Size(1400, 900),
        tabsPlacement: SettingsRepository.readingTabsPlacementSide,
        openTabs: [_StubTab('ספר א')],
        initialScreen: Screen.library,
      );
      harness.libraryChanges.add(
        LibraryState(library: library, currentCategory: folder),
      );
      await tester.pumpAndSettle();
      final grid = find
          .descendant(
            of: find.byType(MyGridView, skipOffstage: false),
            matching: find.byType(Scrollable, skipOffstage: false),
          )
          .first;
      double thumb() =>
          (tester
                      .widget<CustomPaint>(
                        find
                            .descendant(
                              of: grid,
                              matching: find.byWidgetPredicate(
                                (w) =>
                                    w is CustomPaint &&
                                    w.foregroundPainter is ScrollbarPainter,
                                skipOffstage: false,
                              ),
                            )
                            .first,
                      )
                      .foregroundPainter!
                  as ScrollbarPainter)
              .getThumbScrollOffset();
      final position = tester.state<ScrollableState>(grid).position;
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      final before = thumb();

      // הספרייה נראית בכל פריים של ההחלקה, ביציאה ובחזרה.
      for (final screen in [Screen.reading, Screen.library]) {
        harness.navigationChanges.add(NavigationState(currentScreen: screen));
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(thumb(), before, reason: '${screen.name}, פריים $frame');
        }
        await tester.pumpAndSettle();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'בעיון עם כרטיסיות בצד פאנל הכלים ומוק הגרירה נמדדים ליד העמודה (issue #4173)',
    (tester) async {
      await _pumpMainWindow(
        tester,
        Future.value(Library(categories: [])),
        isLoading: false,
        size: const Size(1400, 900),
        tabsPlacement: SettingsRepository.readingTabsPlacementSide,
        openTabs: [_StubTab('ספר א')],
      );
      await tester.pumpAndSettle();
      final keys = AppWindowKeys.of(
        tester.element(find.byType(MainWindowScreen)),
      );
      ToolsLauncherController.instance.open(windowKeys: keys);
      await tester.pumpAndSettle();

      // ה-scrim של הכלים ואזור התוכן הם מסך העיון שליד העמודה, לא העמודה.
      final reading = tester.getRect(find.byType(ReadingScreen));
      final tools = find.ancestor(
        of: find.byType(ToolsLauncherPanel),
        matching: find.byType(ContextOverlayPanel),
      );
      expect(tester.getRect(tools), reading);
      final content =
          keys.windowContentBoundary.currentContext!.findRenderObject()!
              as RenderBox;
      expect(content.size, reading.size);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets('כרטיסייה צפה נשארת לחיצה מעל פאנל הכלים', (tester) async {
    await _pumpMainWindow(
      tester,
      Future.value(Library(categories: [])),
      isLoading: false,
      size: const Size(1400, 900),
      tabsPlacement: SettingsRepository.readingTabsPlacementSide,
      openTabs: [_StubTab('ספר א'), _StubTab('ספר ב כותרת ארוכה מאוד של ספר')],
      collapsedTabs: true,
    );
    await tester.pumpAndSettle();
    final strip = find.byType(VerticalReadingTabStrip);
    final keys = AppWindowKeys.of(
      tester.element(find.byType(MainWindowScreen)),
    );
    ToolsLauncherController.instance.open(windowKeys: keys);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getRect(strip).center);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.getRect(strip).width, greaterThan(100));
    final title = find.descendant(
      of: strip,
      matching: find.text('ספר ב כותרת ארוכה מאוד של ספר'),
    );
    final tabs = tester.element(strip).read<TabsBloc>();
    await tester.tapAt(tester.getCenter(title));
    await tester.pump();
    verify(() => tabs.add(const SetCurrentTab(1))).called(1);
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('פאנל כלים יחיד שומר מצב בזמן סגירה ומעבר בין עמודים', (
    tester,
  ) async {
    final harness = await _pumpMainWindow(
      tester,
      Future.value(Library(categories: [])),
      isLoading: false,
      size: const Size(1400, 900),
      tabsPlacement: SettingsRepository.readingTabsPlacementSide,
      openTabs: [_StubTab('ספר א')],
    );
    await tester.pumpAndSettle();
    final keys = AppWindowKeys.of(
      tester.element(find.byType(MainWindowScreen)),
    );
    State? overlayState;
    for (final screen in [
      Screen.library,
      Screen.settings,
      Screen.reading,
      Screen.search,
    ]) {
      ToolsLauncherController.instance.open(windowKeys: keys);
      await tester.pumpAndSettle();
      final tools = find.byType(ToolsLauncherPanel);
      final overlay = find.ancestor(
        of: tools,
        matching: find.byType(ContextOverlayPanel),
      );
      final key = tester.widget<ContextOverlayPanel>(overlay).key!;
      final keyedOverlay = find.byKey(key, skipOffstage: false);
      overlayState ??= tester.state(overlay);
      expect(tester.state(overlay), same(overlayState));
      final contentState = tester.state(tools);
      final search = find
          .descendant(of: tools, matching: find.byType(EditableText))
          .first;
      await tester.enterText(search, 'לוח');
      harness.navigationChanges.add(NavigationState(currentScreen: screen));
      await tester.pump();
      await tester.pump();
      expect(keyedOverlay, findsOneWidget);
      expect(tester.state(keyedOverlay), same(overlayState));
      expect(tester.widget<ContextOverlayPanel>(keyedOverlay).isOpen, isFalse);
      final closingTools = find.byType(ToolsLauncherPanel, skipOffstage: false);
      expect(tester.state(closingTools), same(contentState));
      final closingSearch = find
          .descendant(
            of: closingTools,
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false,
          )
          .first;
      final editable = tester.widget<EditableText>(closingSearch);
      expect(editable.controller.text, 'לוח');
      expect(editable.focusNode.hasFocus, isFalse);
      await tester.pumpAndSettle();
      expect(
        find.byType(ToolsLauncherPanel, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    ToolsLauncherController.instance.open(windowKeys: keys);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ToolsLauncherPanel, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

class _Harness {
  _Harness(
    this.libraryChanges,
    this.initialState,
    this.indexing,
    this.navigationChanges,
  );

  final StreamController<LibraryState> libraryChanges;
  final StreamController<NavigationState> navigationChanges;
  final LibraryState initialState;
  final _IndexingBloc indexing;
}

Future<_Harness> _pumpMainWindow(
  WidgetTester tester,
  Future<Library> catalog, {
  bool isLoading = true,
  Stream<IndexingState> indexingStates = const Stream.empty(),
  Size size = const Size(1200, 900),
  String tabsPlacement = SettingsRepository.readingTabsPlacementTop,
  List<OpenedTab> openTabs = const [],
  Screen initialScreen = Screen.reading,
  bool collapsedTabs = false,
}) async {
  await Settings.init(cacheProvider: MemoryCacheProvider());
  // כמו חלון שאינו בעל התהליך: בלי ניקוז הפעלות חיצוניות.
  if (ProcessDuties.current.isProcessOwner) {
    ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
    addTearDown(() => ProcessDuties.debugOverride = null);
  }
  DataRepository.instance.library = catalog;
  // הבדיקה מאזינה בעצמה לכשל; כאן רק מונעים שה-Future המקורי ידווח כלא מטופל.
  DataRepository.instance.library.ignore();
  // גודל ה-view ולא רק המשטח, כדי ש-MediaQuery יראה את החלון האמיתי.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final navigation = _NavigationBloc();
  final navigationChanges = StreamController<NavigationState>.broadcast();
  whenListen(
    navigation,
    navigationChanges.stream,
    initialState: NavigationState(currentScreen: initialScreen),
  );
  final focus = FocusRepository();
  final workStatus = WorkStatusCubit();
  final settings = _SettingsBloc();
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(
      isOfflineMode: true,
      readingTabsPlacement: tabsPlacement,
      readingTabsColumnCollapsed: collapsedTabs,
    ),
  );
  final indexing = _IndexingBloc();
  whenListen(indexing, indexingStates, initialState: IndexingInitial());
  final history = _HistoryBloc();
  whenListen(
    history,
    const Stream<HistoryState>.empty(),
    initialState: HistoryLoaded([]),
  );
  final initialState = LibraryState(
    library: Library(categories: []),
    isLoading: isLoading,
  );
  final libraryChanges = StreamController<LibraryState>.broadcast();
  final library = _LibraryBloc();
  whenListen(library, libraryChanges.stream, initialState: initialState);
  final tabs = _TabsBloc();
  whenListen(
    tabs,
    const Stream<TabsState>.empty(),
    initialState: TabsState(tabs: openTabs, currentTabIndex: 0),
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
      library,
      tabs,
      workspace,
      pluginSystem,
      libraryUpdate,
      workStatus,
    ]) {
      await bloc.close();
    }
    DataRepository.instance.invalidateLibraryCache();
    tester.view.reset();
  });
  const window = _FakeWindow(AppWindowId('test-window'));
  await tester.pumpWidget(
    AppWindowScope(
      controller: window,
      geometry: window,
      role: const AppWindowRole(isPrimaryView: false, openedWithTab: true),
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
  return _Harness(libraryChanges, initialState, indexing, navigationChanges);
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
