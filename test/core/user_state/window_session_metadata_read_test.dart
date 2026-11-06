import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('session_metadata_');
    database = UserStateDatabase.openAt('${directory.path}/user_state.db');
    sessions = WindowSessionStore(database: database);
    await database.database;
  });

  tearDown(() async {
    await database.flushWrites();
    database.close();
    directory.deleteSync(recursive: true);
  });

  test('שורה חסרה ועמודות ריקות מחזירות null', () async {
    expect(await sessions.loadBoundsJson(1), isNull);
    expect(await sessions.loadActiveWorkspaceId(1), isNull);
    await sessions.save(1, tabsJson: '[]', currentIndex: 0);
    expect(await sessions.loadBoundsJson(1), isNull);
    expect(await sessions.loadActiveWorkspaceId(1), isNull);

    await sessions.saveBounds(1, '');
    await sessions.saveActiveWorkspace(1, '');
    expect(await sessions.loadBoundsJson(1), '');
    expect(await sessions.loadActiveWorkspaceId(1), '');
  });

  test('השליפות מבודדות משבצות ונשארות עדכניות בלי לשנות כרטיסיות', () async {
    await sessions.save(1, tabsJson: '["a","b"]', currentIndex: 1);
    await sessions.saveBounds(1, '{"left":10}');
    await sessions.saveActiveWorkspace(1, 'first');
    await sessions.saveBounds(2, '{"left":20}');
    await sessions.saveActiveWorkspace(2, 'second');

    expect(await sessions.loadBoundsJson(1), '{"left":10}');
    expect(await sessions.loadBoundsJson(2), '{"left":20}');
    expect(await sessions.loadActiveWorkspaceId(1), 'first');
    expect(await sessions.loadActiveWorkspaceId(2), 'second');

    await sessions.saveBounds(1, null);
    await sessions.saveActiveWorkspace(1, 'updated');
    expect(await sessions.loadBoundsJson(1), isNull);
    expect(await sessions.loadActiveWorkspaceId(1), 'updated');
    expect(await sessions.loadBoundsJson(2), '{"left":20}');
    expect(await sessions.loadActiveWorkspaceId(2), 'second');
    final full = (await sessions.load(1))!;
    expect(full.tabsJson, '["a","b"]');
    expect(full.currentIndex, 1);
  });

  test('קריאות מטא־נתונים ממתינות לכתיבות שכבר בתור', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final barrier = database.runInWriteQueue((_) async {
      started.complete();
      await release.future;
    });
    await started.future;
    final boundsWrite = sessions.saveBounds(1, '{"left":42}');
    final workspaceWrite = sessions.saveActiveWorkspace(1, 'queued');
    var boundsReadFinished = false;
    var workspaceReadFinished = false;
    final boundsRead = sessions.loadBoundsJson(1).then((value) {
      boundsReadFinished = true;
      return value;
    });
    final workspaceRead = sessions.loadActiveWorkspaceId(1).then((value) {
      workspaceReadFinished = true;
      return value;
    });

    await Future<void>.delayed(Duration.zero);
    expect(boundsReadFinished, isFalse);
    expect(workspaceReadFinished, isFalse);
    release.complete();
    await Future.wait([barrier, boundsWrite, workspaceWrite]);
    expect(await boundsRead, '{"left":42}');
    expect(await workspaceRead, 'queued');
  });

  test('השליפות אינן מעריכות את עמודת הכרטיסיות ב-SQLite', () async {
    final tabs = '["${'א' * 500000}"]';
    await sessions.save(1, tabsJson: tabs, currentIndex: 0);
    await sessions.saveBounds(1, '{"left":7}');
    await sessions.saveActiveWorkspace(1, 'workspace');
    final connection = await database.database;
    var tabReads = 0;
    connection.createFunction(
      functionName: 'read_tabs',
      argumentCount: const AllowedArgumentCount(1),
      directOnly: false,
      function: (arguments) {
        tabReads++;
        return arguments.single;
      },
    );
    connection.execute('ALTER TABLE window_sessions RENAME TO session_rows');
    connection.execute('''
      CREATE VIEW window_sessions AS
      SELECT slot, read_tabs(tabs_json) AS tabs_json, current_index,
             active_workspace_id, bounds_json, updated_at
      FROM session_rows
    ''');

    expect((await sessions.load(1))!.tabsJson, tabs);
    expect(tabReads, 1);
    tabReads = 0;
    expect(await sessions.loadBoundsJson(1), '{"left":7}');
    expect(await sessions.loadActiveWorkspaceId(1), 'workspace');
    expect(tabReads, 0);
  });

  test('שגיאת SQLite מתפשטת ואינה נראית כמו שורה חסרה', () async {
    final connection = await database.database;
    connection.execute('DROP TABLE window_sessions');
    await expectLater(
      sessions.loadBoundsJson(1),
      throwsA(isA<SqliteException>()),
    );
    await expectLater(
      sessions.loadActiveWorkspaceId(1),
      throwsA(isA<SqliteException>()),
    );
  });
}
