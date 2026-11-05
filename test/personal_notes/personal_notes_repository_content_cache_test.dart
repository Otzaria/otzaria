import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../helpers/seforim_fixture_db.dart';

const _bookId = 'ספר בדיקה';

class _CountingFiles extends Fake implements FileSystemData {
  _CountingFiles(this.text);

  String text;
  int textReads = 0;

  @override
  Future<String> getBookText(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    textReads++;
    return text;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late _CountingFiles files;
  late PersonalNotesRepository repository;
  late String dbPath;
  final provider = SqliteDataProvider.instance;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_repository_cache_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
    await provider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    final library = Directory('${root.path}/library')..createSync();
    dbPath = '${library.path}/${DatabaseConstants.databaseFileName}';
    File(
      SeforimFixtureDb.create(library, SeforimFixtureVariant.full),
    ).renameSync(dbPath);
    await Settings.setValue(SettingsRepository.keyLibraryPath, library.path);
    await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
    BooksCache.instance.clear();
    await provider.initialize();
    files = _CountingFiles('שורה ראשונה\nשורה שנייה');
    repository = PersonalNotesRepository(fileSystemData: files);
  });

  tearDown(() async {
    await provider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  Future<List<PersonalNote>> add(int lineNumber) => repository.addNote(
    bookId: _bookId,
    lineNumber: lineNumber,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
  );

  Future<List<PersonalNote>> addOfficial(
    PersonalNotesRepository repo, {
    String title = SeforimFixtureIds.bereshitTitle,
    int categoryId = SeforimFixtureIds.torahCategoryId,
    int line = 2,
  }) => repo.addNote(
    bookId: title,
    categoryId: categoryId,
    lineNumber: line,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
  );

  // קריאת 4097 שורות מפעילה checkpoint אחד בדיוק. המונה מודד קריאת תוכן
  // אמיתית, בנפרד מהודעות איתור הספר שנוספו ל-worker ב-#4227.
  Future<int Function()> countOfficialContentReads() async {
    await provider.closeForExternalWrite();
    try {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        db.execute(
          'WITH RECURSIVE c(i) AS (SELECT 3 UNION ALL SELECT i + 1 FROM c '
          'WHERE i < 4096) INSERT INTO line (bookId, lineIndex, content) '
          "SELECT 1, i, 'שורת מילוי' FROM c",
        );
      } finally {
        db.close();
      }
    } finally {
      await provider.reopenAfterExternalWrite();
    }
    DbReadWorker.disposeForTesting();
    var reads = 0;
    final checkpoints = ReceivePort();
    final subscription = checkpoints.listen((message) {
      reads++;
      (message as SendPort).send(null);
    });
    DbReadWorker.bookReadCheckpointPort = checkpoints.sendPort;
    addTearDown(() async {
      await provider.dispose();
      DbReadWorker.disposeForTesting();
      await subscription.cancel();
      checkpoints.close();
    });
    return () => reads;
  }

  test('DB רשמי: הוספה, עריכה ושינוי מיקום משתמשים באותה קריאה', () async {
    final contentReads = await countOfficialContentReads();
    const title = SeforimFixtureIds.bereshitTitle;
    await repository.loadNotes(title);
    expect(contentReads(), 1);
    DbReadWorker.sentMessageCount = 0;
    final added = await addOfficial(repository);
    final updated = await repository.updateNote(
      bookId: title,
      noteId: added.single.id,
      content: 'חדש',
      contentPlain: 'חדש',
      contentFormat: PersonalNoteContentFormat.plain,
    );
    final moved = await repository.repositionNote(
      bookId: title,
      noteId: added.single.id,
      lineNumber: 3,
    );

    expect(added.single.displayTitle, 'שורה ב');
    expect(updated.single.contentPlain, 'חדש');
    expect(moved.single.displayTitle, 'שורה ג');
    expect(contentReads(), 1, reason: 'שלוש הפעולות משתמשות בתוכן שבמטמון');
    expect(DbReadWorker.sentMessageCount, 3, reason: 'איתור ספר לכל פעולה');
  });

  test('חלונית חדשה משתמשת ברשומה המשותפת של אותו ספר רשמי', () async {
    final contentReads = await countOfficialContentReads();
    await repository.loadNotes(
      SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    expect(contentReads(), 1);
    DbReadWorker.sentMessageCount = 0;
    final other = PersonalNotesRepository();
    final notes = await addOfficial(other);

    expect(notes.single.displayTitle, 'שורה ב');
    expect(contentReads(), 1, reason: 'החלונית החדשה אינה קוראת שוב תוכן');
    expect(DbReadWorker.sentMessageCount, 1, reason: 'איתור ספר בלבד');
  });

  test('ספר מחלונית אחרת מפנה את הרשומה היחידה גם בחלונית הישנה', () async {
    final contentReads = await countOfficialContentReads();
    await repository.loadNotes(
      SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    expect(contentReads(), 1);
    final other = PersonalNotesRepository();
    await other.loadNotes(SeforimFixtureIds.rashiTitle);
    DbReadWorker.sentMessageCount = 0;
    final notes = await addOfficial(repository);

    expect(notes.single.displayTitle, 'שורה ב');
    expect(contentReads(), 2, reason: 'התוכן נטען שוב אחרי פינוי המטמון');
    expect(DbReadWorker.sentMessageCount, 3, reason: 'שני איתורים וקריאת תוכן');
  });

  test('קריאה ראשונה בעריכה ממלאת מטמון, טעינה מפורשת מרעננת אותו', () async {
    final contentReads = await countOfficialContentReads();
    await addOfficial(repository);
    expect(contentReads(), 1);
    DbReadWorker.sentMessageCount = 0;
    final notes = await addOfficial(repository, line: 3);
    expect(notes.last.displayTitle, 'שורה ג');
    expect(contentReads(), 1, reason: 'הוספה שנייה משתמשת במטמון');
    expect(DbReadWorker.sentMessageCount, 1, reason: 'איתור ספר בלבד');
    await repository.loadNotes(
      SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    expect(contentReads(), 2, reason: 'טעינה מפורשת קוראת שוב תוכן');
    expect(
      DbReadWorker.sentMessageCount,
      4,
      reason: 'הוספה: איתור אחד; רענון: שני איתורים ותוכן',
    );
  });

  test('רענון ספרייה פוסל את המטמון גם כשהחיבור לא השתנה', () async {
    final contentReads = await countOfficialContentReads();
    await repository.loadNotes(
      SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    expect(contentReads(), 1);
    BooksCache.instance.clear();
    DbReadWorker.sentMessageCount = 0;
    final notes = await addOfficial(repository);

    expect(notes.single.displayTitle, 'שורה ב');
    expect(contentReads(), 2, reason: 'רענון הספרייה מחייב קריאת תוכן חדשה');
    expect(DbReadWorker.sentMessageCount, 3, reason: 'שני איתורים וקריאת תוכן');
  });

  test('פתיחה מחדש אחרי עדכון רשמי מיישבת עוגן מול הספר החדש', () async {
    const title = SeforimFixtureIds.bereshitTitle;
    final added = await repository.addNote(
      bookId: title,
      lineNumber: 2,
      content: 'הערה',
      contentPlain: 'הערה',
      selectedText: 'שורה ב',
      contentFormat: PersonalNoteContentFormat.plain,
    );
    await repository.loadNotes(title);
    await provider.closeForExternalWrite();
    try {
      final db = sqlite3.sqlite3.open(dbPath);
      db.execute('UPDATE line SET lineIndex = lineIndex + 1 WHERE bookId = 1');
      db.execute(
        "INSERT INTO line (id, bookId, lineIndex, content) VALUES (99, 1, 0, 'הקדמה חדשה')",
      );
      db.close();
    } finally {
      await provider.reopenAfterExternalWrite();
    }
    final updated = await repository.updateNote(
      bookId: title,
      noteId: added.single.id,
      content: 'עריכה',
      contentPlain: 'עריכה',
      contentFormat: PersonalNoteContentFormat.plain,
    );

    expect(updated.single.status, PersonalNoteStatus.located);
    expect(updated.single.lineNumber, 3);
    expect(updated.single.anchorText, 'שורה ב');
  });

  test('commit בחיבור אחר פוסל מטמון לפני שהחיבור הרשמי נסגר', () async {
    const title = SeforimFixtureIds.bereshitTitle;
    await provider.dispose();
    final writer = sqlite3.sqlite3.open(dbPath);
    writer.execute('PRAGMA journal_mode=WAL');
    addTearDown(writer.close);
    await provider.initialize();
    final added = await repository.addNote(
      bookId: title,
      lineNumber: 2,
      content: 'הערה',
      contentPlain: 'הערה',
      selectedText: 'שורה ב',
      contentFormat: PersonalNoteContentFormat.plain,
    );
    await repository.loadNotes(title);
    final connection = provider.repository;
    writer.execute('BEGIN');
    writer.execute(
      'UPDATE line SET lineIndex = lineIndex + 1 WHERE bookId = 1',
    );
    writer.execute(
      "INSERT INTO line (id, bookId, lineIndex, content) VALUES (99, 1, 0, 'הקדמה חדשה')",
    );
    writer.execute('COMMIT');
    final updated = await repository.updateNote(
      bookId: title,
      noteId: added.single.id,
      content: 'עריכה',
      contentPlain: 'עריכה',
      contentFormat: PersonalNoteContentFormat.plain,
    );

    expect(provider.repository, same(connection));
    expect(updated.single.lineNumber, 3);
    expect(updated.single.anchorText, 'שורה ב');
    expect(updated.single.status, PersonalNoteStatus.located);
  });

  test('ספרים בעלי אותה כותרת בקטגוריות שונות אינם חולקים תוכן', () async {
    await provider.closeForExternalWrite();
    try {
      final db = sqlite3.sqlite3.open(dbPath);
      db.execute(
        "INSERT INTO book (id, categoryId, sourceId, title, totalLines) VALUES (3, 1, 1, 'בראשית', 1)",
      );
      db.execute(
        "INSERT INTO line (id, bookId, lineIndex, content) VALUES (99, 3, 0, 'ספר אחר בקטגוריה אחרת')",
      );
      db.close();
    } finally {
      await provider.reopenAfterExternalWrite();
    }
    await repository.loadNotes(
      SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    final notes = await addOfficial(repository, categoryId: 1, line: 1);

    expect(notes.single.displayTitle, contains('ספר אחר בקטגוריה'));
  });

  test('קריאת ספר שהחלה לפני רענון אינה ממלאת את המטמון החדש', () async {
    await provider.closeForExternalWrite();
    try {
      final db = sqlite3.sqlite3.open(dbPath);
      final insert = db.prepare(
        'INSERT INTO line (bookId, lineIndex, content) VALUES (1, ?, ?)',
      );
      db.execute('BEGIN');
      for (var i = 3; i < 4097; i++) {
        insert.execute([i, 'שורה $i']);
      }
      insert.close();
      db.execute('COMMIT');
      db.close();
    } finally {
      await provider.reopenAfterExternalWrite();
    }
    DbReadWorker.disposeForTesting();
    final checkpoints = ReceivePort();
    final paused = Completer<SendPort>();
    var contentReads = 0;
    final subscription = checkpoints.listen((message) {
      contentReads++;
      final release = message as SendPort;
      if (!paused.isCompleted) {
        paused.complete(release);
      } else {
        release.send(null);
      }
    });
    DbReadWorker.bookReadCheckpointPort = checkpoints.sendPort;
    addTearDown(() async {
      await subscription.cancel();
      checkpoints.close();
      DbReadWorker.disposeForTesting();
    });
    final loading = repository.loadNotes(
      SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    final release = await paused.future;
    BooksCache.instance.clear();
    release.send(null);
    await loading;
    expect(contentReads, 1);
    DbReadWorker.sentMessageCount = 0;
    final notes = await addOfficial(repository);

    expect(notes.single.displayTitle, 'שורה ב');
    expect(contentReads, 2, reason: 'התוצאה הישנה לא מילאה את המטמון החדש');
    expect(DbReadWorker.sentMessageCount, 3, reason: 'שני איתורים וקריאת תוכן');
  });

  test('טקסט ממערכת הקבצים משתנה בין טעינה לעריכה', () async {
    await repository.loadNotes(_bookId);
    files.text = 'שורה חדשה\nשורה שנייה';
    final notes = await add(1);

    expect(files.textReads, 2);
    expect(notes.single.displayTitle, 'שורה חדשה');
  });

  test('הערה חדשה מקבלת את שורת הספר ומיקום מכווץ לגבולותיו', () async {
    await repository.loadNotes(_bookId);
    final notes = await add(9);

    expect(notes.single.lineNumber, 2);
    expect(notes.single.displayTitle, 'שורה שנייה');
  });

  test('טעינה חוזרת ועריכת טקסט קובץ קוראות כל פעם את הגרסה החדשה', () async {
    await repository.loadNotes(_bookId);
    files.text = 'שורה מעודכנת\nשורה שנייה';
    await repository.loadNotes(_bookId);
    final notes = await add(1);

    expect(files.textReads, 3);
    expect(notes.single.displayTitle, 'שורה מעודכנת');
  });

  test('עריכה בספר אחר מזה שנטען קוראת את הספר שלה', () async {
    await repository.loadNotes('ספר אחר');
    await add(1);

    expect(files.textReads, 2);
  });

  test('תוכן ריק אינו נשמר, ועריכה קוראת את הספר שוב', () async {
    files.text = '';
    await repository.loadNotes(_bookId);
    files.text = 'שורה ראשונה';
    final notes = await add(1);

    expect(files.textReads, 2);
    expect(notes.single.displayTitle, 'שורה ראשונה');
  });
}
