import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:path/path.dart' as p;

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
        expect(link.connectionType, 'COMMENTARY');
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
      await UserContentImporter.importFiles([f], db);
      expect(
        (await repo.forwardUserLinks('ברכות', sourceIsUserBook: false)).length,
        1,
      );
      await repo.clearAllUserContent();
      expect(
        await repo.forwardUserLinks('ברכות', sourceIsUserBook: false),
        isEmpty,
      );
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
}
