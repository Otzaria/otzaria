// טסטי אינטגרציה ל-SeforimRepository.getCommentatorsForReference.
//
// הם בודקים את הלוגיקה החדשה של "טווח קטע": מפרשים על כל התוכן מהכותרת ועד
// הכותרת הבאה ברמה <= level, ופתיחה במיקום המקביל הראשון בספר המפרש. בנוסף
// מאמתים את ההתנהגות לתוצאת ספר (sourceLineId=0): ספר עם כותרות פנימיות
// מחזיר ריק (יש לבחור דף), ספר בלי כותרות פנימיות מחזיר את כל מפרשיו.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:otzaria/migration/models/link.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('commentators-range-');
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<int> createCategory() => repository.insertCategory(
    const Category(title: 'קטגוריה', parentId: null, level: 0),
  );

  Future<int> createBook(int categoryId, String title) =>
      repository.insertExternalContentBook(
        categoryId: categoryId,
        title: title,
        filePath: '/tmp/$title.txt',
        fileType: 'txt',
        fileSize: 0,
        lastModified: 0,
        isPersonal: true,
      );

  /// מכניס שורות ומחזיר את ה-id של כל שורה לפי lineIndex (לשימוש ב-link).
  Future<List<int>> insertLinesAndGetIds(
    int bookId,
    List<String> contents,
  ) async {
    final ids = <int>[];
    for (int i = 0; i < contents.length; i++) {
      final id = await repository.insertLine(
        Line(id: 0, bookId: bookId, lineIndex: i, content: contents[i]),
      );
      ids.add(id);
    }
    return ids;
  }

  Future<int> insertToc({
    required int bookId,
    required int lineIndex,
    required String text,
    required int level,
    int? parentId,
  }) => repository.insertTocEntry(
    TocEntry(
      id: 0,
      bookId: bookId,
      parentId: parentId,
      text: text,
      level: level,
      lineIndex: lineIndex,
      lineId: null,
      isLastChild: true,
      hasChildren: false,
    ),
  );

  Future<void> insertCommentaryLink({
    required int sourceBookId,
    required int sourceLineId,
    required int targetBookId,
    required int targetLineId,
    String connectionTypeName = 'COMMENTARY',
  }) async {
    // עוקפים את `repository.insertLink` הציבורי: הוא משתמש ב-`enum.name`
    // (lowercase "commentary") בעוד `initializeConnectionTypes` מכניס
    // "COMMENTARY" (uppercase) — שזה מה שהשאילתה מחפשת. אנו מחברים את
    // ה-link ישירות ל-id של סוג הקישור הרצוי.
    final connectionTypeId = await repository.getOrCreateConnectionType(
      connectionTypeName,
    );
    await database.linkDao.insertLink(
      Link(
        id: 0,
        sourceBookId: sourceBookId,
        targetBookId: targetBookId,
        sourceLineId: sourceLineId,
        targetLineId: targetLineId,
        connectionType: ConnectionType.commentary,
      ),
      connectionTypeId,
    );
  }

  /// בונה ספר מקור "ברכות" עם:
  ///   - שורות 0..7
  ///   - level 2: "דף ד" ב-lineIndex 0
  ///   - level 3: "עמוד א" ב-lineIndex 0, "עמוד ב" ב-lineIndex 2 (תחת דף ד)
  ///   - level 2: "דף ה" ב-lineIndex 4
  ///   - level 3: "עמוד א" ב-lineIndex 4 (תחת דף ה)
  /// מחזיר את (bookId, lineIds[]) כדי שיהיה אפשר לקשר ספציפית לכל שורה.
  Future<({int bookId, List<int> lineIds})> buildSourceBook() async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ברכות');
    final lineIds = await insertLinesAndGetIds(bookId, [
      'ד-1',
      'ד-2',
      'ד-3',
      'ד-4',
      'ה-1',
      'ה-2',
      'ה-3',
      'ה-4',
    ]);

    final dafD = await insertToc(
      bookId: bookId,
      lineIndex: 0,
      text: 'דף ד',
      level: 2,
    );
    await insertToc(
      bookId: bookId,
      lineIndex: 0,
      text: 'עמוד א',
      level: 3,
      parentId: dafD,
    );
    await insertToc(
      bookId: bookId,
      lineIndex: 2,
      text: 'עמוד ב',
      level: 3,
      parentId: dafD,
    );

    final dafH = await insertToc(
      bookId: bookId,
      lineIndex: 4,
      text: 'דף ה',
      level: 2,
    );
    await insertToc(
      bookId: bookId,
      lineIndex: 4,
      text: 'עמוד א',
      level: 3,
      parentId: dafH,
    );

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    return (bookId: bookId, lineIds: lineIds);
  }

  /// בונה ספר מפרש "רש"י על ברכות" עם 4 שורות; מחזיר את ה-ids שלהן.
  Future<({int bookId, List<int> lineIds})> buildRashiBook() async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'רש"י על ברכות');
    final lineIds = await insertLinesAndGetIds(bookId, [
      'רש"י-1',
      'רש"י-2',
      'רש"י-3',
      'רש"י-4',
    ]);
    return (bookId: bookId, lineIds: lineIds);
  }

  /// מחזיר את ה-`lineId` של ערך TOC לפי טקסט (אחרי
  /// `updateTocEntryLineIdsByLineIndex` כבר רץ).
  Future<int> tocLineIdByText(int bookId, String text) async {
    final db = await database.database;
    final rows = db
        .select(
          '''
        SELECT t.lineId FROM tocEntry t
        JOIN tocText tt ON t.textId = tt.id
        WHERE t.bookId = ? AND tt.text = ?
      ''',
          [bookId, text],
        )
        .toMapList();
    return rows.first['lineId'] as int;
  }

  // ── tests ─────────────────────────────────────────────────────────────────

  group('SeforimRepository.getCommentatorsForReference — טווח קטע', () {
    test('דף ד: מאסוף קישורים מכל שורות דף ד עד דף ה (לא כולל)', () async {
      final source = await buildSourceBook();
      final rashi = await buildRashiBook();

      // מפרש על שורה הראשונה של דף ד (lineIndex 0) → רש"י-1
      await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[0],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[0],
      );
      // מפרש על שורת תוכן באמצע דף ד (lineIndex 3) → רש"י-2
      await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[3],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[1],
      );
      // מפרש על שורה של דף ה (lineIndex 5) → רש"י-3 — אסור שייכנס לטווח של דף ד
      await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[5],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[2],
      );

      final dafDLineId = await tocLineIdByText(source.bookId, "דף ד");
      final rows = await repository.getCommentatorsForReference(
        bookId: source.bookId,
        bookTitle: 'ברכות',
        sourceLineId: dafDLineId,
        startLineIndex: 0,
        level: 2,
      );

      expect(
        rows,
        hasLength(1),
        reason: 'רש"י אחד עם MIN על פני הטווח של דף ד',
      );
      expect(rows.first['targetBookTitle'], 'רש"י על ברכות');
      // MIN(targetLineIndex) מבין שורות 0 ו-1 של רש"י (הקישורים בתוך דף ד) = 0.
      expect(rows.first['targetLineIndex'], 0);
    });

    test('תת-כותרות (level 3) נכללות בטווח של דף ד', () async {
      final source = await buildSourceBook();
      final rashi = await buildRashiBook();

      // קישור משורת תוכן ב-lineIndex 2 (שייכת ל"עמוד ב" שתחת דף ד).
      // ה-boundary ברמה <= 2 הוא דף ה (lineIndex 4), לכן 2 בטווח.
      await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[2],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[1],
      );

      final dafDLineId = await tocLineIdByText(source.bookId, "דף ד");
      final rows = await repository.getCommentatorsForReference(
        bookId: source.bookId,
        bookTitle: 'ברכות',
        sourceLineId: dafDLineId,
        startLineIndex: 0,
        level: 2,
      );

      expect(
        rows,
        hasLength(1),
        reason: 'קישור משורה תחת תת-כותרת חייב להיכלל בטווח של הכותרת הראשית',
      );
      expect(rows.first['targetLineIndex'], 1);
    });

    test('דף ללא קישורים — מחזיר רשימה ריקה', () async {
      final source = await buildSourceBook();
      await buildRashiBook(); // קיים אך בלי קישורים

      final dafDLineId = await tocLineIdByText(source.bookId, "דף ד");
      final rows = await repository.getCommentatorsForReference(
        bookId: source.bookId,
        bookTitle: 'ברכות',
        sourceLineId: dafDLineId,
        startLineIndex: 0,
        level: 2,
      );

      expect(rows, isEmpty);
    });

    test('עין משפט אינו חוזר כמפרש', () async {
      final source = await buildSourceBook();
      final rashi = await buildRashiBook();

      await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[0],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[0],
        connectionTypeName: 'EIN_MISHPAT',
      );

      final dafDLineId = await tocLineIdByText(source.bookId, "דף ד");
      final rows = await repository.getCommentatorsForReference(
        bookId: source.bookId,
        bookTitle: 'ברכות',
        sourceLineId: dafDLineId,
        startLineIndex: 0,
        level: 2,
      );

      expect(
        rows,
        isEmpty,
        reason: 'עין משפט צריך להופיע בפאנל הקישורים, לא ברשימת המפרשים',
      );
    });

    test(
      'ספר עם כותרות פנימיות + sourceLineId=0 → ריק (יש לבחור דף)',
      () async {
        final source = await buildSourceBook();
        final rashi = await buildRashiBook();
        // יש קישור — אבל תוצאת "ספר ברכות" בלי דף לא אמורה להציג מפרשים.
        await insertCommentaryLink(
          sourceBookId: source.bookId,
          sourceLineId: source.lineIds[0],
          targetBookId: rashi.bookId,
          targetLineId: rashi.lineIds[0],
        );

        final rows = await repository.getCommentatorsForReference(
          bookId: source.bookId,
          bookTitle: 'ברכות',
          sourceLineId: 0,
          startLineIndex: 0,
          level: 1,
        );

        expect(
          rows,
          isEmpty,
          reason: 'ספר ברכות (יש לו דפים פנימיים) — המשתמש חייב לבחור דף',
        );
      },
    );

    test('ספר ללא כותרות פנימיות + sourceLineId=0 → כל מפרשי הספר', () async {
      // ספר מקור קצר ללא TOC פנימי.
      final catId = await createCategory();
      final shortBookId = await createBook(catId, 'מסילת ישרים');
      final shortLines = await insertLinesAndGetIds(shortBookId, [
        'פתיחה',
        'פרק',
        'מסקנה',
      ]);

      // ספר מפרש.
      final rashi = await buildRashiBook();

      // קישור משורה 1 (אמצע הספר) — נצפה ש-MIN(targetLineIndex) של הקישור הוא 1
      // (השורה השנייה של "רש"י"). כי השאילתה מחזירה את המיקום הראשון של המפרש.
      await insertCommentaryLink(
        sourceBookId: shortBookId,
        sourceLineId: shortLines[1],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[1],
      );

      final rows = await repository.getCommentatorsForReference(
        bookId: shortBookId,
        bookTitle: 'מסילת ישרים',
        sourceLineId: 0,
        startLineIndex: 0,
        level: 1,
      );

      expect(rows, hasLength(1), reason: 'ספר ללא TOC פנימי מציג את כל מפרשיו');
      expect(rows.first['targetBookTitle'], 'רש"י על ברכות');
      expect(rows.first['targetLineIndex'], 1);
    });
  });
}
