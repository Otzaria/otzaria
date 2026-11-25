import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

InstalledPlugin _plugin(String id) {
  final manifest = PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': 'name-$id',
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': ['network.access'],
  });
  return InstalledPlugin(
    pluginId: id,
    name: manifest.name,
    version: manifest.version,
    installPath: '/plugins/$id',
    entrypointPath: manifest.entrypoint,
    enabled: true,
    pinned: true,
    manifest: manifest,
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  late Directory tempDir;
  late String dbPath;
  final db = PluginSystemDatabase.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_db_off_ui_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    db.resetForTests();
    dbPath = await AppPaths.resolvePluginsDbPath();
    await db.insertOrUpdatePluginWithPermissions(_plugin('p1'), {
      'network.access': true,
    });
    await db.publishRecord('p1', 'calendar.event', 'global', 'e1', '{}', null);
    await db.setPluginKV('p1', 'default', 'k', '"v"');
  });

  tearDown(() async {
    db.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  /// נעילה שמשתחררת רק בטיימר של ה-isolate הזה: פעולה סינכרונית עליו הייתה
  /// ממתינה ל-busy_timeout (5 שניות) ונכשלת.
  Future<T> whileLocked<T>(
    Future<T> Function() action, {
    bool exclusive = false,
  }) async {
    final locker = sqlite3.open(dbPath);
    if (exclusive) locker.execute('PRAGMA journal_mode=DELETE');
    locker.execute(exclusive ? 'BEGIN EXCLUSIVE' : 'BEGIN IMMEDIATE');
    Timer(const Duration(milliseconds: 200), () {
      locker.execute('ROLLBACK');
      locker.close();
    });
    final clock = Stopwatch()..start();
    var lastTick = Duration.zero;
    var longestStall = Duration.zero;
    final ticker = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final stall = clock.elapsed - lastTick;
      if (stall > longestStall) longestStall = stall;
      lastTick = clock.elapsed;
    });
    try {
      return await action();
    } finally {
      ticker.cancel();
      expect(longestStall, lessThan(const Duration(seconds: 1)));
    }
  }

  test('מחיקת תוסף אינה חוסמת את ה-isolate הקורא (#5869)', () async {
    await whileLocked(() => db.deletePlugin('p1'));

    expect(await db.getInstalledPlugin('p1'), isNull);
    expect(await db.getPluginPermissions('p1'), isEmpty);
    expect(await db.getPublishedRecordsFull('calendar.event'), isEmpty);
    expect(await db.getPluginKV('p1', 'default', 'k'), isNull);
  });

  test('איפוס נתוני תוסף אינו חוסם ומשאיר התקנה והרשאות (#5869)', () async {
    await whileLocked(() => db.clearPluginData('p1'));

    expect(await db.getInstalledPlugin('p1'), isNotNull);
    expect((await db.getPluginPermissions('p1')).single.granted, isTrue);
    expect(await db.getPublishedRecordsFull('calendar.event'), isEmpty);
    expect(await db.getPluginKV('p1', 'default', 'k'), isNull);
  });

  test('פתיחת המסד וקריאת ההרשאות אינן חוסמות (#5763)', () async {
    await db.close();

    final grants = await whileLocked(
      () => db.getPluginPermissions('p1'),
      exclusive: true,
    );

    expect(grants.single.permission, 'network.access');
  });

  test('פתיחת המסד וקריאת רשומות הלוח אינן חוסמות (#5862)', () async {
    await db.close();

    final records = await whileLocked(
      () => db.getPublishedRecordsFull('calendar.event'),
      exclusive: true,
    );

    expect(records.single, {
      'plugin_id': 'p1',
      'type': 'calendar.event',
      'scope': 'global',
      'key': 'e1',
      'payload_json': '{}',
    });
  });

  test('קריאה אחרי כתיבה שבתור רואה אותה, וכתיבה אחרי מחיקה נשמרת', () async {
    unawaited(
      db.publishRecord('p1', 'calendar.event', 'global', 'e2', '{}', null),
    );
    expect(await db.getPublishedRecordsFull('calendar.event'), hasLength(2));

    unawaited(db.deletePlugin('p1'));
    await db.setPluginKV('p1', 'default', 'k', '"after"');

    expect(await db.getInstalledPlugin('p1'), isNull);
    expect(await db.getPluginKV('p1', 'default', 'k'), '"after"');
  });
  test('סגירה ממתינה לפתיחה שכבר החלה', () async {
    await db.close();
    final locker = sqlite3.open(dbPath);
    locker.execute('PRAGMA journal_mode=DELETE');
    locker.execute('BEGIN EXCLUSIVE');
    try {
      final reading = db.hasEnabledPlugin();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(db.openDatabase, isNull);
      final closing = db.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      locker.execute('ROLLBACK');
      expect(await reading, isTrue);
      await closing;
      expect(db.openDatabase, isNull);
    } finally {
      locker.close();
    }
  });

  test('כשל במחיקה אינו מבטל כתיבת KV של תוסף אחר', () async {
    (await db.database).execute('''
      CREATE TRIGGER block_delete BEFORE DELETE ON plugin_installation
      BEGIN SELECT RAISE(ABORT, 'boom'); END
    ''');
    final first = db.setPluginKV('p1', 'default', 'first', '1');
    final deleting = expectLater(
      db.deletePlugin('p1'),
      throwsA(isA<SqliteException>()),
    );
    final second = expectLater(
      db.setPluginKV('other', 'default', 'second', '2'),
      completes,
    );
    await first;
    await deleting;
    await second;
    expect(await db.getPluginKV('other', 'default', 'second'), '2');
  });
}
