import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../helpers/memory_settings_cache.dart';

/// "העבר לשולחן עבודה" מתפריט ההקשר, דרך הרצועה וה-blocs האמיתיים.
void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  for (final onSide in [false, true]) {
    final strip = onSide ? 'עמודה בצד' : 'רצועה עליונה';

    testWidgets(
      '$strip: שתי כרטיסיות נבחרות עוברות יחד לשולחן אחר (issue #3868)',
      (tester) async {
        final env = await _pumpStrip(tester, onSide: onSide);

        await _ctrlClick(tester, 'ספר ב');
        expect(env.tabsBloc.state.selectedTabs.map((t) => t.title), [
          'ספר א',
          'ספר ב',
        ]);

        await env.moveToTarget(
          tester,
          rightClickOn: 'ספר ב',
          snack: '2 כרטיסיות הועברו לשולחן העבודה "יעד"',
        );

        expect(env.tabsBloc.state.tabs.map((t) => t.title), ['ספר ג']);
        expect(env.targetTitles(), ['ספר ביעד', 'ספר א', 'ספר ב']);
        expect(env.sourceTitles(), ['ספר ג']);
      },
    );

    testWidgets(
      '$strip: כל הכרטיסיות עוברות בסדר הרצועה, לא בסדר הבחירה (issue #3868)',
      (tester) async {
        final env = await _pumpStrip(tester, onSide: onSide);

        await _ctrlClick(tester, 'ספר ג');
        await _ctrlClick(tester, 'ספר ב');

        await env.moveToTarget(
          tester,
          rightClickOn: 'ספר ג',
          snack: '3 כרטיסיות הועברו לשולחן העבודה "יעד"',
        );

        expect(env.tabsBloc.state.tabs, isEmpty);
        expect(env.targetTitles(), ['ספר ביעד', 'ספר א', 'ספר ב', 'ספר ג']);
        expect(env.sourceTitles(), isEmpty);
      },
    );

    testWidgets(
      '$strip: כרטיסיה שאינה בבחירה עוברת לבדה (issue #3868)',
      (tester) async {
        final env = await _pumpStrip(tester, onSide: onSide);

        await _ctrlClick(tester, 'ספר ב');

        await env.moveToTarget(
          tester,
          rightClickOn: 'ספר ג',
          snack: 'הכרטיסיה הועברה לשולחן העבודה "יעד"',
        );

        expect(env.tabsBloc.state.tabs.map((t) => t.title), [
          'ספר א',
          'ספר ב',
        ]);
        expect(env.targetTitles(), ['ספר ביעד', 'ספר ג']);
      },
    );

    testWidgets(
      '$strip: מידע שלא נשמר בכרטיסיה נבחרת אחרת — ביטול עוצר את כל ההעברה '
      '(issue #3868)',
      (tester) async {
        const key = (pluginId: 'p.editor', instanceId: 'inst-editor');
        PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
        addTearDown(
          () => PluginUnsavedChangesRegistry.instance.removeInstance(key),
        );
        final env = await _pumpStrip(
          tester,
          onSide: onSide,
          tabs: [
            ToolTab(
              toolId: key.pluginId,
              title: 'עורך',
              instanceId: key.instanceId,
            ),
            _StubTab('ספר ב'),
            _StubTab('ספר ג'),
          ],
        );
        await _ctrlClick(tester, 'ספר ב');

        // הלחיצה הימנית על "ספר ב"; המידע שלא נשמר הוא של "עורך".
        await env.chooseTarget(tester, rightClickOn: 'ספר ב');
        expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();
        expect(env.tabsBloc.state.tabs.map((t) => t.title), [
          'עורך',
          'ספר ב',
          'ספר ג',
        ]);
        expect(env.targetTitles(), ['ספר ביעד']);

        await env.chooseTarget(tester, rightClickOn: 'ספר ב');
        await tester.tap(find.text(unsavedChangesCloseAnyway));
        await tester.pumpAndSettle();
        expect(env.tabsBloc.state.tabs.map((t) => t.title), ['ספר ג']);
        expect(env.targetTitles(), ['ספר ביעד', 'עורך', 'ספר ב']);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
      },
    );
  }
}

Future<void> _ctrlClick(WidgetTester tester, String title) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.tap(find.text(title), warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

class _Env {
  _Env(this.tabsBloc, this.workspaces, this.source, this.target);

  final TabsBloc tabsBloc;
  final _MemoryWorkspaceRepository workspaces;
  final Workspace source;
  final Workspace target;

  List<String> _titlesOf(Workspace workspace) => workspaces.workspaces
      .firstWhere((w) => w.id == workspace.id)
      .tabs
      .map((t) => t.title)
      .toList();

  List<String> targetTitles() => _titlesOf(target);
  List<String> sourceTitles() => _titlesOf(source);

  /// קליק ימני על [rightClickOn] ← "העבר לשולחן עבודה" ← "יעד".
  Future<void> chooseTarget(
    WidgetTester tester, {
    required String rightClickOn,
  }) async {
    await tester.tapAt(
      tester.getCenter(find.text(rightClickOn)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('העבר לשולחן עבודה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(target.name));
    await tester.pumpAndSettle();
  }

  Future<void> moveToTarget(
    WidgetTester tester, {
    required String rightClickOn,
    required String snack,
  }) async {
    await chooseTarget(tester, rightClickOn: rightClickOn);
    expect(find.text(snack), findsOneWidget);
    // הודעת ההעברה נעלמת בטיימר.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }
}

Future<_Env> _pumpStrip(
  WidgetTester tester, {
  required bool onSide,
  List<OpenedTab>? tabs,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final tabsBloc = TabsBloc(
    repository: _MemoryTabsRepository(
      tabs ?? [_StubTab('ספר א'), _StubTab('ספר ב'), _StubTab('ספר ג')],
    ),
    disposeDelay: Duration.zero,
  )..add(LoadTabs());
  await tabsBloc.stream.firstWhere((s) => s.tabs.length == 3);

  final source = Workspace(name: 'מקור', tabs: const []);
  final target = Workspace(name: 'יעד', tabs: [_StubTab('ספר ביעד')]);
  final workspaces = _MemoryWorkspaceRepository([source, target], source.id);
  final workspaceBloc = WorkspaceBloc(repository: workspaces)
    ..add(LoadWorkspaces());
  await workspaceBloc.stream.firstWhere((s) => !s.isLoading);

  final settingsBloc = _StubSettingsBloc(
    SettingsState.initial().copyWith(
      readingTabsPlacement: onSide
          ? SettingsRepository.readingTabsPlacementSide
          : SettingsRepository.readingTabsPlacementTop,
    ),
  );
  final historyBloc = _StubHistoryBloc();
  final navigationBloc = _StubNavigationBloc(
    const NavigationState(currentScreen: Screen.reading),
  );
  final pluginSystemBloc = _StubPluginSystemBloc();
  addTearDown(() async {
    await tabsBloc.close();
    await workspaceBloc.close();
    await settingsBloc.close();
    await historyBloc.close();
    await navigationBloc.close();
    await pluginSystemBloc.close();
  });

  await tester.pumpWidget(
    AppWindowScope(
      controller: const WindowManagerAppWindowController(),
      geometry: const WindowManagerAppWindowController(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<PluginSystemBloc>.value(value: pluginSystemBloc),
          BlocProvider<WindowFullscreenCubit>(
            create: (_) =>
                WindowFullscreenCubit(initial: false, persist: (_) async {}),
          ),
        ],
        child: MaterialApp(
          navigatorKey: AppWindowKeys.current.navigator,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: onSide
                  ? const Row(
                      children: [
                        ReadingTabsSidePanel(show: true),
                        Expanded(child: SizedBox.expand()),
                      ],
                    )
                  : SizedBox(
                      width: 900,
                      child: CustomTitleBar(onReadingSettingsPressed: () {}),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Env(tabsBloc, workspaces, source, target);
}

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => _StubTab(title)..isPinned = isPinned;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

class _MemoryTabsRepository extends TabsRepository {
  _MemoryTabsRepository(this._tabs);

  final List<OpenedTab> _tabs;

  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => _tabs;

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}

class _MemoryWorkspaceRepository extends WorkspaceRepository {
  _MemoryWorkspaceRepository(List<Workspace> initial, this._activeId)
    : workspaces = List.of(initial);

  List<Workspace> workspaces;
  final String _activeId;

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async =>
      (List<Workspace>.of(workspaces), _activeId);

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) async {
    workspaces = List.of(apply(List.of(workspaces)));
    return List.of(workspaces);
  }

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {}
}

class _StubSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _StubSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _StubHistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _StubNavigationBloc(super.initialState);

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPluginSystemBloc extends Cubit<PluginSystemState>
    implements PluginSystemBloc {
  _StubPluginSystemBloc() : super(PluginSystemInitial());

  @override
  void add(PluginSystemEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
