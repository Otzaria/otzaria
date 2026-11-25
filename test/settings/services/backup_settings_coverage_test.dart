import 'dart:convert';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:path/path.dart' as p;

/// גיבוי ההגדרות אחרי המעבר מרשימת-היתר לסריקת ה-Hive box:
/// כל מפתח מגובה למעט [BackupService.nonPortableSettingsKeys], ותיקיות ספרים
/// שנתיבן חסר ביעד מדווחות למשתמש.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_settings_test_');
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
    PluginSystemDatabase.instance.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  /// יוצר גיבוי הגדרות בלבד ומחזיר את סעיף ה-settings שבקובץ.
  Future<Map<String, dynamic>> backupSettingsSection() async {
    final result = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: false,
      includeHistory: false,
      includeNotes: false,
      includeWorkspaces: false,
      includeShamorZachor: false,
      includePlugins: false,
    );
    final json =
        jsonDecode(await File(result.path).readAsString())
            as Map<String, dynamic>;
    return (json['settings'] as Map).cast<String, dynamic>();
  }

  String foldersJson(List<String> paths) => CustomFoldersManager.saveFolders([
    for (final path in paths)
      CustomFolder(path: path, addedAt: DateTime(2026, 1, 1)),
  ]);

  group('isPortableSettingKey', () {
    test('מפתח הגדרות רגיל מגובה', () {
      expect(
        BackupService.isPortableSettingKey(SettingsRepository.keyCustomFolders),
        isTrue,
      );
      expect(
        BackupService.isPortableSettingKey(SettingsRepository.keyFontSize),
        isTrue,
      );
    });

    test('מפתח שמור-וזכור אינו חלק מההגדרות (מגובה בסעיף נפרד)', () {
      expect(BackupService.isPortableSettingKey('sz:progress_by_id'), isFalse);
      expect(BackupService.isPortableSettingKey('sz:anything'), isFalse);
    });

    test('טיוטת הערה אישית אינה הגדרה ואינה נכנסת לסעיף ההגדרות', () {
      // הטיוטה מחזיקה את מלוא תוכן ההערה. הכללתה כאן הייתה מגבה הערות גם
      // למשתמש שביקש לגבות הגדרות בלבד.
      const key = '${PersonalNoteDraftService.keyPrefix}book-1:42';
      expect(BackupService.isNonSettingKey(key), isTrue);
      expect(BackupService.isPortableSettingKey(key), isFalse);
    });

    test('מפתח ברשימת החסימה אינו מגובה', () {
      for (final key in BackupService.nonPortableSettingsKeys) {
        expect(
          BackupService.isPortableSettingKey(key),
          isFalse,
          reason: 'ציפינו ש-$key לא ייכנס לגיבוי',
        );
      }
    });

    test('מפתח שאינו מוצהר ב-SettingsRepository מגובה גם כן', () {
      // הגדרות גימטריה וקיצורי תוספים אינן ב-SettingsRepository — סריקת ה-box
      // היא מה שמכניס אותן לגיבוי.
      expect(
        BackupService.isPortableSettingKey('key-gematria-max-results'),
        isTrue,
      );
      expect(
        BackupService.isPortableSettingKey('key-shortcut-open-plugin-abc'),
        isTrue,
      );
    });
  });

  group('createBackup — סעיף ההגדרות', () {
    test('מגבה את רשימת התיקיות המותאמות אישית', () async {
      // רגרסיה: key-custom-folders נשמט מרשימת-ההיתר, ולכן שחזור לא החזיר
      // את תיקיות הספרים של המשתמש.
      final value = foldersJson([p.join(tempDir.path, 'ספרים שלי')]);
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        value,
      );

      final settings = await backupSettingsSection();

      expect(settings[SettingsRepository.keyCustomFolders], value);
    });

    test('מגבה את שם תת-תיקיית הספרייה', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        'אוצריא',
      );

      final settings = await backupSettingsSection();

      expect(settings[SettingsRepository.keyLibraryFolderName], 'אוצריא');
    });

    test('מגבה קיצור מקלדת שהמשתמש שינה', () async {
      await Settings.setValue<String>('key-shortcut-close-tab', 'ctrl+q');

      final settings = await backupSettingsSection();

      expect(settings['key-shortcut-close-tab'], 'ctrl+q');
    });

    test('מגבה קיצור של תוסף — מפתח שנגזר בזמן ריצה', () async {
      await Settings.setValue<String>(
        'key-shortcut-open-plugin-my.plugin',
        'ctrl+shift+p',
      );

      final settings = await backupSettingsSection();

      expect(settings['key-shortcut-open-plugin-my.plugin'], 'ctrl+shift+p');
    });

    test('מגבה הגדרות כלים שאינן מוצהרות ב-SettingsRepository', () async {
      await Settings.setValue<int>('key-gematria-max-results', 42);
      await Settings.setValue<bool>('key-gematria-torah-only', true);

      final settings = await backupSettingsSection();

      expect(settings['key-gematria-max-results'], 42);
      expect(settings['key-gematria-torah-only'], isTrue);
    });

    test('מגבה את העדפות הגיבוי עצמן', () async {
      await Settings.setValue<String>('key-auto-backup-frequency', 'daily');

      final settings = await backupSettingsSection();

      expect(settings['key-auto-backup-frequency'], 'daily');
    });

    test('אינו מגבה מפתחות שאינם ניידים בין התקנות', () async {
      await Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, true);
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        '/data/user/0/otzaria/seforim.db',
      );
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime(2026, 1, 1).toIso8601String(),
      );
      await Settings.setValue<String>(
        SettingsRepository.keyGoogleCalendarCredentialsJson,
        '{"refresh_token":"secret"}',
      );

      final settings = await backupSettingsSection();

      expect(settings.containsKey(SettingsRepository.keyIsFullscreen), isFalse);
      expect(
        settings.containsKey(SettingsRepository.keyDbEffectivePath),
        isFalse,
      );
      expect(settings.containsKey('key-last-auto-backup'), isFalse);
      expect(
        settings.containsKey(
          SettingsRepository.keyGoogleCalendarCredentialsJson,
        ),
        isFalse,
        reason: 'אסימון גישה חי לא נכנס לקובץ גיבוי נייד',
      );
    });

    test('אינו מערבב מפתחות שמור-וזכור לתוך ההגדרות', () async {
      await box.put('sz:progress_by_id', '{"1":{}}');

      final settings = await backupSettingsSection();

      expect(settings.containsKey('sz:progress_by_id'), isFalse);
    });

    test('אינו מכניס טיוטות הערות אישיות לתוך ההגדרות', () async {
      // הטיוטה יושבת באותו box ומחזיקה את מלוא תוכן ההערה: גיבוי הגדרות בלבד
      // היה מוציא איתו הערות שהמשתמש לא ביקש לגבות.
      const draftKey = '${PersonalNoteDraftService.keyPrefix}book-1:42';
      await box.put(draftKey, '{"contentPlain":"טקסט פרטי"}');

      final settings = await backupSettingsSection();

      expect(settings.containsKey(draftKey), isFalse);
      expect(
        settings.values.whereType<String>().any((v) => v.contains('טקסט פרטי')),
        isFalse,
      );
    });

    test('גיבוי הגדרות כולל את מתג האיתור בלי נתוני הלמידה', () async {
      await Settings.setValue<bool>(FindRefPreferenceStore.enabledKey, false);
      await Settings.setValue<String>(
        FindRefPreferenceStore.scoresKey,
        '{"books":{"f|/library/private.pdf":[3,"ספר אישי"]}}',
      );

      final settings = await backupSettingsSection();

      expect(settings[FindRefPreferenceStore.enabledKey], isFalse);
      expect(settings, isNot(contains(FindRefPreferenceStore.scoresKey)));
    });

    test('מגבה את שאר הגדרות יומן Google למרות חסימת האסימון', () async {
      await Settings.setValue<bool>(
        SettingsRepository.keyGoogleCalendarEnabled,
        true,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyGoogleCalendarClientId,
        'client-123',
      );

      final settings = await backupSettingsSection();

      expect(settings[SettingsRepository.keyGoogleCalendarEnabled], isTrue);
      expect(
        settings[SettingsRepository.keyGoogleCalendarClientId],
        'client-123',
      );
    });

    test('כל מפתח שנשמר ב-box ואינו חסום מופיע בגיבוי', () async {
      for (final key in SettingsRepository.allKeys) {
        // נתיב הגיבוי נשאר על תיקיית הבדיקה — דריסתו הייתה מפנה את הכתיבה
        // לנתיב יחסי בשורש הפרויקט.
        if (key == SettingsRepository.keyBackupPath) continue;
        await box.put(key, 'value-of-$key');
      }

      final settings = await backupSettingsSection();

      final expected = SettingsRepository.allKeys
          .where(BackupService.isPortableSettingKey)
          .toSet();
      expect(settings.keys.toSet().containsAll(expected), isTrue);
      for (final key in BackupService.nonPortableSettingsKeys) {
        expect(settings.containsKey(key), isFalse);
      }
    });
  });

  group('backupSettingsFromKeys — נסיגה כשאין Hive box', () {
    test('אוסף את הערכים של המפתחות שנמסרו', () async {
      await Settings.setValue<double>(SettingsRepository.keyFontSize, 30.0);
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        foldersJson(['/books']),
      );

      final settings = BackupService.backupSettingsFromKeys([
        SettingsRepository.keyFontSize,
        SettingsRepository.keyCustomFolders,
      ]);

      expect(settings[SettingsRepository.keyFontSize], 30.0);
      expect(settings[SettingsRepository.keyCustomFolders], isNotNull);
    });

    test('מדלג על מפתח חסום גם במסלול הנסיגה', () async {
      await Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, true);

      final settings = BackupService.backupSettingsFromKeys([
        SettingsRepository.keyIsFullscreen,
      ]);

      expect(settings, isEmpty);
    });

    test('מדלג על מפתח ללא ערך שמור', () {
      final settings = BackupService.backupSettingsFromKeys([
        'key-never-set-by-anyone',
      ]);

      expect(settings, isEmpty);
    });

    test('רשימת הנסיגה כוללת את המפתחות המוצהרים ואת הקיצורים', () {
      final keys = BackupService.fallbackSettingsKeys;

      expect(keys, containsAll(SettingsRepository.allKeys));
      expect(keys, containsAll(ShortcutValidator.shortcutKeys));
      expect(
        keys,
        contains('shortcuts'),
        reason: 'מפת הקיצורים המרכזית נשמרת תחת המפתח shortcuts',
      );
    });
  });

  group('findMissingCustomFolders', () {
    test('מחזיר ריק כשכל התיקיות קיימות', () async {
      final existing = Directory(p.join(tempDir.path, 'קיימת'));
      await existing.create();
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        foldersJson([existing.path]),
      );

      expect(await BackupService.findMissingCustomFolders(), isEmpty);
    });

    test('מחזיר את הנתיב שאינו קיים בדיסק', () async {
      final missingPath = p.join(tempDir.path, 'אינה-קיימת');
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        foldersJson([missingPath]),
      );

      expect(await BackupService.findMissingCustomFolders(), [missingPath]);
    });

    test('מפריד בין תיקייה קיימת לחסרה באותה רשימה', () async {
      final existing = Directory(p.join(tempDir.path, 'יש'));
      await existing.create();
      final missingPath = p.join(tempDir.path, 'אין');
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        foldersJson([existing.path, missingPath]),
      );

      expect(await BackupService.findMissingCustomFolders(), [missingPath]);
    });

    test('מחזיר ריק כשאין תיקיות מוגדרות', () async {
      expect(await BackupService.findMissingCustomFolders(), isEmpty);
    });

    test('רשימה פגומה אינה מפילה את הבדיקה', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        'not-json-at-all',
      );

      expect(await BackupService.findMissingCustomFolders(), isEmpty);
    });
  });

  group('restoreFromBackup — דיווח תיקיות חסרות', () {
    /// כותב קובץ גיבוי עם סעיף הגדרות בלבד.
    Future<File> writeBackup(Map<String, dynamic> settings) async {
      final dir = Directory(p.join(tempDir.path, 'restore'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'backup.json'));
      await file.writeAsString(
        jsonEncode({
          'version': '2.0',
          'timestamp': '2026-01-01T00-00-00.000',
          'includes': {'settings': true},
          'settings': settings,
        }),
      );
      return file;
    }

    test('מדווח על תיקייה שנתיבה אינו קיים במחשב היעד', () async {
      final missingPath = p.join(tempDir.path, 'כונן-שאינו-מחובר');
      final backup = await writeBackup({
        SettingsRepository.keyCustomFolders: foldersJson([missingPath]),
      });

      final result = await BackupService.restoreFromBackup(backup.path);

      expect(result.missingCustomFolders, [missingPath]);
      expect(result.skippedSections, isEmpty);
    });

    test('אינו מדווח כשהתיקייה קיימת ביעד', () async {
      final existing = Directory(p.join(tempDir.path, 'מחוברת'));
      await existing.create();
      final backup = await writeBackup({
        SettingsRepository.keyCustomFolders: foldersJson([existing.path]),
      });

      final result = await BackupService.restoreFromBackup(backup.path);

      expect(result.missingCustomFolders, isEmpty);
    });

    test('התיקיות משוחזרות להגדרות גם כשנתיבן חסר', () async {
      // הרשימה נשמרת כדי שהמשתמש יראה אותן ויוכל להצביע על הנתיב מחדש —
      // מחיקה שקטה הייתה מאבדת את המידע שהתיקייה הזו הייתה מוגדרת.
      final missingPath = p.join(tempDir.path, 'חסרה');
      final backup = await writeBackup({
        SettingsRepository.keyCustomFolders: foldersJson([missingPath]),
      });

      await BackupService.restoreFromBackup(backup.path);

      final restored = CustomFoldersManager.loadFolders(
        Settings.getValue<String>(SettingsRepository.keyCustomFolders),
      );
      expect(restored.map((f) => f.path), [missingPath]);
    });

    test('שחזור הגדרות אינו דורס את נתוני הלמידה המקומיים', () async {
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      await Settings.setValue<String>(
        FindRefPreferenceStore.scoresKey,
        'local',
      );
      final backup = await writeBackup({
        FindRefPreferenceStore.enabledKey: false,
        FindRefPreferenceStore.scoresKey: 'from-backup',
      });

      await BackupService.restoreFromBackup(backup.path);

      expect(
        Settings.getValue<bool>(FindRefPreferenceStore.enabledKey),
        isFalse,
      );
      expect(
        Settings.getValue<String>(FindRefPreferenceStore.scoresKey),
        'local',
      );
    });

    test('גיבוי בלי סעיף הגדרות אינו מדווח על תיקיות', () async {
      final dir = Directory(p.join(tempDir.path, 'restore2'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'backup.json'));
      await file.writeAsString(
        jsonEncode({
          'version': '2.0',
          'timestamp': '2026-01-01T00-00-00.000',
          'includes': {'settings': false},
        }),
      );

      final result = await BackupService.restoreFromBackup(file.path);

      expect(result.missingCustomFolders, isEmpty);
      expect(result.skippedSections, isEmpty);
    });
  });

  group('roundtrip הגדרות', () {
    test('תיקיות מותאמות, קיצור והגדרת כלי חוזרים אחרי מחיקה', () async {
      final folder = Directory(p.join(tempDir.path, 'ספרי הרב'));
      await folder.create();
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        foldersJson([folder.path]),
      );
      await Settings.setValue<String>('key-shortcut-add-note', 'ctrl+alt+n');
      await Settings.setValue<int>('key-gematria-max-results', 7);

      final result = await BackupService.createBackup(
        includeSettings: true,
        includeBookmarks: false,
        includeHistory: false,
        includeNotes: false,
        includeWorkspaces: false,
        includeShamorZachor: false,
        includePlugins: false,
      );

      await Settings.setValue<String>(SettingsRepository.keyCustomFolders, '');
      await Settings.setValue<String>('key-shortcut-add-note', '');
      await Settings.setValue<int>('key-gematria-max-results', 0);

      final restore = await BackupService.restoreFromBackup(result.path);

      expect(restore.missingCustomFolders, isEmpty);
      final restored = CustomFoldersManager.loadFolders(
        Settings.getValue<String>(SettingsRepository.keyCustomFolders),
      );
      expect(restored.map((f) => f.path), [folder.path]);
      expect(Settings.getValue<String>('key-shortcut-add-note'), 'ctrl+alt+n');
      expect(Settings.getValue<int>('key-gematria-max-results'), 7);
    });

    test('דגל addToDatabase של התיקייה שורד את המעבר', () async {
      final folder = Directory(p.join(tempDir.path, 'בתוך המסד'));
      await folder.create();
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(
            path: folder.path,
            addToDatabase: true,
            addedAt: DateTime(2026, 3, 4),
          ),
        ]),
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
      await Settings.setValue<String>(SettingsRepository.keyCustomFolders, '');
      await BackupService.restoreFromBackup(result.path);

      final restored = CustomFoldersManager.loadFolders(
        Settings.getValue<String>(SettingsRepository.keyCustomFolders),
      );
      expect(restored.single.addToDatabase, isTrue);
      expect(restored.single.addedAt, DateTime(2026, 3, 4));
    });
  });
}
