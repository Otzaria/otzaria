import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../helpers/memory_settings_cache.dart';

// issue #2818: אותו ספר בשני שולחנות — המיקום של כל שולחן נשאר שלו.
final _beitza = TextBook(id: 42, title: 'ביצה');
final _beitzaPdf = PdfBook(title: 'ביצה', path: '/nonexistent/ביצה.pdf');

int _positionOf(OpenedTab tab) => switch (tab) {
  TextBookTab t => t.lines.captureAnchor()?.line ?? t.index,
  PdfBookTab p => p.pageNumber,
  _ => throw StateError('unexpected tab ${tab.runtimeType}'),
};

void _navigate(OpenedTab tab, int position) => switch (tab) {
  TextBookTab t => t.lines.scrollToLineOnNextAttach(position),
  PdfBookTab p => p.pageNumber = position,
  _ => throw StateError('unexpected tab ${tab.runtimeType}'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late UserStateDatabase database;
  late UserStateListStore store;
  late WorkspaceRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    dir = Directory.systemTemp.createTempSync('workspace_same_book_');
    database = UserStateDatabase.openAt('${dir.path}/state.db');
    UserStateDatabase.debugWriteInline = true;
    store = UserStateListStore(database: database);
    repository = WorkspaceRepository(
      store: store,
      sessions: WindowSessionStore(database: database),
      slot: () => 1,
    );
  });

  tearDown(() {
    store.dispose();
    database.close();
    UserStateDatabase.debugWriteInline = false;
    dir.deleteSync(recursive: true);
  });

  /// חלון אחד: TabsBloc חי ו-WorkspaceBloc מחוברים כמו ב-window_scope_providers.
  Future<_Window> openWindow() async {
    final tabs = TabsBloc(repository: _TabsRepository());
    final workspace = WorkspaceBloc(
      repository: repository,
      onWorkspaceTabsChanged: (restored, index, pane) async {
        final done = tabs.stream.firstWhere((s) => identical(s.tabs, restored));
        tabs.add(ReplaceAllTabs(restored, index, activePane: pane));
        await done;
      },
    )..add(LoadWorkspaces());
    final loaded = await workspace.stream.firstWhere((s) => !s.isLoading);
    // כמו בעלייה: הכרטיסיות החיות הן אלה של השולחן הפעיל.
    final session = loaded.activeWorkspace!.tabs.map(OpenedTab.from).toList();
    final seeded = tabs.stream.firstWhere((s) => identical(s.tabs, session));
    tabs.add(ReplaceAllTabs(session, 0));
    await seeded;
    final window = _Window(tabs, workspace);
    addTearDown(window.close);
    return window;
  }

  for (final kind in ['text', 'pdf']) {
    OpenedTab bookAt(int position) => kind == 'text'
        ? TextBookTab(book: _beitza, index: position)
        : PdfBookTab(book: _beitzaPdf, pageNumber: position);

    test('$kind: מעבר הלוך-חזור שומר מיקום נפרד לכל שולחן, גם אחרי הפעלה '
        'מחדש', () async {
      final a = Workspace(name: 'סדר א', tabs: [bookAt(25)]);
      final b = Workspace(name: 'סדר ב', tabs: [bookAt(3)]);
      await repository.replaceWorkspaces([a, b], b.id);
      final window = await openWindow();

      await window.switchTo(a.id);
      expect(_positionOf(window.liveBook), 25);
      _navigate(window.liveBook, 26);

      await window.switchTo(b.id);
      expect(_positionOf(window.liveBook), 3);
      _navigate(window.liveBook, 4);

      await window.switchTo(a.id);
      expect(_positionOf(window.liveBook), 26);

      await window.switchTo(b.id);
      expect(_positionOf(window.liveBook), 4);

      await window.close();
      final restarted = await openWindow();
      await restarted.switchTo(a.id);
      expect(_positionOf(restarted.liveBook), 26);
      await restarted.switchTo(b.id);
      expect(_positionOf(restarted.liveBook), 4);
    });

    test(
      '$kind: שולחן שנוצר מהכרטיסיות הפתוחות אינו חולק מיקום עם המקור',
      () async {
        final a = Workspace(name: 'סדר א', tabs: [bookAt(25)]);
        await repository.replaceWorkspaces([a], a.id);
        final window = await openWindow();
        await window.switchTo(a.id);

        final added = window.workspace.stream.firstWhere(
          (s) => s.workspaces.length == 2,
        );
        window.workspace.add(
          AddWorkspace(
            name: 'סדר ב',
            tabs: window.tabs.state.tabs,
            currentTabIndex: 0,
          ),
        );
        final bId = (await added).workspaces.last.id;

        _navigate(window.liveBook, 26);
        await window.switchTo(bId);
        expect(_positionOf(window.liveBook), 25);
        _navigate(window.liveBook, 3);

        await window.switchTo(a.id);
        expect(_positionOf(window.liveBook), 26);
        await window.switchTo(bId);
        expect(_positionOf(window.liveBook), 3);
      },
    );
  }
}

class _Window {
  _Window(this.tabs, this.workspace);

  final TabsBloc tabs;
  final WorkspaceBloc workspace;
  bool _closed = false;

  OpenedTab get liveBook => tabs.state.tabs.single;

  /// כמו workspace_switcher_dialog: שומר את הכרטיסיות החיות ועובר.
  Future<void> switchTo(String id) async {
    final done = workspace.stream.firstWhere((s) => s.activeWorkspaceId == id);
    workspace.add(
      SwitchToWorkspace(
        sourceWorkspaceId: workspace.state.activeWorkspaceId,
        targetWorkspaceId: id,
        readCurrentTabs: () => (
          tabs: tabs.state.tabs,
          activeTabIndex: tabs.state.currentTabIndex,
          activePane: tabs.state.activePaneSide,
        ),
      ),
    );
    await done;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await workspace.close();
    await tabs.close();
  }
}

class _TabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => [];
  @override
  int loadCurrentTabIndex() => 0;
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
  @override
  Future<void> flushPendingWrites() async {}
}
