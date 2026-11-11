import 'dart:async';
import 'dart:io';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_focus_sync.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/multiview/view_window_scope.dart';
import 'package:otzaria/core/windowing/window_title_sync.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' show sqlite3;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../../../helpers/memory_settings_cache.dart';
import '../../../test_helpers/fake_view_window.dart';
import '../../../test_helpers/second_test_view.dart';

class _RuntimeRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

class _RuntimeController extends Fake implements InAppWebViewController {
  final events = <String>[];
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    events.add(source);
    return null;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> setMemoryUsageTargetLevel(MemoryUsageTargetLevel level) async {}
  @override
  Future<void> setAllMediaPlaybackSuspended({required bool suspended}) async {}
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}

void main() {
  late Directory tmp;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('view_window_scope_');
    UserStateDatabase.instance.overridePath('${tmp.path}/user_state.db');
    UserStateDatabase.debugWriteInline = true;
    MultiViewMode.debugOverride = true;
  });

  tearDown(() {
    MultiViewMode.debugOverride = false;
    AppWindowKeys.resetForTest();
    LastActiveWindow.resetForTest();
    UserStateDatabase.instance.close();
    UserStateDatabase.debugWriteInline = false;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows עלול להחזיק את הקובץ עוד רגע; תיקיית temp בלבד.
    }
  });

  /// התוכן של כל חלון: MaterialApp עם ה-navigator של החלון, כמו ב-`App`.
  Future<(Map<int, BuildContext>, BuildContext Function())> pumpHost(
    WidgetTester tester,
    ViewWindowRegistry registry, {
    ViewWindowCloseFlowFactory? closeFlow,
  }) async {
    final contexts = <int, BuildContext>{};
    late BuildContext mainContext;
    await tester.pumpWidget(
      AppScopeProviders(
        settingsRepository: SettingsRepository(),
        child: MultiViewHost(
          registry: registry,
          contentBuilder: (context, entry) => ViewWindowScope(
            entry: entry,
            closeFlow:
                closeFlow ?? (entry) => ViewWindowCloseFlow(entry: entry),
            child: Builder(
              builder: (context) => MaterialApp(
                navigatorKey: AppWindowKeys.of(context).navigator,
                home: Builder(
                  builder: (context) {
                    contexts[entry.slot] = context;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          child: Builder(
            builder: (context) {
              mainContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return (contexts, () => mainContext);
  }

  testWidgets('מזעור חלון Dart משהה רק את התוספים שלו', (tester) async {
    final runtime = PluginRuntimeDispatcher.instance;
    runtime.resetVisibilityForTesting();
    final windows = FakeViewWindows(tester);
    await pumpHost(tester, windows.registry);
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump();
    const keyA = (pluginId: 'minimize.test', instanceId: 'a');
    const keyB = (pluginId: 'minimize.test', instanceId: 'b');
    runtime.registerController(
      keyA.pluginId,
      _RuntimeController(),
      instanceId: 'a',
      viewId: 0,
    );
    runtime.registerController(
      keyB.pluginId,
      _RuntimeController(),
      instanceId: 'b',
      viewId: b.handle.view.viewId,
    );
    runtime.setVisiblePluginInstances({keyA});
    runtime.setVisiblePluginInstances({keyB}, viewId: b.handle.view.viewId);
    await tester.pump();
    windows.stubOf(b)
      ..minimized = true
      ..notify();
    await tester.pump();
    await tester.pump();
    expect(runtime.isInstanceShown(keyA), isTrue);
    expect(runtime.isInstanceShown(keyB), isFalse);
    windows.stubOf(b)
      ..minimized = false
      ..notify();
    await tester.pump();
    await tester.pump();
    expect(runtime.isInstanceShown(keyB), isTrue);
    runtime.unregisterController(keyA.pluginId, instanceId: 'a');
    runtime.unregisterController(keyB.pluginId, instanceId: 'b');
    runtime.resetVisibilityForTesting();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('תפריט בחלון ב נשאר במופע ב גם כשבחירת הטקסט ממתינה', (
    tester,
  ) async {
    final runtime = PluginRuntimeDispatcher.instance;
    runtime.resetVisibilityForTesting();
    runtime.repositoryForTesting = _RuntimeRepo();
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(tester, windows.registry);
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump();
    final aController = _RuntimeController();
    final bController = _RuntimeController();
    const pid = 'context.scope';
    runtime.registerController(pid, aController, instanceId: 'a', viewId: 0);
    runtime.registerController(
      pid,
      bController,
      instanceId: 'b',
      viewId: b.handle.view.viewId,
    );
    runtime.setVisiblePluginInstances({(pluginId: pid, instanceId: 'a')});
    runtime.setVisiblePluginInstances({
      (pluginId: pid, instanceId: 'b'),
    }, viewId: b.handle.view.viewId);
    await tester.pump();
    const item = PluginContextMenuItem(
      id: 'lookup',
      label: 'lookup',
      onClickEvent: 'scope.clicked',
    );
    final registry = ContextMenuRegistry.instance;
    registry.register(pid, item, instanceId: 'a');
    registry.register(pid, item, instanceId: 'b');
    final text = Completer<String>();
    final menu = buildPluginContextMenuSection(
      context: 'reader-selection',
      selection: const {},
      menuContext: contexts[b.slot]!,
      records: [(pid, item)],
      resolveSelectedText: () => text.future,
    );
    aController.events.clear();
    bController.events.clear();
    menu.last.onTap!();
    AppWindowKeys.activateWindow(AppWindowId.primary);
    text.complete('טקסט מחלון ב');
    await tester.pump();
    await tester.pump();
    expect(
      aController.events.where((event) => event.contains('scope.clicked')),
      isEmpty,
    );
    expect(
      bController.events.where((event) => event.contains('scope.clicked')),
      hasLength(1),
    );
    registry.removeAll(pid);
    runtime.unregisterController(pid, instanceId: 'a');
    runtime.unregisterController(pid, instanceId: 'b');
    runtime.resetVisibilityForTesting();
    runtime.repositoryForTesting = PluginRegistryRepository();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('כל חלון Dart מקבל היקף, blocs, מפתחות ותפקיד משלו', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(tester, windows.registry);
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');

    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump();

    final ctxA = contexts[a.slot]!;
    final ctxB = contexts[b.slot]!;
    expect(a.id, const AppWindowId('window-view-2'));
    expect(View.of(ctxA), same(a.handle.view));
    expect(View.of(ctxB), same(b.handle.view));

    // בקר ומפתחות של החלון, לא של החלון הראשי.
    expect(AppWindowScope.controllerOf(ctxA), same(a.controller));
    expect(AppWindowScope.geometryOf(ctxB), same(b.controller));
    expect(AppWindowKeys.of(ctxA), same(a.keys));
    expect(AppWindowKeys.of(ctxB), same(b.keys));

    final roleA = AppWindowScope.roleOf(ctxA);
    expect(roleA.isViewWindow, isTrue);
    expect(roleA.isPrimaryView, isFalse);
    expect(roleA.openedWithTab, isTrue);
    expect(AppWindowScope.roleOf(ctxB).openedWithTab, isFalse);

    // עבודת התהליך והתוספים שברקע נשארות בחלון הראשי.
    final duties = ProcessDuties.of(ctxA);
    expect(duties, same(ViewWindowScope.duties));
    expect(duties.isProcessOwner, isFalse);
    expect(duties.hostsPluginBackground, isFalse);

    // הספק עצל: ה-bloc נוצר בקריאה, והאירועים שלו מטופלים בפריים הבא.
    final tabsA = ctxA.read<TabsBloc>();
    final tabsB = ctxB.read<TabsBloc>();
    await tester.pump();
    expect(identical(tabsA, tabsB), isFalse);
    expect(tabsA.state.tabs, [same(tab)]);
    expect(tabsB.state.tabs, isEmpty);
    expect(a.takeInitialTab(), isNull, reason: 'נצרכת פעם אחת');

    final pluginsA = ctxA.read<PluginSystemBloc>();
    final pluginsB = ctxB.read<PluginSystemBloc>();
    expect(pluginsA.toolbarRegistry, isNotNull);
    expect(pluginsA.toolbarRegistry, isNot(same(pluginsB.toolbarRegistry)));
    expect(
      (pluginsA.declarativeHost as DeclarativePluginHostService)
          .toolbarBinding
          .toolbarRegistry,
      same(pluginsA.toolbarRegistry),
    );

    final focusA = ctxA.read<FocusRepository>();
    expect(focusA, same(FocusRepository.forWindow(a.keys)));
    expect(identical(focusA, ctxB.read<FocusRepository>()), isFalse);
    expect(identical(focusA, FocusRepository.current), isFalse);

    // תיקוני הקלט של ה-runner הותקנו לכל חלון.
    expect(windows.native.hooked, [a.handle.hwnd, b.handle.hwnd]);
    // הכותרת הוסרה פעם אחת לכל חלון, ובנייה מחדש אינה חוזרת על זה.
    expect(windows.native.frameless, [a.handle.hwnd, b.handle.hwnd]);
    await tester.pump();
    expect(windows.native.frameless, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('מצב מסך מלא של חלון חדש נקרא מהחלון ולא מהגדרות חלון אחר', (
    tester,
  ) async {
    await Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, true);
    addTearDown(
      () => Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, false),
    );
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(tester, windows.registry);
    final regular = windows.registry.open(size: const Size(800, 600))!;
    final fullscreen = windows.registry.open(size: const Size(800, 600))!;
    windows.stubOf(fullscreen).fullscreen = true;
    await tester.pump();
    expect(
      contexts[regular.slot]!.read<WindowFullscreenCubit>().state,
      isFalse,
    );
    expect(
      contexts[fullscreen.slot]!.read<WindowFullscreenCubit>().state,
      isTrue,
    );
    expect(Settings.getValue<bool>(SettingsRepository.keyIsFullscreen), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('הכותרת נשלחת לחלון שה-context יושב בו', (tester) async {
    final windows = FakeViewWindows(tester);
    final (contexts, mainContext) = await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();

    expect(WindowTitleSync.of(mainContext()), same(WindowTitleSync.current));
    final syncA = WindowTitleSync.of(contexts[a.slot]!);
    expect(identical(syncA, WindowTitleSync.of(contexts[b.slot]!)), isFalse);

    await syncA.sync('בראשית', tabCount: 2);
    expect(windows.stubOf(a).titles, ['בראשית (2) — אוצריא']);
    expect(windows.stubOf(b).titles, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('הפעלת חלון מעדכנת את החלון הפעיל ואת AppWindowKeys.current', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    expect(LastActiveWindow.id, AppWindowId.primary);

    windows.stubOf(b)
      ..activated = true
      ..notify();
    expect(LastActiveWindow.id, b.id);
    expect(AppWindowKeys.current, same(b.keys));

    windows.stubOf(b)
      ..activated = false
      ..notify();
    windows.stubOf(a)
      ..activated = true
      ..notify();
    expect(LastActiveWindow.id, a.id);
    expect(AppWindowKeys.current, same(a.keys));

    // הודעה מחלון שאינו ב-foreground אינה מפעילה אותו.
    AppWindowKeys.activateWindow(AppWindowId.primary);
    windows.stubOf(a)
      ..activated = false
      ..notify();
    expect(LastActiveWindow.id, AppWindowId.primary);
    expect(AppWindowKeys.current.id, AppWindowId.primary);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('macOS: אירוע הפוקוס של התצוגה מפעיל את החלון שלה', (
    tester,
  ) async {
    addTearDown(ViewFocusSync.resetForTest);
    final windows = FakeViewWindows(tester);
    await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    void focusEvent(ViewWindowEntry entry, ViewFocusState state) =>
        tester.binding.handleViewFocusChanged(
          ViewFocusEvent(
            viewId: entry.handle.view.viewId,
            state: state,
            direction: ViewFocusDirection.undefined,
          ),
        );

    // Windows/Linux: ההפעלה לפי הבקר בלבד.
    ViewFocusSync.debugMacOSOverride = false;
    focusEvent(b, ViewFocusState.focused);
    expect(AppWindowKeys.current.id, AppWindowId.primary);

    ViewFocusSync.debugMacOSOverride = true;
    focusEvent(b, ViewFocusState.focused);
    expect(AppWindowKeys.current, same(b.keys));
    expect(LastActiveWindow.id, b.id);

    focusEvent(a, ViewFocusState.unfocused);
    expect(AppWindowKeys.current, same(b.keys));
    focusEvent(a, ViewFocusState.focused);
    expect(AppWindowKeys.current, same(a.keys));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ESC בחלון Dart שחזר לפוקוס אינו סוגר תפריט הקשר בראשי', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    final menuKey = GlobalKey<AppContextMenuRegionState>();
    final mainWindow = _FakeWindow();
    await tester.pumpWidget(
      AppScopeProviders(
        settingsRepository: SettingsRepository(),
        child: MultiViewHost(
          registry: windows.registry,
          contentBuilder: (context, entry) => ViewWindowScope(
            entry: entry,
            child: const SizedBox.shrink(),
          ),
          child: AppWindowScope(
            controller: mainWindow,
            geometry: mainWindow,
            keys: AppWindowKeys.byId(AppWindowId.primary),
            child: MaterialApp(
              home: Scaffold(
                body: AppContextMenuRegion(
                  key: menuKey,
                  menuBuilder: (_, _) => [
                    AppContextMenuEntry(label: 'פריט בתפריט', onTap: () {}),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    final stubB = windows.stubOf(b);
    stubB
      ..activated = true
      ..notify();
    expect(AppWindowKeys.current, same(b.keys));

    // לחיצה על הראשי: ב-WA_INACTIVE של החלון הוא עוד ה-foreground.
    stubB.notify();
    AppWindowKeys.activateWindow(AppWindowId.primary);
    stubB.activated = false;
    await menuKey.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(find.text('פריט בתפריט'), findsOneWidget);

    // חזרה לחלון Dart ו-ESC בו: התפריט בראשי נשאר.
    stubB
      ..activated = true
      ..notify();
    expect(AppWindowKeys.current, same(b.keys));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('פריט בתפריט'), findsOneWidget);

    // ESC בראשי עצמו סוגר אותו.
    stubB.activated = false;
    AppWindowKeys.activateWindow(AppWindowId.primary);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('פריט בתפריט'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('היסטוריה ושולחנות שנכתבו בחלון אחד נטענים מחדש בשני', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    final historyA = contexts[a.slot]!.read<HistoryBloc>();
    final historyB = contexts[b.slot]!.read<HistoryBloc>();
    final workspacesA = contexts[a.slot]!.read<WorkspaceBloc>();
    final workspacesB = contexts[b.slot]!.read<WorkspaceBloc>();
    await tester.pump(const Duration(milliseconds: 200));

    final beforeB = historyB.state;
    historyA.add(ClearHistory());
    await tester.pump(const Duration(milliseconds: 200));
    // החלון השני טען מחדש (מצב חדש), אף שהוא עצמו לא שינה דבר.
    expect(historyA.state, isA<HistoryLoaded>());
    expect(historyB.state, isA<HistoryLoaded>());
    expect(identical(historyB.state, beforeB), isFalse);

    // כתיבה שאינה של אף חלון (שחזור גיבוי) מגיעה לשניהם.
    // בלי await: ההמתנה נעשית ב-pump, שמריץ את המשימות של אזור הבדיקה.
    unawaited(
      WorkspaceRepository().mutateWorkspaces(
        (current) => [
          ...current,
          Workspace(name: 'עיון', tabs: const [], activeTabIndex: 0),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(workspacesA.state.workspaces.map((w) => w.name), contains('עיון'));
    expect(workspacesB.state.workspaces.map((w) => w.name), contains('עיון'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('הגבולות נשמרים למשבצת החלון לפי ה-DPR של התצוגה שלו', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    (a.handle.view as SecondTestView).devicePixelRatio = 2.0;
    windows.native.rects[a.handle.hwnd!] = const Rect.fromLTWH(
      200,
      100,
      1600,
      1200,
    );

    windows.stubOf(a).notify();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final session = await WindowSessionStore.instance.load(a.slot);
    final bounds = WindowBounds.decode(session?.boundsJson)!;
    expect(bounds.left, 100);
    expect(bounds.top, 50);
    expect(bounds.width, 800);
    expect(bounds.height, 600);
    expect(bounds.dpr, 2.0);
    expect(await WindowSessionStore.instance.load(1), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('סגירה: ביטול משאיר את החלון; אישור מוחק סשן, הורס ומפרק', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    var allow = false;
    final asked = <List<OpenedTab>>[];
    final (contexts, _) = await pumpHost(
      tester,
      windows.registry,
      closeFlow: (entry) => ViewWindowCloseFlow(
        entry: entry,
        opener: ViewWindowOpener(
          registry: windows.registry,
          native: windows.native,
        ),
        confirm: (context, tabs) async {
          asked.add(tabs);
          return allow;
        },
      ),
    );
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');
    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final tabsA = contexts[a.slot]!.read<TabsBloc>();
    await tester.pump(const Duration(seconds: 1));
    expect(await WindowSessionStore.instance.load(a.slot), isNotNull);
    windows.stubOf(a)
      ..activated = true
      ..notify();
    expect(AppWindowKeys.current, same(a.keys));

    // X מהמערכת → מסלול הסגירה של החלון הזה, עם הכרטיסיות שלו.
    windows.handleOf(a).requestClose();
    await tester.pump();
    expect(asked.single, [same(tab)]);
    expect(windows.stubOf(a).destroyed, isFalse);
    expect(windows.registry.windows, [a, b]);

    allow = true;
    await a.controller.close();
    await tester.pump();
    expect(windows.stubOf(a).destroyed, isTrue);
    expect(windows.registry.windows, [b]);
    expect(a.tabsSession.slot, isNull);
    expect(find.byType(View), findsNWidgets(2));
    expect(AppWindowKeys.current, isNot(same(a.keys)));

    await tester.pump(const Duration(seconds: 1));
    expect(windows.stubOf(a).disposed, isTrue);
    expect(tabsA.isClosed, isTrue);
    // סגירת ה-blocs אינה יוצרת מחדש את הסשן שנמחק.
    expect(await WindowSessionStore.instance.load(a.slot), isNull);
    expect(windows.stubOf(b).destroyed, isFalse);

    // חלון שנהרס כבר אינו רשום: הפעלה לפי המזהה שלו אינה מחליפה מפתחות.
    AppWindowKeys.activateWindow(a.id);
    expect(AppWindowKeys.current, isNot(same(a.keys)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('סגירת חלון Dart מסיימת את סשני התיקון בכרטיסיות שלו', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    final service = PluginCorrectionSessionService.instance
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(db.close);
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(
      tester,
      windows.registry,
      closeFlow: (entry) => ViewWindowCloseFlow(
        entry: entry,
        opener: ViewWindowOpener(
          registry: windows.registry,
          native: windows.native,
        ),
        confirm: (_, _) async => true,
        flush: () async {},
      ),
    );
    final tab = TextBookTab(book: TextBook(title: 'ברכות'), index: 0);
    final tabId = PluginCorrectionSessionService.tabIdFor(tab);
    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    await tester.pump();
    final tabsA = contexts[a.slot]!.read<TabsBloc>();
    await tester.pump(const Duration(seconds: 1));
    expect(tabsA.state.tabs, [same(tab)]);
    final ended = <Object?>[];
    await tester.runAsync(
      () => service.begin(
        owner: 'p',
        tabId: tabId,
        bookId: 'ברכות',
        bookUid: 'id:1',
        libraryVersion: 'v1',
        loadSource: (_) async => 'מקור',
        onEvent: (topic, payload) {
          if (topic == 'reader.correctionSessionEnded') {
            ended.add(payload['reason']);
          }
        },
      ),
    );
    expect(service.hasSessionForTab(tabId), isTrue);

    await a.controller.close();
    await tester.pump();
    expect(windows.stubOf(a).destroyed, isTrue);
    // מסתיים מיד ובסיבה window_closed, לפני שחרור הכרטיסיות.
    expect(service.hasSessionForTab(tabId), isFalse);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 4));
    expect(ended, ['window_closed']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('סגירת חלון Dart משחררת את הכרטיסיות שלו', (tester) async {
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(
      tester,
      windows.registry,
      closeFlow: (entry) => ViewWindowCloseFlow(
        entry: entry,
        opener: ViewWindowOpener(
          registry: windows.registry,
          native: windows.native,
        ),
        confirm: (_, _) async => true,
        flush: () async {},
      ),
    );
    final tab = TextBookTab(book: TextBook(title: 'שבת'), index: 0);
    // ה-bloc מאזין לזרם סטטי; בלי שחרור הוא והכרטיסיה נשארים חיים.
    final bloc = tab.bloc;
    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    await tester.pump();
    final tabsA = contexts[a.slot]!.read<TabsBloc>();
    await tester.pump(const Duration(seconds: 1));
    expect(tabsA.state.tabs, [same(tab)]);

    await a.controller.close();
    await tester.pump();
    expect(windows.stubOf(a).destroyed, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(bloc.isClosed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
