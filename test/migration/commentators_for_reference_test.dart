// טסטי אינטגרציה ל-SeforimRepository.getCommentatorsForReference.
//
// הם בודקים את הלוגיקה החדשה של "טווח קטע": מפרשים על כל התוכן מהכותרת ועד
// הכותרת הבאה ברמה <= level, ופתיחה במיקום המקביל הראשון בספר המפרש. בנוסף
// מאמתים את ההתנהגות לתוצאת ספר (sourceLineId=0): ספר עם כותרות פנימיות
// מחזיר ריק (יש לבחור דף), ספר בלי כותרות פנימיות מחזיר את כל מפרשיו.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/link_visibility_sql.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
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

  Future<int> insertCommentaryLink({
    required int sourceBookId,
    required int sourceLineId,
    required int targetBookId,
    required int targetLineId,
    String connectionTypeName = 'COMMENTARY',
  }) async {
    // `initializeConnectionTypes` מכניס את שמות הסוגים באותיות גדולות
    // ("COMMENTARY") — וזה מה שהשאילתה מחפשת, בעוד `enum.name` קטן
    // ("commentary"). לכן מחברים את ה-link ישירות ל-id של סוג הקישור הרצוי.
    final connectionTypeId = await repository.getOrCreateConnectionType(
      connectionTypeName,
    );
    return database.linkDao.insertLink(
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

  Future<void> enableSideVisibility() async {
    final db = await database.database;
    db.execute('''
      CREATE TABLE link_suppressed_side (
        linkId INTEGER NOT NULL,
        side INTEGER NOT NULL,
        reasonMask INTEGER NOT NULL,
        PRIMARY KEY (linkId, side)
      )
    ''');
  }

  Future<void> suppressSourceSide(int linkId) async {
    final db = await database.database;
    db.execute(
      'INSERT INTO link_suppressed_side VALUES (?, 0, 1)',
      [linkId],
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

    test(
      'כותרות רמה 1 בלבד (שולחן ערוך) + sourceLineId=0 → ריק',
      () async {
        final catId = await createCategory();
        final bookId = await createBook(catId, 'שולחן ערוך, אורח חיים');
        final lines = await insertLinesAndGetIds(bookId, [
          'סימן א',
          'סימן ב',
        ]);
        await insertToc(
          bookId: bookId,
          lineIndex: 0,
          text: 'סימן א',
          level: 1,
        );
        await insertToc(
          bookId: bookId,
          lineIndex: 1,
          text: 'סימן ב',
          level: 1,
        );
        final rashi = await buildRashiBook();
        await insertCommentaryLink(
          sourceBookId: bookId,
          sourceLineId: lines[0],
          targetBookId: rashi.bookId,
          targetLineId: rashi.lineIds[0],
        );

        final rows = await repository.getCommentatorsForReference(
          bookId: bookId,
          bookTitle: 'שולחן ערוך, אורח חיים',
          sourceLineId: 0,
          startLineIndex: 0,
          level: 1,
        );

        expect(
          rows,
          isEmpty,
          reason: 'סימנים ברמה 1 הם כותרות פנימיות — אין לסרוק את כל הספר',
        );
      },
    );

    test('כותרת פנימית אחת + sourceLineId=0 → כל מפרשי הספר', () async {
      final catId = await createCategory();
      final bookId = await createBook(catId, 'מסילת ישרים');
      final lines = await insertLinesAndGetIds(bookId, ['פתיחה', 'פרק']);
      await insertToc(
        bookId: bookId,
        lineIndex: 0,
        text: 'מסילת ישרים',
        level: 1,
      );
      final rashi = await buildRashiBook();
      await insertCommentaryLink(
        sourceBookId: bookId,
        sourceLineId: lines[1],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[1],
      );

      final rows = await repository.getCommentatorsForReference(
        bookId: bookId,
        bookTitle: 'מסילת ישרים',
        sourceLineId: 0,
        startLineIndex: 0,
        level: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.first['targetBookTitle'], 'רש"י על ברכות');
    });

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

    for (final headingCount in [0, 1, 2]) {
      for (final warmCache in [false, true]) {
        test('תוצאת ספר עם $headingCount כותרות ורמה 0 '
            '(מטמון ${warmCache ? 'חם' : 'קר'})', () async {
          final catId = await createCategory();
          final bookId = await createBook(catId, 'ספר מקור');
          final lineIds = await insertLinesAndGetIds(bookId, ['שורה']);
          final rootId = await insertToc(
            bookId: bookId,
            lineIndex: 0,
            text: 'ספר מקור',
            level: 0,
          );
          for (var i = 0; i < headingCount; i++) {
            await insertToc(
              bookId: bookId,
              lineIndex: 0,
              text: 'פרק ${i + 1}',
              level: 1,
              parentId: rootId,
            );
          }
          final commentator = await buildRashiBook();
          await insertCommentaryLink(
            sourceBookId: bookId,
            sourceLineId: lineIds.single,
            targetBookId: commentator.bookId,
            targetLineId: commentator.lineIds.first,
          );
          if (warmCache) {
            final toc = await repository.getTocEntriesForReference(
              bookId,
              'ספר מקור',
            );
            expect(toc, hasLength(headingCount));
          }

          final rows = await repository.getCommentatorsForReference(
            bookId: bookId,
            bookTitle: 'ספר מקור',
            sourceLineId: 0,
            startLineIndex: 0,
            level: 1,
          );
          expect(rows, hasLength(headingCount > 1 ? 0 : 1));
        });
      }
    }

    test('הוספת כותרת שנייה מבטלת את המטמון החם', () async {
      final catId = await createCategory();
      final bookId = await createBook(catId, 'ספר מקור');
      final lineIds = await insertLinesAndGetIds(bookId, ['שורה']);
      await insertToc(
        bookId: bookId,
        lineIndex: 0,
        text: 'פרק א',
        level: 1,
      );
      final commentator = await buildRashiBook();
      await insertCommentaryLink(
        sourceBookId: bookId,
        sourceLineId: lineIds.single,
        targetBookId: commentator.bookId,
        targetLineId: commentator.lineIds.first,
      );
      expect(
        await repository.getTocEntriesForReference(bookId, 'ספר מקור'),
        hasLength(1),
      );

      Future<List<Map<String, dynamic>>> commentators() =>
          repository.getCommentatorsForReference(
            bookId: bookId,
            bookTitle: 'ספר מקור',
            sourceLineId: 0,
            startLineIndex: 0,
            level: 1,
          );
      expect(await commentators(), hasLength(1));
      await insertToc(
        bookId: bookId,
        lineIndex: 0,
        text: 'פרק ב',
        level: 1,
      );
      expect(await commentators(), isEmpty);
    });
  });

  group('נראות מפרשים בסכמה 3', () {
    test('שלוש שאילתות המפרשים מתעלמות מצד מקור מדוכא', () async {
      final source = await buildSourceBook();
      final rashi = await buildRashiBook();
      await enableSideVisibility();

      final suppressedLinkId = await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[0],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[0],
      );
      final visibleLinkId = await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[1],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[2],
      );
      await suppressSourceSide(suppressedLinkId);

      final byBook = await database.linkDao.selectCommentatorsByBook(
        source.bookId,
      );
      final byRange = await database.linkDao.selectCommentatorsByLineRange(
        source.bookId,
        0,
        4,
      );
      final links = await database.linkDao.selectCommentaryLinksByLineRange(
        source.bookId,
        0,
        4,
        -1,
        0,
      );

      expect(byBook.single['linkCount'], 1);
      expect(byRange.single['linkCount'], 1);
      expect(byRange.single['targetLineIndex'], 2);
      expect(links.single['minTargetLineIndex'], 2);
      expect(links.single['maxTargetLineIndex'], 2);
      expect(links.single['exactTargetLineIndex'], isNull);

      await suppressSourceSide(visibleLinkId);
      expect(
        await database.linkDao.selectCommentatorsByBook(source.bookId),
        isEmpty,
      );
      expect(
        await database.linkDao.selectCommentatorsByLineRange(
          source.bookId,
          0,
          4,
        ),
        isEmpty,
      );
      expect(
        await database.linkDao.selectCommentaryLinksByLineRange(
          source.bookId,
          0,
          4,
          -1,
          0,
        ),
        isEmpty,
      );
    });
  });

  group('selectCommentatorsByBook', () {
    // השאילתה הבלתי-מצטברת, מקור להשוואת התוצאות.
    const legacyQuery = '''
SELECT DISTINCT l.targetBookId, b.title AS targetBookTitle, a.name AS author, COUNT(*) AS linkCount
FROM link l
JOIN connection_type ct ON l.connectionTypeId = ct.id
JOIN book b ON l.targetBookId = b.id
LEFT JOIN book_author ba ON b.id = ba.bookId
LEFT JOIN author a ON ba.authorId = a.id
WHERE l.sourceBookId = ?
AND ct.name IN ('COMMENTARY', 'SUPER_COMMENTARY', 'TARGUM', 'MIDRASH', 'PARSHANUT', 'DIBUR_HAMATCHIL', 'ELUCIDATION', 'FOOTNOTES')
/*LINK_VISIBILITY_FILTER*/
GROUP BY l.targetBookId, b.title, a.name
ORDER BY b.orderIndex, b.title''';

    String withVisibility(String query) => query.replaceFirst(
      linkVisibilityFilterMarker,
      suppressedSideFilter(true, displayedSide: 0),
    );

    test('קישורי הספר נצברים לפני הצירוף לספר ולמחברים', () async {
      await enableSideVisibility();
      final db = await database.database;
      final query = (await database.capabilities).adaptBookQuery(
        QueryLoader.loadQueries('LinkQueries.sq')['selectCommentatorsByBook']!,
      );
      final plan = db.select('EXPLAIN QUERY PLAN ${withVisibility(query)}', [
        1,
      ]);
      final rowById = {for (final row in plan) row['id'] as int: row};
      bool insideSubquery(int id) {
        for (var p = rowById[id]!['parent'] as int; p != 0;) {
          final row = rowById[p]!;
          if (RegExp(
            r'^(CO-ROUTINE|MATERIALIZE)',
          ).hasMatch('${row['detail']}')) {
            return true;
          }
          p = row['parent'] as int;
        }
        return false;
      }

      int nodeFor(String table) =>
          plan.firstWhere(
                (r) => RegExp('^(SCAN|SEARCH) $table\\b').hasMatch(
                  '${r['detail']}',
                ),
              )['id']
              as int;
      expect(insideSubquery(nodeFor('l')), isTrue);
      expect(insideSubquery(nodeFor('b')), isFalse);
    });

    test('התוצאה זהה לשאילתה הקודמת', () async {
      final source = await buildSourceBook();
      final rashi = await buildRashiBook();
      final catId = await createCategory();
      final tosafot = await createBook(catId, 'תוספות');
      final tosafotLines = await insertLinesAndGetIds(tosafot, ['ת-1', 'ת-2']);
      await enableSideVisibility();
      final db = await database.database;
      db.execute("INSERT INTO author (name) VALUES ('רש\"י'), ('ר\"ת')");
      db.execute(
        'INSERT INTO book_author (bookId, authorId) SELECT ?, id FROM author',
        [rashi.bookId],
      );

      for (var i = 0; i < 4; i++) {
        await insertCommentaryLink(
          sourceBookId: source.bookId,
          sourceLineId: source.lineIds[i],
          targetBookId: rashi.bookId,
          targetLineId: rashi.lineIds[i],
        );
      }
      final suppressed = await insertCommentaryLink(
        sourceBookId: source.bookId,
        sourceLineId: source.lineIds[5],
        targetBookId: rashi.bookId,
        targetLineId: rashi.lineIds[3],
      );
      await suppressSourceSide(suppressed);
      for (final type in ['TARGUM', 'QUOTATION']) {
        await insertCommentaryLink(
          sourceBookId: source.bookId,
          sourceLineId: source.lineIds[6],
          targetBookId: tosafot,
          targetLineId: tosafotLines[0],
          connectionTypeName: type,
        );
      }

      final actual = await database.linkDao.selectCommentatorsByBook(
        source.bookId,
      );
      expect(actual, hasLength(3));
      expect(
        actual.map((row) => row['collectiveTitleHe']),
        everyElement(isNull),
      );
      expect(
        [for (final row in actual) Map.of(row)..remove('collectiveTitleHe')],
        db.select(withVisibility(legacyQuery), [source.bookId]).toMapList(),
      );
    });
  });
}
