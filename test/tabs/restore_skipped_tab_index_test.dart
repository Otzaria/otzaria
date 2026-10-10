import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

Map<String, dynamic> pdfJson(String title) => PdfBookTab(
  book: PdfBook(title: title, path: '/tmp/$title.pdf'),
  pageNumber: 1,
).toJson();

/// טאב שהמפענח אינו מכיר, ולכן מדלגים עליו.
const Map<String, dynamic> unknownTab = {'type': 'FutureTab', 'title': 'x'};

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  void disposeTabs(List<OpenedTab> tabs) {
    for (final tab in tabs) {
      tab.dispose();
    }
  }

  Future<void> putSession(List<dynamic> tabs, int index) => sessions.save(
    UserStateSlot.single,
    tabsJson: jsonEncode(tabs),
    currentIndex: index,
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('restore_skipped_tab');
    MultiWindowService.debugSupportedOverride = false;
    database = UserStateDatabase.openAt(p.join(tempDir.path, 'user_state.db'));
    await database.database;
    sessions = WindowSessionStore(database: database);
  });

  tearDown(() async {
    database.close();
    MultiWindowService.debugSupportedOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'session restore keeps the active tab when an earlier tab is skipped',
    () async {
      await sessions.save(
        UserStateSlot.single,
        tabsJson: jsonEncode([
          unknownTab,
          pdfJson('A'),
          pdfJson('B'),
          pdfJson('C'),
        ]),
        currentIndex: 2,
      );
      final bloc = TabsBloc(repository: TabsRepository(sessions: sessions));
      addTearDown(bloc.close);
      bloc.add(LoadTabs());
      await bloc.stream.firstWhere((s) => s.tabs.isNotEmpty);

      expect(bloc.state.tabs.map((t) => t.title), ['A', 'B', 'C']);
      expect(bloc.state.currentTab!.title, 'B');
    },
  );

  test(
    'workspace restore keeps the active tab when an earlier tab is skipped',
    () {
      final ws = Workspace.fromJson({
        'id': 'w',
        'name': 'w',
        'tabs': [unknownTab, pdfJson('A'), pdfJson('B'), pdfJson('C')],
        'currentTab': 2,
      });

      expect(ws.tabs.map((t) => t.title), ['A', 'B', 'C']);
      expect(ws.tabs[ws.activeTabIndex].title, 'B');
    },
  );

  test(
    'workspace restore falls back to the previous tab when the active one is skipped',
    () {
      final ws = Workspace.fromJson({
        'id': 'w',
        'name': 'w',
        'tabs': [pdfJson('A'), unknownTab, pdfJson('B')],
        'currentTab': 1,
      });

      expect(ws.tabs[ws.activeTabIndex].title, 'A');
    },
  );

  test(
    'session and workspace map every skipped-tab pattern and invalid index',
    () async {
      final repository = TabsRepository(sessions: sessions);
      for (var mask = 0; mask < 16; mask++) {
        final raw = List.generate(
          4,
          (i) => mask & (1 << i) == 0 ? pdfJson('$i') : unknownTab,
        );
        final kept = [
          for (var i = 0; i < 4; i++)
            if (mask & (1 << i) == 0) i,
        ];
        for (final index in [-3, -1, 0, 1, 2, 3, 4, 7]) {
          await putSession(raw, index);
          final tabs = repository.loadTabs();
          final mapped = repository.loadCurrentTabIndex();
          final workspace = Workspace.fromJson({
            'name': 'w',
            'tabs': raw,
            'currentTab': index,
          });
          final expected = kept.isEmpty
              ? null
              : kept.where((i) => i <= index).lastOrNull ?? kept.first;
          expect(
            tabs.isEmpty ? null : tabs[mapped].title,
            expected?.toString(),
          );
          expect(
            workspace.tabs.isEmpty
                ? null
                : workspace.tabs[workspace.activeTabIndex].title,
            expected?.toString(),
          );
          disposeTabs(tabs);
          disposeTabs(workspace.tabs);
        }
      }
    },
  );

  for (final index in [-0x8000000000000000, 0x7fffffffffffffff]) {
    test('session and workspace restore a bounded index from $index', () async {
      final raw = [unknownTab, pdfJson('A'), pdfJson('B'), unknownTab];
      await putSession(raw, index);
      final repository = TabsRepository(sessions: sessions);
      final tabs = repository.loadTabs();
      addTearDown(() => disposeTabs(tabs));
      final workspace = Workspace.fromJson({
        'name': 'w',
        'tabs': raw,
        'currentTab': index,
      });
      addTearDown(() => disposeTabs(workspace.tabs));
      final expected = index < 0 ? 'A' : 'B';

      expect(tabs[repository.loadCurrentTabIndex()].title, expected);
      expect(workspace.tabs[workspace.activeTabIndex].title, expected);
    });

    test(
      'empty and entirely skipped lists resolve to zero with $index',
      () async {
        final repository = TabsRepository(sessions: sessions);
        for (final raw in [
          <dynamic>[],
          [unknownTab, unknownTab],
        ]) {
          await putSession(raw, index);
          expect(repository.loadTabs(), isEmpty);
          expect(repository.loadCurrentTabIndex(), 0);
          final workspace = Workspace.fromJson({
            'name': 'w',
            'tabs': raw,
            'currentTab': index,
          });
          expect(workspace.tabs, isEmpty);
          expect(workspace.activeTabIndex, 0);
        }
      },
    );

    test(
      'full and index-only saves clamp $index without changing tabs',
      () async {
        final repository = TabsRepository(sessions: sessions);
        final tabs = [
          PdfBookTab(
            book: PdfBook(title: 'A', path: '/tmp/A.pdf'),
            pageNumber: 1,
          ),
          PdfBookTab(
            book: PdfBook(title: 'B', path: '/tmp/B.pdf'),
            pageNumber: 1,
          ),
        ];
        addTearDown(() => disposeTabs(tabs));
        final expected = index < 0 ? 0 : 1;

        await repository.saveTabs(tabs, index);
        final original = sessions.loadOpened(UserStateSlot.single)!;
        expect(original.currentIndex, expected);
        await repository.saveCurrentTabIndex(tabs, index);
        await repository.flushPendingWrites();
        final saved = sessions.loadOpened(UserStateSlot.single)!;
        expect(saved.currentIndex, expected);
        expect(saved.tabsJson, original.tabsJson);
        await repository.saveTabs([], index);
        expect(sessions.loadOpened(UserStateSlot.single)!.currentIndex, 0);
      },
    );
  }

  test(
    'filtering and nested-split expansion preserve the active split and side',
    () async {
      Map<String, dynamic> split(
        Map<String, dynamic> right,
        Map<String, dynamic> left,
      ) => {'type': 'CombinedTab', 'rightTab': right, 'leftTab': left};
      final raw = [
        unknownTab,
        split(pdfJson('A'), split(pdfJson('B'), pdfJson('C'))),
        split(pdfJson('D'), pdfJson('E')),
        pdfJson('F'),
      ];
      await putSession(raw, 2);
      final repository = TabsRepository(sessions: sessions);
      final restored = flattenRestoredSplits(
        repository.loadTabs(),
        currentIndex: repository.loadCurrentTabIndex(),
      );
      addTearDown(() => disposeTabs(restored.tabs));
      final workspace = Workspace.fromJson({
        'name': 'w',
        'tabs': raw,
        'currentTab': 2,
        'activePane': 'left',
      });
      addTearDown(() => disposeTabs(workspace.tabs));

      expect(
        (restored.tabs[restored.currentIndex] as CombinedTab).leftTab.title,
        'E',
      );
      expect(
        paneForSide(
          workspace.tabs[workspace.activeTabIndex],
          workspace.activePane,
        )?.title,
        'E',
      );
    },
  );
}
