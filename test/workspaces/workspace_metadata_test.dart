import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

class _MetadataSessions extends WindowSessionStore {
  _MetadataSessions({required super.database});

  @override
  Future<WindowSession?> load(int slot) =>
      throw StateError('טעינת שולחנות אינה זקוקה לכרטיסיות הסשן');
}

void main() {
  late Directory directory;
  late UserStateDatabase database;
  late UserStateListStore lists;
  late _MetadataSessions sessions;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('workspace_metadata_');
    database = UserStateDatabase.openAt('${directory.path}/state.db');
    lists = UserStateListStore(database: database);
    sessions = _MetadataSessions(database: database);
  });

  tearDown(() async {
    await database.flushWrites();
    lists.dispose();
    database.close();
    directory.deleteSync(recursive: true);
  });

  WorkspaceRepository repository(int? slot) => WorkspaceRepository(
    store: lists,
    sessions: sessions,
    slot: () => slot,
  );

  test('זהות השולחן שייכת למשבצת ונקראת בלי סשן מלא', () async {
    final first = Workspace(id: 'first', name: 'ראשון', tabs: []);
    final second = Workspace(id: 'second', name: 'שני', tabs: []);
    await repository(1).replaceWorkspaces([first, second], first.id);
    await sessions.saveActiveWorkspace(2, second.id);

    expect((await repository(1).loadWorkspaces()).$2, first.id);
    expect((await repository(2).loadWorkspaces()).$2, second.id);
    expect((await repository(3).loadWorkspaces()).$2, isNull);
    expect((await repository(null).loadWorkspaces()).$2, isNull);
  });

  test('מזהה לא קיים חוזר לשולחן הראשון או ל-null ברשימה ריקה', () async {
    final first = Workspace(id: 'first', name: 'ראשון', tabs: []);
    await repository(1).replaceWorkspaces([first], 'missing');
    final (workspaces, activeId) = await repository(1).loadWorkspaces();
    expect(workspaces, [first]);
    expect(activeId, first.id);
    await repository(1).replaceWorkspaces([], 'missing');
    expect((await repository(1).loadWorkspaces()).$2, isNull);
  });
}
