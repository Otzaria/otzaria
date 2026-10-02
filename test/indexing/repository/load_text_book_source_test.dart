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

  TextStorage storageFor(TextBook book, int? libraryDbBookId) =>
      IndexingRepository.textStorageFor(
        filePath: IndexingRepository.buildIndexedBookFilePath(book),
        libraryDbBookId: libraryDbBookId,
        hostApiReady: true,
      );

  test('שורות נקיות מהמסד — המנוע יקרא אותן משם', () async {
    final book = TextBook(id: 301, title: 'שורות נקיות', categoryId: 7);
    final source = await repository.loadTextBookSource(book);

    expect(source.bytes, utf8.encode('א\nב'));
    expect(source.libraryDbBookId, 301);
    expect(storageFor(book, source.libraryDbBookId), TextStorage.libraryDb);
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
  });
}

class _UnusedTantivyDataProvider implements TantivyDataProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
