import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_crash_guard_test_');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    PluginCrashGuard.resetForTesting();
  });

  tearDown(() async {
    AppPaths.debugOverrideDataRootPath(null);
    PluginCrashGuard.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PluginCrashGuard', () {
    test('starts with empty quarantine when file does not exist', () async {
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('any.plugin'), false);
    });

    test('markLoadAttempt persists the plugin id', () async {
      await PluginCrashGuard.markLoadAttempt('com.example.plugin');
      // בתוך הסשן שבו הניסיון קרה — לא חסום (הטעינה עוד בטיסה, לא קריסה)
      expect(PluginCrashGuard.isBlocked('com.example.plugin'), false);

      // simulate a fresh app launch
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.example.plugin'), true);
    });

    test('markLoadSuccess clears a previously marked plugin', () async {
      await PluginCrashGuard.markLoadAttempt('com.example.plugin');
      await PluginCrashGuard.markLoadSuccess('com.example.plugin');
      expect(PluginCrashGuard.isBlocked('com.example.plugin'), false);

      // also persisted to disk
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.example.plugin'), false);
    });

    test('retry removes a single plugin from quarantine', () async {
      PluginCrashGuard.setInitialBlockedForTesting({'a', 'b', 'c'});
      await PluginCrashGuard.retry('b');
      expect(PluginCrashGuard.isBlocked('a'), true);
      expect(PluginCrashGuard.isBlocked('b'), false);
      expect(PluginCrashGuard.isBlocked('c'), true);
    });

    test('isBlocked returns false before ensureInitialized', () {
      // לפני אתחול — לא חוסם, כדי שלא נחסום בטעות בזמן שהקובץ עוד לא נטען.
      // (main.dart דואג לקרוא ל-ensureInitialized לפני שמראים תוספים.)
      expect(PluginCrashGuard.isBlocked('something'), false);
    });

    test('persisted file includes version and sorted blocked list', () async {
      await PluginCrashGuard.markLoadAttempt('com.b.plugin');
      await PluginCrashGuard.markLoadAttempt('com.a.plugin');

      final file = File(p.join(tempDir.path, 'plugin_crash_guard.json'));
      expect(await file.exists(), true);
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded['version'], isNotNull);
      expect(decoded['blocked'], ['com.a.plugin', 'com.b.plugin']);
    });

    test('survives a corrupted file (silently falls back to empty)', () async {
      final file = File(p.join(tempDir.path, 'plugin_crash_guard.json'));
      await file.writeAsString('this is not valid json');

      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('any'), false);

      // After a successful write, the file is rewritten in the new format
      await PluginCrashGuard.markLoadAttempt('x');
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['blocked'], ['x']);
    });

    test(
      'ignores quarantine from a different app version (auto-recovery)',
      () async {
        // simulate a quarantine file written by an older version
        final file = File(p.join(tempDir.path, 'plugin_crash_guard.json'));
        await file.writeAsString(
          jsonEncode({
            'version': '0.9.91+90910', // older
            'blocked': ['com.crashed.plugin'],
          }),
        );

        // current app version may be anything (real PackageInfo in tests) — but
        // as long as it's not '0.9.91+90910', the canary should be ignored.
        await PluginCrashGuard.ensureInitialized();
        expect(
          PluginCrashGuard.isBlocked('com.crashed.plugin'),
          false,
          reason:
              'plugin quarantined under a previous app version should not '
              'block on a newer version — the upgrade might have fixed the '
              'crash, so we give it another chance automatically',
        );
      },
    );

    test('honors quarantine from the same app version', () async {
      // First write under an app version (simulated via test helper)
      PluginCrashGuard.setInitialBlockedForTesting(
        {'com.same.version.plugin'},
        appVersion: 'test-fixed',
      );
      await PluginCrashGuard.markLoadAttempt('com.same.version.plugin');

      // simulate a fresh launch with the SAME app version
      PluginCrashGuard.resetForTesting();
      PluginCrashGuard.setInitialBlockedForTesting(
        {},
        appVersion: 'test-fixed',
      );
      // load from disk to apply our version comparison logic
      final file = File(p.join(tempDir.path, 'plugin_crash_guard.json'));
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded['version'], 'test-fixed');
      expect(decoded['blocked'], ['com.same.version.plugin']);
    });

    test('ignores quarantine from old list-format files (legacy)', () async {
      // older versions of this code stored just a JSON list. After upgrade,
      // we don't know which app version wrote it, so we conservatively clear.
      final file = File(p.join(tempDir.path, 'plugin_crash_guard.json'));
      await file.writeAsString('["com.legacy.plugin"]');

      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.legacy.plugin'), false);
    });

    test('end-to-end: crash → quarantine on next launch → user retry → '
        'next crash again', () async {
      // First launch: attempt to load plugin, then "crash" (no success call)
      await PluginCrashGuard.markLoadAttempt('com.crash.plugin');

      // Second launch: see the plugin as blocked
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.crash.plugin'), true);

      // User clicks retry: plugin is unblocked
      await PluginCrashGuard.retry('com.crash.plugin');
      expect(PluginCrashGuard.isBlocked('com.crash.plugin'), false);

      // Retry triggers a new load attempt — עדיין לא חסום בסשן הנוכחי
      await PluginCrashGuard.markLoadAttempt('com.crash.plugin');
      expect(PluginCrashGuard.isBlocked('com.crash.plugin'), false);

      // Crashes again (no success call). Third launch: still blocked.
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.crash.plugin'), true);
    });

    test('end-to-end: load succeeds → not blocked next time', () async {
      // First successful launch
      await PluginCrashGuard.markLoadAttempt('com.ok.plugin');
      await PluginCrashGuard.markLoadSuccess('com.ok.plugin');

      // Second launch: not blocked
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.ok.plugin'), false);
    });

    test('markLoadSuccess מ-dispose מנקה את הסימון מהדיסק', () async {
      await PluginCrashGuard.markLoadAttempt('com.sync.plugin');

      // dispose() מפעיל בלי await; העדכון בזיכרון מיידי
      final cleared = PluginCrashGuard.markLoadSuccess('com.sync.plugin');
      expect(PluginCrashGuard.isBlocked('com.sync.plugin'), false);
      await cleared;

      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.sync.plugin'), false);
    });

    test('markLoadSuccess לפני אתחול אינו כותב לדיסק', () async {
      await PluginCrashGuard.markLoadSuccess('any.plugin');
      expect(await File(_guardPath(tempDir)).exists(), false);
    });

    test('markLoadAttemptIfInitialized מסתיים כשהסימון כבר בדיסק', () async {
      await PluginCrashGuard.ensureInitialized();
      await PluginCrashGuard.markLoadAttemptIfInitialized('com.sync.attempt');
      expect(PluginCrashGuard.isBlocked('com.sync.attempt'), false);
      expect(_blockedOnDisk(tempDir), ['com.sync.attempt']);

      // verified on next "launch"
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.sync.attempt'), true);
    });

    test('markLoadAttemptIfInitialized לפני אתחול אינו מסמן', () async {
      expect(PluginCrashGuard.markLoadAttemptIfInitialized('something'), null);
      expect(await File(_guardPath(tempDir)).exists(), false);
    });

    test('מסלול הסימון אינו כותב לדיסק באופן סינכרוני (#4008)', () async {
      final spy = _SyncIoSpy();
      await IOOverrides.runWithIOOverrides(() async {
        await PluginCrashGuard.ensureInitialized();
        await PluginCrashGuard.markLoadAttempt('com.async.plugin', owner: 't');
        await PluginCrashGuard.markLoadSuccess('com.async.plugin', owner: 't');
        await PluginCrashGuard.markLoadAttempt('com.async.plugin', owner: 't');
        await PluginCrashGuard.markCleanShutdown();
      }, spy);
      expect(spy.syncCalls, isEmpty);
      expect(spy.asyncWrites, 4);
    });

    test('סגירה בזמן שמירת הסימון אינה משאירה סימון ישן', () async {
      await PluginCrashGuard.ensureInitialized();
      final attempt = _attempt('com.closing.plugin', 'tab-1');
      // dispose רץ לפני שהשמירה הסתיימה
      final cleared = PluginCrashGuard.markLoadSuccess(
        'com.closing.plugin',
        owner: 'tab-1',
      );
      await Future.wait([attempt, cleared]);
      expect(_blockedOnDisk(tempDir), isEmpty);
    });

    test('סגירה יזומה ממתינה לכתיבה של טאב שנסגר רגע לפניה', () async {
      await PluginCrashGuard.markLoadAttempt('com.tab.plugin', owner: 'tab-1');
      unawaited(
        PluginCrashGuard.markLoadSuccess('com.tab.plugin', owner: 'tab-1'),
      );
      await PluginCrashGuard.markCleanShutdown();
      expect(_blockedOnDisk(tempDir), isEmpty);
    });

    test('ניסיון בסשן הנוכחי אינו נחשב חסימה — rebuild באמצע טעינה לא '
        'מציג "התוסף קרס"', () async {
      // תוסף שנחסם בהפעלה קודמת (ניסיון בלי הצלחה), המשתמש לחץ "נסה שוב"
      await PluginCrashGuard.markLoadAttempt('com.live.plugin');
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.live.plugin'), true);

      await PluginCrashGuard.retry('com.live.plugin');
      await PluginCrashGuard.markLoadAttempt('com.live.plugin');

      // ה-canary על הדיסק, אבל בסשן הזה אסור לחסום את הטעינה החיה
      expect(PluginCrashGuard.isBlocked('com.live.plugin'), false);

      // ואם בכל זאת קרס — ההפעלה הבאה כן חוסמת
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.live.plugin'), true);
    });

    test(
      'markCleanShutdown מנקה canaries בטיסה אך לא quarantine קיים',
      () async {
        // quarantine מהפעלה קודמת + טעינה חדשה שבטיסה ברגע הסגירה
        await PluginCrashGuard.markLoadAttempt('com.old.blocked');
        PluginCrashGuard.resetForTesting();
        await PluginCrashGuard.ensureInitialized();
        await PluginCrashGuard.markLoadAttempt('com.inflight.plugin');

        await PluginCrashGuard.markCleanShutdown();

        // הפעלה הבאה: הבטיסה נוקתה, החסום נשאר חסום
        PluginCrashGuard.resetForTesting();
        await PluginCrashGuard.ensureInitialized();
        expect(PluginCrashGuard.isBlocked('com.inflight.plugin'), false);
        expect(PluginCrashGuard.isBlocked('com.old.blocked'), true);
      },
    );

    test('markCleanShutdown בטוח לפני אתחול', () async {
      await PluginCrashGuard.markCleanShutdown(); // לא זורק
    });

    test('canary נשאר עד אירוע מפורש — אין ניקוי לפי זמן', () async {
      await PluginCrashGuard.markLoadAttempt('com.slow.plugin');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // קריסה אחרי טעינה איטית — עדיין נתפסת בהפעלה הבאה
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.slow.plugin'), true);
    });

    test('שני מופעים טוענים — סגירת האחד לא מנקה canary של השני', () async {
      await PluginCrashGuard.ensureInitialized();
      await Future.wait([
        _attempt('com.two.plugin', 'tab-1'),
        _attempt('com.two.plugin', 'tab-2'),
        // המופע הראשון נסגר תקין בזמן שהשני עוד באמצע טעינה — ואז קריסה.
        PluginCrashGuard.markLoadSuccess('com.two.plugin', owner: 'tab-1'),
      ]);

      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.two.plugin'), true);
    });

    test('שני מופעים — ה-canary נמחק רק כשהאחרון שבהם מסיים', () async {
      await PluginCrashGuard.ensureInitialized();
      await Future.wait([
        _attempt('com.two.plugin', 'tab-1'),
        _attempt('com.two.plugin', 'tab-2'),
        PluginCrashGuard.markLoadSuccess('com.two.plugin', owner: 'tab-1'),
        PluginCrashGuard.markLoadSuccess('com.two.plugin', owner: 'tab-2'),
      ]);

      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.two.plugin'), false);
    });

    test('מסלול async עם שני מופעים מתנהג זהה למסלול ה-sync', () async {
      await PluginCrashGuard.markLoadAttempt('com.two.plugin', owner: 'tab-1');
      await PluginCrashGuard.markLoadAttempt('com.two.plugin', owner: 'tab-2');
      await PluginCrashGuard.markLoadSuccess('com.two.plugin', owner: 'tab-1');

      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.two.plugin'), true);
    });

    test('attempt ומיד success — אין race', () async {
      // פתיחת הטאב מסמנת ומיד dispose() מנקה, בלי await ביניהם;
      // התור הסדרתי מבטיח שהתוסף לא נשאר ב-quarantine.
      await PluginCrashGuard.ensureInitialized();
      await Future.wait([
        _attempt('com.race.plugin', ''),
        PluginCrashGuard.markLoadSuccess('com.race.plugin'),
      ]);

      // verify on next launch
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.race.plugin'), false);
    });
  });
}

Future<void> _attempt(String pluginId, String owner) =>
    PluginCrashGuard.markLoadAttemptIfInitialized(pluginId, owner: owner)!;

String _guardPath(Directory root) =>
    p.join(root.path, 'plugin_crash_guard.json');

List<Object?> _blockedOnDisk(Directory root) =>
    (jsonDecode(File(_guardPath(root)).readAsStringSync()) as Map)['blocked']
        as List<Object?>;

/// מתעד גישה סינכרונית לקובץ ה-guard ולתיקיות; השאר עובר לקבצים אמיתיים.
final class _SyncIoSpy extends IOOverrides {
  final syncCalls = <String>[];
  int asyncWrites = 0;

  @override
  File createFile(String path) {
    final real = super.createFile(path);
    return path.contains('plugin_crash_guard') ? _SpyFile(real, this) : real;
  }

  @override
  Directory createDirectory(String path) =>
      _SpyDirectory(super.createDirectory(path), this);
}

class _SpyFile implements File {
  _SpyFile(this._real, this._spy);
  final File _real;
  final _SyncIoSpy _spy;

  @override
  String get path => _real.path;

  @override
  Directory get parent => Directory(p.dirname(path));

  @override
  Future<bool> exists() => _real.exists();

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _real.readAsString(encoding: encoding);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    _spy.asyncWrites++;
    return _real.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    _spy.syncCalls.add('File.${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _SpyDirectory implements Directory {
  _SpyDirectory(this._real, this._spy);
  final Directory _real;
  final _SyncIoSpy _spy;

  @override
  String get path => _real.path;

  @override
  Future<Directory> create({bool recursive = false}) =>
      _real.create(recursive: recursive);

  @override
  Future<bool> exists() => _real.exists();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    _spy.syncCalls.add('Directory.${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}
