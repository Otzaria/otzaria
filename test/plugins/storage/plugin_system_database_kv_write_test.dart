import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  late Directory tempDir;
  final db = PluginSystemDatabase.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_kv_write_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    db.resetForTests();
  });

  tearDown(() async {
    db.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  test('כתיבת KV מול מסד נעול אינה חוסמת את ה-isolate הקורא (#3378)', () async {
    await db.database;
    final locker = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    locker.execute('BEGIN IMMEDIATE');

    final write = db.setPluginKV('p', 'ns', 'k', '"v"');
    final tick = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    tick.stop();

    locker.execute('COMMIT');
    locker.close();
    await write;

    expect(tick.elapsedMilliseconds, lessThan(1000));
    expect(await db.getPluginKV('p', 'ns', 'k'), '"v"');
  });

  final big = '"${'x' * PluginSystemDatabase.maxInlineKVReadBytes}"';

  test('ערך KV גדול אינו נקרא בחיבור של ה-UI (#3644)', () async {
    await db.setPluginKV('p', 'ns', 'big', big);
    await db.setPluginKV('p', 'ns', 'small', '1');
    // שינוי שלא נשמר נראה רק בחיבור של ה-UI, וכך מזהים איזה חיבור קרא.
    final ui = (await db.database)
      ..execute('BEGIN')
      ..execute("UPDATE plugin_kv_store SET value_json = value_json || ' '");
    try {
      expect(await db.getPluginKV('p', 'ns', 'big'), big);
      expect(await db.getPluginKVMany('p', 'ns', ['big', 'small']), {
        'big': big,
        'small': '1',
      });
      expect(await db.getPluginKV('p', 'ns', 'small'), '1 ');
      expect(await db.getPluginKV('p', 'ns', 'missing'), isNull);
    } finally {
      ui.execute('ROLLBACK');
    }
  });

  test('close מחכה לקריאת KV שרצה ב-isolate', () async {
    await db.setPluginKV('p', 'ns', 'k', big);
    final read = db.getPluginKV('p', 'ns', 'k');
    var readDone = false;
    unawaited(read.then((_) => readDone = true));
    for (var i = 0; i < 5; i++) {
      await Future<void>.microtask(() {});
    }
    await db.close();
    // תשובת isolate מגיעה כאירוע, לא כ-microtask: אם close לא חיכה, היא עוד לא הגיעה.
    await Future<void>.microtask(() {});
    expect(readDone, isTrue);
  });

  test('קריאה, מחיקה וכתיבה רצופות שומרות על הסדר', () async {
    final pending = [
      db.setPluginKV('p', 'ns', 'a', '1'),
      db.setPluginKV('p', 'ns', 'a', '2'),
      db.setPluginKV('p', 'ns', 'b', '3'),
      db.removePluginKV('p', 'ns', 'b'),
    ];
    expect(await db.getPluginKV('p', 'ns', 'a'), '2');
    expect(await db.listPluginKVKeys('p', 'ns'), ['a']);
    await Future.wait(pending);
  });

  test('close מחכה גם לכתיבה שנכנסה בזמן אצווה רצה', () async {
    await db.database;
    final first = db.setPluginKV('p', 'ns', 'a', '1');
    await Future<void>.delayed(Duration.zero);
    unawaited(db.setPluginKV('p', 'ns', 'b', '2'));
    unawaited(db.writeLog('p', 'error', 'boom'));
    await first;
    await db.close();

    final file = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    addTearDown(file.close);
    expect(
      file
          .select('SELECT key FROM plugin_kv_store ORDER BY key')
          .map(
            (r) => r['key'],
          ),
      ['a', 'b'],
    );
    expect(file.select('SELECT message FROM plugin_runtime_log'), hasLength(1));
  });

  for (final alreadyOpen in [false, true]) {
    test(
      'כתיבה מיד אחרי בקשת העברה ממתינה לשחרור (פתוח: $alreadyOpen)',
      () async {
        if (alreadyOpen) await db.database;
        final lock = db.lockForStorageMove('move');
        var completed = false;
        final write = db.setPluginKV('p', 'ns', 'after', '2').then((_) {
          completed = true;
        });
        try {
          await lock.timeout(const Duration(seconds: 5));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(completed, isFalse);
          expect(db.openDatabase, isNull);
        } finally {
          db.releaseStorageMove('move');
          await write;
        }
        expect(await db.getPluginKV('p', 'ns', 'after'), '2');
      },
    );
  }

  test('העברה מנקזת כתיבות קודמות, סוגרת ומחדשת כתיבה ביעד החדש', () async {
    await db.database;
    final oldPath = await AppPaths.resolvePluginsDbPath();
    final locker = sqlite3.open(oldPath)..execute('BEGIN IMMEDIATE');
    final first = db.setPluginKV('p', 'ns', 'before', '1');
    final lock = db.lockForStorageMove('move');
    final queued = [
      db.setPluginKV('p', 'ns', 'after', '2'),
      db.removePluginKV('p', 'ns', 'before'),
      db.writeLog('p', 'info', 'moved'),
      db.publishRecord('p', 'type', 'scope', 'record', '{}', null),
      db.unpublishRecord('p', 'type', 'scope', 'record'),
    ];
    final target = await Directory.systemTemp.createTemp('plugin_move_target_');
    try {
      locker.execute('COMMIT');
      locker.close();
      await first;
      await lock.timeout(const Duration(seconds: 5));
      await db.close().timeout(const Duration(seconds: 5));
      final old = sqlite3.open(oldPath);
      try {
        expect(
          old.select('SELECT key FROM plugin_kv_store').single['key'],
          'before',
        );
        expect(old.select('SELECT * FROM plugin_runtime_log'), isEmpty);
      } finally {
        old.close();
      }
      AppPaths.debugOverrideDataRootPath(target.path);
      final newPath = await AppPaths.resolvePluginsDbPath();
      await File(oldPath).copy(newPath);
      db.releaseStorageMove('wrong-id');
      expect(db.openDatabase, isNull);
      db.releaseStorageMove('move');
      await Future.wait(queued);
      expect(await db.listPluginKVKeys('p', 'ns'), ['after']);
      expect(await db.getPluginKV('p', 'ns', 'after'), '2');
      expect(await db.getPublishedRecordsByType('type'), isEmpty);
      final current = await db.database;
      expect(
        current
            .select('SELECT message FROM plugin_runtime_log')
            .single['message'],
        'moved',
      );
    } finally {
      db.releaseStorageMove('move');
      await Future.wait(queued);
      await db.close();
      await target.delete(recursive: true);
    }
  });

  test('בקשת העברה מנקזת גם אצוות שעדיין פותחות את המסד', () async {
    final first = db.setPluginKV('p', 'ns', 'first', '1');
    final second = db.setPluginKV('p', 'ns', 'second', '2');
    final lock = db.lockForStorageMove('move');
    final repeatedLock = db.lockForStorageMove('move');
    final rejected = expectLater(
      db.lockForStorageMove('other'),
      throwsStateError,
    );
    try {
      await Future.wait([
        first,
        second,
        lock,
        repeatedLock,
        rejected,
      ]).timeout(const Duration(seconds: 5));
      await db.lockForStorageMove('move').timeout(const Duration(seconds: 5));
      final file = sqlite3.open(await AppPaths.resolvePluginsDbPath());
      try {
        expect(
          file
              .select('SELECT key FROM plugin_kv_store ORDER BY key')
              .map((row) => row['key']),
          ['first', 'second'],
        );
      } finally {
        file.close();
      }
    } finally {
      db.releaseStorageMove('move');
    }
  });

  test('close מנקז גם כתיבה שהוגשה אחרי תחילת הסגירה', () async {
    await db.database;
    final first = db.setPluginKV('p', 'ns', 'first', '1');
    final close = db.close();
    final second = db.setPluginKV('p', 'ns', 'second', '2');
    await close.timeout(const Duration(seconds: 5));
    expect(db.openDatabase, isNull);
    await Future.wait([first, second]);
    expect(await db.listPluginKVKeys('p', 'ns'), ['first', 'second']);
  });

  test('כשל באצווה אינו תוקע העברה וכתיבה לאחר השחרור', () async {
    final connection = await db.database;
    connection.execute(
      "CREATE TRIGGER reject_kv BEFORE INSERT ON plugin_kv_store BEGIN SELECT RAISE(FAIL, 'rejected'); END",
    );
    final failed = expectLater(
      db.setPluginKV('p', 'ns', 'bad', '1'),
      throwsA(isA<SqliteException>()),
    );
    final lock = db.lockForStorageMove('move');
    final queued = db.writeLog('p', 'info', 'after-failure');
    try {
      await failed;
      await lock.timeout(const Duration(seconds: 5));
    } finally {
      db.releaseStorageMove('move');
      await queued;
    }
    final reopened = await db.database;
    expect(reopened.select('SELECT * FROM plugin_kv_store'), isEmpty);
    expect(
      reopened
          .select('SELECT message FROM plugin_runtime_log')
          .single['message'],
      'after-failure',
    );
  });

  test('קריאה אינה ממתינה לכתיבות שנכנסו אחריה', () async {
    await db.setPluginKV('p', 'ns', 'a', '1');
    final writes = <Future<void>>[];
    final writer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      for (var i = 0; i < 200; i++) {
        writes.add(db.setPluginKV('p', 'ns', 'k${writes.length}', 'x'));
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final value = await db
        .getPluginKV('p', 'ns', 'a')
        .timeout(const Duration(seconds: 5), onTimeout: () => 'starved');
    writer.cancel();
    await Future.wait(writes);

    expect(value, '1');
  });
}
