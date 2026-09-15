import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup/backup_import_merge.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:path/path.dart' as p;

/// ייבוא ממזג מגיבוי של מכשיר אחר: מוסיף ואינו מוחק, ואינו נוגע בהגדרות
/// ובכרטיסיות הפתוחות של המכשיר המייבא.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_import_merge_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Hive.openBox<dynamic>('workspaces');
    await Hive.openBox<dynamic>('bookmarks');
    await Hive.openBox<dynamic>('history');
    await Hive.openBox<dynamic>(DirectErrorReportService.queueBoxName);
    await Hive.openBox<dynamic>(PluginReportService.queueBoxName);
    // בלי אפיק חלונות, ולכן המשבצת היא של החלון היחיד.
    MultiWindowService.debugSupportedOverride = false;
    UserStateDatabase.instance.overridePath(
      p.join(tempDir.path, 'user_state.db'),
    );
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      p.join(tempDir.path, 'backups'),
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
    UserStateDatabase.instance.close();
    MultiWindowService.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Bookmark buildBookmark(String title, {int index = 0}) => Bookmark(
    ref: 'ref-$title-$index',
    book: TextBook(title: title),
    index: index,
  );

  PersonalNote buildNote({
    required String id,
    required String content,
    required DateTime updatedAt,
  }) => PersonalNote(
    id: id,
    bookId: 'ספר-הערות',
    lineNumber: 5,
    displayTitle: 'שורה לדוגמה',
    anchorText: 'מילה',
    anchorPrefix: 'לפני',
    anchorSuffix: 'אחרי',
    anchorStart: 10,
    anchorEnd: 14,
    lastKnownLineNumber: 5,
    status: PersonalNoteStatus.located,
    content: content,
    contentPlain: content,
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime.parse('2026-01-01T10:00:00.000'),
    updatedAt: updatedAt,
  );

  Future<String> createFullBackup() async {
    final result = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: true,
      includeHistory: true,
      includeNotes: true,
      includeWorkspaces: true,
      includeShamorZachor: true,
      includePlugins: false,
    );
    return result.path;
  }

  Future<BackupImportCounts?> importMerge(String path) async {
    final result = await BackupService.restoreFromBackup(
      path,
      mode: BackupImportMode.merge,
    );
    return result.added;
  }

  test('סימניות והיסטוריה מתווספות, והמקומיות נשמרות', () async {
    final repo = BookmarkRepository();
    final history = HistoryRepository();
    await repo.replaceBookmarks([
      buildBookmark('משותף'),
      buildBookmark('מהגיבוי'),
    ]);
    await history.replaceHistory([buildBookmark('היסטוריה מהגיבוי')]);
    final path = await createFullBackup();

    await repo.replaceBookmarks([
      buildBookmark('משותף'),
      buildBookmark('מקומי'),
    ]);
    await history.replaceHistory([buildBookmark('היסטוריה מקומית')]);

    final added = await importMerge(path);

    final titles = (await repo.loadBookmarks()).map((b) => b.book.title);
    expect(titles, ['משותף', 'מקומי', 'מהגיבוי']);
    expect(added?.bookmarks, 1);
    expect((await history.loadHistory()).length, 2);
    expect(added?.history, 1);
  });

  test('ההגדרות והכרטיסיות הפתוחות אינן משתנות', () async {
    await Settings.setValue<double>('key-font-size', 20);
    final sessions = WindowSessionStore.instance;
    await sessions.save(
      UserStateSlot.single,
      tabsJson: '["טאב מהגיבוי"]',
      currentIndex: 0,
    );
    final path = await createFullBackup();

    await Settings.setValue<double>('key-font-size', 30);
    await sessions.save(
      UserStateSlot.single,
      tabsJson: '["טאב מקומי"]',
      currentIndex: 0,
    );

    await importMerge(path);

    expect(Settings.getValue<double>('key-font-size'), 30);
    expect(
      (await sessions.load(UserStateSlot.single))!.tabsJson,
      '["טאב מקומי"]',
    );
  });

  test('שולחן עבודה מיובא נוסף ואינו מחליף את הקיימים', () async {
    final repo = WorkspaceRepository();
    await repo.replaceWorkspaces([
      Workspace(id: 'from-backup', name: 'לימוד', tabs: const []),
    ], 'from-backup');
    final path = await createFullBackup();

    await repo.replaceWorkspaces([
      Workspace(id: 'local', name: 'לימוד', tabs: const []),
    ], 'local');

    final added = await importMerge(path);

    final (workspaces, currentId) = await repo.loadWorkspaces();
    expect(workspaces.map((w) => w.name), ['לימוד', 'לימוד (ממכשיר אחר)']);
    expect(currentId, 'local', reason: 'השולחן הפעיל אינו זז בייבוא');
    expect(added?.workspaces, 1);
  });

  test('הערה מקומית עדכנית יותר אינה נדרסת, וחדשה מתווספת', () async {
    final db = PersonalNotesDatabase.instance;
    await db.insertNote(
      buildNote(
        id: 'note-1',
        content: 'הגרסה שבגיבוי',
        updatedAt: DateTime.parse('2026-01-02T10:00:00.000'),
      ),
    );
    await db.insertNote(
      buildNote(
        id: 'note-2',
        content: 'הערה שרק בגיבוי',
        updatedAt: DateTime.parse('2026-01-02T10:00:00.000'),
      ),
    );
    final path = await createFullBackup();

    await db.deleteNote('note-2');
    await db.insertNote(
      buildNote(
        id: 'note-1',
        content: 'הגרסה המקומית החדשה',
        updatedAt: DateTime.parse('2026-05-01T10:00:00.000'),
      ),
    );

    final added = await importMerge(path);

    expect((await db.getNote('note-1'))?.content, 'הגרסה המקומית החדשה');
    expect((await db.getNote('note-2'))?.content, 'הערה שרק בגיבוי');
    expect(added?.notes, 1);
    expect(added?.notesUpdated, 0);
  });

  test('ייבוא חוזר של אותו קובץ אינו מוסיף דבר', () async {
    await BookmarkRepository().replaceBookmarks([buildBookmark('ספר')]);
    await WorkspaceRepository().replaceWorkspaces([
      Workspace(id: 'w1', name: 'לימוד', tabs: const []),
    ], 'w1');
    final path = await createFullBackup();

    await importMerge(path);
    final second = await importMerge(path);

    expect(second?.total, 0);
  });
}
