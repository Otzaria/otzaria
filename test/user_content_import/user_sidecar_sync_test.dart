import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/user_content_import/services/user_sidecar_sync.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory folder;
  late MyDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_sidecar');
    folder = Directory(p.join(tempDir.path, 'ספרים'))..createSync();
    db = MyDatabase.withPath(p.join(tempDir.path, 'user_books.db'));
    final raw = await db.database;
    raw.execute("INSERT INTO source (name) VALUES ('external')");
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  /// יוצר קובץ ספר בתיקייה ורשומת ספר תואמת (כמו אחרי סריקה).
  Future<int> addBook(String fileName, String content) async {
    final path = p.join(folder.path, fileName);
    File(path).writeAsStringSync(content);
    final raw = await db.database;
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, filePath, fileType, lastModified) '
      'VALUES (1, 1, ?, ?, ?, 1)',
      [
        p.basenameWithoutExtension(fileName),
        path,
        p.extension(fileName).substring(1),
      ],
    );
    return raw.lastInsertRowId;
  }

  File writeSidecar(String name, String content) =>
      File(p.join(folder.path, name))..writeAsStringSync(content);

  Future<List<Map<String, Object?>>> headingRows(int bookId) async {
    final raw = await db.database;
    return raw.select(
      'SELECT s.heTitle, s.key, e.text, e.lineIndex, e.parentId '
      'FROM user_alt_toc_structure s '
      'JOIN user_alt_toc_entry e ON e.structureId = s.id '
      'WHERE s.bookId = ? ORDER BY e.id',
      [bookId],
    ).toList();
  }

  test('קובץ כותרות של ספר נקלט לפי שם הקובץ', () async {
    final bookId = await addBook('משנה.txt', 'הקדמה\nפרק ראשון\nפרק שני');
    writeSidecar(
      'משנה.כותרות.csv',
      'מבנה,כותרת,שורה,טקסט\nסימנים,סימן א,2,\nסימנים,סימן ב,,פרק שני\n',
    );

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors, isEmpty);
    final rows = await headingRows(bookId);
    expect(rows.map((r) => r['text']), ['סימן א', 'סימן ב']);
    expect(rows.map((r) => r['lineIndex']), [1, 2]);
    expect(rows.first['key'], 'Simanim');
  });

  test('קובץ כותרות רוחבי מזהה ספרים לפי עמודת ספר', () async {
    final first = await addBook('א.txt', 'שורה\nשורה');
    final second = await addBook('ב.txt', 'שורה\nשורה');
    writeSidecar('כותרות.csv', 'ספר,כותרת,שורה\nא,ראשון,1\nב,שני,2\n');

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors, isEmpty);
    expect((await headingRows(first)).single['text'], 'ראשון');
    expect((await headingRows(second)).single['lineIndex'], 1);
  });

  test('עריכת הקובץ מחליפה את הכותרות, ומחיקתו מסירה אותן', () async {
    final bookId = await addBook('ספר.txt', 'א\nב\nג');
    final sidecar = writeSidecar('ספר.כותרות.csv', 'כותרת,שורה\nישן,1\n');
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

    sidecar.writeAsStringSync('כותרת,שורה\nחדש,3\nנוסף,2\n');
    sidecar.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
    expect((await headingRows(bookId)).map((r) => r['text']), ['חדש', 'נוסף']);

    sidecar.deleteSync();
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
    expect(await headingRows(bookId), isEmpty);
  });

  test('שגיאה בקובץ מדווחת עם שם הקובץ', () async {
    await addBook('ספר.txt', 'שורה אחת');
    writeSidecar('ספר.כותרות.csv', 'כותרת,שורה\nרחוקה,50\n');

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors.single, contains('ספר.כותרות.csv'));
    expect(errors.single, contains('חורגת מגבולות הספר'));
  });

  test('כותרות לספר PDF נדחות', () async {
    await addBook('סרוק.pdf', '%PDF-1.4');
    writeSidecar('סרוק.כותרות.csv', 'כותרת,שורה\nפרק,1\n');

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors.single, contains('רק בספרי טקסט'));
  });

  test('קובץ גרסאות מקשר קבצים לפי נתיב יחסי', () async {
    final primary = await addBook('רשבא.txt', 'א');
    final version = await addBook('רשבא קוק.txt', 'א');
    writeSidecar(
      'גרסאות.csv',
      'ראשי,גרסה,שם\nרשבא.txt,רשבא קוק.txt,מוסד הרב קוק\n',
    );

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors, isEmpty);
    final raw = await db.database;
    final rows = raw.select('SELECT * FROM user_book_version').toList();
    expect(rows.single['primaryBookId'], primary);
    expect(rows.single['versionBookId'], version);
    expect(rows.single['versionTitle'], 'מוסד הרב קוק');
  });

  test('ייבוא מההגדרות קולט כותרות וגרסאות לפי כותרות ספרים', () async {
    final primary = await addBook('ראשי.txt', 'א\nב\nג');
    final version = await addBook('משני.txt', 'א');
    final headings = writeSidecar(
      'import-כותרות.csv',
      'ספר,מבנה,כותרת,שורה\nראשי,נושאים,הלכות א,3\n',
    );
    final headingsPath = p.join(tempDir.path, 'כותרות.csv');
    headings.renameSync(headingsPath);
    final versionsPath = p.join(tempDir.path, 'גרסאות.csv');
    File(versionsPath).writeAsStringSync('ראשי,גרסה,שם\nראשי,משני,דפוס ישן\n');

    final result = await UserContentImporter.importFiles([
      headingsPath,
      versionsPath,
    ], db);

    expect(result.errors, isEmpty);
    expect(result.headingsApplied, 1);
    expect(result.versionsApplied, 1);
    final rows = await headingRows(primary);
    expect(rows.single['key'], 'Topic');
    expect(rows.single['lineIndex'], 2);
    final raw = await db.database;
    expect(
      raw
          .select('SELECT versionBookId FROM user_book_version')
          .single['versionBookId'],
      version,
    );

    await UserContentRepository(db).clearAllUserContent();
    expect(await headingRows(primary), isEmpty);
  });

  test('מחיקת ספר מוחקת את כותרותיו ואת רשומות הגרסאות שלו', () async {
    final primary = await addBook('ראשי.txt', 'א\nב');
    await addBook('משני.txt', 'א');
    writeSidecar('ראשי.כותרות.csv', 'כותרת,שורה\nפרק,1\n');
    writeSidecar('גרסאות.csv', 'ראשי,גרסה\nראשי.txt,משני.txt\n');
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

    await SeforimRepository(db).deleteBookCompletely(primary);

    final raw = await db.database;
    expect(raw.select('SELECT * FROM user_alt_toc_structure'), isEmpty);
    expect(raw.select('SELECT * FROM user_alt_toc_entry'), isEmpty);
    expect(raw.select('SELECT * FROM user_book_version'), isEmpty);
  });

  group('גרסה אישית של ספר רשמי', () {
    test('קובץ הגרסאות שומר את הראשי לפי מקור, כותרת וקטגוריה', () async {
      final version = await addBook('בראשית כתב יד.txt', 'א');
      writeSidecar(
        'גרסאות.csv',
        'ראשי,גרסה,שם,מקור_ראשי,קטגוריית_ראשי\n'
            'בראשית,בראשית כתב יד.txt,כתב יד,רשמי,תורה\n',
      );

      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );

      expect(errors, isEmpty);
      final raw = await db.database;
      final row = raw.select('SELECT * FROM user_book_version').single;
      expect(row['versionBookId'], version);
      expect(row['primaryBookId'], isNull);
      expect(row['primarySource'], 'o');
      expect(row['primaryTitle'], 'בראשית');
      expect(row['primaryCategoryPath'], 'תורה');
      expect(row['versionTitle'], 'כתב יד');
    });

    test('קובץ הגרסה חסר — שגיאה בשורה, בלי לעצור את שאר הקובץ', () async {
      await addBook('קיים.txt', 'א');
      writeSidecar(
        'גרסאות.csv',
        'ראשי,גרסה,מקור_ראשי\nבראשית,חסר.txt,רשמי\nשמות,קיים.txt,רשמי\n',
      );

      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );

      expect(errors.single, contains('חסר.txt'));
      final raw = await db.database;
      final rows = raw.select('SELECT primaryTitle FROM user_book_version');
      expect(rows.single['primaryTitle'], 'שמות');
    });

    test('ייבוא מההגדרות: ראשי ממסד מצורף נשמר גם כשאינו מחובר', () async {
      final version = await addBook('גרסה מצורפת.txt', 'א');
      final versionsPath = p.join(tempDir.path, 'גרסאות.csv');
      File(versionsPath).writeAsStringSync(
        'ראשי,גרסה,מקור_ראשי\nבראשית,גרסה מצורפת,מסד:ספרייה\n',
      );

      final result = await UserContentImporter.importFiles([versionsPath], db);

      expect(result.errors, isEmpty);
      final raw = await db.database;
      final row = raw.select('SELECT * FROM user_book_version').single;
      expect(row['versionBookId'], version);
      expect(row['primarySource'], 'd:ספרייה');
    });
  });
}
