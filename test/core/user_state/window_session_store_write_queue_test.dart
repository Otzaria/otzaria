import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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

  test('mutate מחיל פעם אחת את השינוי על המצב שננעל ב-worker', () async {
    final lists = UserStateListStore(database: db);
    addTearDown(lists.dispose);
    await lists.write('history', 'items', ['a']);

    final other = sqlite3.open(path);
    addTearDown(other.close);
    other.execute('BEGIN IMMEDIATE');
    var calls = 0;
    final pending = lists.mutate('history', 'items', (current) {
      calls++;
      return [...current, 'b'];
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 0);
    other.execute(
      "UPDATE lists SET payload_json = '[\"a\",\"x\"]' "
      "WHERE box = 'history' AND key = 'items'",
    );
    other.execute('COMMIT');
    final result = await pending;

    expect(calls, 1);
    expect(result, ['a', 'x', 'b']);
    expect(await lists.read('history', 'items'), ['a', 'x', 'b']);
  });

  for (final inline in [false, true]) {
    group('כשלי mutate, inline=$inline', () {
      late UserStateListStore lists;

      setUp(() {
        UserStateDatabase.debugWriteInline = inline;
        lists = UserStateListStore(database: db);
      });

      tearDown(() {
        UserStateDatabase.debugWriteInline = false;
        lists.dispose();
      });

      test('שגיאת callback משחררת את הטרנזקציה בלי שינוי או אירוע', () async {
        await lists.write('history', 'items', ['a']);
        var events = 0;
        final sub = lists.changes.listen((_) => events++);
        addTearDown(sub.cancel);
        final failure = StateError('apply failed');
        await expectLater(
          lists.mutate('history', 'items', (_) => throw failure),
          throwsA(same(failure)),
        );
        expect(await lists.read('history', 'items'), ['a']);
        expect(events, 0);
        await lists.mutate('history', 'items', (current) => [...current, 'b']);
        expect(await lists.read('history', 'items'), ['a', 'b']);
      });

      test('שגיאת קידוד JSON משחררת את הטרנזקציה', () async {
        await lists.write('history', 'items', ['a']);
        final cyclic = <dynamic>[];
        cyclic.add(cyclic);
        await expectLater(
          lists.mutate('history', 'items', (_) => cyclic),
          throwsA(isA<Error>()),
        );
        expect(await lists.read('history', 'items'), ['a']);
        await lists.clear('history', 'items');
        expect(await lists.read('history', 'items'), isEmpty);
      });

      test('payload פגום מבטל את הטרנזקציה ומאפשר כתיבה אחריה', () async {
        await lists.write('history', 'items', ['a']);
        final conn = await db.database;
        conn.execute("UPDATE lists SET payload_json = 'invalid json'");
        await expectLater(
          lists.mutate('history', 'items', (current) => current),
          throwsFormatException,
        );
        await lists.write('history', 'items', ['b']);
        expect(await lists.read('history', 'items'), ['b']);
      });

      test('כשל worker לפני שליחת payload אינו משאיר Future תלוי', () async {
        final conn = await db.database;
        conn.execute('ALTER TABLE lists RENAME TO hidden_lists');
        var calls = 0;
        await expectLater(
          lists.mutate('history', 'items', (current) {
            calls++;
            return current;
          }),
          throwsA(isA<SqliteException>()),
        );
        expect(calls, 0);
        conn.execute('ALTER TABLE hidden_lists RENAME TO lists');
        await lists.write('history', 'items', ['a']);
        expect(await lists.read('history', 'items'), ['a']);
      });

      test('כשל כתיבה אחרי payload מבטל שינוי ומאפשר את הכתיבה הבאה', () async {
        await lists.write('history', 'items', ['a']);
        final conn = await db.database;
        conn.execute(
          "CREATE TRIGGER deny_list_write BEFORE INSERT ON lists "
          "BEGIN SELECT RAISE(ABORT, 'write denied'); END",
        );
        var calls = 0;
        await expectLater(
          lists.mutate('history', 'items', (current) {
            calls++;
            return [...current, 'b'];
          }),
          throwsA(isA<SqliteException>()),
        );
        expect(calls, 1);
        expect(await lists.read('history', 'items'), ['a']);
        conn.execute('DROP TRIGGER deny_list_write');
        await lists.write('history', 'items', ['c']);
        expect(await lists.read('history', 'items'), ['c']);
      });
    });
  }

  test('callback שלוכד ReceivePort נשאר ב-isolate הקורא', () async {
    final lists = UserStateListStore(database: db);
    addTearDown(lists.dispose);
    final captured = ReceivePort();
    addTearDown(captured.close);
    final message = captured.first;
    await lists.mutate('history', 'items', (current) {
      captured.sendPort.send('callback ran');
      return [...current, 'a'];
    });
    expect(await message, 'callback ran');
    expect(await lists.read('history', 'items'), ['a']);
  });

  test('קידוד ה-JSON של מוטציה רץ ב-worker ולא ב-isolate הקורא', () async {
    final lists = UserStateListStore(database: db);
    addTearDown(lists.dispose);
    final encodedIn = ReceivePort();
    addTearDown(encodedIn.close);
    final isolateName = encodedIn.first;
    await lists.mutate('history', 'items', (current) {
      return [...current, _EncodeProbe(encodedIn.sendPort)];
    });
    expect(await isolateName, isNot(Isolate.current.debugName));
    expect(await lists.read('history', 'items'), ['probe']);
  });

  test('כשל COMMIT ב-worker מבטל את השינוי ומשחרר את התור', () async {
    final lists = UserStateListStore(database: db);
    addTearDown(lists.dispose);
    await lists.write('history', 'items', ['a']);
    final conn = await db.database;
    conn.execute('PRAGMA journal_mode=DELETE');
    final reader = sqlite3.open(path);
    addTearDown(reader.close);
    var events = 0;
    final sub = lists.changes.listen((_) => events++);
    addTearDown(sub.cancel);
    final pending = lists.mutate('history', 'items', (current) {
      reader.execute('BEGIN');
      reader.select('SELECT * FROM lists');
      return [...current, 'b'];
    });
    try {
      await expectLater(pending, throwsA(isA<SqliteException>()));
    } finally {
      reader.execute('ROLLBACK');
    }
    expect(events, 0);
    expect(await lists.read('history', 'items'), ['a']);
    await lists.write('history', 'items', ['c']);
    expect(await lists.read('history', 'items'), ['c']);
  });

  test('שתי מוטציות מתחרות מחיבורים נפרדים אינן מאבדות עדכון', () async {
    final secondDb = UserStateDatabase.openAt(path);
    final first = UserStateListStore(database: db);
    final second = UserStateListStore(database: secondDb);
    addTearDown(() async {
      first.dispose();
      second.dispose();
      await secondDb.flushWrites();
      secondDb.close();
    });
    await secondDb.database;
    await first.write('counter', 'items', [0]);
    var calls = 0;
    final results = await Future.wait([
      for (var i = 0; i < 6; i++)
        (i.isEven ? first : second).mutate('counter', 'items', (current) {
          calls++;
          return [(current.single as int) + 1];
        }),
    ]);
    expect(calls, 6);
    expect(results.map((result) => result.single).toSet(), {1, 2, 3, 4, 5, 6});
    expect(await first.read('counter', 'items'), [6]);
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

/// מדווח באיזה isolate `jsonEncode` קרא ל-[toJson].
class _EncodeProbe {
  _EncodeProbe(this.port);

  final SendPort port;

  String toJson() {
    port.send(Isolate.current.debugName);
    return 'probe';
  }
}
