import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_navigation_bloc.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _StubHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _StubHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
}

class _PluginRepository extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

class _PluginController extends Fake implements InAppWebViewController {
  final List<String> events = [];

  @override
  Future<void> resume() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    events.add(source);
    return null;
  }
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}

class _CountingOpener extends Fake implements WindowOpener {
  int emptyWindows = 0;
  int restoredWindows = 0;

  @override
  Future<bool> openEmptyWindow() async {
    emptyWindows++;
    return true;
  }

  @override
  Future<bool> restoreLastClosedWindow() async {
    restoredWindows++;
    return true;
  }
}

/// חלון Dart אחד: TabsBloc משלו מתחת ל-scope עם המפתחות שלו.
class _Window {
  _Window(String id) : keys = AppWindowKeys(id: AppWindowId(id));

  final AppWindowKeys keys;
  final TabsBloc tabs = TabsBloc(repository: _FakeTabsRepository());
  final _StubHistoryBloc history = _StubHistoryBloc();
  final StubNavigationBloc navigation = StubNavigationBloc();

  Future<void> dispose() async {
    await tabs.close();
    await history.close();
    await navigation.close();
  }

  /// [scoped] false — scope בלי מפתחות, כמו חלון יחיד בלי הדגל.
  Widget build(
    SettingsBloc settings,
    _FakeWindow window, {
    bool scoped = true,
  }) => Expanded(
    child: AppWindowScope(
      controller: window,
      geometry: window,
      keys: scoped ? keys : null,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<HistoryBloc>.value(value: history),
          BlocProvider<NavigationBloc>.value(value: navigation),
          Provider<FocusRepository>.value(value: FocusRepository()),
        ],
        child: KeyboardShortcuts(
          onFindRefRequested: () {},
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    ),
  );
}

Future<void> _press(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final key in keys) {
    await tester.sendKeyDownEvent(key);
  }
  for (final key in keys.reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pump();
}

const _ctrlShiftT = [
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.keyT,
];

const _ctrlAltN = [
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.keyN,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSettingsBloc settings;
  late StreamController<SettingsState> settingsChanges;
  late _CountingOpener opener;
  late _Window a;
  late _Window b;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    ShortcutHelper.isMacForTesting = false;
    ShortcutHelper.isWindowsForTesting = false;
    RunnerWindowChannel.debugSupportedOverride = true;
    opener = _CountingOpener();
    WindowOpener.debugOverride = opener;
    settings = _MockSettingsBloc();
    settingsChanges = StreamController<SettingsState>.broadcast();
    whenListen(
      settings,
      settingsChanges.stream,
      initialState: SettingsState.initial().copyWith(
        shortcuts: const {
          'key-shortcut-restore-closed-tab': 'ctrl+shift+t',
          'key-shortcut-open-new-window': 'ctrl+alt+n',
        },
      ),
    );
  });

  tearDown(() async {
    await settingsChanges.close();
    AppWindowKeys.resetForTest();
    WindowOpener.debugOverride = null;
    RunnerWindowChannel.debugSupportedOverride = null;
    ShortcutHelper.isMacForTesting = null;
    ShortcutHelper.isWindowsForTesting = null;
  });

  /// ה-blocs נוצרים בתוך גוף הבדיקה, כדי שה-pump יריץ את האירועים שלהם.
  void createWindows() {
    a = _Window('a');
    b = _Window('b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    AppWindowKeys.register(a.keys);
    AppWindowKeys.register(b.keys);
  }

  Future<void> pumpWindows(WidgetTester tester) async {
    final window = _FakeWindow();
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [a.build(settings, window), b.build(settings, window)],
        ),
      ),
    );
    await tester.pump();
  }

  /// סוגר כרטיסיה בחלון [w], כך ש-Ctrl+Shift+T שם ישחזר אותה.
  Future<void> closeOneTab(WidgetTester tester, _Window w) async {
    final kept = SearchingTab('נשאר', 'א');
    final closed = SearchingTab('נסגר', 'ב');
    w.tabs.add(AddTab(kept));
    await tester.pump();
    w.tabs.add(AddTab(closed));
    await tester.pump();
    w.tabs.add(RemoveTab(closed));
    await tester.pump();
  }

  testWidgets('קיצור פקודת PDF נמסר למופע התוסף בחלון המקור', (tester) async {
    createWindows();
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בחלון ב', path: '/book.pdf'),
      pageNumber: 1,
    );
    b.tabs.add(AddTab(tab));
    await tester.pump();
    final dispatcher = PluginRuntimeDispatcher.instance;
    const pluginId = 'pdf.shortcut.window';
    final controllerA = _PluginController();
    final controllerB = _PluginController();
    dispatcher.repositoryForTesting = _PluginRepository();
    dispatcher.registerController(
      pluginId,
      controllerA,
      instanceId: 'a',
      viewId: -1,
    );
    dispatcher.registerController(
      pluginId,
      controllerB,
      instanceId: 'b',
      viewId: tester.view.viewId,
    );
    dispatcher.setVisiblePluginInstances({
      (pluginId: pluginId, instanceId: 'a'),
    }, viewId: -1);
    dispatcher.setVisiblePluginInstances({
      (pluginId: pluginId, instanceId: 'b'),
    }, viewId: tester.view.viewId);
    ShortcutValidator.registerPluginShortcuts({
      'key-shortcut-plugin-window-command': (
        pluginId: pluginId,
        shortcutId: 'window-command',
        label: 'פקודה בחלון',
        defaultKey: 'ctrl+shift+f12',
        command: 'window-command',
        contextMenuItemId: null,
      ),
    });
    addTearDown(() {
      ShortcutValidator.registerPluginShortcuts({});
      dispatcher.unregisterController(pluginId, instanceId: 'a');
      dispatcher.unregisterController(pluginId, instanceId: 'b');
      dispatcher.resetVisibilityForTesting();
      dispatcher.repositoryForTesting = PluginRegistryRepository();
      dispatcher.invalidatePlugin(pluginId);
    });
    await pumpWindows(tester);
    AppWindowKeys.activateWindow(b.keys.id);

    await _press(tester, [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.f12,
    ]);

    expect(
      controllerA.events.where((event) => event.contains('app.command')),
      isEmpty,
    );
    expect(
      controllerB.events.where(
        (event) =>
            event.contains('app.command') && event.contains('window-command'),
      ),
      hasLength(1),
    );
  });

  testWidgets('Ctrl+Alt+N בשני חלונות פותח חלון אחד בלבד', (tester) async {
    createWindows();
    await pumpWindows(tester);
    AppWindowKeys.activateWindow(b.keys.id);

    await _press(tester, _ctrlAltN);
    expect(opener.emptyWindows, 1);

    AppWindowKeys.activateWindow(a.keys.id);
    await _press(tester, _ctrlAltN);
    expect(opener.emptyWindows, 2);
  });

  testWidgets('Ctrl+Shift+T פועל רק בחלון הפעיל', (tester) async {
    createWindows();
    await closeOneTab(tester, a);
    await pumpWindows(tester);

    // B פעיל ואין לו כרטיסיה סגורה: משחזר חלון פעם אחת, ולא נוגע בכרטיסיות של A.
    AppWindowKeys.activateWindow(b.keys.id);
    await _press(tester, _ctrlShiftT);
    expect(opener.restoredWindows, 1);
    expect(a.tabs.state.tabs, hasLength(1));
    expect(a.tabs.hasRecentlyClosedTabs, isTrue);

    // A פעיל: משחזר את הכרטיסיה שלו, ו-B לא משחזר חלון בשמו.
    AppWindowKeys.activateWindow(a.keys.id);
    await _press(tester, _ctrlShiftT);
    expect(a.tabs.state.tabs, hasLength(2));
    expect(b.tabs.state.tabs, isEmpty);
    expect(opener.restoredWindows, 1);

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('macOS בלי handshake: הקיצור אינו פותח חלון ועובר הלאה', (
    tester,
  ) async {
    // ⚠️ בלי דריסה: כך נגזר חלון יחיד כשה-runner לא הפך את ריבוי התצוגות.
    RunnerWindowChannel.debugSupportedOverride = null;
    MultiViewMode.debugOverride = null;
    MultiViewMode.debugIsMacOS = true;
    addTearDown(() {
      MultiViewMode.debugOverride = false;
      MultiViewMode.debugResetMacRunner();
    });
    createWindows();
    AppWindowKeys.resetForTest();
    await tester.pumpWidget(
      MaterialApp(
        home: Row(children: [a.build(settings, _FakeWindow(), scoped: false)]),
      ),
    );
    await tester.pump();

    await _press(tester, _ctrlAltN);
    expect(opener.emptyWindows, 0);
  });

  testWidgets('חלון יחיד מטפל בקיצור גם בלי הפעלה מפורשת', (tester) async {
    // כמו בלי הדגל: רק הראשי רשום, והוא current תמיד.
    createWindows();
    AppWindowKeys.resetForTest();
    await tester.pumpWidget(
      MaterialApp(
        home: Row(children: [a.build(settings, _FakeWindow(), scoped: false)]),
      ),
    );
    await tester.pump();

    await _press(tester, _ctrlAltN);
    expect(opener.emptyWindows, 1);
  });
}
