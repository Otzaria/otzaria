import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
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

  // רשימת המפתחות ב-_backupSettings קשיחה; הטסט הזה הוא השומר שמונע השמטה של
  // התאמות הכלים (סדר, הסתרה, הצמדה) בגיבוי הבא.
  test('createBackup כולל את הגדרות הכלים ומשחזר אותן', () async {
    await Settings.setValue<String>(
      SettingsRepository.keyBuiltInToolsOrder,
      'builtin.gematria,builtin.calendar',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyHiddenBuiltInToolIds,
      'builtin.notes',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyBuiltInToolsPinnedToNavRail,
      'builtin.calendar',
    );

    final result = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: false,
      includeHistory: false,
      includeNotes: false,
      includeWorkspaces: false,
      includeShamorZachor: false,
      includePlugins: false,
    );

    final settings =
        (jsonDecode(await File(result.path).readAsString())
                as Map<String, dynamic>)['settings']
            as Map<String, dynamic>;
    expect(
      settings[SettingsRepository.keyBuiltInToolsOrder],
      'builtin.gematria,builtin.calendar',
    );
    expect(
      settings[SettingsRepository.keyHiddenBuiltInToolIds],
      'builtin.notes',
    );
    expect(
      settings[SettingsRepository.keyBuiltInToolsPinnedToNavRail],
      'builtin.calendar',
    );

    await Settings.setValue<String>(
      SettingsRepository.keyBuiltInToolsOrder,
      '',
    );
    await BackupService.restoreFromBackup(result.path);

    expect(
      Settings.getValue<String>(
        SettingsRepository.keyBuiltInToolsOrder,
        defaultValue: '',
      ),
      'builtin.gematria,builtin.calendar',
    );
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

    // ה-plugin_id מגיע מקובץ הגיבוי ומרכיב נתיב שנמחק ב-recursive; `..` היה
    // מוחק את תיקיית האב של תיקיות התוספים.
    test('שחזור דוחה plugin_id זדוני ואינו מוחק תיקייה שרירותית', () async {
      const pluginId = 'evil.plugin';
      await installTestPlugin(pluginId);
      final backup = await createPluginsBackup();

      final dataRoot = Directory(
        p.dirname(await AppPaths.getPluginDataPath(pluginId)),
      );
      final bystander = File(p.join(dataRoot.path, 'bystander.txt'))
        ..writeAsStringSync('חייב לשרוד');

      final json =
          jsonDecode(await File(backup.path).readAsString())
              as Map<String, dynamic>;
      final entry = (json['plugins'] as List).single as Map<String, dynamic>;
      (entry['installation'] as Map)['plugin_id'] = '..';
      await File(backup.path).writeAsString(jsonEncode(json));

      final result = await BackupService.restoreFromBackup(backup.path);

      expect(bystander.existsSync(), isTrue);
      expect(bystander.readAsStringSync(), 'חייב לשרוד');
      expect(dataRoot.existsSync(), isTrue);
      expect(result.skippedSections, contains('plugins'));
    });

    test('גיבוי אינו עוקב אחרי symlink בתיקיית נתוני התוסף', () async {
      const pluginId = 'link.plugin';
      final paths = await installTestPlugin(pluginId);

      final outside = Directory(p.join(tempDir.path, 'outside_secret'))
        ..createSync(recursive: true);
      File(p.join(outside.path, 'secret.txt')).writeAsStringSync('סוד');
      try {
        Link(p.join(paths.dataPath, 'leak')).createSync(outside.path);
      } catch (_) {
        markTestSkipped('יצירת symlink אינה נתמכת בסביבה זו');
        return;
      }

      final backup = await createPluginsBackup();
      final json =
          jsonDecode(await File(backup.path).readAsString())
              as Map<String, dynamic>;
      final entry = (json['plugins'] as List).single as Map<String, dynamic>;
      final data = (entry['data'] as Map).cast<String, dynamic>();

      expect(data.keys, contains('state.bin'));
      expect(data.keys.any((k) => k.contains('secret')), isFalse);
    });

    test('תוסף שחורג מתקרת הארכיון מדולג ומדווח כחלקי', () async {
      await installTestPlugin('small.plugin');
      BackupService.debugMaxPluginBytesOverride = 1; // כל תוסף חורג
      addTearDown(() => BackupService.debugMaxPluginBytesOverride = null);

      final backup = await createPluginsBackup();

      expect(backup.skipped, contains('plugins'));
      final json =
          jsonDecode(await File(backup.path).readAsString())
              as Map<String, dynamic>;
      expect(json['plugins'], isEmpty);
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

      final skipped = (await BackupService.restoreFromBackup(
        backup.path,
      )).skippedSections;

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

        final skipped = (await BackupService.restoreFromBackup(
          standalone.path,
        )).skippedSections;

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

        final skipped = (await BackupService.restoreFromBackup(
          backup.path,
        )).skippedSections;

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

      final skipped = (await BackupService.restoreFromBackup(
        backup.path,
      )).skippedSections;

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

        final skipped = (await BackupService.restoreFromBackup(
          backup.path,
        )).skippedSections;

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

  // ─── הגדרות פר-ספר ─────────────────────────────────────────────────────────
  // ההתאמות הפר-ספריות (מפרשים פעילים, גופן, רוחבי צורת הדף) יושבות בקבצי JSON
  // מחוץ ל-Hive, ולכן נשמטו מהגיבוי לגמרי — ספר שהוגדרו לו מפרשים חזר ריק.
  group('גיבוי ושחזור הגדרות פר-ספר', () {
    setUp(() => AppPaths.debugOverrideDataRootPath(tempDir.path));

    Future<File> perBookFile(String name) async =>
        File(p.join(await AppPaths.getPerBookSettingsPath(), name));

    Future<String> createSettingsBackup() async =>
        (await BackupService.createBackup(
          includeSettings: true,
          includeBookmarks: false,
          includeHistory: false,
          includeNotes: false,
          includeWorkspaces: false,
          includeShamorZachor: false,
          includePlugins: false,
        )).path;

    test('קובץ הגדרות פר-ספר מגובה ומשוחזר', () async {
      const content = '{"activeCommentators":["מנחת חינוך"],"fontSize":31.0}';
      final file = await perBookFile('settings_${'a' * 40}.json');
      await file.create(recursive: true);
      await file.writeAsString(content);

      final path = await createSettingsBackup();
      await file.delete();

      final result = await BackupService.restoreFromBackup(path);

      expect(result.hasLegacyPartialSettings, isFalse);
      expect(await file.readAsString(), content);
    });

    test('שחזור אינו מוחק התאמות של ספרים שאינם בגיבוי', () async {
      final backedUp = await perBookFile('settings_${'b' * 40}.json');
      await backedUp.create(recursive: true);
      await backedUp.writeAsString('{"fontSize":20.0}');

      final path = await createSettingsBackup();

      final untouched = await perBookFile('settings_${'c' * 40}.json');
      await untouched.writeAsString('{"fontSize":40.0}');
      await BackupService.restoreFromBackup(path);

      expect(await untouched.readAsString(), '{"fontSize":40.0}');
    });

    test('שם קובץ חורג בגיבוי מדולג ואינו נכתב מחוץ לתיקייה', () async {
      final path = await createSettingsBackup();
      final backupFile = File(path);
      final json =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      (json['perBookSettings'] as Map)['../escaped.json'] = '{"fontSize":9.0}';
      await backupFile.writeAsString(jsonEncode(json));

      final result = await BackupService.restoreFromBackup(path);

      final escaped = File(
        p.normalize(
          p.join(await AppPaths.getPerBookSettingsPath(), '..', 'escaped.json'),
        ),
      );
      expect(await escaped.exists(), isFalse);
      expect(result.skippedSections, contains('perBookSettings'));
    });

    test('ערך קובץ לא קריא מדווח כשחזור חלקי', () async {
      final path = await createSettingsBackup();
      final backupFile = File(path);
      final json =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      (json['perBookSettings'] as Map)['settings_bad.json'] = 1;
      await backupFile.writeAsString(jsonEncode(json));

      final result = await BackupService.restoreFromBackup(path);

      expect(result.skippedSections, contains('perBookSettings'));
    });

    test('גיבוי ללא חתימת מקור ההגדרות מדווח כחלקי', () async {
      final path = await createSettingsBackup();
      final backupFile = File(path);
      final json =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      // גיבוי מגרסה שאספה רשימת מפתחות מוצהרת בלבד — בלי השדה הזה.
      json.remove('settingsSource');
      await backupFile.writeAsString(jsonEncode(json));

      final result = await BackupService.restoreFromBackup(path);

      expect(result.hasLegacyPartialSettings, isTrue);
    });

    test('גיבוי שלם מלפני החתימה אינו מדווח כחלקי', () async {
      // page_shape_* אינו מפתח מוצהר, ולכן רק סריקת ה-Box מייצרת אותו.
      await box.put('page_shape_book_בראשית', 'left|רש"י');
      final path = await createSettingsBackup();
      final backupFile = File(path);
      final json =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      json.remove('settingsSource');
      await backupFile.writeAsString(jsonEncode(json));

      final result = await BackupService.restoreFromBackup(path);

      expect(result.hasLegacyPartialSettings, isFalse);
    });
  });

  // ─── עוגן ההערות בשחזור ────────────────────────────────────────────────────
  // גיבוי מלפני שהעיגון נכנס אליו אינו נושא את שדות העוגן כלל, ו-insertNote
  // הוא INSERT OR REPLACE — בלי שימור, הערה שהצביעה על מילה נמתחה על כל השורה.
  group('שחזור הערות — שימור העוגן', () {
    late Directory dataRoot;

    PersonalNote anchoredNote() => PersonalNote(
      id: 'note-1',
      bookId: 'ספר',
      lineNumber: 5,
      anchorText: 'כוס',
      anchorPrefix: 'לפני ',
      anchorSuffix: ' אחרי',
      anchorStart: 10,
      anchorEnd: 13,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'תוכן ההערה',
      contentPlain: 'תוכן ההערה',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime.parse('2026-06-14T13:36:57.000Z'),
      updatedAt: DateTime.parse('2026-06-14T13:36:57.000Z'),
    );

    /// מניפסט גיבוי עם הערה אחת. [withAnchorKeys] false = פורמט מדור קודם.
    Future<String> writeNotesBackup({required bool withAnchorKeys}) async {
      final note = <String, dynamic>{
        'id': 'note-1',
        'bookId': 'ספר',
        'lineNumber': 5,
        'displayTitle': null,
        'lastKnownLineNumber': null,
        'status': 'located',
        'content': 'תוכן ההערה',
        'contentPlain': 'תוכן ההערה',
        'contentFormat': 'plain',
        'createdAt': '2026-06-14T13:36:57.000Z',
        'updatedAt': '2026-06-14T13:36:57.000Z',
        if (withAnchorKeys) ...{
          'anchorText': null,
          'anchorPrefix': null,
          'anchorSuffix': null,
          'anchorStart': null,
          'anchorEnd': null,
        },
      };
      final file = File(p.join(dataRoot.path, 'notes_backup.json'));
      await file.writeAsString(
        jsonEncode({
          'version': '2.0',
          'timestamp': '2026-07-06T00-00-00.000',
          'includes': {'notes': true},
          'notes': [
            {
              'bookId': 'ספר',
              'notes': [note],
            },
          ],
        }),
      );
      return file.path;
    }

    setUp(() async {
      dataRoot = await Directory.systemTemp.createTemp('notes_anchor_test_');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      await PersonalNotesDatabase.instance.close();
      await PersonalNotesDatabase.instance.insertNote(anchoredNote());
    });

    tearDown(() async {
      await PersonalNotesDatabase.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      try {
        await dataRoot.delete(recursive: true);
      } catch (_) {}
    });

    test('גיבוי מדור קודם אינו מוחק עוגן קיים, ומדווח', () async {
      final path = await writeNotesBackup(withAnchorKeys: false);

      final result = await BackupService.restoreFromBackup(path);

      final restored = await PersonalNotesDatabase.instance.getNote('note-1');
      expect(restored!.anchorText, 'כוס');
      expect(restored.anchorStart, 10);
      expect(restored.content, 'תוכן ההערה');
      expect(result.notesWithoutAnchor, 0);
    });

    test('גיבוי מדור קודם בלי עוגן קיים ב-DB — מדווח על ההערה', () async {
      await PersonalNotesDatabase.instance.deleteNote('note-1');
      final path = await writeNotesBackup(withAnchorKeys: false);

      final result = await BackupService.restoreFromBackup(path);

      expect(result.notesWithoutAnchor, 1);
      final restored = await PersonalNotesDatabase.instance.getNote('note-1');
      expect(restored!.isWordAnchored, isFalse);
    });

    test('עוגן null מפורש הוא בחירת משתמש ומכובד', () async {
      final path = await writeNotesBackup(withAnchorKeys: true);

      final result = await BackupService.restoreFromBackup(path);

      final restored = await PersonalNotesDatabase.instance.getNote('note-1');
      expect(restored!.anchorText, isNull);
      expect(result.notesWithoutAnchor, 0);
    });
  });

  // ─── זיהוי סעיף הגדרות חלקי ────────────────────────────────────────────────
  group('isPartialSettingsSection', () {
    final declaredOnly = {
      SettingsRepository.keyFontSize: 25.0,
      SettingsRepository.keyLibraryViewMode: 'grid',
    };
    final scanned = {
      ...declaredOnly,
      'page_shape_view_mode_בראשית': true,
    };

    test('חתימת box שוללת חלקיות', () {
      expect(
        BackupService.isPartialSettingsSection(declaredOnly, 'box'),
        isFalse,
      );
    });

    test('חתימת declared-keys מצהירה על חלקיות', () {
      expect(
        BackupService.isPartialSettingsSection(scanned, 'declared-keys'),
        isTrue,
      );
    });

    test('בלי חתימה: רק מפתחות מוצהרים = חלקי', () {
      expect(
        BackupService.isPartialSettingsSection(declaredOnly, null),
        isTrue,
      );
    });

    test('בלי חתימה: מפתח שאינו מוצהר מוכיח סריקת Box', () {
      expect(BackupService.isPartialSettingsSection(scanned, null), isFalse);
    });

    test('בלי חתימה: קיצור מקלדת לבדו אינו מוכיח סריקה', () {
      // הקיצורים היו בתוך רשימת הנסיגה, ולכן אינם עדות לסריקת Box.
      final withShortcut = {
        ...declaredOnly,
        ...{
          for (final key in ShortcutValidator.shortcutKeys.take(1))
            key: 'ctrl+a',
        },
      };
      expect(
        BackupService.isPartialSettingsSection(withShortcut, null),
        isTrue,
      );
    });

    test('סעיף הגדרות ריק אינו מדווח כשלם', () {
      expect(BackupService.isPartialSettingsSection(const {}, null), isTrue);
    });
  });

  // ─── הטאבים הפתוחים ────────────────────────────────────────────────────────
  // הטאבים יושבים ב-box נפרד ולא היו בגיבוי כלל: אחרי שחזור התוכנה נפתחה
  // בלי הספרים שהיו פתוחים.
  group('גיבוי ושחזור הטאבים הפתוחים', () {
    late Box<dynamic> tabsBox;

    setUp(() async {
      tabsBox = await Hive.openBox<dynamic>(TabsRepository.boxName);
    });

    Future<String> createWorkspacesBackup() async =>
        (await BackupService.createBackup(
          includeSettings: false,
          includeBookmarks: false,
          includeHistory: false,
          includeNotes: false,
          includeWorkspaces: true,
          includeShamorZachor: false,
          includePlugins: false,
        )).path;

    test('הטאבים והטאב הפעיל עוברים גיבוי ושחזור', () async {
      final tabs = [
        {'type': 'TextBookTab', 'title': 'בראשית'},
        {'type': 'TextBookTab', 'title': 'שמות'},
      ];
      await tabsBox.put('key-tabs', tabs);
      await tabsBox.put('key-current-tab', 1);

      final path = await createWorkspacesBackup();
      await tabsBox.put('key-tabs', <dynamic>[]);
      await tabsBox.put('key-current-tab', 0);

      await BackupService.restoreFromBackup(path);

      expect((tabsBox.get('key-tabs') as List), hasLength(2));
      expect(tabsBox.get('key-current-tab'), 1);
    });

    test('גיבוי בלי סעיף טאבים אינו מרוקן את הטאבים הקיימים', () async {
      final path = await createWorkspacesBackup();
      final backupFile = File(path);
      final json =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      json.remove('openTabs');
      await backupFile.writeAsString(jsonEncode(json));

      await tabsBox.put('key-tabs', [
        {'type': 'TextBookTab', 'title': 'ויקרא'},
      ]);
      await BackupService.restoreFromBackup(path);

      expect((tabsBox.get('key-tabs') as List), hasLength(1));
    });
  });

  group('גיבוי ושחזור דיווחי טעות שמורים', () {
    late Box<dynamic> reportsBox;

    setUp(() async {
      reportsBox = await Hive.openBox<dynamic>(
        DirectErrorReportService.queueBoxName,
      );
      await Hive.openBox<dynamic>(PluginReportService.queueBoxName);
    });

    Map<String, dynamic> report(String id) => {
      'id': id,
      'senderEmail': 'a@b.com',
      'subject': 'טעות',
      'bookTitle': 'בראשית',
      'currentRef': 'א,א',
      'lineNumber': 1,
      'createdAt': '2026-08-20T10:00:00.000',
    };

    Future<String> createSettingsBackup() async =>
        (await BackupService.createBackup(
          includeSettings: true,
          includeBookmarks: false,
          includeHistory: false,
          includeNotes: false,
          includeWorkspaces: false,
          includeShamorZachor: false,
          includePlugins: false,
        )).path;

    test('הדיווחים הממתינים וההיסטוריה עוברים גיבוי ושחזור', () async {
      await reportsBox.put(DirectErrorReportService.pendingReportsKey, [
        report('pending-1'),
      ]);
      await reportsBox.put(DirectErrorReportService.sentReportsKey, [
        report('sent-1'),
      ]);

      final path = await createSettingsBackup();
      // איפוס הגדרות מוחק את התור — זה בדיוק המצב שבו השחזור נדרש.
      await reportsBox.clear();

      await BackupService.restoreFromBackup(path);

      // דרך השירות ולא רק דרך ה-box: מאמת שהצורה ששוחזרה נטענת למודל.
      final service = DirectErrorReportService();
      expect((await service.getPendingReports()).single.id, 'pending-1');
      expect((await service.getSentReports()).single.id, 'sent-1');
      await service.closeHttpClient();
    });

    test('דיווח שנשלח מאז אינו חוזר לתור בשחזור', () async {
      await reportsBox.put(DirectErrorReportService.pendingReportsKey, [
        report('r-1'),
      ]);
      final path = await createSettingsBackup();

      // הדיווח נשלח בין הגיבוי לשחזור: עבר לרשימת הנשלחים והתור התרוקן.
      await reportsBox.put(
        DirectErrorReportService.pendingReportsKey,
        <dynamic>[],
      );
      await reportsBox.put(DirectErrorReportService.sentReportsKey, [
        report('r-1'),
      ]);

      await BackupService.restoreFromBackup(path);

      expect(
        reportsBox.get(DirectErrorReportService.pendingReportsKey),
        isEmpty,
      );
      expect(
        (reportsBox.get(DirectErrorReportService.sentReportsKey) as List),
        hasLength(1),
      );
    });

    test('דיווח שנוצר אחרי הגיבוי שורד את השחזור', () async {
      await reportsBox.put(DirectErrorReportService.pendingReportsKey, [
        report('old'),
      ]);
      final path = await createSettingsBackup();

      await reportsBox.put(DirectErrorReportService.pendingReportsKey, [
        report('new'),
      ]);
      await BackupService.restoreFromBackup(path);

      final ids =
          (reportsBox.get(DirectErrorReportService.pendingReportsKey) as List)
              .map((e) => (e as Map)['id'])
              .toList();
      expect(ids, containsAll(['new', 'old']));
    });

    test('box סגור בזמן הגיבוי מסמן את הסעיף כחלקי', () async {
      await reportsBox.close();

      final result = await BackupService.createBackup(
        includeSettings: true,
        includeBookmarks: false,
        includeHistory: false,
        includeNotes: false,
        includeWorkspaces: false,
        includeShamorZachor: false,
        includePlugins: false,
      );

      expect(result.skippedSections, contains('reportQueues'));
    });
  });
}
