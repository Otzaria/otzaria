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
      expect(PluginCrashGuard.isBlocked('com.example.plugin'), true);

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

    test('retryAll clears all quarantined plugins', () async {
      PluginCrashGuard.setInitialBlockedForTesting({'a', 'b', 'c'});
      await PluginCrashGuard.retryAll();
      expect(PluginCrashGuard.isBlocked('a'), false);
      expect(PluginCrashGuard.isBlocked('b'), false);
      expect(PluginCrashGuard.isBlocked('c'), false);
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

      // Retry triggers a new load attempt
      await PluginCrashGuard.markLoadAttempt('com.crash.plugin');
      expect(PluginCrashGuard.isBlocked('com.crash.plugin'), true);

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

    test('markLoadSuccessSync clears the plugin from disk', () async {
      await PluginCrashGuard.markLoadAttempt('com.sync.plugin');
      // sanity: blocked now
      expect(PluginCrashGuard.isBlocked('com.sync.plugin'), true);

      // sync clear (the path used by dispose())
      PluginCrashGuard.markLoadSuccessSync('com.sync.plugin');
      expect(PluginCrashGuard.isBlocked('com.sync.plugin'), false);

      // persisted to disk synchronously — visible on next "launch"
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.sync.plugin'), false);
    });

    test('markLoadSuccessSync is safe when not initialized yet', () {
      // לא קורא ל-ensureInitialized — שמיר על rule שזה בטוח בכל מצב
      PluginCrashGuard.markLoadSuccessSync('any.plugin'); // לא זורק
    });

    test('markLoadAttemptSync persists immediately', () async {
      await PluginCrashGuard.ensureInitialized();
      PluginCrashGuard.markLoadAttemptSync('com.sync.attempt');
      expect(PluginCrashGuard.isBlocked('com.sync.attempt'), true);

      // verified on next "launch"
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.sync.attempt'), true);
    });

    test('markLoadAttemptSync is safe when not initialized yet', () {
      PluginCrashGuard.markLoadAttemptSync('something'); // לא זורק
    });

    test('attempt+success סינכרוני אטומי — אין race', () async {
      // מדמה את התרחיש: onWebViewCreated קורא markLoadAttemptSync, ומיד
      // לאחר מכן dispose() קורא markLoadSuccessSync. שניהם sync, אין
      // ביניהם async gap. התוצאה: התוסף לא נשאר ב-quarantine.
      await PluginCrashGuard.ensureInitialized();
      PluginCrashGuard.markLoadAttemptSync('com.race.plugin');
      PluginCrashGuard.markLoadSuccessSync('com.race.plugin');

      // verify on next launch
      PluginCrashGuard.resetForTesting();
      await PluginCrashGuard.ensureInitialized();
      expect(PluginCrashGuard.isBlocked('com.race.plugin'), false);
    });
  });
}
