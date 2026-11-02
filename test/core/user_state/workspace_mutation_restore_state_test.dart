import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (final concurrentWriter in [false, true]) {
    test(
      'workspace clone preserves restore state with external writer=$concurrentWriter',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'otzaria_workspace_mutation_',
        );
        final path = '${dir.path}/state.db';
        final db = UserStateDatabase.openAt(path);
        final lists = UserStateListStore(database: db);
        final repo = WorkspaceRepository(store: lists, slot: () => null);
        final restore = PluginRestoreStateStore.instance;
        final source = ToolTab(toolId: 'test.plugin', title: 'מקור');
        final sourceKey = (
          pluginId: source.toolId,
          instanceId: source.instanceId,
        );
        final fillers = [
          for (var i = 0; i < 63; i++)
            (pluginId: 'filler', instanceId: '$concurrentWriter-$i'),
        ];
        final clones = <ToolTab>[];
        try {
          await lists.write('workspaces', 'key-workspaces', [
            Workspace(id: 'w', name: 'שולחן', tabs: []).toJson(),
          ]);
          restore.set(sourceKey, {'important': 'saved draft'});
          for (final key in fillers) {
            restore.set(key, {'other': true});
          }
          expect(restore.length, 64);
          final other = sqlite3.open(path);
          var calls = 0;
          try {
            if (concurrentWriter) other.execute('BEGIN IMMEDIATE');
            final pending = repo.mutateWorkspaces((current) {
              calls++;
              final copy = source.clone() as ToolTab;
              clones.add(copy);
              return [
                current.single.withTabs(
                  tabs: [copy],
                  activeTabIndex: 0,
                  activePane: null,
                ),
              ];
            });
            if (concurrentWriter) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              other.execute(
                'UPDATE lists SET payload_json = ? WHERE box = ? AND key = ?',
                [
                  jsonEncode([
                    Workspace(id: 'w', name: 'שולחן עודכן', tabs: []).toJson(),
                  ]),
                  'workspaces',
                  'key-workspaces',
                ],
              );
              other.execute('COMMIT');
            }
            final saved = await pending;
            expect(
              saved.single.name,
              concurrentWriter ? 'שולחן עודכן' : 'שולחן',
            );
            final tab = saved.single.tabs.single as ToolTab;
            expect(
              tab.toJson()['pluginRestoreState'],
              jsonEncode({'important': 'saved draft'}),
            );
            final persisted =
                (await lists.read(
                      WorkspaceRepository.boxName,
                      WorkspaceRepository.workspacesKey,
                    )).single
                    as Map;
            expect(
              (persisted['tabs'] as List).single['pluginRestoreState'],
              jsonEncode({'important': 'saved draft'}),
            );
            expect(calls, 1);
          } finally {
            other.close();
          }
        } finally {
          source.dispose();
          for (final clone in clones) {
            clone.dispose();
          }
          for (final key in fillers) {
            restore.remove(key);
          }
          lists.dispose();
          await db.flushWrites();
          db.close();
          dir.deleteSync(recursive: true);
        }
      },
    );
  }
}
