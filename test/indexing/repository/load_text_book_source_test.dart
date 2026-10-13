import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

/// [IndexingRepository.loadTextBookSource] האמיתי מול seforim.db: רק ספר שהטקסט
/// שנמסר למנוע הוא בדיוק שורות המסד יכול להיות מאונדקס בלי הטקסט.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late IndexingRepository repository;

  // מתרוקן לגמרי בניקוי ה-data URI, ולכן הטקסט נלקח מהקובץ.
  final imageOnlyRow = 'data:image/png;base64,${'A' * 100}';
  const bom = '\uFEFF';
  final illustratedRows = [
    '$bom<img src="$imageOnlyRow"> פתיחה',
    'שורה נקייה',
    'שתיים: <img src="$imageOnlyRow"> <img src="$imageOnlyRow">',
    'קצר data:abc נשאר',
  ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_load_source');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));

    final dbPath = path.join(tempDir.path, 'seforim.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    for (final (id, title, rows) in [
      (301, 'שורות נקיות', ['א', 'ב']),
      (302, 'מעבר בשורה', ['א\nב', 'ג']),
      (303, 'תמונה בלבד', [imageOnlyRow]),
      (304, 'ספר מצויר', illustratedRows),
    ]) {
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
        'totalLines) VALUES (?, 7, 1, ?, ?, ?)',
        [id, title, id, rows.length],
      );
      for (var i = 0; i < rows.length; i++) {
        db.execute(
          'INSERT INTO line (bookId, lineIndex, content) VALUES (?, ?, ?)',
          [id, i, rows[i]],
        );
      }
    }
    database.close();

    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    repository = IndexingRepository(_UnusedTantivyDataProvider());
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    DbReadWorker.disposeForTesting();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows שחרור ה-handle של ה-worker אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  TextStorage storageFor(
    TextBook book,
    int? libraryDbBookId, {
    int? userBooksDbBookId,
  }) => IndexingRepository.textStorageFor(
    filePath: IndexingRepository.buildIndexedBookFilePath(book),
    libraryDbBookId: libraryDbBookId,
    userBooksDbBookId: userBooksDbBookId,
    hostApiReady: true,
    userBooksConfigured: true,
  );

  test('שורות נקיות מהמסד — המנוע יקרא אותן משם', () async {
    final book = TextBook(id: 301, title: 'שורות נקיות', categoryId: 7);
    final source = await repository.loadTextBookSource(book);

    expect(source.bytes, utf8.encode('א\nב'));
    expect(source.libraryDbBookId, 301);
    expect(source.userBooksDbBookId, isNull);
    expect(storageFor(book, source.libraryDbBookId), TextStorage.libraryDb);
    expect(source.dataUriLines, isNull);
  });

  test('ספר מצויר מהמסד — שורות התמונות נמסרות לפי מיקומן', () async {
    final book = TextBook(id: 304, title: 'ספר מצויר', categoryId: 7);
    final source = await repository.loadTextBookSource(book);

    expect(source.libraryDbBookId, 304);
    expect(storageFor(book, source.libraryDbBookId), TextStorage.libraryDb);
    expect(source.dataUriLines, [0, 2]);
    // המיקום הוא מספר השורה שהמנוע מקבל אחרי הפיצול ב-\n.
    final lines = source.text!.split('\n');
    expect(lines, hasLength(illustratedRows.length));
    expect(lines[0], '<img src=""> פתיחה');
    expect(lines[2], 'שתיים: <img src=""> <img src="">');
    expect(lines[3], illustratedRows[3]);
  });

  test(r'שורה עם \n פנימי — הטקסט נשמר באינדקס', () async {
    final book = TextBook(id: 302, title: 'מעבר בשורה', categoryId: 7);
    final source = await repository.loadTextBookSource(book);

    expect(source.bytes, utf8.encode('א\nב\nג'));
    expect(source.libraryDbBookId, isNull);
    expect(storageFor(book, source.libraryDbBookId), TextStorage.inIndex);
  });

  test('טקסט שנלקח מהקובץ ולא מהמסד — הטקסט נשמר באינדקס', () async {
    final file = File(path.join(tempDir.path, 'תמונה בלבד.html'));
    await file.writeAsString('<html><body><p>מהקובץ</p></body></html>');
    final book = TextBook(
      id: 303,
      title: 'תמונה בלבד',
      categoryId: 7,
      fileType: 'html',
      filePath: file.path,
    );
    final source = await repository.loadTextBookSource(book);

    expect(source.bytes, isNull);
    expect(source.text, contains('מהקובץ'));
    expect(source.libraryDbBookId, isNull);
    expect(storageFor(book, source.libraryDbBookId), TextStorage.inIndex);
    expect(source.dataUriLines, isNull);
  });

  group('ספרים אישיים מ-user_books.db', () {
    late File importedFile;

    setUp(() async {
      await Settings.setValue<String>(
        SettingsRepository.keyDatabasesPath,
        path.join(tempDir.path, 'databases'),
      );
      importedFile = File(path.join(tempDir.path, 'מקובץ.txt'));
      await importedFile.writeAsString('מהקובץ');
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final db = await repo.database.database;
      db.execute(
        "INSERT INTO category (id, title, level) VALUES (50, 'ספרים אישיים', 0)",
      );
      db.execute("INSERT OR IGNORE INTO source (id, name) VALUES (1, 'אישי')");
      for (final (id, title, rows, filePath) in [
        (7, 'אישי נקי', ['א', 'ב'], null),
        (8, 'אישי מעבר', ['א\nב', 'ג'], null),
        (9, 'אישי מקובץ', ['מהסריקה'], importedFile.path),
        (10, 'אישי מצויר', illustratedRows, null),
      ]) {
        db.execute(
          'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
          'totalLines, filePath) VALUES (?, 50, 1, ?, ?, ?, ?)',
          [id, title, id, rows.length, filePath],
        );
        for (var i = 0; i < rows.length; i++) {
          db.execute(
            'INSERT INTO line (bookId, lineIndex, content) VALUES (?, ?, ?)',
            [id, i, rows[i]],
          );
        }
      }
    });

    TextBook userBook(int id, String title) =>
        TextBook(id: id, title: title, categoryId: 50, source: BookSource.user);

    test('שורות נקיות — ה-id של user_books.db ולא של seforim.db', () async {
      final book = userBook(7, 'אישי נקי');
      final source = await repository.loadTextBookSource(book);

      expect(source.bytes, utf8.encode('א\nב'));
      expect(source.libraryDbBookId, isNull);
      expect(source.userBooksDbBookId, 7);
      expect(
        storageFor(book, null, userBooksDbBookId: source.userBooksDbBookId),
        TextStorage.libraryDb,
      );
    });

    test('ספר מצויר — שורות התמונות נמסרות כמו בספר רשמי', () async {
      final source = await repository.loadTextBookSource(
        userBook(10, 'אישי מצויר'),
      );

      expect(source.userBooksDbBookId, 10);
      expect(source.dataUriLines, [0, 2]);
    });

    test(r'שורה עם \n פנימי — בלי id', () async {
      final source = await repository.loadTextBookSource(
        userBook(8, 'אישי מעבר'),
      );

      expect(source.bytes, utf8.encode('א\nב\nג'));
      expect(source.userBooksDbBookId, isNull);
    });

    test('ספר מקובץ — בלי id גם כשיש לו שורות מהסריקה', () async {
      final source = await repository.loadTextBookSource(
        userBook(9, 'אישי מקובץ'),
      );

      expect(source.userBooksDbBookId, isNull);
      expect(source.libraryDbBookId, isNull);
    });
  });
}

class _UnusedTantivyDataProvider implements TantivyDataProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
