import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/services/backup/backup_maintenance.dart';
import 'package:otzaria/settings/services/backup/backup_store.dart';

/// Status of the most recent backup and whether a new one is recommended.
class BackupStatus {
  final DateTime? lastBackupDate;
  final bool hasSignificantChanges;

  const BackupStatus({
    this.lastBackupDate,
    required this.hasSignificantChanges,
  });
}

/// Service for backing up and restoring app data
class BackupService {
  static final Logger _logger = Logger('BackupService');
  static const String backupFolderName = 'backups';

  /// תקרת סך תוכן התוספים בגיבוי אחד. עם [BackupStore] הבייטים נכתבים כ-blob
  /// לדיסק ומוסרים מהזיכרון; בגיבוי ידני הם נכנסים כ-base64 (×1.33) למחרוזת
  /// JSON יחידה (UTF-16 בזיכרון) — ולכן התקרה שם נמוכה בהרבה.
  static const int maxPluginBytesWithStore = 500 * 1024 * 1024;
  static const int maxPluginBytesInline = 100 * 1024 * 1024;

  @visibleForTesting
  static int? debugMaxPluginBytesOverride;

  /// Get the backup directory path
  static Future<String> getBackupDirectory() async {
    final backupPath = await AppPaths.getBackupPath();
    final dir = Directory(backupPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return backupPath;
  }

  /// Open the backup directory in the file explorer
  static Future<void> openBackupDirectory() async {
    final dir = await getBackupDirectory();
    if (Platform.isWindows) {
      await Process.run('explorer', [dir]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir]);
    }
  }

  /// Create a backup with specified options.
  /// Returns the backup path and a list of sections that were skipped (e.g. when Hive box is not open).
  ///
  /// [isAutoBackup] — גיבוי אוטומטי כפוף לרוטציה; גיבוי ידני מסומן בשם הקובץ
  /// (`_manual`) והרוטציה לא נוגעת בו לעולם.
  static Future<({String path, List<String> skippedSections})> createBackup({
    required bool includeSettings,
    required bool includeBookmarks,
    required bool includeHistory,
    required bool includeNotes,
    required bool includeWorkspaces,
    required bool includeShamorZachor,
    // [EDITING DISABLED] required bool includeUserOverrides,
    required bool includePlugins,
    bool isAutoBackup = false,
  }) async {
    final skippedSections = <String>[];
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupDir = await getBackupDirectory();
      final suffix = isAutoBackup ? '' : '_manual';
      final backupFileName = 'otzaria_backup_$timestamp$suffix.json';
      final backupPath = p.join(backupDir, backupFileName);
      // גיבוי ידני חייב להיות קובץ עצמאי שניתן להעתיק למחשב אחר — קבצי
      // התוספים מוטמעים בו כ-base64. גיבוי אוטומטי מפנה ל-blobs במחסן.
      final store = isAutoBackup ? BackupStore.forBackupDir(backupDir) : null;

      _logger.info('Creating backup at: $backupPath');
      _logger.info('Backup directory: $backupDir');

      final backupData = <String, dynamic>{
        'version': '2.0',
        'timestamp': timestamp,
        'origin': isAutoBackup ? 'auto' : 'manual',
        'includes': {
          'settings': includeSettings,
          'bookmarks': includeBookmarks,
          'history': includeHistory,
          'notes': includeNotes,
          'workspaces': includeWorkspaces,
          'shamorZachor': includeShamorZachor,
          // [EDITING DISABLED] 'userOverrides': includeUserOverrides,
          'plugins': includePlugins,
        },
      };

      // Backup settings
      if (includeSettings) {
        backupData['settings'] = await _backupSettings(skippedSections);
        // חתימת מקור ההגדרות. גיבוי שנוצר לפני שהגיבוי סרק את ה-Box אסף
        // רשימת מפתחות מוצהרת בלבד, ואינו נושא את השדה — כך השחזור מזהה
        // אותו ומדווח למשתמש במקום להכריז "שוחזר בהצלחה" על קובץ חסר.
        backupData['settingsSource'] = skippedSections.contains('settings')
            ? 'declared-keys'
            : 'box';
        final perBookSettings = await _backupPerBookSettings();
        backupData['perBookSettings'] = perBookSettings.files;
        if (perBookSettings.hadFailures) {
          skippedSections.add('perBookSettings');
        }
        backupData['reportQueues'] = _backupReportQueues(skippedSections);
      }

      // Backup bookmarks
      if (includeBookmarks) {
        backupData['bookmarks'] = await _backupBookmarks();
      }

      // Backup history
      if (includeHistory) {
        backupData['history'] = await _backupHistory();
      }

      // Backup notes
      if (includeNotes) {
        backupData['notes'] = await _backupNotes();
      }

      // [EDITING DISABLED]
      // if (includeUserOverrides) {
      //   backupData['user_overrides'] = await _backupUserOverrides();
      // }

      // Backup plugins
      if (includePlugins) {
        backupData['plugins'] = await _backupPlugins(skippedSections, store);
      }

      // Backup workspaces
      if (includeWorkspaces) {
        final workspacesData = await _backupWorkspaces();
        backupData['workspaces'] = workspacesData['workspaces'];
        backupData['currentWorkspace'] = workspacesData['currentWorkspace'];
        final openTabs = _backupOpenTabs();
        if (openTabs != null) backupData['openTabs'] = openTabs;
      }

      // Backup Shamor Zachor
      if (includeShamorZachor) {
        if (!Hive.isBoxOpen(HiveCache.keyName)) {
          skippedSections.add('shamorZachor');
        }
        backupData['shamorZachor'] = await _backupShamorZachor();
      }

      if (skippedSections.isNotEmpty) {
        backupData['partial_sections'] = skippedSections;
      }

      // Write backup file
      final file = File(backupPath);
      _logger.info('Writing backup data (${backupData.length} keys)...');

      final jsonString = json.encode(backupData);
      _logger.info('JSON size: ${jsonString.length} characters');

      await file.writeAsString(jsonString);
      _logger.info('Backup file written successfully');

      // Verify file was created
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      _logger.info('File exists: $exists, Size: $size bytes');

      return (path: backupPath, skippedSections: skippedSections);
    } catch (e, stackTrace) {
      _logger.severe('Error creating backup: $e');
      _logger.severe('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// מקומות השמירה שהגיבוי מכסה: Hive boxes ותיקיות תחת שורש הנתונים.
  ///
  /// `databases` מכוסה חלקית — `personal_notes.db` ו-`plugins_host.db` מגובים,
  /// ו-`user_books.db`/`cache.db` נבנים מחדש מסריקת הספרים.
  static const Set<String> backedUpStores = {
    'app_preferences',
    'bookmarks',
    'history',
    'workspaces',
    'tabs',
    'databases',
    'plugins',
    'per_book_settings',
    'error_reports_queue',
    'plugin_reports_queue',
  };

  /// מקומות שמירה שאינם מגובים במכוון, עם הסיבה לכל אחד.
  ///
  /// כל מקום שמירה בתוכנה חייב להופיע כאן או ב-[backedUpStores]:
  /// `backup_storage_coverage_test` סורק את הקוד ונכשל על מקום שאינו מוצהר,
  /// כך שתיקייה חדשה לא תישמט מהגיבוי בשקט כפי שקרה ל-`per_book_settings`.
  static const Map<String, String> unbackedStores = {
    'pending_external_activations.jsonl':
        'תור זמני של בקשות פתיחה מחוץ לתוכנה, מתרוקן בעיבוד',
    'books': 'תוכן הספרייה, מגיע מההתקנה או מההורדה',
    'הספרים שלי': 'קובצי הספרים; הנתיב נשמר בהגדרות והתיקייה נסרקת מחדש',
    'index': 'אינדקס החיפוש, נבנה מחדש מהספרים',
    'dictionaries': 'נכסי מילון שניתן להוריד שוב',
    'library_update_cache': 'קאש הורדות זמני',
    'webview2': 'נתוני מנוע הדפדפן המשובץ',
    'backups': 'תיקיית הגיבויים עצמה',
  };

  /// מפתחות הגדרות שאינם מועברים בין התקנות.
  ///
  /// הגיבוי סורק את *כל* מפתחות ההגדרות (ראה [_backupSettings]) ומחסיר את
  /// אלה, כדי שהגדרה חדשה תיכנס לגיבוי מעצמה ולא תישמט בשקט כפי שקרה
  /// לתיקיות המותאמות אישית.
  static const Set<String> nonPortableSettingsKeys = {
    // מצב ממשק רגעי — לא בחירה של המשתמש.
    SettingsRepository.keyIsFullscreen,
    'key-splited-view',
    'key-sidebar-tab-index-combined',
    'key-sidebar-tab-index-pending',
    'key-last-search-typing',
    // נתיבים שנגזרים מהמכשיר: שחזור למכשיר אחר מכניס נתיב שאינו קיים בו.
    SettingsRepository.keyDbEffectivePath,
    SettingsRepository.keyAndroidLibraryRoot,
    // חותמות זמן ומזהים תפעוליים: שחזור ערך ישן מבלבל את התזמון.
    'key-last-auto-backup',
    _kLastPartialAutoBackupKey,
    SettingsRepository.keyCalendarEventNotificationIds,
    SettingsRepository.keyGoogleCalendarLastSync,
    // אסימון גישה חי ליומן Google — אין להטמיע אותו בקובץ גיבוי נייד.
    // ההתחברות נדרשת מחדש ביעד, ושאר הגדרות היומן משוחזרות.
    SettingsRepository.keyGoogleCalendarCredentialsJson,
    // דגל פנימי שמסמן שברירות המחדל נכתבו לדיסק.
    'settings_initialized',
  };

  /// מפתחות ההגדרות שהגיבוי אוסף כשאין גישה ל-Hive box (ראה [_backupSettings]).
  /// כולל את הקיצורים הדינמיים, שמפתחותיהם נגזרים מהתוספים המותקנים.
  static List<String> get fallbackSettingsKeys => [
    ...SettingsRepository.allKeys,
    ...ShortcutValidator.shortcutKeys,
    'shortcuts',
  ];

  /// גיבוי ההגדרות.
  ///
  /// המקור המועדף הוא ה-Hive box עצמו, כדי לתפוס גם מפתחות שאינם מוצהרים
  /// ב-[SettingsRepository] — קיצורי מקלדת (כולל של תוספים), העדפות גיבוי
  /// והגדרות כלים. כשה-box אינו פתוח (נסיגת `Settings.init` ל-
  /// `SharePreferenceCache`) נאספת רשימת המפתחות המוצהרת, והסעיף מסומן חלקי.
  static Future<Map<String, dynamic>> _backupSettings(
    List<String> skippedSections,
  ) async {
    if (!Hive.isBoxOpen(HiveCache.keyName)) {
      _logger.warning(
        '_backupSettings: Hive box not open — falling back to declared keys',
      );
      skippedSections.add('settings');
      return backupSettingsFromKeys(fallbackSettingsKeys);
    }

    final box = Hive.box<dynamic>(HiveCache.keyName);
    final settings = <String, dynamic>{};
    for (final key in box.keys) {
      final name = key.toString();
      if (!isPortableSettingKey(name)) continue;
      final value = box.get(key);
      if (value != null) {
        settings[name] = value;
      }
    }
    return settings;
  }

  /// אוסף את [keys] דרך `Settings.getValue`, בדילוג על מפתחות לא ניידים.
  @visibleForTesting
  static Map<String, dynamic> backupSettingsFromKeys(List<String> keys) {
    final settings = <String, dynamic>{};
    for (final key in keys) {
      if (!isPortableSettingKey(key)) continue;
      final value = Settings.getValue(key);
      if (value != null) {
        settings[key] = value;
      }
    }
    return settings;
  }

  /// גיבוי ההגדרות הפר-ספריות, שנשמרות בקבצי JSON מחוץ ל-Hive: המפרשים
  /// הפעילים בכל ספר, גופן/ניקוד/פיסוק פר-ספר, רוחבי הטורים בצורת הדף וזום
  /// ה-PDF. נשמרות כטקסט ולא כ-blob — הקבצים זעירים והמניפסט נשאר קריא.
  static Future<({Map<String, String> files, bool hadFailures})>
  _backupPerBookSettings() async {
    final dir = Directory(await AppPaths.getPerBookSettingsPath());
    if (!await dir.exists()) {
      return (files: <String, String>{}, hadFailures: false);
    }

    final files = <String, String>{};
    var hadFailures = false;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        files[p.basename(entity.path)] = await entity.readAsString();
      } catch (e) {
        hadFailures = true;
        _logger.warning('Skipping per-book settings ${entity.path}: $e');
      }
    }
    return (files: files, hadFailures: hadFailures);
  }

  /// קידומות של נתונים שאינם הגדרות, אף שהם נשמרים באותו Hive box.
  static final List<String> _nonSettingKeyPrefixes = [
    'sz:',
    PersonalNoteDraftService.keyPrefix,
  ];

  /// האם המפתח אינו הגדרה כלל, לפי [_nonSettingKeyPrefixes].
  @visibleForTesting
  static bool isNonSettingKey(String key) =>
      _nonSettingKeyPrefixes.any(key.startsWith);

  /// האם המפתח מגובה. מסנן את [nonPortableSettingsKeys] ואת מה שאינו הגדרה.
  @visibleForTesting
  static bool isPortableSettingKey(String key) =>
      !isNonSettingKey(key) && !nonPortableSettingsKeys.contains(key);

  /// Backup bookmarks
  static Future<List<Map<String, dynamic>>> _backupBookmarks() async {
    final repo = BookmarkRepository();
    final bookmarks = await repo.loadBookmarks();
    return bookmarks.map((b) => b.toJson()).toList();
  }

  /// Backup history
  static Future<List<Map<String, dynamic>>> _backupHistory() async {
    final repo = HistoryRepository();
    final history = await repo.loadHistory();
    return history.map((h) => h.toJson()).toList();
  }

  /// Backup notes from SQLite database
  static Future<List<Map<String, dynamic>>> _backupNotes() async {
    final database = PersonalNotesDatabase.instance;
    final booksWithNotes = await database.listBooksWithNotes();

    final List<Map<String, dynamic>> result = [];

    for (final bookInfo in booksWithNotes) {
      try {
        final notes = await database.loadNotes(bookInfo.bookId);
        if (notes.isEmpty) continue;

        result.add({
          'bookId': bookInfo.bookId,
          'notes': notes.map((note) => _noteToBackupJson(note)).toList(),
        });
      } catch (e) {
        _logger.warning(
          'Skipping notes for book ${bookInfo.bookId} due to error: $e',
        );
      }
    }

    return result;
  }

  /// Convert PersonalNote to backup JSON format
  static Map<String, dynamic> _noteToBackupJson(PersonalNote note) {
    return {
      'id': note.id,
      'bookId': note.bookId,
      'lineNumber': note.lineNumber,
      'displayTitle': note.displayTitle,
      'anchorText': note.anchorText,
      'anchorPrefix': note.anchorPrefix,
      'anchorSuffix': note.anchorSuffix,
      'anchorStart': note.anchorStart,
      'anchorEnd': note.anchorEnd,
      'lastKnownLineNumber': note.lastKnownLineNumber,
      'status': note.status.name,
      'content': note.content,
      'contentPlain': note.contentPlain,
      'contentFormat': note.contentFormat.name,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    };
  }

  // [EDITING DISABLED]
  // /// Backup user overrides
  // static Future<Map<String, dynamic>> _backupUserOverrides() async {
  //   final overridesDir = Directory(await AppPaths.getUserOverridesRootPath());
  //   if (!await overridesDir.exists()) return {};
  //   final overridesData = <String, dynamic>{};
  //   await for (final entity in overridesDir.list(recursive: true)) {
  //     if (entity is File &&
  //         (entity.path.endsWith('.md') ||
  //             entity.path.endsWith('.tmp') ||
  //             entity.path.endsWith('.recovery'))) {
  //       final relativePath = p.relative(entity.path, from: overridesDir.path);
  //       try {
  //         overridesData[relativePath] = await entity.readAsString();
  //       } catch (e) {
  //         _logger.warning('Failed to backup override file $relativePath: $e');
  //       }
  //     }
  //   }
  //   return overridesData;
  // }

  //גיבוי תוספים: גיבוי קבצים, תיקיית נתונים, הרשאות ונתוני DB
  // תוספי פיתוח (`development`) מדולגים, כיון שאינם קיימים במחשב היעד.
  // גיבוי תוסף שנכשל מתבצע דילוג, ומסומן ב-[skippedSections] למניעת שגיאות בשחזור
  static Future<List<Map<String, dynamic>>> _backupPlugins(
    List<String> skippedSections,
    BackupStore? store,
  ) async {
    final db = PluginSystemDatabase.instance;
    final plugins = await db.getAllInstalledPlugins();
    final result = <Map<String, dynamic>>[];
    final budget =
        debugMaxPluginBytesOverride ??
        (store != null ? maxPluginBytesWithStore : maxPluginBytesInline);
    var consumed = 0;

    for (final plugin in plugins) {
      if (plugin.isDevelopment) continue;
      try {
        final dataPath = await AppPaths.getPluginDataPath(plugin.pluginId);
        final size =
            await _dirSizeBytes(plugin.installPath) +
            await _dirSizeBytes(dataPath);
        if (consumed + size > budget) {
          _logger.warning(
            'Skipping plugin ${plugin.pluginId} backup: exceeds archive budget',
          );
          UiSnack.showError(
            SettingsMessages.backupPluginTooLarge(plugin.pluginId),
          );
          if (!skippedSections.contains('plugins')) {
            skippedSections.add('plugins');
          }
          continue;
        }
        consumed += size;

        final aux = await db.exportPluginAuxData(plugin.pluginId);
        final files = await _readDirAsRefs(plugin.installPath, store);
        final data = await _readDirAsRefs(dataPath, store);
        result.add({
          'installation': plugin.toDbMap(),
          'permissions': aux['permissions'],
          'kvStore': aux['kvStore'],
          'publishedRecords': aux['publishedRecords'],
          'files': files,
          'data': data,
        });
      } catch (e) {
        _logger.warning(
          'Skipping plugin ${plugin.pluginId} backup due to error: $e',
        );
        if (!skippedSections.contains('plugins')) {
          skippedSections.add('plugins');
        }
      }
    }

    return result;
  }

  /// קורא את כל הקבצים בתיקייה (רקורסיבית) וממפה נתיב-יחסי → הפניית blob
  /// במחסן (`sha256:<hex>`), או base64 מוטמע כש-[store] הוא null (גיבוי ידני).
  /// הנתיבים מנורמלים למפריד `/` כדי לאפשר שחזור חוצה-פלטפורמות.
  ///
  /// כשל בקריאת קובץ אינו נבלע אלא מתפשט לקורא — כך גיבוי תוסף נכשל במלואו
  /// ומסומן כחלקי, במקום ליצור גיבוי עם קבצים חסרים בשתיקה.
  /// סך הבתים בתיקייה. symlinks מדולגים — הם אינם תוכן של התוסף, ומעקב
  /// אחריהם היה מזליג לארכיון קבצים מחוץ למרחב.
  static Future<int> _dirSizeBytes(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && !await FileSystemEntity.isLink(entity.path)) {
        total += await entity.length();
      }
    }
    return total;
  }

  static Future<Map<String, String>> _readDirAsRefs(
    String dirPath,
    BackupStore? store,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return {};

    final map = <String, String>{};
    await for (final entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.isLink(entity.path)) continue;
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: dir.path);
        final bytes = await entity.readAsBytes();
        map[p.split(relativePath).join('/')] = store != null
            ? await store.putBytes(bytes)
            : base64Encode(bytes);
      }
    }
    return map;
  }

  /// Backup workspaces
  static Future<Map<String, dynamic>> _backupWorkspaces() async {
    final repo = WorkspaceRepository();
    final (workspaces, currentWorkspace) = repo.loadWorkspaces();
    return {
      'workspaces': workspaces.map((w) => w.toJson()).toList(),
      'currentWorkspace': currentWorkspace,
    };
  }

  /// הטאבים הפתוחים, כחלק מסעיף שולחנות העבודה — אותו סוג נתון (סידור
  /// הספרים הפתוחים), ולכן אין להם העדפת גיבוי נפרדת.
  ///
  /// היעדר ה-box אינו מסמן את השחזור כחלקי: הטאבים הפתוחים הם מצב רגעי
  /// שמשתנה בכל פתיחת ספר, ואין להבהיל את המשתמש בגללם.
  static Map<String, dynamic>? _backupOpenTabs() {
    if (!Hive.isBoxOpen(TabsRepository.boxName)) {
      _logger.warning('_backupOpenTabs: tabs box not open — skipping');
      return null;
    }
    return TabsRepository().exportRaw();
  }

  /// תורי הדיווחים השמורים. לשני ה-boxes מבנה זהה — רשימת ממתינים ורשימת
  /// נשלחים — ולכן אותו גיבוי ושחזור משרת את שניהם.
  static const List<
    ({String box, String pendingKey, String sentKey, int maxSent})
  >
  _reportQueues = [
    (
      box: DirectErrorReportService.queueBoxName,
      pendingKey: DirectErrorReportService.pendingReportsKey,
      sentKey: DirectErrorReportService.sentReportsKey,
      maxSent: DirectErrorReportService.maxSentReportsToKeep,
    ),
    (
      box: PluginReportService.queueBoxName,
      pendingKey: PluginReportService.pendingReportsKey,
      sentKey: PluginReportService.sentReportsKey,
      maxSent: PluginReportService.maxSentReportsToKeep,
    ),
  ];

  /// גיבוי הדיווחים השמורים — הממתינים לשליחה וההיסטוריה שנשלחה. נכנסים
  /// לסעיף ההגדרות, שבו נשמרת כבר כתובת המייל שאליה הם משויכים.
  static Map<String, dynamic> _backupReportQueues(
    List<String> skippedSections,
  ) {
    final queues = <String, dynamic>{};
    for (final queue in _reportQueues) {
      if (!Hive.isBoxOpen(queue.box)) {
        _logger.warning(
          '_backupReportQueues: ${queue.box} not open — skipping (partial backup)',
        );
        if (!skippedSections.contains('reportQueues')) {
          skippedSections.add('reportQueues');
        }
        continue;
      }
      final box = Hive.box<dynamic>(queue.box);
      queues[queue.box] = {
        'pending': _reportList(box.get(queue.pendingKey)),
        'sent': _reportList(box.get(queue.sentKey)),
      };
    }
    return queues;
  }

  /// המרת רשימת דיווחים מ-Hive/JSON לרשימת מפות עם מפתחות מחרוזת.
  static List<Map<String, dynamic>> _reportList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// מזהה הדיווח, שנקרא `id` בדיווחי הטעות ו-`reportId` בדיווחי התוספים.
  static String? _reportId(Map<String, dynamic> report) =>
      (report['id'] ?? report['reportId'])?.toString();

  /// Backup Shamor Zachor data - backs up all sz: keys found in Hive
  static Future<Map<String, dynamic>> _backupShamorZachor() async {
    if (!Hive.isBoxOpen(HiveCache.keyName)) {
      _logger.warning(
        '_backupShamorZachor: Hive box not open — skipping (partial backup)',
      );
      return {};
    }
    final box = Hive.box<dynamic>(HiveCache.keyName);
    final shamorZachorData = <String, dynamic>{};

    for (final key in box.keys.where((k) => k.toString().startsWith('sz:'))) {
      final value = box.get(key);
      if (value != null) {
        shamorZachorData[key.toString()] = value;
      }
    }

    return shamorZachorData;
  }

  /// Restore from backup file.
  ///
  /// [skippedSections] — סעיפים שחסרו בקובץ הגיבוי או שדולגו בזמן השחזור.
  /// [missingCustomFolders] — נתיבי תיקיות ספרים מותאמות אישית ששוחזרו אך
  /// אינם קיימים במחשב היעד (שם משתמש אחר, כונן שאינו מחובר). הספרים שבהן
  /// לא ייסרקו, ולכן המשתמש חייב לדעת ולהצביע על הנתיב מחדש.
  /// [hasLegacyPartialSettings] — קובץ הגיבוי נוצר לפני שהגיבוי סרק את ה-Box,
  /// ולכן נשא רשימת מפתחות מוצהרת בלבד. כל השאר (קיצורי מקלדת, ברירות החיפוש,
  /// צורת הדף, התאמות פר-ספר) אינו בקובץ ואינו בר-שחזור — והמשתמש חייב לדעת.
  /// [notesWithoutAnchor] — הערות שקובץ הגיבוי אינו יכול לבטא להן עיגון (נוצר
  /// לפני שהעיגון נכנס לגיבוי), ולכן תסומנה על כל השורה במקום על המילים.
  static Future<
    ({
      List<String> skippedSections,
      List<String> missingCustomFolders,
      bool hasLegacyPartialSettings,
      int notesWithoutAnchor,
    })
  >
  restoreFromBackup(String backupPath) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('קובץ הגיבוי לא נמצא');
    }

    final content = await file.readAsString();
    final backupData = json.decode(content) as Map<String, dynamic>;

    // Validate backup version
    final version = backupData['version'] as String?;
    if (version != '1.0' && version != '2.0') {
      throw Exception('גרסת גיבוי לא נתמכת');
    }

    final missingCustomFolders = <String>[];

    // מניפסט v2 מפנה ל-blobs במחסן. מחפשים אותו קודם ליד קובץ הגיבוי עצמו
    // (גיבוי שהועתק ממחשב אחר עם תיקיית ה-store שלו), ואז בתיקייה המוגדרת.
    final stores = [
      BackupStore.forBackupDir(file.parent.path),
      BackupStore.forBackupDir(await getBackupDirectory()),
    ];

    final partialSections =
        (backupData['partial_sections'] as List?)?.cast<String>() ?? [];
    if (partialSections.isNotEmpty) {
      _logger.warning(
        'Restoring a partial backup — sections missing: ${partialSections.join(", ")}',
      );
    }

    final includes = backupData['includes'] as Map<String, dynamic>;

    final runtimeSkipped = <String>[];

    // Restore settings
    var hasLegacyPartialSettings = false;
    if (includes['settings'] == true && backupData.containsKey('settings')) {
      final settings = backupData['settings'] as Map<String, dynamic>;
      await _restoreSettings(settings);
      missingCustomFolders.addAll(await findMissingCustomFolders());
      hasLegacyPartialSettings = isPartialSettingsSection(
        settings,
        backupData['settingsSource'],
      );
      final perBookHadFailures = await _restorePerBookSettings(
        (backupData['perBookSettings'] as Map?)?.cast<String, dynamic>() ??
            const {},
      );
      if (perBookHadFailures) runtimeSkipped.add('perBookSettings');
      final reportsSkipped = await _restoreReportQueues(
        (backupData['reportQueues'] as Map?)?.cast<String, dynamic>(),
      );
      if (reportsSkipped) runtimeSkipped.add('reportQueues');
    }

    // Restore bookmarks
    if ((includes['bookmarks'] == true ||
            includes['bookmarksAndHistory'] == true) &&
        backupData.containsKey('bookmarks')) {
      await _restoreBookmarks(
        (backupData['bookmarks'] as List).cast<Map<String, dynamic>>(),
      );
    }

    // Restore history
    if ((includes['history'] == true ||
            includes['bookmarksAndHistory'] == true) &&
        backupData.containsKey('history')) {
      await _restoreHistory(
        (backupData['history'] as List).cast<Map<String, dynamic>>(),
      );
    }

    // Restore notes
    var notesWithoutAnchor = 0;
    if (includes['notes'] == true && backupData.containsKey('notes')) {
      notesWithoutAnchor = await _restoreNotes(
        (backupData['notes'] as List).cast<Map<String, dynamic>>(),
      );
    }

    // [EDITING DISABLED]
    // final includeOverrides =
    //     includes['userOverrides'] as bool? ?? includes['notes'] == true;
    // if (includeOverrides && backupData.containsKey('user_overrides')) {
    //   await _restoreUserOverrides(
    //     backupData['user_overrides'] as Map<String, dynamic>,
    //   );
    // }

    // Restore workspaces
    if (includes['workspaces'] == true &&
        backupData.containsKey('workspaces')) {
      await _restoreWorkspaces(
        (backupData['workspaces'] as List).cast<Map<String, dynamic>>(),
        backupData['currentWorkspace'],
      );
      await _restoreOpenTabs(
        (backupData['openTabs'] as Map?)?.cast<String, dynamic>(),
      );
    }

    // Restore plugins
    if (includes['plugins'] == true && backupData.containsKey('plugins')) {
      final pluginsHadFailures = await _restorePlugins(
        (backupData['plugins'] as List).cast<Map<String, dynamic>>(),
        stores,
      );
      if (pluginsHadFailures) runtimeSkipped.add('plugins');
    }

    // Restore Shamor Zachor
    if (includes['shamorZachor'] == true &&
        backupData.containsKey('shamorZachor')) {
      final skipped = await _restoreShamorZachor(
        backupData['shamorZachor'] as Map<String, dynamic>,
      );
      if (skipped) runtimeSkipped.add('shamorZachor');
    }

    // Merge: sections missing in the backup file + sections skipped at runtime
    final allSkipped = [
      ...partialSections,
      ...runtimeSkipped.where((s) => !partialSections.contains(s)),
    ];
    return (
      skippedSections: allSkipped,
      missingCustomFolders: missingCustomFolders,
      hasLegacyPartialSettings: hasLegacyPartialSettings,
      notesWithoutAnchor: notesWithoutAnchor,
    );
  }

  /// שחזור ההגדרות הפר-ספריות (ראה [_backupPerBookSettings]).
  ///
  /// קובץ שאינו בגיבוי נשאר במקומו: השחזור מחזיר את מה שנשמר בו ואינו מוחק
  /// התאמות של ספרים אחרים. שם הקובץ מאומת כשם בסיס בלבד לפני הכתיבה, כדי
  /// שגיבוי פגום/זדוני לא יכתוב מחוץ לתיקייה.
  static Future<bool> _restorePerBookSettings(
    Map<String, dynamic> files,
  ) async {
    if (files.isEmpty) return false;
    final dir = Directory(await AppPaths.getPerBookSettingsPath());
    await dir.create(recursive: true);

    var hadFailures = false;
    for (final entry in files.entries) {
      if (p.basename(entry.key) != entry.key || !entry.key.endsWith('.json')) {
        hadFailures = true;
        _logger.warning(
          'Unsafe per-book settings name in backup: ${entry.key}',
        );
        continue;
      }
      try {
        await File(
          p.join(dir.path, entry.key),
        ).writeAsString(entry.value as String);
      } catch (e) {
        hadFailures = true;
        _logger.warning('Failed to restore per-book settings ${entry.key}: $e');
      }
    }
    return hadFailures;
  }

  /// שחזור הדיווחים השמורים (ראה [_backupReportQueues]). ממזג ולא מחליף:
  /// דיווח שנשלח מאז אינו חוזר לתור, אחרת היה נשלח שוב לצוות אוצריא.
  static Future<bool> _restoreReportQueues(Map<String, dynamic>? queues) async {
    if (queues == null || queues.isEmpty) return false;

    // השליחה האוטומטית כותבת לאותם מפתחות אחרי בקשת רשת; בלי עצירה שלה
    // הכתיבה כאן עלולה לדרוס את רשומת הנשלחים ולהחזיר דיווח שכבר נמסר.
    await DirectErrorReportService.suspendAutomaticFlush();
    await PluginReportService.suspendAutomaticFlush();

    var skipped = false;
    for (final queue in _reportQueues) {
      final backedUp = (queues[queue.box] as Map?)?.cast<String, dynamic>();
      if (backedUp == null) continue;
      if (!Hive.isBoxOpen(queue.box)) {
        _logger.warning(
          '_restoreReportQueues: ${queue.box} not open — skipping (partial restore)',
        );
        skipped = true;
        continue;
      }

      final box = Hive.box<dynamic>(queue.box);
      final sent = _mergeReports(
        _reportList(box.get(queue.sentKey)),
        _reportList(backedUp['sent']),
      );
      if (sent.length > queue.maxSent) {
        sent.removeRange(queue.maxSent, sent.length);
      }
      final sentIds = sent.map(_reportId).whereType<String>().toSet();
      final pending = _mergeReports(
        _reportList(box.get(queue.pendingKey)),
        _reportList(backedUp['pending']),
      ).where((report) => !sentIds.contains(_reportId(report))).toList();

      await box.put(queue.pendingKey, pending);
      await box.put(queue.sentKey, sent);
    }
    return skipped;
  }

  /// איחוד שתי רשימות דיווחים לפי מזהה — המקומי מנצח, כי הוא העדכני.
  /// דיווח בלי מזהה נשמר כמות שהוא: אין דרך לזהות אותו ככפול.
  static List<Map<String, dynamic>> _mergeReports(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> backedUp,
  ) {
    final merged = [...local];
    final localIds = local.map(_reportId).whereType<String>().toSet();
    for (final report in backedUp) {
      final id = _reportId(report);
      if (id != null && localIds.contains(id)) continue;
      merged.add(report);
    }
    return merged;
  }

  /// האם סעיף ההגדרות נאסף מרשימת מפתחות מוצהרת ולכן חסר את השאר.
  ///
  /// [source] הוא `settingsSource` מהמניפסט: `'declared-keys'` מצהיר על עצמו,
  /// ו-`'box'` שולל. גיבוי מלפני שהשדה נוסף אינו נושא אותו כלל, ולכן ההכרעה
  /// נופלת על התוכן: אוסף מרשימה מוצהרת יכול להכיל רק מפתחות מתוכה
  /// (ראה [fallbackSettingsKeys]), ולכן מפתח אחד מחוצה לה מוכיח סריקת Box.
  /// בלי הבדיקה הזאת גם גיבוי שלם מלפני התיקון היה מתריע התראת שקר.
  @visibleForTesting
  static bool isPartialSettingsSection(
    Map<String, dynamic> settings,
    Object? source,
  ) {
    if (source == 'declared-keys') return true;
    if (source != null) return false;
    final declared = fallbackSettingsKeys.toSet();
    return !settings.keys.any((key) => !declared.contains(key));
  }

  /// נתיבי התיקיות המותאמות אישית שרשומות בהגדרות ואינן קיימות בדיסק.
  ///
  /// נקרא אחרי שחזור ההגדרות: נתיבי התיקיות נשמרים מוחלטים, ולכן גיבוי
  /// שנוצר במחשב אחר מצביע על נתיב שאינו קיים ביעד. בלי דיווח, הספרים
  /// פשוט לא מופיעים והמשתמש אינו יודע שעליו להצביע על התיקייה מחדש.
  @visibleForTesting
  static Future<List<String>> findMissingCustomFolders() async {
    final folders = CustomFoldersManager.loadFolders(
      Settings.getValue<String>(SettingsRepository.keyCustomFolders),
    );

    final missing = <String>[];
    for (final folder in folders) {
      if (!await Directory(folder.path).exists()) {
        missing.add(folder.path);
      }
    }
    return missing;
  }

  /// Restore settings
  static Future<void> _restoreSettings(Map<String, dynamic> settings) async {
    for (final entry in settings.entries) {
      // גיבויים ישנים עשויים להכיל נתונים שאינם הגדרות בסעיף הזה.
      if (isNonSettingKey(entry.key)) continue;
      // keyDbEffectivePath הוא setting פנימי ל-Android בלבד.
      // אם backup נוצר ב-Android ומשוחזר על macOS/Windows — מדלגים,
      // כדי למנוע נתיב /data/user/0/... להחליף את ה-DB path הנכון.
      if (entry.key == SettingsRepository.keyDbEffectivePath &&
          !Platform.isAndroid) {
        continue;
      }
      await Settings.setValue(entry.key, entry.value);
    }
  }

  /// Restore bookmarks
  static Future<void> _restoreBookmarks(
    List<Map<String, dynamic>> bookmarksData,
  ) async {
    final repo = BookmarkRepository();
    final bookmarks = bookmarksData
        .map((data) => Bookmark.fromJson(data))
        .toList();
    await repo.saveBookmarks(bookmarks);
  }

  /// Restore history
  static Future<void> _restoreHistory(
    List<Map<String, dynamic>> historyData,
  ) async {
    final repo = HistoryRepository();
    final history = historyData.map((data) => Bookmark.fromJson(data)).toList();
    await repo.saveHistory(history);
  }

  /// מפתח העיגון שנוכחותו מעידה שהגיבוי יודע לבטא עיגון להערה.
  static const String _noteAnchorKey = 'anchorText';

  /// Restore notes to SQLite database.
  ///
  /// מחזיר את מספר ההערות שקובץ הגיבוי אינו יכול לבטא להן עיגון (ראה
  /// [_restoreNoteAnchoredAsBefore]) — הן תסומנה על כל השורה במקום על המילים.
  static Future<int> _restoreNotes(
    List<Map<String, dynamic>> notesData,
  ) async {
    final database = PersonalNotesDatabase.instance;
    var anchorlessNotes = 0;

    for (final entry in notesData) {
      try {
        final bookId = (entry['bookId'] as String?)?.trim();
        if (bookId == null || bookId.isEmpty) {
          continue;
        }

        if (entry.containsKey('notes')) {
          final notesList = entry['notes'] as List<dynamic>;
          for (final noteData in notesList) {
            try {
              final json = noteData as Map<String, dynamic>;
              var note = _noteFromBackupJson(json);
              if (!json.containsKey(_noteAnchorKey)) {
                note = await _restoreNoteAnchoredAsBefore(database, note);
                if (!note.isWordAnchored) anchorlessNotes++;
              }
              await database.insertNote(note);
            } catch (e) {
              _logger.warning('Failed to restore single note from backup: $e');
            }
          }
        }
      } catch (e) {
        _logger.warning('Failed to restore note entry: $e');
      }
    }

    return anchorlessNotes;
  }

  /// משמר את עוגן ההערה הקיימת כששדות העיגון חסרים לגמרי בקובץ הגיבוי.
  ///
  /// גיבוי מלפני שהעיגון נכנס אליו אינו מבדיל בין "הערה על כל השורה" לבין
  /// "הערה על מילה" — בשניהם המפתח נעדר. `insertNote` הוא `INSERT OR REPLACE`,
  /// ולכן בלי השימור שחזור כזה מוחק עיגון קיים והערה שהצביעה על מילה מסוימת
  /// נמתחת על כל השורה. מפתח שקיים בערך `null` הוא בחירת משתמש ומכובד.
  static Future<PersonalNote> _restoreNoteAnchoredAsBefore(
    PersonalNotesDatabase database,
    PersonalNote note,
  ) async {
    try {
      final existing = await database.getNote(note.id);
      if (existing == null || !existing.isWordAnchored) return note;
      return note.copyWith(
        anchorText: existing.anchorText,
        anchorPrefix: existing.anchorPrefix,
        anchorSuffix: existing.anchorSuffix,
        anchorStart: existing.anchorStart,
        anchorEnd: existing.anchorEnd,
      );
    } catch (e) {
      _logger.warning('Failed to preserve anchor for note ${note.id}: $e');
      return note;
    }
  }

  /// Convert backup JSON to PersonalNote
  static PersonalNote _noteFromBackupJson(Map<String, dynamic> json) {
    return PersonalNote(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      lineNumber: json['lineNumber'] as int?,
      displayTitle: json['displayTitle'] as String?,
      anchorText: json['anchorText'] as String?,
      anchorPrefix: json['anchorPrefix'] as String?,
      anchorSuffix: json['anchorSuffix'] as String?,
      anchorStart: json['anchorStart'] as int?,
      anchorEnd: json['anchorEnd'] as int?,
      lastKnownLineNumber: json['lastKnownLineNumber'] as int?,
      status: PersonalNoteStatus.values.byName(json['status'] as String),
      content: json['content'] as String,
      contentPlain:
          (json['contentPlain'] as String?) ?? (json['content'] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
        json['contentFormat'] as String? ??
            PersonalNoteContentFormat.plain.name,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  // [EDITING DISABLED]
  /// Restore user overrides to files
  // static Future<void> _restoreUserOverrides(
  //     Map<String, dynamic> overridesData) async {
  //   final overridesDir = Directory(await AppPaths.getUserOverridesRootPath());
  //   for (final entry in overridesData.entries) {
  //     try {
  //       final relativePath = entry.key;
  //       final content = entry.value as String;
  //       final filePath = p.join(overridesDir.path, relativePath);
  //       final file = File(filePath);
  // Ensure parent directory exists
  //       await file.parent.create(recursive: true);
  // Only restore if file doesn't exist, to not overwrite user's latest edits,
  // or overwrite it if wanted. The standard restore overwrites.
  //       await file.writeAsString(content);
  //     } catch (e) {
  //       _logger.warning('Failed to restore override file ${entry.key}: $e');
  //     }
  //   }
  // }

  // שחזור תוספים: נתיב ההתקנה מותאם לשינויי מערכות ושם משתמש.
  // אם תוסף אחד נכשל — מחזיר `true` כדי שהמשתמש יראה שחזור חלקי.
  static Future<bool> _restorePlugins(
    List<Map<String, dynamic>> pluginsData,
    List<BackupStore> stores,
  ) async {
    final db = PluginSystemDatabase.instance;
    var hadFailures = false;

    for (final entry in pluginsData) {
      try {
        final installation = (entry['installation'] as Map)
            .cast<String, dynamic>();
        final pluginId = installation['plugin_id'] as String;
        // המזהה מגיע מקובץ הגיבוי ומרכיב נתיב שנמחק ב-recursive; מזהה כמו `..`
        // היה מוחק תיקייה שרירותית.
        if (!PluginManifestValidator.isValidPluginId(pluginId)) {
          throw Exception('מזהה תוסף לא תקין בגיבוי: $pluginId');
        }

        final installPath = await AppPaths.getPluginInstallPath(pluginId);
        installation['install_path'] = installPath;

        // כתיבת קבצי התוסף (דריסת התקנה קיימת אם יש).
        await _restoreDirFromBackup(
          installPath,
          (entry['files'] as Map?)?.cast<String, dynamic>() ?? const {},
          stores,
        );

        // כתיבת נתוני התוסף.
        final dataPath = await AppPaths.getPluginDataPath(pluginId);
        await _restoreDirFromBackup(
          dataPath,
          (entry['data'] as Map?)?.cast<String, dynamic>() ?? const {},
          stores,
        );

        // רשומת ההתקנה.
        await db.insertOrUpdatePlugin(InstalledPlugin.fromDbMap(installation));

        // רשומות נלוות.
        await db.importPluginAuxData(pluginId, {
          'permissions': entry['permissions'],
          'kvStore': entry['kvStore'],
          'publishedRecords': entry['publishedRecords'],
        });
      } catch (e) {
        _logger.warning('Failed to restore plugin entry: $e');
        hadFailures = true;
      }
    }

    return hadFailures;
  }

  /// כותב קבצים מגיבוי לתיקייה, אחרי ניקוי תוכן קודם. הערכים הם base64
  /// מוטמע (v1) או הפניית blob במחסן (v2) — לפי הקידומת `sha256:`.
  /// נתיבים שמורים עם מפריד `/` ומומרים למפריד המקומי בשחזור.
  ///
  /// blob חסר או פגום מכשיל את שחזור התוסף כולו (חריגה) — עדיף תוסף מדולג
  /// ומדווח מאשר תוסף משוחזר-חלקית ושבור בשקט.
  static Future<void> _restoreDirFromBackup(
    String dirPath,
    Map<String, dynamic> files,
    List<BackupStore> stores,
  ) async {
    // כל התוכן נקרא וכל הנתיבים מאומתים לפני מחיקת התיקייה הקיימת —
    // store חסר/פגום או נתיב לא בטוח (path traversal, רכיבי `..` בגיבוי
    // פגום/זדוני) מכשילים את השחזור בלי להשאיר את המשתמש בלי ההתקנה הקודמת.
    final normalizedRoot = p.normalize(dirPath);
    final resolved = <String, List<int>>{};
    for (final fileEntry in files.entries) {
      final targetPath = p.normalize(
        p.joinAll([dirPath, ...fileEntry.key.split('/')]),
      );
      if (!p.isWithin(normalizedRoot, targetPath)) {
        throw Exception('נתיב לא בטוח בגיבוי התוסף: ${fileEntry.key}');
      }
      final value = fileEntry.value as String;
      List<int>? bytes;
      if (BackupStore.isHashRef(value)) {
        for (final store in stores) {
          bytes = await store.getBytes(value);
          if (bytes != null) break;
        }
        if (bytes == null) {
          throw Exception('קובץ חסר במחסן הגיבוי: ${fileEntry.key} ($value)');
        }
      } else {
        bytes = base64Decode(value);
      }
      resolved[targetPath] = bytes;
    }

    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    if (resolved.isEmpty) return;
    await dir.create(recursive: true);

    for (final fileEntry in resolved.entries) {
      try {
        final file = File(fileEntry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(fileEntry.value);
      } catch (e) {
        _logger.warning('Failed to restore plugin file ${fileEntry.key}: $e');
      }
    }
  }

  /// Restore workspaces
  static Future<void> _restoreWorkspaces(
    List<Map<String, dynamic>> workspacesData,
    Object? currentWorkspace,
  ) async {
    final repo = WorkspaceRepository();
    final workspaces = workspacesData
        .map((data) => Workspace.fromJson(data))
        .toList();
    final currentId = _resolveCurrentWorkspaceId(
      workspaces: workspaces,
      currentWorkspace: currentWorkspace,
    );
    await repo.saveWorkspaces(workspaces, currentId);
  }

  /// שחזור הטאבים הפתוחים (ראה [_backupOpenTabs]). גיבוי בלעדיהם משאיר את
  /// הטאבים הקיימים — עדיף מלרוקן את המסך על סמך מה שאין בקובץ.
  static Future<void> _restoreOpenTabs(Map<String, dynamic>? openTabs) async {
    if (openTabs == null) return;
    if (!Hive.isBoxOpen(TabsRepository.boxName)) {
      _logger.warning('_restoreOpenTabs: tabs box not open — skipping');
      return;
    }
    await TabsRepository().importRaw(openTabs);
  }

  static String? _resolveCurrentWorkspaceId({
    required List<Workspace> workspaces,
    required Object? currentWorkspace,
  }) {
    if (currentWorkspace is String &&
        workspaces.any((w) => w.id == currentWorkspace)) {
      return currentWorkspace;
    }

    if (currentWorkspace is int &&
        currentWorkspace >= 0 &&
        currentWorkspace < workspaces.length) {
      return workspaces[currentWorkspace].id;
    }

    return workspaces.isNotEmpty ? workspaces.first.id : null;
  }

  /// Restore Shamor Zachor data - restores ALL backed up keys.
  /// Returns true if the section was skipped (Hive box not open).
  static Future<bool> _restoreShamorZachor(
    Map<String, dynamic> shamorZachorData,
  ) async {
    if (!Hive.isBoxOpen(HiveCache.keyName)) {
      _logger.warning(
        '_restoreShamorZachor: Hive box not open — skipping (partial restore)',
      );
      return true;
    }
    final box = Hive.box<dynamic>(HiveCache.keyName);

    for (final entry in shamorZachorData.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value == null) continue;

      await box.put(key, value);
    }
    return false;
  }

  static const _kLastPartialAutoBackupKey = 'key-last-partial-auto-backup';
  static const _kPartialRetryMinutes = 60;

  /// Check if automatic backup is needed
  static Future<bool> shouldPerformAutoBackup() async {
    final frequency =
        Settings.getValue<String>('key-auto-backup-frequency') ?? 'weekly';
    if (frequency == 'none') return false;

    final lastBackup = Settings.getValue<String>('key-last-auto-backup');
    final now = DateTime.now();

    // Check normal schedule against the last successful full backup.
    // מועד לא-פרסבילי נחשב "אין גיבוי" — עדיף לגבות מלהפיל את בדיקת ההמלצה.
    final lastBackupDate = DateTime.tryParse(lastBackup ?? '');
    if (lastBackupDate != null) {
      final daysSince = now.difference(lastBackupDate).inDays;
      final dueAfterDays = switch (frequency) {
        'daily' => 1,
        'weekly' => 7,
        'monthly' => 30,
        _ => null,
      };
      if (dueAfterDays == null) return false;
      if (daysSince < dueAfterDays) return false;
    }

    // Cooldown: if a partial attempt happened recently, don't flood the folder
    final lastPartial = DateTime.tryParse(
      Settings.getValue<String>(_kLastPartialAutoBackupKey) ?? '',
    );
    if (lastPartial != null) {
      final minutesSince = now.difference(lastPartial).inMinutes;
      if (minutesSince < _kPartialRetryMinutes) return false;
    }

    return true;
  }

  /// Perform automatic backup
  static Future<void> performAutoBackup() async {
    final includeSettings =
        Settings.getValue<bool>('key-backup-settings') ?? true;
    final includeBookmarks =
        Settings.getValue<bool>('key-backup-bookmarks') ?? true;
    final includeHistory =
        Settings.getValue<bool>('key-backup-history') ?? true;
    final includeNotes = Settings.getValue<bool>('key-backup-notes') ?? true;
    final includeWorkspaces =
        Settings.getValue<bool>('key-backup-workspaces') ?? true;
    final includeShamorZachor =
        Settings.getValue<bool>('key-backup-shamor-zachor') ?? true;
    // [EDITING DISABLED]
    // final includeUserOverrides = Settings.getValue<bool>('key-backup-user-overrides') ?? true;
    final includePlugins =
        Settings.getValue<bool>('key-backup-plugins') ?? true;

    final result = await createBackup(
      includeSettings: includeSettings,
      includeBookmarks: includeBookmarks,
      includeHistory: includeHistory,
      includeNotes: includeNotes,
      includeWorkspaces: includeWorkspaces,
      includeShamorZachor: includeShamorZachor,
      // [EDITING DISABLED] includeUserOverrides: includeUserOverrides,
      includePlugins: includePlugins,
      isAutoBackup: true,
    );

    if (result.skippedSections.isNotEmpty) {
      _logger.warning(
        'Auto-backup partial — skipped: ${result.skippedSections.join(", ")} — will retry after ${_kPartialRetryMinutes}min cooldown',
      );
      await Settings.setValue(
        _kLastPartialAutoBackupKey,
        DateTime.now().toIso8601String(),
      );
      return;
    }

    await Settings.setValue(
      'key-last-auto-backup',
      DateTime.now().toIso8601String(),
    );

    // תחזוקה אחרי גיבוי מוצלח: רוטציה, מיזוג לארכיון וניקוי blobs יתומים.
    try {
      await BackupMaintenance.runMaintenance();
    } catch (e) {
      _logger.warning('Backup maintenance failed: $e');
    }
  }

  /// Get list of available backups (ללא קובץ הארכיון)
  static Future<List<FileSystemEntity>> getAvailableBackups() async {
    final backupDir = await getBackupDirectory();
    final backups = await BackupMaintenance.listBackups(backupDir);
    return backups.map((b) => File(b.path)).toList();
  }

  /// נתיב קובץ הארכיון הממוזג, או null אם אינו קיים.
  static Future<String?> getArchivePathIfExists() async {
    final backupDir = await getBackupDirectory();
    final archive = File(p.join(backupDir, BackupMaintenance.archiveFileName));
    return await archive.exists() ? archive.path : null;
  }

  /// Analyzes the most recent backup and returns whether a new backup is recommended.
  static Future<BackupStatus> analyzeBackupStatus() async {
    try {
      final backups = await getAvailableBackups();
      if (backups.isEmpty) {
        return const BackupStatus(
          lastBackupDate: null,
          hasSignificantChanges: false,
        );
      }

      final latestFile = backups.first as File;
      final stat = await latestFile.stat();
      final backupDate = stat.modified;

      // Don't recommend again within 24 hours of the last backup
      if (DateTime.now().difference(backupDate).inHours < 24) {
        return BackupStatus(
          lastBackupDate: backupDate,
          hasSignificantChanges: false,
        );
      }

      Map<String, dynamic> backupData;
      try {
        final content = await latestFile.readAsString();
        backupData = json.decode(content) as Map<String, dynamic>;
      } catch (_) {
        return BackupStatus(
          lastBackupDate: backupDate,
          hasSignificantChanges: false,
        );
      }

      final hasChanges = await _hasSignificantChanges(backupData, backupDate);
      return BackupStatus(
        lastBackupDate: backupDate,
        hasSignificantChanges: hasChanges,
      );
    } catch (e) {
      _logger.warning('Failed to analyze backup status: $e');
      return const BackupStatus(
        lastBackupDate: null,
        hasSignificantChanges: false,
      );
    }
  }

  static Future<bool> _hasSignificantChanges(
    Map<String, dynamic> backupData,
    DateTime backupDate,
  ) async {
    // Always recommend: any settings change
    if (_hasSettingsChanges(backupData)) return true;

    // Always recommend: workspace added
    if (_hasWorkspaceAdded(backupData)) return true;

    // Always recommend: plugin added
    if (await _hasPluginAdded(backupData)) return true;

    // Threshold: shamor zachor changes
    if (_hasShamorZachorChanges(backupData)) return true;

    // Threshold: notes changes
    if (await _hasNotesChanges(backupData, backupDate)) return true;

    // Threshold: bookmarks/history after 1 week with >50% change
    if (DateTime.now().difference(backupDate).inDays >= 7 &&
        await _hasBookmarksHistoryChanges(backupData)) {
      return true;
    }

    return false;
  }

  static bool _hasSettingsChanges(Map<String, dynamic> backupData) {
    final backedUpSettings = backupData['settings'] as Map<String, dynamic>?;
    if (backedUpSettings == null) return false;
    for (final entry in backedUpSettings.entries) {
      final current = Settings.getValue(entry.key);
      if (current?.toString() != entry.value?.toString()) return true;
    }
    return false;
  }

  static bool _hasWorkspaceAdded(Map<String, dynamic> backupData) {
    final backedUpWorkspaces = backupData['workspaces'] as List?;
    if (backedUpWorkspaces == null) return false;
    final (workspaces, _) = WorkspaceRepository().loadWorkspaces();
    return workspaces.length > backedUpWorkspaces.length;
  }

  static Future<bool> _hasPluginAdded(Map<String, dynamic> backupData) async {
    final backedUpPlugins = backupData['plugins'] as List?;
    if (backedUpPlugins == null) return false;
    try {
      final db = PluginSystemDatabase.instance;
      final currentPlugins = await db.getAllInstalledPlugins();
      final currentCount = currentPlugins.where((p) => !p.isDevelopment).length;
      return currentCount > backedUpPlugins.length;
    } catch (_) {
      return false;
    }
  }

  /// Checks if shamor zachor data changed meaningfully since the backup:
  /// new books added, a book newly marked, or a review cycle crossed 50% for any book.
  static bool _hasShamorZachorChanges(Map<String, dynamic> backupData) {
    final szBackup = backupData['shamorZachor'] as Map<String, dynamic>?;
    if (szBackup == null) return false;

    final backupProgressStr = szBackup['sz:progress_by_id'] as String?;
    final currentProgressStr = Settings.getValue<String>('sz:progress_by_id');
    if (backupProgressStr == null ||
        currentProgressStr == null ||
        currentProgressStr.isEmpty) {
      return false;
    }

    try {
      final backupProgress =
          json.decode(backupProgressStr) as Map<String, dynamic>;
      final currentProgress =
          json.decode(currentProgressStr) as Map<String, dynamic>;

      final backupBookIds = backupProgress.keys.toSet();

      // New books added
      if (currentProgress.keys.any((id) => !backupBookIds.contains(id))) {
        return true;
      }

      // Existing books: newly marked or 50% review threshold crossed
      for (final bookId in backupBookIds) {
        final backupBook =
            backupProgress[bookId] as Map<String, dynamic>? ?? {};
        final currentBook =
            currentProgress[bookId] as Map<String, dynamic>? ?? {};

        int backupLearn = 0, currentLearn = 0;
        int backupR1 = 0, currentR1 = 0;
        int backupR2 = 0, currentR2 = 0;
        int backupR3 = 0, currentR3 = 0;

        for (final page in backupBook.values) {
          if (page is Map) {
            if (page['learn'] == true) backupLearn++;
            if (page['review1'] == true) backupR1++;
            if (page['review2'] == true) backupR2++;
            if (page['review3'] == true) backupR3++;
          }
        }
        for (final page in currentBook.values) {
          if (page is Map) {
            if (page['learn'] == true) currentLearn++;
            if (page['review1'] == true) currentR1++;
            if (page['review2'] == true) currentR2++;
            if (page['review3'] == true) currentR3++;
          }
        }

        // Book newly started (was untouched, now has progress)
        if (backupLearn == 0 && currentLearn > 0) return true;

        // Any review cycle crossed the 50% threshold since backup
        final total = currentBook.length;
        if (total > 0) {
          final half = total * 0.5;
          if (backupR1 < half && currentR1 >= half) return true;
          if (backupR2 < half && currentR2 >= half) return true;
          if (backupR3 < half && currentR3 >= half) return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if notes changed significantly since backup:
  /// 5 or more new notes, or 30%+ of previous notes edited.
  static Future<bool> _hasNotesChanges(
    Map<String, dynamic> backupData,
    DateTime backupDate,
  ) async {
    final backedUpNotesList = backupData['notes'] as List?;
    if (backedUpNotesList == null) return false;

    int backupNoteCount = 0;
    for (final entry in backedUpNotesList) {
      final notes = (entry as Map<String, dynamic>)['notes'] as List?;
      if (notes != null) backupNoteCount += notes.length;
    }

    try {
      final database = PersonalNotesDatabase.instance;
      final booksWithNotes = await database.listBooksWithNotes();

      int currentNoteCount = 0;
      int editedAfterBackup = 0;

      for (final bookInfo in booksWithNotes) {
        try {
          final notes = await database.loadNotes(bookInfo.bookId);
          currentNoteCount += notes.length;
          editedAfterBackup += notes
              .where((n) => n.updatedAt.isAfter(backupDate))
              .length;
        } catch (_) {}
      }

      // 5+ new notes
      if (currentNoteCount - backupNoteCount >= 5) return true;

      // 30%+ of previous notes edited
      if (backupNoteCount > 0 && editedAfterBackup >= backupNoteCount * 0.3) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Checks if bookmarks or history changed by more than half since backup (used after 1 week).
  static Future<bool> _hasBookmarksHistoryChanges(
    Map<String, dynamic> backupData,
  ) async {
    final backedUpBookmarks = backupData['bookmarks'] as List?;
    if (backedUpBookmarks != null) {
      try {
        final currentBookmarks = await BookmarkRepository().loadBookmarks();
        final backupCount = backedUpBookmarks.length;
        final currentCount = currentBookmarks.length;
        final diff = (currentCount - backupCount).abs();
        if (backupCount == 0 ? currentCount > 0 : diff > backupCount / 2) {
          return true;
        }
      } catch (_) {}
    }

    final backedUpHistory = backupData['history'] as List?;
    if (backedUpHistory != null) {
      try {
        final currentHistory = await HistoryRepository().loadHistory();
        final backupCount = backedUpHistory.length;
        final currentCount = currentHistory.length;
        final diff = (currentCount - backupCount).abs();
        if (backupCount == 0 ? currentCount > 0 : diff > backupCount / 2) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }
}
