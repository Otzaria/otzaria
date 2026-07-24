import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_service_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(HiveCache.keyName);
    await Hive.openBox<dynamic>('workspaces');
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      p.join(tempDir.path, 'backups'),
    );
  });

  tearDown(() async {
    await Hive.close();
    // סוגר את חיבור ה-DB של התוספים כדי שמחיקת התיקייה תצליח (Windows נועל
    // קבצים פתוחים), ומאפס את ה-override של נתיב הנתונים.
    PluginSystemDatabase.instance.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  test('createBackup מגבה מפתחות sz דינמיים מה-Box', () async {
    await box.put('sz:future_key', ['a', 'b']);
    await box.put('sz:progress_data', '{"tracked":true}');
    await box.put('other:key', 'ignored');

    final result = await BackupService.createBackup(
      includeSettings: false,
      includeBookmarks: false,
      includeHistory: false,
      includeNotes: false,
      includeWorkspaces: false,
      includeShamorZachor: true,
      // includeUserOverrides: false,
      includePlugins: false,
    );

    expect(result.skippedSections, isEmpty);

    final backupJson =
        jsonDecode(
              await File(result.path).readAsString(),
            )
            as Map<String, dynamic>;
    final shamorZachor = backupJson['shamorZachor'] as Map<String, dynamic>;

    expect(shamorZachor['sz:future_key'], ['a', 'b']);
    expect(shamorZachor['sz:progress_data'], '{"tracked":true}');
    expect(shamorZachor.containsKey('other:key'), isFalse);
  });

  test('restoreFromBackup משחזר טיפוסים ישירות ל-Hive', () async {
    final backupDir = Directory(p.join(tempDir.path, 'manual_backups'));
    await backupDir.create(recursive: true);
    final backupFile = File(p.join(backupDir.path, 'restore.json'));

    await backupFile.writeAsString(
      jsonEncode({
        'version': '1.0',
        'timestamp': '2026-04-24T00:00:00.000Z',
        'includes': {
          'settings': false,
          'bookmarks': false,
          'history': false,
          'notes': false,
          'workspaces': false,
          'shamorZachor': true,
          'userOverrides': false,
        },
        'shamorZachor': {
          'sz:future_key': ['a', 'b'],
          'sz:migration_completed': true,
        },
      }),
    );

    await BackupService.restoreFromBackup(backupFile.path);

    expect(box.get('sz:future_key'), ['a', 'b']);
    expect(box.get('sz:migration_completed'), isTrue);
  });

  test('restoreFromBackup משחזר currentWorkspace חדש לפי מזהה', () async {
    final backupDir = Directory(p.join(tempDir.path, 'workspace_backups'));
    await backupDir.create(recursive: true);
    final backupFile = File(
      p.join(backupDir.path, 'restore_workspace_id.json'),
    );

    const firstWorkspaceId = 'workspace-a';
    const secondWorkspaceId = 'workspace-b';

    await backupFile.writeAsString(
      jsonEncode({
        'version': '1.0',
        'timestamp': '2026-05-04T00:00:00.000Z',
        'includes': {
          'settings': false,
          'bookmarks': false,
          'history': false,
          'notes': false,
          'workspaces': true,
          'shamorZachor': false,
          'userOverrides': false,
        },
        'workspaces': [
          {
            'id': firstWorkspaceId,
            'name': 'ראשון',
            'tabs': [],
            'currentTab': 0,
          },
          {
            'id': secondWorkspaceId,
            'name': 'שני',
            'tabs': [],
            'currentTab': 0,
          },
        ],
        'currentWorkspace': secondWorkspaceId,
      }),
    );

    await BackupService.restoreFromBackup(backupFile.path);

    final (workspaces, currentWorkspaceId) = WorkspaceRepository()
        .loadWorkspaces();
    expect(workspaces, hasLength(2));
    expect(currentWorkspaceId, secondWorkspaceId);
  });

  test('restoreFromBackup תומך ב-currentWorkspace ישן כאינדקס', () async {
    final backupDir = Directory(
      p.join(tempDir.path, 'workspace_backups_legacy'),
    );
    await backupDir.create(recursive: true);
    final backupFile = File(
      p.join(backupDir.path, 'restore_workspace_index.json'),
    );

    const firstWorkspaceId = 'workspace-a';
    const secondWorkspaceId = 'workspace-b';

    await backupFile.writeAsString(
      jsonEncode({
        'version': '1.0',
        'timestamp': '2026-05-04T00:00:00.000Z',
        'includes': {
          'settings': false,
          'bookmarks': false,
          'history': false,
          'notes': false,
          'workspaces': true,
          'shamorZachor': false,
          'userOverrides': false,
        },
        'workspaces': [
          {
            'id': firstWorkspaceId,
            'name': 'ראשון',
            'tabs': [],
            'currentTab': 0,
          },
          {
            'id': secondWorkspaceId,
            'name': 'שני',
            'tabs': [],
            'currentTab': 0,
          },
        ],
        'currentWorkspace': 1,
      }),
    );

    await BackupService.restoreFromBackup(backupFile.path);

    final (workspaces, currentWorkspaceId) = WorkspaceRepository()
        .loadWorkspaces();
    expect(workspaces.map((workspace) => workspace.id), [
      firstWorkspaceId,
      secondWorkspaceId,
    ]);
    expect(currentWorkspaceId, secondWorkspaceId);
  });

  // ─── shouldPerformAutoBackup ───────────────────────────────────────────────
  group('shouldPerformAutoBackup', () {
    setUp(() async {
      await Settings.setValue<String>('key-auto-backup-frequency', 'weekly');
      await Settings.setValue<String?>('key-last-auto-backup', null);
      await Settings.setValue<String?>('key-last-partial-auto-backup', null);
    });

    test('מחזיר false כש-frequency הוא none', () async {
      await Settings.setValue<String>('key-auto-backup-frequency', 'none');
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
    });

    test('ברירת המחדל כשלא הוגדרה תדירות היא weekly', () async {
      await Settings.setValue<String?>('key-auto-backup-frequency', null);
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);
    });

    test('מחזיר true כשאין גיבוי קודם (weekly)', () async {
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);
    });

    test('מחזיר false כשגיבוי מלא לפני פחות מ-7 ימים (weekly)', () async {
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
    });

    test('מחזיר true כשגיבוי מלא לפני יותר מ-7 ימים (weekly)', () async {
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);
    });

    test('מחזיר false כשגיבוי מלא לפני פחות מ-30 ימים (monthly)', () async {
      await Settings.setValue<String>('key-auto-backup-frequency', 'monthly');
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 20)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
    });

    test('מחזיר true כשגיבוי מלא לפני יותר מ-30 ימים (monthly)', () async {
      await Settings.setValue<String>('key-auto-backup-frequency', 'monthly');
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 31)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);
    });

    test('מחזיר false אם partial cooldown פעיל (פחות משעה)', () async {
      await Settings.setValue<String>(
        'key-last-partial-auto-backup',
        DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
    });

    test('מחזיר true אם partial cooldown פג (יותר משעה)', () async {
      await Settings.setValue<String>(
        'key-last-partial-auto-backup',
        DateTime.now().subtract(const Duration(minutes: 90)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);
    });
  });

  // ─── גיבוי ושחזור תוספים ───────────────────────────────────────────────────
  group('גיבוי ושחזור תוספים', () {
    setUp(() {
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      PluginSystemDatabase.instance.resetForTests();
    });

    InstalledPlugin buildPlugin({
      required String id,
      required String installPath,
      String sourceType = 'packaged',
      String? devRootPath,
    }) {
      final manifest = PluginManifest.fromJson({
        'id': id,
        'name': 'תוסף בדיקה',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'icon': 'assets/logo.png',
        'permissions': ['clipboard.read'],
      });
      return InstalledPlugin(
        pluginId: id,
        name: 'תוסף בדיקה',
        version: '1.0.0',
        installPath: installPath,
        entrypointPath: 'index.html',
        iconPath: 'assets/logo.png',
        enabled: true,
        pinned: true,
        manifest: manifest,
        installedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
        sourceType: sourceType,
        devRootPath: devRootPath,
      );
    }

    Future<({String path, List<String> skipped})> createPluginsBackup({
      bool isAutoBackup = false,
    }) async {
      final result = await BackupService.createBackup(
        includeSettings: false,
        includeBookmarks: false,
        includeHistory: false,
        includeNotes: false,
        includeWorkspaces: false,
        includeShamorZachor: false,
        // includeUserOverrides: false,
        includePlugins: true,
        isAutoBackup: isAutoBackup,
      );
      return (path: result.path, skipped: result.skippedSections);
    }

    /// יוצר תוסף מותקן עם קובץ התקנה וקובץ נתונים, ומחזיר את הנתיבים.
    Future<({String installPath, String dataPath})> installTestPlugin(
      String pluginId,
    ) async {
      final db = PluginSystemDatabase.instance;
      final installPath = await AppPaths.getPluginInstallPath(pluginId);
      await File(p.join(installPath, 'index.html')).create(recursive: true);
      await File(p.join(installPath, 'index.html')).writeAsString('original');
      final dataPath = await AppPaths.getPluginDataPath(pluginId);
      await File(p.join(dataPath, 'state.bin')).create(recursive: true);
      await File(p.join(dataPath, 'state.bin')).writeAsBytes([7, 7, 7]);
      await db.insertOrUpdatePlugin(
        buildPlugin(id: pluginId, installPath: installPath),
      );
      return (installPath: installPath, dataPath: dataPath);
    }

    test('משחזר תוסף packaged עם קבצים, נתונים, הרשאות ו-KV', () async {
      final db = PluginSystemDatabase.instance;
      const pluginId = 'test.plugin';

      final installPath = await AppPaths.getPluginInstallPath(pluginId);
      await File(p.join(installPath, 'index.html')).create(recursive: true);
      await File(
        p.join(installPath, 'index.html'),
      ).writeAsString('<html>hi</html>');
      await File(
        p.join(installPath, 'assets', 'logo.png'),
      ).create(recursive: true);
      await File(
        p.join(installPath, 'assets', 'logo.png'),
      ).writeAsBytes([1, 2, 3, 4]);

      final dataPath = await AppPaths.getPluginDataPath(pluginId);
      await File(p.join(dataPath, 'state.bin')).create(recursive: true);
      await File(p.join(dataPath, 'state.bin')).writeAsBytes([9, 9, 9]);

      await db.insertOrUpdatePlugin(
        buildPlugin(id: pluginId, installPath: installPath),
      );
      await db.setPermission(pluginId, 'clipboard.read', true);
      await db.setPluginKV(pluginId, 'settings', 'theme', '"dark"');

      final backup = await createPluginsBackup();
      expect(backup.skipped, isEmpty);

      // מחיקה מלאה — קבצים, נתונים ורשומות DB.
      await db.deletePlugin(pluginId);
      await Directory(installPath).delete(recursive: true);
      await Directory(dataPath).delete(recursive: true);

      await BackupService.restoreFromBackup(backup.path);

      // רשומת ההתקנה שוחזרה, עם install_path מחושב מחדש.
      final restored = await db.getInstalledPlugin(pluginId);
      expect(restored, isNotNull);
      expect(restored!.name, 'תוסף בדיקה');
      expect(restored.installPath, installPath);
      expect(restored.entrypointPath, 'index.html');

      // הקבצים והנתונים שוחזרו (כולל תת-תיקיות וקבצים בינאריים).
      expect(
        await File(p.join(installPath, 'index.html')).readAsString(),
        '<html>hi</html>',
      );
      expect(
        await File(p.join(installPath, 'assets', 'logo.png')).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(await File(p.join(dataPath, 'state.bin')).readAsBytes(), [
        9,
        9,
        9,
      ]);

      // הרשאות ו-KV שוחזרו.
      expect(await db.getPermission(pluginId, 'clipboard.read'), isTrue);
      expect(await db.getPluginKV(pluginId, 'settings', 'theme'), '"dark"');
    });

    test('מדלג על תוספי development בגיבוי', () async {
      final db = PluginSystemDatabase.instance;
      final devPath = p.join(tempDir.path, 'dev_src');
      await Directory(devPath).create(recursive: true);

      await db.insertOrUpdatePlugin(
        buildPlugin(
          id: 'dev.plugin',
          installPath: devPath,
          sourceType: 'development',
          devRootPath: devPath,
        ),
      );

      final backup = await createPluginsBackup();
      final backupJson =
          jsonDecode(await File(backup.path).readAsString())
              as Map<String, dynamic>;

      expect(backupJson['plugins'], isEmpty);
    });

    test(
      'שחזור מוחק הרשאות ו-KV שאינם בגיבוי (restore נאמן, לא merge)',
      () async {
        final db = PluginSystemDatabase.instance;
        const pluginId = 'merge.plugin';

        final installPath = await AppPaths.getPluginInstallPath(pluginId);
        await File(p.join(installPath, 'index.html')).create(recursive: true);
        await File(p.join(installPath, 'index.html')).writeAsString('x');

        await db.insertOrUpdatePlugin(
          buildPlugin(id: pluginId, installPath: installPath),
        );
        await db.setPermission(pluginId, 'clipboard.read', true);
        await db.setPluginKV(pluginId, 'settings', 'theme', '"dark"');

        final backup = await createPluginsBackup();

        // אחרי הגיבוי — מוסיפים הרשאה ו-KV שאינם קיימים בגיבוי.
        await db.setPermission(pluginId, 'network.fetch', true);
        await db.setPluginKV(pluginId, 'settings', 'lang', '"he"');

        await BackupService.restoreFromBackup(backup.path);

        // מה שהיה בגיבוי שוחזר.
        expect(await db.getPermission(pluginId, 'clipboard.read'), isTrue);
        expect(await db.getPluginKV(pluginId, 'settings', 'theme'), '"dark"');
        // מה שלא היה בגיבוי נמחק.
        expect(await db.getPermission(pluginId, 'network.fetch'), isNull);
        expect(await db.getPluginKV(pluginId, 'settings', 'lang'), isNull);
      },
    );

    test('שחזור מסמן "plugins" כדילוג כשתוסף נכשל בשחזור', () async {
      final db = PluginSystemDatabase.instance;
      const pluginId = 'broken.plugin';

      final installPath = await AppPaths.getPluginInstallPath(pluginId);
      await File(p.join(installPath, 'index.html')).create(recursive: true);
      await File(p.join(installPath, 'index.html')).writeAsString('x');

      await db.insertOrUpdatePlugin(
        buildPlugin(id: pluginId, installPath: installPath),
      );

      final backup = await createPluginsBackup();

      // משבשים את ה-manifest_json כך ש-InstalledPlugin.fromDbMap יזרוק
      // בעת השחזור (אחרי שתיקיית ההתקנה כבר נמחקה).
      final backupFile = File(backup.path);
      final backupJson =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      final pluginEntry =
          (backupJson['plugins'] as List).first as Map<String, dynamic>;
      (pluginEntry['installation'] as Map)['manifest_json'] = 'not-json{';
      await backupFile.writeAsString(jsonEncode(backupJson));

      final skipped = await BackupService.restoreFromBackup(backup.path);

      expect(
        skipped,
        contains('plugins'),
        reason: 'כשל בשחזור חייב להציג שחזור חלקי במקום דיווח-שווא',
      );
    });

    test(
      'גיבוי ידני עצמאי — קבצי תוספים מוטמעים כ-base64 ללא הפניות store',
      () async {
        const pluginId = 'manual.plugin';
        final paths = await installTestPlugin(pluginId);

        final backup = await createPluginsBackup();
        expect(backup.skipped, isEmpty);

        final backupJson =
            jsonDecode(await File(backup.path).readAsString())
                as Map<String, dynamic>;
        final pluginEntry =
            (backupJson['plugins'] as List).first as Map<String, dynamic>;
        final allValues = [
          ...(pluginEntry['files'] as Map).values,
          ...(pluginEntry['data'] as Map).values,
        ];
        expect(allValues, isNotEmpty);
        for (final value in allValues) {
          expect(
            value,
            isNot(startsWith('sha256:')),
            reason: 'גיבוי ידני חייב להיות קובץ עצמאי בלי תלות במחסן',
          );
        }

        // הקובץ לבדו מספיק לשחזור — גם בלי תיקיית store ליד.
        final standalone = File(p.join(tempDir.path, 'copied_backup.json'));
        await File(backup.path).copy(standalone.path);
        await PluginSystemDatabase.instance.deletePlugin(pluginId);
        await Directory(paths.installPath).delete(recursive: true);
        await Directory(paths.dataPath).delete(recursive: true);

        final skipped = await BackupService.restoreFromBackup(standalone.path);

        expect(skipped, isEmpty);
        expect(
          await File(p.join(paths.installPath, 'index.html')).readAsString(),
          'original',
        );
        expect(await File(p.join(paths.dataPath, 'state.bin')).readAsBytes(), [
          7,
          7,
          7,
        ]);
      },
    );

    test(
      'roundtrip גיבוי אוטומטי v2 — קבצים כהפניות store ושחזור מלא',
      () async {
        const pluginId = 'auto.plugin';
        final paths = await installTestPlugin(pluginId);

        final backup = await createPluginsBackup(isAutoBackup: true);
        expect(backup.skipped, isEmpty);

        final backupJson =
            jsonDecode(await File(backup.path).readAsString())
                as Map<String, dynamic>;
        final pluginEntry =
            (backupJson['plugins'] as List).first as Map<String, dynamic>;
        for (final value in (pluginEntry['files'] as Map).values) {
          expect(value, startsWith('sha256:'));
        }

        await PluginSystemDatabase.instance.deletePlugin(pluginId);
        await Directory(paths.installPath).delete(recursive: true);
        await Directory(paths.dataPath).delete(recursive: true);

        final skipped = await BackupService.restoreFromBackup(backup.path);

        expect(skipped, isEmpty);
        expect(
          await File(p.join(paths.installPath, 'index.html')).readAsString(),
          'original',
        );
        expect(await File(p.join(paths.dataPath, 'state.bin')).readAsBytes(), [
          7,
          7,
          7,
        ]);
      },
    );

    test('store חסר — השחזור נכשל בלי למחוק את ההתקנה הקיימת', () async {
      const pluginId = 'nostore.plugin';
      final paths = await installTestPlugin(pluginId);

      final backup = await createPluginsBackup(isAutoBackup: true);
      await Directory(
        p.join(File(backup.path).parent.path, 'store'),
      ).delete(recursive: true);

      final skipped = await BackupService.restoreFromBackup(backup.path);

      expect(skipped, contains('plugins'));
      expect(
        await File(p.join(paths.installPath, 'index.html')).readAsString(),
        'original',
        reason: 'התקנה קיימת חייבת לשרוד שחזור שנכשל על store חסר',
      );
      expect(await File(p.join(paths.dataPath, 'state.bin')).readAsBytes(), [
        7,
        7,
        7,
      ]);
    });

    test(
      'נתיב path traversal מכשיל את שחזור התוסף לפני מחיקת ההתקנה הקיימת',
      () async {
        final db = PluginSystemDatabase.instance;
        const pluginId = 'evil.plugin';

        final installPath = await AppPaths.getPluginInstallPath(pluginId);
        await File(p.join(installPath, 'index.html')).create(recursive: true);
        await File(p.join(installPath, 'index.html')).writeAsString('safe');

        await db.insertOrUpdatePlugin(
          buildPlugin(id: pluginId, installPath: installPath),
        );

        final backup = await createPluginsBackup();

        // מזריקים נתיב traversal לתוך קטע התוספים של הגיבוי.
        final backupFile = File(backup.path);
        final backupJson =
            jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
        final pluginEntry =
            (backupJson['plugins'] as List).first as Map<String, dynamic>;
        (pluginEntry['files'] as Map)['../evil.txt'] = base64Encode([6, 6, 6]);
        await backupFile.writeAsString(jsonEncode(backupJson));

        final skipped = await BackupService.restoreFromBackup(backup.path);

        // שחזור התוסף נכשל, ההתקנה הקיימת שרדה והקובץ החורג לא נכתב.
        expect(skipped, contains('plugins'));
        expect(
          await File(p.join(installPath, 'index.html')).readAsString(),
          'safe',
        );
        final escaped = File(
          p.normalize(p.join(installPath, '..', 'evil.txt')),
        );
        expect(await escaped.exists(), isFalse);
      },
    );
  });
}
