import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

/// בדיקת קצה-לקצה לתלונה "user_books.db לא מתכווץ": כיבוי "הוסף למסד
/// הנתונים" מוחק את תוכן הספרים, וצריך גם להקטין את הקובץ בפועל.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late String customFolderPath;
  late String libraryPath;
  late List<CustomFolder> folders;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'otzaria-file-sync-compaction-',
    );
    FileSyncService.resetSingletonForTesting();
    database = MyDatabase.withPath(path.join(tempDir.path, 'user_books.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();

    libraryPath = path.join(tempDir.path, 'library');
    customFolderPath = path.join(tempDir.path, 'ספרים אישיים');
    await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
    await Directory(customFolderPath).create(recursive: true);

    // ספר גדול דיו כדי לחצות את סף הכיווץ (1MB פנוי ולפחות רבע מהקובץ).
    final line = '${'א' * 200}\n';
    await File(
      path.join(customFolderPath, 'ספר גדול.txt'),
    ).writeAsString(line * 12000);
  });

  tearDown(() async {
    database.close();
    FileSyncService.resetSingletonForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void setFolderStorage({required bool addToDatabase}) => folders = [
    CustomFolder(
      path: customFolderPath,
      addToDatabase: addToDatabase,
      addedAt: DateTime(2026, 4, 13),
    ),
  ];

  Future<void> sync() async {
    FileSyncService.resetSingletonForTesting();
    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    final result = await service!.syncCustomFoldersWithInputs(
      libraryPath: libraryPath,
      customFolders: folders,
    );
    expect(result.errors, isEmpty);
  }

  /// גודל הקובץ על הדיסק. ב-WAL הכתיבות יושבות ביומן עד checkpoint, ולכן
  /// בלי זה המדידה משקפת מצב ישן.
  Future<int> dbFileSize() async {
    (await database.database).execute('PRAGMA wal_checkpoint(TRUNCATE)');
    return File(path.join(tempDir.path, 'user_books.db')).lengthSync();
  }

  test('כיבוי "הוסף למסד הנתונים" מקטין את user_books.db בפועל', () async {
    setFolderStorage(addToDatabase: true);
    await sync();
    final sizeWithContent = await dbFileSize();
    expect(
      sizeWithContent,
      greaterThan(2 * 1024 * 1024),
      reason: 'תוכן הספר אמור להיות ב-DB',
    );

    setFolderStorage(addToDatabase: false);
    await sync();

    final db = await database.database;
    expect(
      db.select('SELECT count(*) FROM line').first.values.first,
      0,
      reason: 'התוכן נמחק — הספר נקרא מהקובץ',
    );
    expect(
      await dbFileSize(),
      lessThan(sizeWithContent ~/ 2),
      reason: 'הקובץ חייב להתכווץ, לא רק להשתחרר ל-freelist',
    );
  });

  test('מחיקת תיקייה מותאמת מקטינה את user_books.db', () async {
    setFolderStorage(addToDatabase: true);
    await sync();
    final sizeWithContent = await dbFileSize();
    expect(sizeWithContent, greaterThan(2 * 1024 * 1024));

    FileSyncService.resetSingletonForTesting();
    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    await service!.deleteFolderFromDatabase(customFolderPath);

    final db = await database.database;
    expect(db.select('SELECT count(*) FROM book').first.values.first, 0);
    expect(
      await dbFileSize(),
      lessThan(sizeWithContent ~/ 2),
      reason: 'הסרת תיקייה היא הפעולה שמשחררת הכי הרבה — חייבת לכווץ',
    );
  });

  test('מחיקה שלא הסירה ספרים אינה מכווצת', () async {
    setFolderStorage(addToDatabase: true);
    await sync();
    final sizeWithContent = await dbFileSize();

    FileSyncService.resetSingletonForTesting();
    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    await service!.deleteFolderFromDatabase('/תיקייה/שלא/קיימת');

    final db = await database.database;
    expect(db.select('SELECT count(*) FROM book').first.values.first, 1);
    expect(await dbFileSize(), sizeWithContent);
  });

  test('prune של תיקייה שהוסרה ברענון ספרייה מקטין את user_books.db', () async {
    setFolderStorage(addToDatabase: true);
    await sync();
    final sizeWithContent = await dbFileSize();
    expect(sizeWithContent, greaterThan(2 * 1024 * 1024));

    // המסלול של LibraryBloc ברענון רגיל: התיקייה כבר לא בהגדרות, וה-prune
    // מסיר את ספריה מה-DB.
    FileSyncService.resetSingletonForTesting();
    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    await service!.refreshSourcesAndPruneRemovedCustomFolders(const []);

    final db = await database.database;
    expect(db.select('SELECT count(*) FROM book').first.values.first, 0);
    expect(
      await dbFileSize(),
      lessThan(sizeWithContent ~/ 2),
      reason: 'גם מסלול ה-prune הישיר חייב לכווץ, לא רק זרימת הסנכרון',
    );
  });
}
