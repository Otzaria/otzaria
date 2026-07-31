import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup/backup_maintenance.dart';
import 'package:otzaria/settings/services/backup/backup_rotation.dart';
import 'package:otzaria/settings/services/backup/backup_store.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:path/path.dart' as p;

/// טסטים לכל שרשרת הגיבוי/שחזור שמאחורי הגדרות › מערכת › מתקדם:
/// "צור כעת", "שחזור מהגיבוי האחרון", "שחזור מהארכיון", גיבוי אוטומטי
/// ו"ניקוי גיבויים ישנים".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String backupDir;
  late Box<dynamic> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_advanced_test_');
    backupDir = p.join(tempDir.path, 'backups');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(HiveCache.keyName);
    await Hive.openBox<dynamic>('workspaces');
    await Hive.openBox<dynamic>('bookmarks');
    await Hive.openBox<dynamic>('history');
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      backupDir,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(tempDir.path, 'databases'),
    );
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    PluginSystemDatabase.instance.resetForTests();
  });

  tearDown(() async {
    await PersonalNotesDatabase.instance.close();
    PluginSystemDatabase.instance.resetForTests();
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // ─── עזרים ─────────────────────────────────────────────────────────────────

  Future<({String path, List<String> skipped})> createBackup({
    bool settings = false,
    bool bookmarks = false,
    bool history = false,
    bool notes = false,
    bool workspaces = false,
    bool shamorZachor = false,
    bool plugins = false,
    bool isAuto = false,
  }) async {
    final result = await BackupService.createBackup(
      includeSettings: settings,
      includeBookmarks: bookmarks,
      includeHistory: history,
      includeNotes: notes,
      includeWorkspaces: workspaces,
      includeShamorZachor: shamorZachor,
      includePlugins: plugins,
      isAutoBackup: isAuto,
    );
    return (path: result.path, skipped: result.skippedSections);
  }

  Future<Map<String, dynamic>> readManifest(String path) async =>
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;

  Bookmark buildBookmark(String title, {int index = 0}) => Bookmark(
    ref: 'ref-$title-$index',
    book: TextBook(title: title),
    index: index,
  );

  PersonalNote buildNote({
    required String id,
    String bookId = 'ספר-הערות',
    String? anchorText,
  }) => PersonalNote(
    id: id,
    bookId: bookId,
    lineNumber: 5,
    displayTitle: 'שורה לדוגמה',
    anchorText: anchorText,
    anchorPrefix: anchorText == null ? null : 'לפני',
    anchorSuffix: anchorText == null ? null : 'אחרי',
    anchorStart: anchorText == null ? null : 10,
    anchorEnd: anchorText == null ? null : 20,
    lastKnownLineNumber: 5,
    status: PersonalNoteStatus.located,
    content: 'תוכן ההערה',
    contentPlain: 'תוכן ההערה',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime.parse('2026-01-01T10:00:00.000'),
    updatedAt: DateTime.parse('2026-01-02T10:00:00.000'),
  );

  /// timestamp בפורמט שם קובץ גיבוי (ISO עם מקפים במקום נקודתיים).
  /// [daysAgo] של 500 יום פג-תוקף לפי כל פרופיל שמירה, אך צעיר מגיל הגיזום
  /// של פריטי ארכיון (3 שנים) — כך המיזוג נבדק על פריטים שאמורים לשרוד.
  String agedTimestamp(int daysAgo) => DateTime.now()
      .subtract(Duration(days: daysAgo))
      .toIso8601String()
      .replaceAll(':', '-');

  /// כותב קובץ גיבוי סינתטי בשם עם [timestamp] (פורמט שם קובץ, מקפים).
  Future<String> writeBackupFile({
    required String timestamp,
    required Map<String, dynamic> data,
    bool isManual = false,
  }) async {
    await Directory(backupDir).create(recursive: true);
    final suffix = isManual ? '_manual' : '';
    final path = p.join(backupDir, 'otzaria_backup_$timestamp$suffix.json');
    await File(path).writeAsString(jsonEncode(data));
    return path;
  }

  Map<String, dynamic> manifestWithBookmarks(
    String timestamp,
    List<Bookmark> bookmarks,
  ) => {
    'version': '2.0',
    'timestamp': timestamp,
    'origin': 'auto',
    'includes': {
      'settings': false,
      'bookmarks': true,
      'history': false,
      'notes': false,
      'workspaces': false,
      'shamorZachor': false,
      'plugins': false,
    },
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
  };

  InstalledPlugin buildPlugin(String id, String installPath) => InstalledPlugin(
    pluginId: id,
    name: 'תוסף בדיקה',
    version: '1.0.0',
    installPath: installPath,
    entrypointPath: 'index.html',
    iconPath: 'assets/logo.png',
    enabled: true,
    pinned: true,
    manifest: PluginManifest.fromJson({
      'id': id,
      'name': 'תוסף בדיקה',
      'version': '1.0.0',
      'entrypoint': 'index.html',
      'icon': 'assets/logo.png',
      'permissions': ['clipboard.read'],
    }),
    installedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
    updatedAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
    sourceType: 'packaged',
  );

  Future<({String installPath, String dataPath})> installTestPlugin(
    String pluginId,
  ) async {
    final installPath = await AppPaths.getPluginInstallPath(pluginId);
    final indexFile = File(p.join(installPath, 'index.html'));
    await indexFile.create(recursive: true);
    await indexFile.writeAsString('original');
    final dataPath = await AppPaths.getPluginDataPath(pluginId);
    final stateFile = File(p.join(dataPath, 'state.bin'));
    await stateFile.create(recursive: true);
    await stateFile.writeAsBytes([7, 7, 7]);
    await PluginSystemDatabase.instance.insertOrUpdatePlugin(
      buildPlugin(pluginId, installPath),
    );
    return (installPath: installPath, dataPath: dataPath);
  }

  // ─── "צור כעת" + "שחזור": מסלול נתוני המשתמש ───────────────────────────────

  group('roundtrip של נתוני משתמש', () {
    test('הגדרות: הערכים חוזרים לערכם בגיבוי', () async {
      await Settings.setValue<double>(SettingsRepository.keyFontSize, 22.5);
      await Settings.setValue<bool>(SettingsRepository.keyDarkMode, true);
      await Settings.setValue<String>(
        SettingsRepository.keyFontFamily,
        'FrankRuhlCLM',
      );

      final backup = await createBackup(settings: true);

      await Settings.setValue<double>(SettingsRepository.keyFontSize, 12.0);
      await Settings.setValue<bool>(SettingsRepository.keyDarkMode, false);
      await Settings.setValue<String>(
        SettingsRepository.keyFontFamily,
        'Arial',
      );

      final skipped = await BackupService.restoreFromBackup(backup.path);

      expect(skipped, isEmpty);
      expect(Settings.getValue<double>(SettingsRepository.keyFontSize), 22.5);
      expect(Settings.getValue<bool>(SettingsRepository.keyDarkMode), isTrue);
      expect(
        Settings.getValue<String>(SettingsRepository.keyFontFamily),
        'FrankRuhlCLM',
      );
    });

    test('סימניות והיסטוריה: שתי הרשימות משוחזרות במלואן', () async {
      await BookmarkRepository().saveBookmarks([
        buildBookmark('בראשית'),
        buildBookmark('שמות', index: 4),
      ]);
      await HistoryRepository().saveHistory([buildBookmark('ויקרא', index: 7)]);

      final backup = await createBackup(bookmarks: true, history: true);

      await BookmarkRepository().clearBookmarks();
      await HistoryRepository().clearHistory();

      await BackupService.restoreFromBackup(backup.path);

      final restoredBookmarks = await BookmarkRepository().loadBookmarks();
      final restoredHistory = await HistoryRepository().loadHistory();
      expect(restoredBookmarks.map((b) => b.book.title), ['בראשית', 'שמות']);
      expect(restoredBookmarks.last.index, 4);
      expect(restoredHistory.map((b) => b.book.title), ['ויקרא']);
      expect(restoredHistory.first.index, 7);
    });

    test('שולחנות עבודה: שולחן נוסף שנוצר לאחר הגיבוי נמחק בשחזור', () async {
      final repo = WorkspaceRepository();
      await repo.saveWorkspaces([
        Workspace(id: 'ws-1', name: 'ראשון', tabs: []),
      ], 'ws-1');

      final backup = await createBackup(workspaces: true);

      await repo.saveWorkspaces([
        Workspace(id: 'ws-1', name: 'ראשון', tabs: []),
        Workspace(id: 'ws-2', name: 'שני', tabs: []),
      ], 'ws-2');

      await BackupService.restoreFromBackup(backup.path);

      final (workspaces, current) = repo.loadWorkspaces();
      expect(workspaces.map((w) => w.id), ['ws-1']);
      expect(current, 'ws-1');
    });

    test('הערות אישיות: שדות הבסיס משוחזרים אחרי מחיקה', () async {
      final db = PersonalNotesDatabase.instance;
      await db.insertNote(buildNote(id: 'note-1'));

      final backup = await createBackup(notes: true);
      await db.deleteNote('note-1');
      expect(await db.loadNotes('ספר-הערות'), isEmpty);

      await BackupService.restoreFromBackup(backup.path);

      final restored = await db.loadNotes('ספר-הערות');
      expect(restored, hasLength(1));
      expect(restored.first.id, 'note-1');
      expect(restored.first.content, 'תוכן ההערה');
      expect(restored.first.lineNumber, 5);
      expect(restored.first.displayTitle, 'שורה לדוגמה');
      expect(restored.first.status, PersonalNoteStatus.located);
      expect(
        restored.first.updatedAt,
        DateTime.parse('2026-01-02T10:00:00.000'),
      );
    });

    test('הערות אישיות: עוגן המילים (anchor) שורד גיבוי ושחזור', () async {
      final db = PersonalNotesDatabase.instance;
      await db.insertNote(
        buildNote(id: 'note-anchor', anchorText: 'בְּרֵאשִׁית'),
      );

      final backup = await createBackup(notes: true);
      await db.deleteNote('note-anchor');
      await BackupService.restoreFromBackup(backup.path);

      final restored = await db.loadNotes('ספר-הערות');
      expect(restored, hasLength(1));
      expect(
        restored.first.anchorText,
        'בְּרֵאשִׁית',
        reason: 'הערה המעוגנת למילים חייבת להישאר מעוגנת אחרי שחזור',
      );
      expect(restored.first.anchorPrefix, 'לפני');
      expect(restored.first.anchorSuffix, 'אחרי');
      expect(restored.first.anchorStart, 10);
      expect(restored.first.anchorEnd, 20);
      expect(restored.first.isWordAnchored, isTrue);
    });

    test('הערה קיימת עם אותו מזהה נדרסת בערך שבגיבוי', () async {
      final db = PersonalNotesDatabase.instance;
      await db.insertNote(buildNote(id: 'note-1'));
      final backup = await createBackup(notes: true);

      await db.insertNote(
        buildNote(
          id: 'note-1',
        ).copyWith(content: 'נערך אחרי הגיבוי', contentPlain: 'נערך'),
      );

      await BackupService.restoreFromBackup(backup.path);

      final restored = await db.loadNotes('ספר-הערות');
      expect(restored, hasLength(1));
      expect(restored.first.content, 'תוכן ההערה');
    });

    test('"שמור וזכור": מפתחות sz משוחזרים', () async {
      await box.put('sz:progress_by_id', '{"1":{"1":{"learn":true}}}');
      final backup = await createBackup(shamorZachor: true);
      await box.delete('sz:progress_by_id');

      await BackupService.restoreFromBackup(backup.path);

      expect(box.get('sz:progress_by_id'), '{"1":{"1":{"learn":true}}}');
    });
  });

  // ─── מצב גיבוי מותאם אישית: מה נכנס לקובץ ─────────────────────────────────

  group('בחירת מקטעים', () {
    test('מקטע שלא נבחר אינו נכתב לקובץ ואינו מסומן ב-includes', () async {
      await BookmarkRepository().saveBookmarks([buildBookmark('בראשית')]);
      final backup = await createBackup(bookmarks: false, history: true);
      final manifest = await readManifest(backup.path);

      expect(manifest.containsKey('bookmarks'), isFalse);
      expect((manifest['includes'] as Map)['bookmarks'], isFalse);
      expect(manifest.containsKey('history'), isTrue);
    });

    test('includes=false חוסם שחזור גם כשהנתונים קיימים בקובץ', () async {
      await BookmarkRepository().saveBookmarks([buildBookmark('בראשית')]);
      final backup = await createBackup(bookmarks: true);

      final manifest = await readManifest(backup.path);
      (manifest['includes'] as Map)['bookmarks'] = false;
      await File(backup.path).writeAsString(jsonEncode(manifest));

      await BookmarkRepository().clearBookmarks();
      await BackupService.restoreFromBackup(backup.path);

      expect(await BookmarkRepository().loadBookmarks(), isEmpty);
    });

    test('גיבוי ריק לגמרי נוצר בהצלחה ונטען בשחזור', () async {
      final backup = await createBackup();
      final skipped = await BackupService.restoreFromBackup(backup.path);
      expect(skipped, isEmpty);
    });
  });

  // ─── אימות קלט בשחזור ─────────────────────────────────────────────────────

  group('אימות קובץ הגיבוי', () {
    test('קובץ חסר — נזרקת שגיאה', () async {
      expect(
        () => BackupService.restoreFromBackup(
          p.join(tempDir.path, 'no_such_file.json'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('גרסה לא נתמכת — נזרקת שגיאה', () async {
      final path = await writeBackupFile(
        timestamp: '2026-01-01T00-00-00.000',
        data: {
          'version': '3.0',
          'includes': {'settings': false},
        },
      );
      expect(
        () => BackupService.restoreFromBackup(path),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('גרסת גיבוי'),
          ),
        ),
      );
    });

    test('גרסה 1.0 עדיין נתמכת', () async {
      final path = await writeBackupFile(
        timestamp: '2026-01-01T00-00-01.000',
        data: {
          'version': '1.0',
          'includes': {'bookmarks': true},
          'bookmarks': [buildBookmark('בראשית').toJson()],
        },
      );

      await BackupService.restoreFromBackup(path);

      expect(
        (await BookmarkRepository().loadBookmarks()).map((b) => b.book.title),
        ['בראשית'],
      );
    });

    test('JSON פגום — נזרקת שגיאה ולא נכתבים נתונים', () async {
      await Directory(backupDir).create(recursive: true);
      final path = p.join(backupDir, 'otzaria_backup_broken.json');
      await File(path).writeAsString('{not json');

      expect(
        () => BackupService.restoreFromBackup(path),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'שדה includes חסר — השחזור נכשל במקום להתנהג באופן לא מוגדר',
      () async {
        final path = await writeBackupFile(
          timestamp: '2026-01-01T00-00-02.000',
          data: {'version': '2.0', 'bookmarks': []},
        );
        expect(() => BackupService.restoreFromBackup(path), throwsA(anything));
      },
    );

    test('גיבוי חלקי מסומן — השחזור מחזיר את המקטעים החסרים', () async {
      final path = await writeBackupFile(
        timestamp: '2026-01-01T00-00-03.000',
        data: {
          'version': '2.0',
          'includes': {'bookmarks': true},
          'bookmarks': [],
          'partial_sections': ['plugins'],
        },
      );

      expect(await BackupService.restoreFromBackup(path), ['plugins']);
    });
  });

  // ─── שמות קבצים, רשימת גיבויים וארכיון ───────────────────────────────────

  group('קבצי הגיבוי בתיקייה', () {
    test('גיבוי ידני מקבל סיומת _manual, אוטומטי לא', () async {
      final manual = await createBackup();
      final auto = await createBackup(isAuto: true);

      expect(p.basename(manual.path), endsWith('_manual.json'));
      expect(p.basename(auto.path), isNot(contains('_manual')));
      expect(
        (await readManifest(manual.path))['origin'],
        'manual',
      );
      expect((await readManifest(auto.path))['origin'], 'auto');
    });

    test(
      'getAvailableBackups ממוין מהחדש לישן ואינו כולל את הארכיון',
      () async {
        await writeBackupFile(
          timestamp: '2026-01-01T00-00-00.000',
          data: {'version': '2.0', 'includes': {}},
        );
        await writeBackupFile(
          timestamp: '2026-03-01T00-00-00.000',
          data: {'version': '2.0', 'includes': {}},
        );
        await File(
          p.join(backupDir, BackupMaintenance.archiveFileName),
        ).writeAsString('{}');

        final backups = await BackupService.getAvailableBackups();

        expect(backups.map((f) => p.basename(f.path)), [
          'otzaria_backup_2026-03-01T00-00-00.000.json',
          'otzaria_backup_2026-01-01T00-00-00.000.json',
        ]);
      },
    );

    test('getArchivePathIfExists: null לפני יצירה, נתיב אחרי', () async {
      expect(await BackupService.getArchivePathIfExists(), isNull);
      await Directory(backupDir).create(recursive: true);
      final archive = File(
        p.join(backupDir, BackupMaintenance.archiveFileName),
      );
      await archive.writeAsString('{}');
      expect(await BackupService.getArchivePathIfExists(), archive.path);
    });

    test('תיקיית הגיבוי נוצרת אם אינה קיימת', () async {
      expect(await Directory(backupDir).exists(), isFalse);
      expect(await BackupService.getBackupDirectory(), backupDir);
      expect(await Directory(backupDir).exists(), isTrue);
    });
  });

  // ─── גיבוי אוטומטי ────────────────────────────────────────────────────────

  group('גיבוי אוטומטי', () {
    test('performAutoBackup מכבד את מתגי המקטעים בהגדרות', () async {
      await Settings.setValue<bool>('key-backup-bookmarks', false);
      await Settings.setValue<bool>('key-backup-history', true);

      await BackupService.performAutoBackup();

      final backups = await BackupService.getAvailableBackups();
      expect(backups, hasLength(1));
      final manifest = await readManifest(backups.first.path);
      expect((manifest['includes'] as Map)['bookmarks'], isFalse);
      expect((manifest['includes'] as Map)['history'], isTrue);
    });

    test('גיבוי אוטומטי מוצלח מעדכן את מועד הגיבוי האחרון', () async {
      expect(Settings.getValue<String>('key-last-auto-backup'), isNull);
      await BackupService.performAutoBackup();
      expect(Settings.getValue<String>('key-last-auto-backup'), isNotNull);
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
    });

    test('תדירות יומית: גיבוי מלפני יומיים מחייב גיבוי חדש', () async {
      await Settings.setValue<String>('key-auto-backup-frequency', 'daily');
      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isTrue);

      await Settings.setValue<String>(
        'key-last-auto-backup',
        DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
      );
      expect(await BackupService.shouldPerformAutoBackup(), isFalse);
    });

    test(
      'מועד גיבוי פגום בהגדרות אינו מפיל את בדיקת הגיבוי האוטומטי',
      () async {
        await Settings.setValue<String>('key-last-auto-backup', 'לא-תאריך');
        expect(await BackupService.shouldPerformAutoBackup(), isTrue);

        await Settings.setValue<String>(
          'key-last-partial-auto-backup',
          'גם-לא-תאריך',
        );
        expect(await BackupService.shouldPerformAutoBackup(), isTrue);
      },
    );
  });

  // ─── analyzeBackupStatus (הכתובית תחת "גיבוי אוטומטי") ────────────────────

  group('analyzeBackupStatus', () {
    test('אין גיבויים — אין תאריך ואין המלצה', () async {
      final status = await BackupService.analyzeBackupStatus();
      expect(status.lastBackupDate, isNull);
      expect(status.hasSignificantChanges, isFalse);
    });

    test('גיבוי טרי (פחות מ-24 שעות) — אין המלצה לגבות שוב', () async {
      await Settings.setValue<double>(SettingsRepository.keyFontSize, 20);
      await createBackup(settings: true, isAuto: true);
      await Settings.setValue<double>(SettingsRepository.keyFontSize, 30);

      final status = await BackupService.analyzeBackupStatus();

      expect(status.lastBackupDate, isNotNull);
      expect(status.hasSignificantChanges, isFalse);
    });

    test('קובץ גיבוי פגום אינו מפיל את הניתוח', () async {
      await Directory(backupDir).create(recursive: true);
      await File(
        p.join(backupDir, 'otzaria_backup_2026-01-01T00-00-00.000.json'),
      ).writeAsString('{not json');

      final status = await BackupService.analyzeBackupStatus();

      expect(status.hasSignificantChanges, isFalse);
    });
  });

  // ─── "ניקוי גיבויים ישנים" (רוטציה + ארכיון + GC) ─────────────────────────

  group('תחזוקה: ניקוי גיבויים ישנים', () {
    test('גיבוי ישן ממוזג לארכיון ונמחק; הידני שורד', () async {
      final oldPath = await writeBackupFile(
        timestamp: agedTimestamp(500),
        data: manifestWithBookmarks(agedTimestamp(500), [
          buildBookmark('ישן'),
        ]),
      );
      final manualPath = await writeBackupFile(
        timestamp: agedTimestamp(480),
        isManual: true,
        data: manifestWithBookmarks(agedTimestamp(480), [
          buildBookmark('ידני'),
        ]),
      );

      final result = await BackupMaintenance.runMaintenance();

      expect(result.mergedIntoArchive, 1);
      expect(result.deletedBackups, 1);
      expect(await File(oldPath).exists(), isFalse);
      expect(await File(manualPath).exists(), isTrue);
      expect(await BackupService.getArchivePathIfExists(), isNotNull);
    });

    test('פרופיל "שמור הכל" אינו מוחק דבר', () async {
      await Settings.setValue<String>(
        BackupMaintenance.keyRetentionProfile,
        'keepAll',
      );
      final oldPath = await writeBackupFile(
        timestamp: agedTimestamp(500),
        data: manifestWithBookmarks(agedTimestamp(500), [
          buildBookmark('ישן'),
        ]),
      );

      final result = await BackupMaintenance.runMaintenance();

      expect(result.mergedIntoArchive, 0);
      expect(result.deletedBackups, 0);
      expect(await File(oldPath).exists(), isTrue);
      expect(await BackupService.getArchivePathIfExists(), isNull);
    });

    test('ארכיון פגום — התחזוקה נעצרת והגיבויים נשארים', () async {
      final oldPath = await writeBackupFile(
        timestamp: agedTimestamp(500),
        data: manifestWithBookmarks(agedTimestamp(500), [
          buildBookmark('ישן'),
        ]),
      );
      await File(
        p.join(backupDir, BackupMaintenance.archiveFileName),
      ).writeAsString('{corrupt');

      final result = await BackupMaintenance.runMaintenance();

      expect(result.mergedIntoArchive, 0);
      expect(result.deletedBackups, 0);
      expect(await File(oldPath).exists(), isTrue);
    });

    test('שחזור מהארכיון מחזיר גם פריטים שנמחקו מאז', () async {
      await writeBackupFile(
        timestamp: agedTimestamp(600),
        data: manifestWithBookmarks(agedTimestamp(600), [
          buildBookmark('נמחק-מאז'),
        ]),
      );
      await writeBackupFile(
        timestamp: agedTimestamp(500),
        data: manifestWithBookmarks(agedTimestamp(500), [
          buildBookmark('נשמר'),
        ]),
      );

      await BackupMaintenance.runMaintenance();
      final archivePath = await BackupService.getArchivePathIfExists();
      expect(archivePath, isNotNull);

      await BookmarkRepository().clearBookmarks();
      await BackupService.restoreFromBackup(archivePath!);

      final titles = (await BookmarkRepository().loadBookmarks())
          .map((b) => b.book.title)
          .toSet();
      expect(titles, containsAll(['נמחק-מאז', 'נשמר']));
    });

    test('הסתעפות v1→v2: base64 מומר ל-blobs ושחזור מהארכיון עובד', () async {
      const pluginId = 'archive.plugin';
      final paths = await installTestPlugin(pluginId);

      // גיבוי ידני (base64 מוטמע), מסומן כישן כדי שהרוטציה תמזג אותו לארכיון.
      final manual = await createBackup(plugins: true);
      final manifest = await readManifest(manual.path);
      await File(manual.path).delete();
      final agedPath = await writeBackupFile(
        timestamp: agedTimestamp(500),
        data: manifest,
      );
      expect(await File(agedPath).exists(), isTrue);

      final result = await BackupMaintenance.runMaintenance();
      expect(result.mergedIntoArchive, 1);

      final archivePath = (await BackupService.getArchivePathIfExists())!;
      final archive = await readManifest(archivePath);
      final pluginEntry =
          (archive['plugins'] as List).first as Map<String, dynamic>;
      for (final value in (pluginEntry['files'] as Map).values) {
        expect(value, startsWith(BackupStore.hashPrefix));
      }

      await PluginSystemDatabase.instance.deletePlugin(pluginId);
      await Directory(paths.installPath).delete(recursive: true);
      await Directory(paths.dataPath).delete(recursive: true);

      final skipped = await BackupService.restoreFromBackup(archivePath);

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
    });

    test(
      'דה-דופליקציה: שני גיבויים אוטומטיים חולקים blob אחד לכל קובץ',
      () async {
        const pluginId = 'dedup.plugin';
        await installTestPlugin(pluginId);

        await createBackup(plugins: true, isAuto: true);
        await createBackup(plugins: true, isAuto: true);

        final objects = Directory(p.join(backupDir, 'store', 'objects'));
        final blobs = await objects
            .list(recursive: true)
            .where((e) => e is File && !e.path.endsWith('.tmp'))
            .length;

        expect(
          blobs,
          2,
          reason: 'index.html ו-state.bin — כל אחד blob אחד בלבד',
        );
      },
    );

    test('ה-GC אינו מוחק blobs שהארכיון עדיין מפנה אליהם', () async {
      const pluginId = 'gc.plugin';
      await installTestPlugin(pluginId);

      final auto = await createBackup(plugins: true, isAuto: true);
      final manifest = await readManifest(auto.path);
      await File(auto.path).delete();
      await writeBackupFile(
        timestamp: agedTimestamp(500),
        data: manifest,
      );

      await BackupMaintenance.runMaintenance();

      final archivePath = (await BackupService.getArchivePathIfExists())!;
      final archive = await readManifest(archivePath);
      final store = BackupStore.forBackupDir(backupDir);
      for (final ref in BackupStore.collectRefs(archive)) {
        expect(await store.exists(ref), isTrue);
      }
    });

    test('תמונת המצב במסך מציגה את מספר הגיבויים והארכיון', () async {
      await writeBackupFile(
        timestamp: '2026-01-01T00-00-00.000',
        data: manifestWithBookmarks('2026-01-01T00-00-00.000', const []),
      );
      var overview = await BackupMaintenance.getOverview();
      expect(overview.backupCount, 1);
      expect(overview.archiveExists, isFalse);
      expect(overview.totalBytes, greaterThan(0));

      await File(
        p.join(backupDir, BackupMaintenance.archiveFileName),
      ).writeAsString('{}');
      overview = await BackupMaintenance.getOverview();
      expect(overview.archiveExists, isTrue);
    });

    test('פרופיל השמירה נקרא מההגדרות כפי שהמסך שומר אותו', () async {
      await Settings.setValue<String>(
        BackupMaintenance.keyRetentionProfile,
        'economy',
      );
      expect(
        RetentionProfile.fromName(
          Settings.getValue<String>(BackupMaintenance.keyRetentionProfile),
        ),
        RetentionProfile.economy,
      );
    });
  });
}
