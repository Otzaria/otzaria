import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/user_content_import/services/user_link_ref_resolver.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:path/path.dart' as p;

import '../../tool/generate_text_encoding_fixtures.dart' show encodeLegacy;
import '../helpers/seforim_fixture_db.dart';

/// פותר-כתובות מזויף לבדיקות: "לא קיים" → null (כשל resolution); כל כתובת
/// טקסטואלית אחרת → שורה 41.
Future<int?> fakeResolver({
  required String targetTitle,
  required int? targetCategoryId,
  required bool targetIsUserBook,
  required String ref,
}) async => ref == 'לא קיים' ? null : 41;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserContentImporter.importFiles', () {
    late Directory tempDir;
    late Directory folder;
    late MyDatabase db;
    late UserContentRepository repo;
    late int bookId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_import');
      folder = Directory(p.join(tempDir.path, 'ספרים אישיים'))
        ..createSync(recursive: true);
      db = MyDatabase.withPath(p.join(tempDir.path, 'user_books.db'));
      final raw = await db.database;
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute("INSERT INTO source (name) VALUES ('external')");
      raw.execute(
        'INSERT INTO book (categoryId, sourceId, title) VALUES (1, 1, ?)',
        ['ביאורי יוסף'],
      );
      bookId = raw.lastInsertRowId;
      repo = UserContentRepository(db);
    });

    tearDown(() async {
      db.close();
      await tempDir.delete(recursive: true);
    });

    /// כותב קובץ בתיקיית הבדיקה ומחזיר את נתיבו (לבחירה ידנית בייבוא).
    String writeCsv(String name, String content) {
      final path = p.join(folder.path, name);
      File(path).writeAsStringSync(content);
      return path;
    }

    test('קולט דור וקישורים וכותב ל-DB', () async {
      final gen = writeCsv(
        'דורות.csv',
        'ספר,דור,מחבר\nביאורי יוסף,מחברי זמננו,יוסף כהן\n',
      );
      final links = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
            '12,ברכות,5,פירוש,לא\n'
            '47,שולחן ערוך אורח חיים,רטו א,הפניה,לא\n',
      );

      final result = await UserContentImporter.importFiles(
        [gen, links],
        db,
        resolveRef: fakeResolver,
      );
      expect(result.errors, isEmpty);
      expect(result.generationsApplied, 1);
      expect(result.linksApplied, 2);

      final raw = await db.database;
      final genRow = raw.select(
        'SELECT g.name FROM book_generation bg '
        'JOIN generation g ON g.id = bg.generationId WHERE bg.bookId = ?',
        [bookId],
      );
      expect(genRow.single['name'], 'מחברי זמננו');

      // עמודת "מחבר" נכתבת ל-book_author — ממנה מוזרם book.author לאיתור
      // בספרייה (issue #1082).
      final authorRow = raw.select(
        'SELECT a.name FROM book_author ba '
        'JOIN author a ON a.id = ba.authorId WHERE ba.bookId = ?',
        [bookId],
      );
      expect(authorRow.single['name'], 'יוסף כהן');

      // פירוש נשמר בכיוון הקנוני (בסיס→מפרש): ברכות היא המקור.
      final commentary = await repo.forwardUserLinks(
        'ברכות',
        sourceIsUserBook: false,
      );
      expect(commentary.single.sourceLineIndex, 4); // "5" → אינדקס 4
      expect(commentary.single.targetTitle, 'ביאורי יוסף');
      expect(commentary.single.targetIsUserBook, isTrue);
      expect(commentary.single.targetLineIndex, 11);
      expect(commentary.single.connectionType, 'COMMENTARY');

      // הפניה נשמרת בכיוון כפי שנכתבה; כתובת טקסטואלית נשמרת להצגה.
      final reference = await repo.forwardUserLinks(
        'ביאורי יוסף',
        sourceIsUserBook: true,
      );
      expect(reference.single.sourceLineIndex, 46);
      expect(reference.single.targetRef, 'רטו א');
      expect(reference.single.targetLineIndex, 41);
      expect(reference.single.connectionType, 'REFERENCE');
    });

    test('כתובת וספר חוזרים נפתרים פעם אחת לכל קובץ', () async {
      final rows = StringBuffer('מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n');
      for (var i = 1; i <= 300; i++) {
        rows.writeln('$i,ברכות,${i.isEven ? 'ב.' : 'ב:'},פירוש,לא');
      }
      final links = writeCsv('ביאורי יוסף.links.csv', rows.toString());
      var resolveCalls = 0;

      final result = await UserContentImporter.importFiles(
        [links],
        db,
        resolveRef:
            ({
              required targetTitle,
              required targetCategoryId,
              required targetIsUserBook,
              required ref,
            }) async {
              resolveCalls++;
              return ref == 'ב.' ? 10 : 20;
            },
      );

      expect(result.errors, isEmpty);
      expect(result.linksApplied, 300);
      expect(resolveCalls, 2);
      final forward = await repo.forwardUserLinks(
        'ברכות',
        sourceIsUserBook: false,
      );
      expect(forward.map((l) => l.sourceLineIndex).toSet(), {10, 20});
    });

    test('מקור רשמי וכתובת שלא נפתרת: חיפוש אחד', () async {
      final rows = StringBuffer(
        'מקור,ספר_מקור,מקור_אישי,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n',
      );
      for (var i = 1; i <= 50; i++) {
        rows.writeln('$i,ברכות,לא,שולחן ערוך,לא קיים,הפניה,לא');
      }
      final links = writeCsv('קישורים.csv', rows.toString());
      var resolveCalls = 0;
      var sourceCalls = 0;

      final result = await UserContentImporter.importFiles(
        [links],
        db,
        resolveRef:
            ({
              required targetTitle,
              required targetCategoryId,
              required targetIsUserBook,
              required ref,
            }) async {
              resolveCalls++;
              return null;
            },
        sourceExists:
            ({required title, categoryId, required isUserBook}) async {
              sourceCalls++;
              return true;
            },
      );

      expect(result.errors, hasLength(50));
      expect(resolveCalls, 1);
      expect(sourceCalls, 1);
    });

    test('קובץ ייבוא ב-ANSI עברית נקלט כמו UTF-8', () async {
      // קובץ CSV שנשמר מאקסל בעברית הוא Windows-1255, ו-`readAsString` היה
      // זורק עליו — הייבוא כולו נכשל בהודעת "קריאת הקובץ נכשלה".
      final path = p.join(folder.path, 'דורות.csv');
      File(path).writeAsBytesSync(
        encodeLegacy(
          'ספר,דור,מחבר\nביאורי יוסף,מחברי זמננו,יוסף כהן\n',
          TextEncoding.windows1255,
        ),
      );

      final result = await UserContentImporter.importFiles(
        [path],
        db,
        resolveRef: fakeResolver,
      );
      expect(result.errors, isEmpty);
      expect(result.generationsApplied, 1);

      final raw = await db.database;
      final genRow = raw.select(
        'SELECT g.name FROM book_generation bg '
        'JOIN generation g ON g.id = bg.generationId WHERE bg.bookId = ?',
        [bookId],
      );
      expect(genRow.single['name'], 'מחברי זמננו');
    });

    test('קולט קישורים מקובץ JSON', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.json',
        '[{"מקור": 12, "ספר_יעד": "ברכות", "מיקום_יעד": 5, "סוג": "פירוש"},'
            '{"מקור": 47, "ספר_יעד": "ברכות", "מיקום_יעד": 8, "סוג": "הפניה"}]',
      );
      final result = await UserContentImporter.importFiles([f], db);
      expect(result.errors, isEmpty);
      expect(result.linksApplied, 2);
      // פירוש מתהפך לכיוון הקנוני; הפניה נשארת כפי שנכתבה.
      final commentary = await repo.forwardUserLinks(
        'ברכות',
        sourceIsUserBook: false,
      );
      expect(commentary.single.connectionType, 'COMMENTARY');
      expect(commentary.single.targetLineIndex, 11);
      final reference = await repo.forwardUserLinks(
        'ביאורי יוסף',
        sourceIsUserBook: true,
      );
      expect(reference.single.connectionType, 'REFERENCE');
      expect(reference.single.targetLineIndex, 7);
    });

    test('כתובת טקסטואלית נפתרת לשורה דרך resolveRef', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,שולחן ערוך אורח חיים,רטו א,הפניה\n',
      );
      final result = await UserContentImporter.importFiles(
        [f],
        db,
        resolveRef: fakeResolver,
      );
      expect(result.errors, isEmpty);
      expect(result.linksApplied, 1);
      final links = await repo.forwardUserLinks(
        'ביאורי יוסף',
        sourceIsUserBook: true,
      );
      expect(links.single.targetLineIndex, 41);
      expect(links.single.targetRef, 'רטו א');
    });

    test('כתובת טקסטואלית שלא נפתרה → שגיאה, אין כתיבה', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,לא קיים,הפניה\n',
      );
      final result = await UserContentImporter.importFiles(
        [f],
        db,
        resolveRef: fakeResolver,
      );
      expect(result.errors, isNotEmpty);
      expect(result.linksApplied, 0);
      expect(
        await repo.forwardUserLinks('ביאורי יוסף', sourceIsUserBook: true),
        isEmpty,
      );
    });

    test('מיקום_יעד חסר → שגיאה, אין כתיבה', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,סוג\n12,ברכות,פירוש\n',
      );
      final result = await UserContentImporter.importFiles(
        [f],
        db,
        resolveRef: fakeResolver,
      );
      expect(result.errors, isNotEmpty);
      expect(result.linksApplied, 0);
    });

    test('ייבוא חוזר של אותו קישור לא מכפיל (upsert)', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,פירוש\n',
      );
      await UserContentImporter.importFiles([f], db);
      await UserContentImporter.importFiles([f], db);
      final links = await repo.forwardUserLinks(
        'ברכות',
        sourceIsUserBook: false,
      );
      expect(links.length, 1);
    });

    test('ייבוא קישור חדש מצטבר לקיימים', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,פירוש\n',
      );
      await UserContentImporter.importFiles([f], db);
      // קובץ עם קישור שונה (שורת מקור אחרת) — מתווסף, לא מחליף.
      File(
        f,
      ).writeAsStringSync('מקור,ספר_יעד,מיקום_יעד,סוג\n20,ברכות,8,פירוש\n');
      await UserContentImporter.importFiles([f], db);
      final links = await repo.forwardUserLinks(
        'ברכות',
        sourceIsUserBook: false,
      );
      expect(links.length, 2);
    });

    test('ייבוא חוזר של קישור זהה דורס את סוג הקשר', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,הפניה\n',
      );
      await UserContentImporter.importFiles([f], db);
      File(f).writeAsStringSync('מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,אחר\n');
      await UserContentImporter.importFiles([f], db);
      final links = await repo.forwardUserLinks(
        'ביאורי יוסף',
        sourceIsUserBook: true,
      );
      expect(links.length, 1);
      expect(links.single.connectionType, 'OTHER');
    });

    test('דור חדש דורס דור קודם לאותו ספר', () async {
      final g = writeCsv('דורות.csv', 'ספר,דור\nביאורי יוסף,ראשונים\n');
      await UserContentImporter.importFiles([g], db);
      File(g).writeAsStringSync('ספר,דור\nביאורי יוסף,אחרונים\n');
      await UserContentImporter.importFiles([g], db);
      final raw = await db.database;
      final rows = raw.select(
        'SELECT g.name FROM book_generation bg '
        'JOIN generation g ON g.id = bg.generationId WHERE bg.bookId = ?',
        [bookId],
      );
      expect(rows.single['name'], 'אחרונים');
    });

    test('פירוש: הכיוון הקנוני נשמר וההפוך נמצא מצד המפרש', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,פירוש\n',
      );
      await UserContentImporter.importFiles([f], db);
      // בקריאת המפרש (ביאורי יוסף) הקישור נמצא כ-inverse ומצביע אל הבסיס.
      final inverse = await repo.inverseUserLinks(
        'ביאורי יוסף',
        targetIsUserBook: true,
      );
      expect(inverse.length, 1);
      expect(inverse.single.sourceTitle, 'ברכות');
      expect(inverse.single.sourceIsUserBook, isFalse);
      expect(inverse.single.connectionType, 'COMMENTARY');
      // מפרשי-המשתמש של הבסיס נגזרים מהקישורים היוצאים ממנו.
      final commentators = await repo.userCommentatorTitles(
        'ברכות',
        sourceIsUserBook: false,
      );
      expect(commentators, ['ביאורי יוסף']);
    });

    test('קישור ממקור רשמי נקלט ונשמר עם sourceIsUserBook=0', () async {
      final f = writeCsv(
        'קישורים.csv',
        'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
            'שולחן ערוך אורח חיים,לא,3,ברכות,5,הפניה,לא\n',
      );
      final result = await UserContentImporter.importFiles(
        [f],
        db,
        resolveRef: fakeResolver,
        sourceExists:
            ({required title, categoryId, required isUserBook}) async =>
                !isUserBook && title == 'שולחן ערוך אורח חיים',
      );
      expect(result.errors, isEmpty);
      expect(result.linksApplied, 1);

      // המקור הרשמי אינו בטבלת book של user_books.db — נשלף לפי כותרת.
      final forward = await repo.forwardUserLinks(
        'שולחן ערוך אורח חיים',
        sourceIsUserBook: false,
      );
      expect(forward.single.sourceIsUserBook, isFalse);
      expect(forward.single.targetTitle, 'ברכות');
      expect(forward.single.sourceLineIndex, 2);

      // הקישור ההפוך (הנקרא בספר היעד) מצביע חזרה אל המקור הרשמי.
      final inverse = await repo.inverseUserLinks(
        'ברכות',
        targetIsUserBook: false,
      );
      expect(inverse.single.sourceTitle, 'שולחן ערוך אורח חיים');
      expect(inverse.single.sourceIsUserBook, isFalse);
    });

    test('מקור רשמי שאינו קיים → שגיאה, אין כתיבה', () async {
      final f = writeCsv(
        'קישורים.csv',
        'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג\n'
            'ספר רשמי דמיוני,לא,3,ברכות,5,הפניה\n',
      );
      final result = await UserContentImporter.importFiles(
        [f],
        db,
        resolveRef: fakeResolver,
        sourceExists:
            ({required title, categoryId, required isUserBook}) async => false,
      );
      expect(result.errors, isNotEmpty);
      expect(result.linksApplied, 0);
    });

    group('פורמט native (<ספר>_links.json)', () {
      /// מאתר מזויף: "מגילה" רשמי (200 שורות), "הכי גרסינן מגילה" אישי
      /// (2000 שורות); כל כותרת אחרת לא נמצאת.
      Future<({bool isUserBook, int? categoryId, int totalLines})?> fakeLocator(
        String title,
      ) async => switch (title) {
        'מגילה' => (isUserBook: false, categoryId: 5, totalLines: 200),
        'הכי גרסינן מגילה' => (
          isUserBook: true,
          categoryId: 1,
          totalLines: 2000,
        ),
        _ => null,
      };

      test('נקלט: בסיס רשמי משם הקובץ, יעד אישי מ-path_2', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 3, "line_index_2": 5, '
              '"heRef_2": "הכי גרסינן מגילה ב., א", '
              '"path_2": "הכי גרסינן מגילה.txt", '
              '"Conection Type": "commentary"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        expect(result.linksApplied, 1);

        final stored = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
        );
        final link = stored.single;
        expect(link.sourceCategoryId, 5);
        expect(link.sourceLineIndex, 2); // 1-based → 0-based
        expect(link.targetTitle, 'הכי גרסינן מגילה');
        expect(link.targetIsUserBook, isTrue);
        expect(link.targetLineIndex, 4);
        expect(link.targetRef, 'הכי גרסינן מגילה ב., א');
        expect(link.connectionType, LinkTypes.commentary);
      });

      test('native linker שומר עוגן וקצה טווח במסד', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 3, "line_index_2": 5, '
              '"line_index_2_end": 7, "start": 4, "end": 9, '
              '"heRef_2": "הכי גרסינן מגילה ב., א אות א", '
              '"heRef_2_end": "הכי גרסינן מגילה ב., ג", '
              '"path_2": "הכי גרסינן מגילה.txt", '
              '"Conection Type": "linker"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        final link = (await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
        )).single;
        expect(link.connectionType, LinkTypes.commentary);
        expect(link.anchorStart, 4);
        expect(link.anchorEnd, 9);
        expect(link.anchorLabel, 'א');
        expect(link.targetLineIndexEnd, 6);
        expect(link.targetRefEnd, contains('ג'));
      });

      test('צמד דו-כיווני מתלכד לרשומה אחת עם ה-ref נשמר', () async {
        // הקובץ של הבסיס (מגילה) + הקובץ ההפוך שהכלי יוצר למפרש.
        final canonical = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 3, "line_index_2": 5, '
              '"heRef_2": "הכי גרסינן מגילה ב., א", '
              '"path_2": "הכי גרסינן מגילה.txt", '
              '"Conection Type": "commentary"}]',
        );
        final reverse = writeCsv(
          'הכי גרסינן מגילה_links.json',
          '[{"line_index_1": 5, "line_index_2": 3, '
              '"heRef_2": "מגילה ב.", "path_2": "מגילה.txt", '
              '"Conection Type": "commentary"}]',
        );
        final result = await UserContentImporter.importFiles(
          [canonical, reverse],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        expect(result.linksApplied, 1);

        final stored = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
        );
        expect(stored.single.targetTitle, 'הכי גרסינן מגילה');
        expect(stored.single.targetRef, 'הכי גרסינן מגילה ב., א');
      });

      test('סוג תלוי-טקסט מורחב מתהפך למפרש; סוג הפניה נשאר', () async {
        final f = writeCsv(
          'הכי גרסינן מגילה_links.json',
          '[{"line_index_1": 5, "line_index_2": 3, "path_2": "מגילה.txt", '
              '"Conection Type": "midrash"},'
              '{"line_index_1": 6, "line_index_2": 4, "path_2": "מגילה.txt", '
              '"Conection Type": "law"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        expect(result.linksApplied, 2);

        final flipped = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
        );
        expect(flipped.single.connectionType, LinkTypes.midrash);
        expect(flipped.single.targetTitle, 'הכי גרסינן מגילה');
        expect(
          await repo.userCommentatorTitles('מגילה', sourceIsUserBook: false),
          ['הכי גרסינן מגילה'],
        );

        final kept = await repo.forwardUserLinks(
          'הכי גרסינן מגילה',
          sourceIsUserBook: true,
        );
        expect(kept.single.connectionType, LinkTypes.law);
        expect(kept.single.targetTitle, 'מגילה');
      });

      test('כמה עוגנים באותו צמד-שורות נשמרים כרשומות נפרדות', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 3, "line_index_2": 5, "start": 4, '
              '"heRef_2": "הכי גרסינן מגילה ב., א אות א", '
              '"path_2": "הכי גרסינן מגילה.txt"}, '
              '{"line_index_1": 3, "line_index_2": 5, "start": 20, '
              '"heRef_2": "הכי גרסינן מגילה ב., א אות ב", '
              '"path_2": "הכי גרסינן מגילה.txt"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        expect(result.linksApplied, 2);
        final stored = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
        );
        expect(stored.map((l) => l.anchorStart), [4, 20]);
        expect(stored.map((l) => l.anchorLabel), ['א', 'ב']);
      });

      test('ייבוא חוזר של צמד-שורות מעוגן אינו מכפיל', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 3, "line_index_2": 5, "start": 4, '
              '"path_2": "הכי גרסינן מגילה.txt"}, '
              '{"line_index_1": 3, "line_index_2": 5, "start": 20, '
              '"path_2": "הכי גרסינן מגילה.txt"}]',
        );
        for (var i = 0; i < 2; i++) {
          final result = await UserContentImporter.importFiles(
            [f],
            db,
            locateBook: fakeLocator,
          );
          expect(result.errors, isEmpty);
        }
        final stored = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
        );
        expect(stored.map((l) => l.anchorStart), [4, 20]);
      });

      test('קישור-טווח נטען גם בכיוון ההפוך כשהחלון מתחיל באמצעו', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 2, "line_index_2": 5, "line_index_2_end": 9, '
              '"path_2": "הכי גרסינן מגילה.txt"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        // הקישור מצביע על שורות 4..8 (0-based) במפרש; החלון 6..7 באמצעו.
        final inWindow = await repo.inverseUserLinks(
          'הכי גרסינן מגילה',
          targetIsUserBook: true,
          startLineIndex: 6,
          endLineIndex: 7,
        );
        expect(inWindow, hasLength(1));
        expect(
          await repo.inverseUserLinks(
            'הכי גרסינן מגילה',
            targetIsUserBook: true,
            startLineIndex: 20,
            endLineIndex: 30,
          ),
          isEmpty,
        );
      });

      test('קישור-טווח נטען גם כשהחלון מתחיל באמצעו', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 2, "line_index_1_end": 9, "line_index_2": 5, '
              '"path_2": "הכי גרסינן מגילה.txt"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors, isEmpty);
        // הקישור מתחיל בשורה 1 (0-based) ונמשך עד 8; החלון 4..6 באמצעו.
        final inWindow = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
          startLineIndex: 4,
          endLineIndex: 6,
        );
        expect(inWindow, hasLength(1));
        final afterRange = await repo.forwardUserLinks(
          'מגילה',
          sourceIsUserBook: false,
          startLineIndex: 20,
          endLineIndex: 30,
        );
        expect(afterRange, isEmpty);
      });

      test('שורה מעבר ל-totalLines → שגיאה, אין כתיבה', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 999, "line_index_2": 5, '
              '"path_2": "הכי גרסינן מגילה.txt"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors.single, contains('חורגת מגבולות'));
        expect(result.linksApplied, 0);
      });

      test('ספר בסיס לא נמצא → שגיאה אחת לקובץ', () async {
        final f = writeCsv(
          'ספר עלום_links.json',
          '[{"line_index_1": 1, "line_index_2": 2, "path_2": "מגילה"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors.single, contains('ספר עלום'));
        expect(result.linksApplied, 0);
      });

      test('ספר יעד לא נמצא → שגיאה, אין כתיבה', () async {
        final f = writeCsv(
          'מגילה_links.json',
          '[{"line_index_1": 1, "line_index_2": 2, "path_2": "לא קיים.txt"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: fakeLocator,
        );
        expect(result.errors.single, contains('לא קיים'));
        expect(result.linksApplied, 0);
      });
    });

    group('ספר במסד מצורף (#4237)', () {
      late AttachedLinkBooks attached;

      setUp(() {
        final dir = Directory(p.join(tempDir.path, 'attached'))..createSync();
        final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
        final raw = sqlite3.sqlite3.open(path);
        raw.execute("UPDATE book SET title = 'ספר מצורף' WHERE id = 1");
        raw.close();
        attached = AttachedLinkBooks.open([
          (slug: 'my-db', path: path, immutable: false, visible: true),
        ]);
      });
      tearDown(() => attached.close());

      Future<bool> notOfficial({
        required String title,
        required int? categoryId,
        required bool isUserBook,
      }) async => false;

      test('CSV: יעד שאינו ברשמית נמצא במסד המצורף', () async {
        final f = writeCsv(
          'ביאורי יוסף.links.csv',
          'מקור,ספר_יעד,מיקום_יעד,סוג\n3,ספר מצורף,2,הפניה\n',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          resolveRef: fakeResolver,
          sourceExists: notOfficial,
          attachedBooks: attached,
        );
        expect(result.errors, isEmpty);
        final link = (await repo.forwardUserLinks(
          'ביאורי יוסף',
          sourceIsUserBook: true,
        )).single;
        expect(link.targetDb, 'my-db');
        expect(link.targetIsUserBook, isFalse);
        expect(link.targetCategoryId, isNull);
        expect(link.targetLineIndex, 1);
      });

      test('CSV: פירוש על ספר מצורף נשמר כשהמסד המצורף הוא הבסיס', () async {
        final f = writeCsv(
          'ביאורי יוסף.links.csv',
          'מקור,ספר_יעד,מיקום_יעד,סוג,מסד_יעד\n3,ספר מצורף,1,פירוש,db:my-db\n',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          resolveRef: fakeResolver,
          attachedBooks: attached,
        );
        expect(result.errors, isEmpty);
        final link = (await repo.forwardUserLinks(
          'ספר מצורף',
          sourceIsUserBook: false,
          sourceDb: 'my-db',
        )).single;
        expect(link.targetTitle, 'ביאורי יוסף');
        expect(link.targetIsUserBook, isTrue);
        expect(
          await repo.forwardUserLinks('ספר מצורף', sourceIsUserBook: false),
          isEmpty,
        );
      });

      test('CSV: מסד מפורש שאינו מכיל את הספר → שגיאה', () async {
        final f = writeCsv(
          'ביאורי יוסף.links.csv',
          'מקור,ספר_יעד,מיקום_יעד,סוג,מסד_יעד\n3,ספר מצורף,1,הפניה,מסד:other\n',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          resolveRef: fakeResolver,
          attachedBooks: attached,
        );
        expect(result.errors.single, contains('ספר היעד "ספר מצורף" לא נמצא'));
        expect(result.linksApplied, 0);
      });

      test(
        'גרסאות: ספר הגרסה במסד מצורף נשמר לפי slug וכותרת (#4392)',
        () async {
          final f = writeCsv(
            'גרסאות.csv',
            'ראשי,גרסה,שם,מקור_ראשי\n'
                'בראשית,ספר מצורף,נוסח אחר,רשמי\n'
                'ביאורי יוסף,ספר מצורף,,אישי\n',
          );
          final result = await UserContentImporter.importFiles(
            [f],
            db,
            sourceExists:
                ({required title, categoryId, required isUserBook}) async =>
                    title == 'בראשית',
            attachedBooks: attached,
          );
          expect(result.errors, isEmpty);
          expect(result.versionsApplied, 2);
          final rows = (await db.database).select(
            'SELECT * FROM user_attached_book_version',
          );
          final row = rows.single;
          // הצהרה שנייה על אותו ספר דורסת את הראשונה (מפתח slug+כותרת).
          expect(row['versionDb'], 'my-db');
          expect(row['versionBookTitle'], 'ספר מצורף');
          expect(row['primarySource'], 'u');
          expect(row['primaryTitle'], 'ביאורי יוסף');
          expect(
            (await db.database).select('SELECT * FROM user_book_version'),
            isEmpty,
          );
        },
      );

      test('גרסאות: מסד_גרסה שאינו מכיל את הספר → שגיאה', () async {
        final f = writeCsv(
          'גרסאות.csv',
          'ראשי,גרסה,מקור_ראשי,מסד_גרסה\nבראשית,ספר מצורף,רשמי,other\n',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          sourceExists:
              ({required title, categoryId, required isUserBook}) async => true,
          attachedBooks: attached,
        );
        expect(result.errors.single, contains('לא נמצא במסד "other"'));
      });

      test('native: ספר בסיס במסד מצורף נקלט', () async {
        final f = writeCsv(
          'ספר מצורף_links.json',
          '[{"line_index_1": 2, "line_index_2": 5, '
              '"path_2": "ביאורי יוסף.txt", '
              '"Conection Type": "reference"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: (title) async => title == 'ביאורי יוסף'
              ? (isUserBook: true, categoryId: 1, totalLines: 50)
              : null,
          attachedBooks: attached,
        );
        expect(result.errors, isEmpty);
        final link = (await repo.forwardUserLinks(
          'ספר מצורף',
          sourceIsUserBook: false,
          sourceDb: 'my-db',
        )).single;
        expect(link.sourceLineIndex, 1);
        expect(link.targetIsUserBook, isTrue);
      });

      test('native: שורה מעבר לאורך הספר המצורף → שגיאה', () async {
        final f = writeCsv(
          'ספר מצורף_links.json',
          '[{"line_index_1": 9, "line_index_2": 5, '
              '"path_2": "ביאורי יוסף.txt", '
              '"Conection Type": "reference"}]',
        );
        final result = await UserContentImporter.importFiles(
          [f],
          db,
          locateBook: (title) async => title == 'ביאורי יוסף'
              ? (isUserBook: true, categoryId: 1, totalLines: 50)
              : null,
          attachedBooks: attached,
        );
        expect(result.errors.single, contains('חורגת מגבולות'));
      });
    });

    test('ספר לא קיים בדורות → שגיאה, אין כתיבה', () async {
      final g = writeCsv('דורות.csv', 'ספר,דור\nספר שלא קיים,ראשונים\n');
      final result = await UserContentImporter.importFiles([g], db);
      expect(result.generationsApplied, 0);
      expect(result.errors, isNotEmpty);
    });

    test('קובץ לא-מזוהה → שגיאה, אין כתיבה', () async {
      final f = writeCsv('notes.csv', 'a,b\n1,2\n');
      final result = await UserContentImporter.importFiles([f], db);
      expect(result.errors, isNotEmpty);
      expect(result.linksApplied, 0);
    });

    test('שורה פגומה חוסמת כתיבה כלשהי (אטומי) ושומרת קיימים', () async {
      await repo.upsertUserLink(
        UserLinkRecord(
          sourceTitle: 'ביאורי יוסף',
          sourceLineIndex: 99,
          targetTitle: 'קיים',
          connectionType: 'COMMENTARY',
        ),
      );
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,פירוש\nאבג,ברכות,5,פירוש\n',
      );
      final result = await UserContentImporter.importFiles([f], db);
      expect(result.errors, isNotEmpty);
      final links = await repo.forwardUserLinks(
        'ביאורי יוסף',
        sourceIsUserBook: true,
      );
      expect(links.length, 1);
      expect(links.single.sourceLineIndex, 99); // הישן נשמר, לא נכתב חלקית
    });

    test('שגיאת פענוח לא מוחקת נתונים קיימים', () async {
      await repo.upsertUserLink(
        UserLinkRecord(
          sourceTitle: 'ביאורי יוסף',
          sourceLineIndex: 0,
          targetTitle: 'ברכות',
          connectionType: 'COMMENTARY',
        ),
      );
      // CSV עם שגיאה (ספר שאינו קיים) — אסור שימחק את הקישור הקיים.
      final g = writeCsv('דורות.csv', 'ספר,דור\nספר שלא קיים,ראשונים\n');
      final result = await UserContentImporter.importFiles([g], db);
      expect(result.errors, isNotEmpty);
      expect(
        (await repo.forwardUserLinks(
          'ביאורי יוסף',
          sourceIsUserBook: true,
        )).length,
        1,
      );
    });

    test('clearAllUserContent מוחק את כל המיובא', () async {
      final f = writeCsv(
        'ביאורי יוסף.links.csv',
        'מקור,ספר_יעד,מיקום_יעד,סוג\n12,ברכות,5,פירוש\n',
      );
      final g = writeCsv(
        'דורות.csv',
        'ספר,דור,מחבר\nביאורי יוסף,מחברי זמננו,יוסף כהן\n',
      );
      await UserContentImporter.importFiles([f, g], db);
      expect(
        (await repo.forwardUserLinks('ברכות', sourceIsUserBook: false)).length,
        1,
      );
      await repo.clearAllUserContent();
      expect(
        await repo.forwardUserLinks('ברכות', sourceIsUserBook: false),
        isEmpty,
      );
      final raw = await db.database;
      expect(raw.select('SELECT * FROM book_author'), isEmpty);
      expect(raw.select('SELECT * FROM author'), isEmpty);
    });

    test('inverseUserLinks מסנן לפי targetCategoryId', () async {
      for (final link in [
        UserLinkRecord(
          sourceTitle: 'ביאורי יוסף',
          sourceLineIndex: 0,
          targetTitle: 'משותף',
          targetCategoryId: 10,
          targetLineIndex: 0,
          connectionType: 'COMMENTARY',
        ),
        UserLinkRecord(
          sourceTitle: 'ביאורי יוסף',
          sourceLineIndex: 1,
          targetTitle: 'משותף',
          targetCategoryId: 20,
          targetLineIndex: 1,
          connectionType: 'COMMENTARY',
        ),
        UserLinkRecord(
          sourceTitle: 'ביאורי יוסף',
          sourceLineIndex: 2,
          targetTitle: 'משותף',
          targetLineIndex: 2,
          connectionType: 'COMMENTARY',
        ),
      ]) {
        await repo.upsertUserLink(link);
      }
      // קטגוריה 10 + השורה ללא קטגוריה; לא קטגוריה 20.
      final cat10 = await repo.inverseUserLinks(
        'משותף',
        targetIsUserBook: false,
        targetCategoryId: 10,
      );
      expect(cat10.length, 2);
      final all = await repo.inverseUserLinks('משותף', targetIsUserBook: false);
      expect(all.length, 3);
    });
  });

  group('mergeUserLinks', () {
    UserLinkRecord link({
      int sourceLineIndex = 1,
      int? targetLineIndex = 5,
      int? anchorStart,
      String? targetRef,
      String? anchorLabel,
    }) => UserLinkRecord(
      sourceTitle: 'מגילה',
      sourceIsUserBook: false,
      sourceLineIndex: sourceLineIndex,
      targetTitle: 'מפרש',
      targetIsUserBook: true,
      targetLineIndex: targetLineIndex,
      targetRef: targetRef,
      anchorStart: anchorStart,
      anchorLabel: anchorLabel,
      connectionType: 'COMMENTARY',
    );

    test('רשומות זהות לגמרי מתמזגות לאחת', () {
      expect(mergeUserLinks([link(), link()]), hasLength(1));
    });

    test('העשירה בשדות תצוגה מנצחת', () {
      final merged = mergeUserLinks([
        link(),
        link(targetRef: 'מפרש א, ב'),
      ]);
      expect(merged.single.targetRef, 'מפרש א, ב');
    });

    test('עוגנים שונים באותו צמד-שורות נשמרים וממוינים', () {
      final merged = mergeUserLinks([
        link(anchorStart: 30, anchorLabel: 'ב'),
        link(anchorStart: 4, anchorLabel: 'א'),
      ]);
      expect(merged.map((l) => l.anchorStart), [4, 30]);
    });

    test('רשומה חסרת-עוגן נבלעת במעוגנת ומשלימה לה את ה-heRef', () {
      // הצד ההפוך של צמד דו-כיווני מגיע בלי עוגן; הוא אותו קישור ולכן אינו
      // שורה נוספת, אבל ה-heRef שיש רק בו נשמר.
      final merged = mergeUserLinks([
        link(targetRef: 'מפרש א, ב'),
        link(anchorStart: 4, anchorLabel: 'א'),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.anchorStart, 4);
      expect(merged.single.targetRef, 'מפרש א, ב');
    });

    test('צמדי-שורות שונים אינם מתמזגים', () {
      final merged = mergeUserLinks([
        link(sourceLineIndex: 1),
        link(sourceLineIndex: 2),
        link(targetLineIndex: 6),
        link(targetLineIndex: null),
      ]);
      expect(merged, hasLength(4));
    });
  });
}
