import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;
  late String path;
  late UserStateDatabase db;
  late WindowSessionStore store;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_session_writes_');
    path = '${tmp.path}${Platform.pathSeparator}user_state.db';
    db = UserStateDatabase.openAt(path);
    store = WindowSessionStore(database: db);
    await db.database;
  });

  tearDown(() async {
    await db.flushWrites();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test(
    'שמירת סשן מול מסד נעול אינה חוסמת את ה-isolate הקורא (#3412)',
    () async {
      final locker = sqlite3.open(path);
      locker.execute('BEGIN IMMEDIATE');

      final write = store.save(1, tabsJson: '[{"a":1}]', currentIndex: 0);
      final tick = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tick.stop();

      locker.execute('COMMIT');
      locker.close();
      await write;

      expect(tick.elapsedMilliseconds, lessThan(500));
      expect((await store.load(1))!.tabsJson, '[{"a":1}]');
    },
  );

  test(
    'כתיבת רשימה בזמן אצוות סשן ממתינה לה ואינה חוסמת את ה-isolate',
    () async {
      final lists = UserStateListStore(database: db);
      addTearDown(lists.dispose);
      final locker = sqlite3.open(path);
      locker.execute('BEGIN IMMEDIATE');

      var sessionDone = false;
      final session = store
          .save(1, tabsJson: '["x"]', currentIndex: 0)
          .then((_) => sessionDone = true);
      var listDoneAfterSession = false;
      final list = lists
          .write('history', 'items', ['a'])
          .then((_) => listDoneAfterSession = sessionDone);
      final tick = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tick.stop();

      locker.execute('COMMIT');
      locker.close();
      await Future.wait([session, list]);

      expect(tick.elapsedMilliseconds, lessThan(500));
      expect(listDoneAfterSession, isTrue);
      expect(await lists.read('history', 'items'), ['a']);
    },
  );

  test(
    'mutate, write ו-clear מול מסד נעול אינם חוסמים את ה-isolate (#3900)',
    () async {
      final lists = UserStateListStore(database: db);
      addTearDown(lists.dispose);
      final locker = sqlite3.open(path);
      locker.execute('BEGIN IMMEDIATE');

      final writes = [
        lists.write('history', 'items', ['a']),
        lists.mutate('history', 'items', (current) => [...current, 'b']),
        lists.mutate('history', 'items', (current) => [...current, 'c']),
        lists.clear('bookmarks', 'items'),
      ];
      final tick = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tick.stop();

      locker.execute('COMMIT');
      locker.close();
      await Future.wait(writes);

      expect(tick.elapsedMilliseconds, lessThan(500));
      expect(await lists.read('history', 'items'), ['a', 'b', 'c']);
    },
  );

  test('קריאה מיד אחרי כתיבות רשימה שלא הומתנו רואה את כולן', () async {
    final lists = UserStateListStore(database: db);
    addTearDown(lists.dispose);
    unawaited(lists.write('history', 'items', ['a']));
    unawaited(lists.mutate('history', 'items', (current) => [...current, 'b']));
    expect(await lists.read('history', 'items'), ['a', 'b']);

    unawaited(lists.clear('history', 'items'));
    expect(await lists.read('history', 'items'), isEmpty);
  });

  test('mutate מחיל מחדש כשכותב אחר שינה את הרשימה מאז הקריאה', () async {
    final lists = UserStateListStore(database: db);
    addTearDown(lists.dispose);
    await lists.write('history', 'items', ['a']);

    final other = sqlite3.open(path);
    addTearDown(other.close);
    var calls = 0;
    final result = await lists.mutate('history', 'items', (current) {
      if (calls++ == 0) {
        other.execute(
          "UPDATE lists SET payload_json = '[\"a\",\"x\"]' "
          "WHERE box = 'history' AND key = 'items'",
        );
      }
      return [...current, 'b'];
    });

    expect(calls, 2);
    expect(result, ['a', 'x', 'b']);
    expect(await lists.read('history', 'items'), ['a', 'x', 'b']);
  });

  test('קריאה מיד אחרי שמירה שלא הומתנה רואה את הערך החדש', () async {
    final pending = [
      store.save(1, tabsJson: '["old"]', currentIndex: 0),
      store.save(1, tabsJson: '["new"]', currentIndex: 2),
      store.saveCurrentIndex(1, 1),
      store.saveBounds(2, '{"w":800}'),
      store.delete(3),
    ];
    final session = (await store.load(1))!;
    expect(session.tabsJson, '["new"]');
    expect(session.currentIndex, 1);
    expect((await store.load(2))!.boundsJson, '{"w":800}');

    unawaited(store.delete(2));
    expect(await store.load(2), isNull);
    expect((await store.loadAll()).map((s) => s.slot), [1]);
    await Future.wait(pending);
  });

  test('דחיסת משבצות ממתינה לשמירות שבתור', () async {
    unawaited(store.save(1, tabsJson: '["host"]', currentIndex: 0));
    unawaited(store.save(4, tabsJson: '["orphan"]', currentIndex: 0));

    expect(await store.compactAround(1, 8), [2]);
    expect((await store.load(2))!.tabsJson, '["orphan"]');
  });

  test('flushWrites מנקז גם כתיבה שנכנסה בזמן אצווה רצה', () async {
    final first = store.save(1, tabsJson: '["a"]', currentIndex: 0);
    await Future<void>.delayed(Duration.zero);
    unawaited(store.saveCurrentIndex(1, 5));
    unawaited(store.saveActiveWorkspace(1, 'ws'));
    await first;
    await db.flushWrites();

    final file = sqlite3.open(path);
    addTearDown(file.close);
    final row = file.select('SELECT * FROM window_sessions WHERE slot = 1');
    expect(row.single['current_index'], 5);
    expect(row.single['active_workspace_id'], 'ws');
  });
}
