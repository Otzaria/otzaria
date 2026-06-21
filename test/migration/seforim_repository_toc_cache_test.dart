// Regression tests for SeforimRepository.getTocEntriesForReference + הקאש שלו.
//
// השיפור: SQL רץ פעם אחת לכל bookId; סינון לפי queryTokens עובד in-memory על
// טוקנים מנורמלים מראש. הבדיקות מאמתות שהחוזה (תוצאות) נשמר ושהקאש לא
// פוגע בעקביות לאורך מספר קריאות.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('toc-cache-test-');
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

  Future<void> insertLines(int bookId, List<String> contents) async {
    for (int i = 0; i < contents.length; i++) {
      await repository.insertLine(
        Line(id: 0, bookId: bookId, lineIndex: i, content: contents[i]),
      );
    }
  }

  Future<int> insertToc({
    required int bookId,
    required int lineIndex,
    required String text,
    required int level,
    int? parentId,
  }) =>
      repository.insertTocEntry(
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

  /// יוצר ספר בסיסי עם שורות + ערכי TOC ומחזיר את bookId.
  /// מבנה TOC לדוגמה:
  /// level 1: "פרק א" (lineIndex 0)
  /// level 2: "פסוק א" (lineIndex 0, parent=פרק א)
  /// level 2: "פסוק ב" (lineIndex 1, parent=פרק א)
  /// level 1: "פרק ב" (lineIndex 2)
  Future<int> buildSampleBook(String title) async {
    final catId = await createCategory();
    final bookId = await createBook(catId, title);
    await insertLines(bookId, ['l0', 'l1', 'l2', 'l3']);

    final pereqA =
        await insertToc(bookId: bookId, lineIndex: 0, text: 'פרק א', level: 1);
    await insertToc(
        bookId: bookId,
        lineIndex: 0,
        text: 'פסוק א',
        level: 2,
        parentId: pereqA);
    await insertToc(
        bookId: bookId,
        lineIndex: 1,
        text: 'פסוק ב',
        level: 2,
        parentId: pereqA);
    await insertToc(bookId: bookId, lineIndex: 2, text: 'פרק ב', level: 1);

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    return bookId;
  }

  // ── tests ─────────────────────────────────────────────────────────────────

  group('SeforimRepository.getTocEntriesForReference', () {
    test('ללא queryTokens — מחזיר את כל ערכי TOC מסודרים לפי segment',
        () async {
      final bookId = await buildSampleBook('בראשית');

      final results =
          await repository.getTocEntriesForReference(bookId, 'בראשית');

      // 4 ערכים (פרק א, פסוק א, פסוק ב, פרק ב) — level 0 לא מוכנס בכלל.
      expect(results, hasLength(4));
      expect(results.map((r) => r['reference']).toList(), [
        'בראשית פרק א',
        'בראשית פרק א פסוק א',
        'בראשית פרק א פסוק ב',
        'בראשית פרק ב',
      ]);

      // המיון לפי segment (lineIndex).
      expect(results.map((r) => r['segment']).toList(), [0, 0, 1, 2]);
    });

    test('queryTokens מסנן ברמת טוקן שלם (לא substring)', () async {
      final bookId = await buildSampleBook('בראשית');

      // "א" — טוקן שלם — אמור לתפוס "פרק א" ו"פסוק א" אבל לא "פרק ב".
      final results = await repository
          .getTocEntriesForReference(bookId, 'בראשית', queryTokens: ['א']);

      final refs = results.map((r) => r['reference']).toList();
      expect(refs, contains('בראשית פרק א'));
      expect(refs, isNot(contains('בראשית פרק ב')));
    });

    test('סינון רמה רדודה — level 1 ניצח את level 2 כשגם הוא תואם', () async {
      final bookId = await buildSampleBook('בראשית');

      // "א" תואם גם ל-"פרק א" (level 1) וגם ל-"פסוק א" (level 2).
      // הסינון אמור לשמר רק את level 1.
      final results = await repository
          .getTocEntriesForReference(bookId, 'בראשית', queryTokens: ['א']);

      expect(results, hasLength(1));
      expect(results.first['level'], equals(1));
      expect(results.first['reference'], equals('בראשית פרק א'));
    });

    test('ספר ללא TOC מחזיר רשימה ריקה', () async {
      final catId = await createCategory();
      final bookId = await createBook(catId, 'ספר ריק');
      await insertLines(bookId, ['שורה אחת']);
      // לא מוסיפים tocEntry.

      final results =
          await repository.getTocEntriesForReference(bookId, 'ספר ריק');

      expect(results, isEmpty);
    });

    test('queryTokens ריק שווה ערך ל-null — מחזיר את כל הערכים', () async {
      final bookId = await buildSampleBook('בראשית');

      final withNull =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      final withEmpty = await repository
          .getTocEntriesForReference(bookId, 'בראשית', queryTokens: const []);

      expect(withEmpty.length, equals(withNull.length));
    });

    // ── הקאש ────────────────────────────────────────────────────────────────

    test('קריאה חוזרת עם queryTokens שונים מחזירה תוצאות עקביות', () async {
      final bookId = await buildSampleBook('בראשית');

      // קריאה ראשונה — בלי סינון.
      final all = await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(all, hasLength(4));

      // קריאה שנייה — עם סינון. אם הקאש הראשון "צרך" את הנתונים, השנייה
      // אמורה עדיין לעבוד.
      final filtered = await repository
          .getTocEntriesForReference(bookId, 'בראשית', queryTokens: ['ב']);
      // "ב" תופס "פרק ב" (level 1) ו"פסוק ב" (level 2) — אבל min-level שומר רק level 1.
      expect(filtered, hasLength(1));
      expect(filtered.first['reference'], equals('בראשית פרק ב'));

      // קריאה שלישית — חוזרים לבלי סינון. הקאש לא אמור להיות פגום.
      final allAgain =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(allAgain, hasLength(4));
      expect(
        allAgain.map((r) => r['reference']).toList(),
        equals(all.map((r) => r['reference']).toList()),
      );
    });

    test('הקאש לא מערבב בין ספרים שונים (bookId שונה)', () async {
      final bookA = await buildSampleBook('בראשית');
      final bookB = await buildSampleBook('שמות');

      final aResults =
          await repository.getTocEntriesForReference(bookA, 'בראשית');
      final bResults =
          await repository.getTocEntriesForReference(bookB, 'שמות');

      expect(
          aResults
              .every((r) => (r['reference'] as String).startsWith('בראשית')),
          isTrue);
      expect(
          bResults.every((r) => (r['reference'] as String).startsWith('שמות')),
          isTrue);
    });

    test('הקאש משתמש ב-normalizeForFindRefMatch — סינון "א" לא תופס "יא"',
        () async {
      final catId = await createCategory();
      final bookId = await createBook(catId, 'ירמיהו');
      await insertLines(bookId, ['l0', 'l1']);
      await insertToc(bookId: bookId, lineIndex: 0, text: 'פרק יא', level: 1);
      await insertToc(bookId: bookId, lineIndex: 1, text: 'פרק א', level: 1);
      await repository.updateTocEntryLineIdsByLineIndex(bookId);

      final results = await repository
          .getTocEntriesForReference(bookId, 'ירמיהו', queryTokens: ['א']);

      // צריך לקבל רק את "פרק א", לא את "פרק יא".
      expect(results, hasLength(1));
      expect(results.first['reference'], equals('ירמיהו פרק א'));
    });
  });

  // ── invalidation: מוטציות אחרי קריאה ראשונה ──────────────────────────────

  group('SeforimRepository — invalidation של קאש TOC אחרי מוטציה', () {
    test('insertTocEntry מבטל את הקאש של הספר — ערך חדש נראה מיד', () async {
      final bookId = await buildSampleBook('בראשית');

      // קריאה ראשונה — מאחסנת snapshot בקאש.
      final before =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(before, hasLength(4));

      // מוטציה: מוסיפים פרק חדש.
      await insertLines(bookId, ['l4']);
      await insertToc(bookId: bookId, lineIndex: 3, text: 'פרק ג', level: 1);
      await repository.updateTocEntryLineIdsByLineIndex(bookId);

      // קריאה שנייה — הקאש חייב להיות מבוטל.
      final after =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(after, hasLength(5),
          reason: 'הערך החדש חייב להופיע מיד אחרי insertTocEntry');
      expect(
          after.map((r) => r['reference']).toList(), contains('בראשית פרק ג'));
    });

    test('deleteBookTocEntries מבטל את הקאש — תוצאות ריקות אחרי המחיקה',
        () async {
      final bookId = await buildSampleBook('בראשית');

      // קריאה ראשונה — מאחסנת snapshot בקאש.
      final before =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(before, hasLength(4));

      // מוטציה: מוחקים את כל TOC של הספר.
      await repository.deleteBookTocEntries(bookId);

      // קריאה שנייה — אחרי מחיקה, ה-TOC ריק.
      final after =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(after, isEmpty,
          reason: 'אחרי delete אין TOC — הרשימה חייבת להיות ריקה');
    });

    test('clearBookContent (דרך deleteBookTocEntries) מבטל את הקאש', () async {
      final bookId = await buildSampleBook('בראשית');

      final before =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(before, hasLength(4));

      await repository.clearBookContent(bookId);

      final after =
          await repository.getTocEntriesForReference(bookId, 'בראשית');
      expect(after, isEmpty, reason: 'clearBookContent → TOC ריק, אין ערכים');
    });

    test('updateTocEntryLineId מבטל את הקאש — segment חדש מופיע מיד', () async {
      final catId = await createCategory();
      final bookId = await createBook(catId, 'ספר');
      await insertLines(bookId, ['l0', 'l1']);
      final tocId = await insertToc(
          bookId: bookId, lineIndex: 0, text: 'פרק א', level: 1);
      await repository.updateTocEntryLineIdsByLineIndex(bookId);

      // קריאה ראשונה — segment=0 (מתאים ל-lineIndex=0).
      final before = await repository.getTocEntriesForReference(bookId, 'ספר');
      expect(before.first['segment'], equals(0));

      // מוטציה: מעדכנים את ה-lineId של ערך ה-TOC לשורה אחרת (lineIndex=1).
      final db = await database.database;
      final line1Id = db
          .select(
              'SELECT id FROM line WHERE bookId=? AND lineIndex=1', [bookId])
          .toMapList()
          .first['id'] as int;
      await repository.updateTocEntryLineId(tocId, line1Id);

      // קריאה שנייה — segment חייב להתעדכן.
      final after = await repository.getTocEntriesForReference(bookId, 'ספר');
      expect(after.first['segment'], equals(1),
          reason: 'segment חייב לשקף את ה-lineId המעודכן');
    });

    test('updateTocEntryLineIdsByLineIndex מבטל את הקאש של הספר', () async {
      final catId = await createCategory();
      final bookId = await createBook(catId, 'ספר');
      await insertLines(bookId, ['l0', 'l1']);
      await insertToc(bookId: bookId, lineIndex: 0, text: 'פרק א', level: 1);

      // קריאה ראשונה — לפני updateTocEntryLineIdsByLineIndex (אין lineId).
      // כאן segment ייקח את הערך מ-COALESCE(l.lineIndex, t.lineId).
      final before = await repository.getTocEntriesForReference(bookId, 'ספר');
      expect(before, hasLength(1));

      // עכשיו מבצעים את ה-update הגלובלי — חייב לבטל את הקאש.
      await repository.updateTocEntryLineIdsByLineIndex(bookId);

      final after = await repository.getTocEntriesForReference(bookId, 'ספר');
      // עדיין רשומה אחת, אבל הקאש נבנה מחדש (ה-segment עכשיו תואם
      // ל-lineIndex דרך ה-JOIN על line).
      expect(after, hasLength(1));
      expect(after.first['segment'], equals(0));
    });

    // ── חיפוש היררכי ────────────────────────────────────────────────────────

    group('SeforimRepository — חיפוש היררכי', () {
      // buildSampleBook מייצר:
      //   level 1: "פרק א" (lineIndex 0), "פרק ב" (lineIndex 2)
      //   level 2: "פסוק א" (lineIndex 0, parent=פרק א)
      //   level 2: "פסוק ב" (lineIndex 1, parent=פרק א)

      test('שני טוקנים — פרק ופסוק', () async {
        final bookId = await buildSampleBook('בראשית');

        // "א ב" → פרק א, פסוק ב
        final results = await repository.getTocEntriesForReference(
            bookId, 'בראשית',
            queryTokens: ['א', 'ב']);

        expect(results, hasLength(1));
        expect(results.first['reference'], equals('בראשית פרק א פסוק ב'));
        expect(results.first['level'], equals(2));
      });

      test('טוקן חוזר — פרק א פסוק א (לא מחזיר false-positive)', () async {
        final bookId = await buildSampleBook('בראשית');

        // "א א" → פרק א, פסוק א — לא "פרק ב פסוק א" שאינו קיים כאן
        final results = await repository.getTocEntriesForReference(
            bookId, 'בראשית',
            queryTokens: ['א', 'א']);

        expect(results, hasLength(1));
        expect(results.first['reference'], equals('בראשית פרק א פסוק א'));
      });

      test('ירידה לרמה 2 כשרמה 1 לא מכילה את הטוקן', () async {
        final bookId = await buildSampleBook('בראשית');

        // "א פסוק" → רמה 1 "פרק א" → ירידה לילדים; "פסוק" מופיע שם
        final results = await repository.getTocEntriesForReference(
            bookId, 'בראשית',
            queryTokens: ['א', 'פסוק']);

        // שני הפסוקים של פרק א ("פסוק א" ו"פסוק ב") תואמים
        expect(results.map((r) => r['level']).toSet(), equals({2}));
        expect(results.length, greaterThanOrEqualTo(1));
      });

      test('טוקן יחיד מחזיר entry ברמה 1 בלבד', () async {
        final bookId = await buildSampleBook('בראשית');

        final results = await repository
            .getTocEntriesForReference(bookId, 'בראשית', queryTokens: ['א']);

        expect(results, hasLength(1));
        expect(results.first['level'], equals(1));
        expect(results.first['reference'], equals('בראשית פרק א'));
      });

      test('טוקן שאינו קיים כלל — מחזיר רשימה ריקה', () async {
        final bookId = await buildSampleBook('בראשית');

        final results = await repository
            .getTocEntriesForReference(bookId, 'בראשית', queryTokens: ['קלז']);

        expect(results, isEmpty);
      });
    });

    // ── נתיב אבות שלם לרמה 3 ────────────────────────────────────────────────

    group('SeforimRepository — נתיב אבות מלא לרמה 3', () {
      // ספר דוגמה: סימן → סעיף → ס"ק
      Future<int> buildDeepBook(String title) async {
        final catId = await createCategory();
        final bookId = await createBook(catId, title);
        await insertLines(bookId, ['l0', 'l1', 'l2', 'l3', 'l4']);

        // level 1: "סימן יב"
        final simanId = await insertToc(
            bookId: bookId, lineIndex: 0, text: 'סימן יב', level: 1);

        // level 2: "סעיף א" + "סעיף ב" תחת "סימן יב"
        final seifAId = await insertToc(
            bookId: bookId,
            lineIndex: 0,
            text: 'סעיף א',
            level: 2,
            parentId: simanId);
        await insertToc(
            bookId: bookId,
            lineIndex: 2,
            text: 'סעיף ב',
            level: 2,
            parentId: simanId);

        // level 3: "סק א" + "סק ב" + "סק ג" תחת "סעיף א"
        await insertToc(
            bookId: bookId,
            lineIndex: 0,
            text: 'סק א',
            level: 3,
            parentId: seifAId);
        await insertToc(
            bookId: bookId,
            lineIndex: 1,
            text: 'סק ב',
            level: 3,
            parentId: seifAId);
        await insertToc(
            bookId: bookId,
            lineIndex: 2,
            text: 'סק ג',
            level: 3,
            parentId: seifAId);

        await repository.updateTocEntryLineIdsByLineIndex(bookId);
        return bookId;
      }

      test('reference של רמה 3 כולל את כל נתיב האבות', () async {
        final bookId = await buildDeepBook('משנה ברורה');

        final all =
            await repository.getTocEntriesForReference(bookId, 'משנה ברורה');

        final level3Refs =
            all.where((r) => r['level'] == 3).map((r) => r['reference']);
        expect(level3Refs, contains('משנה ברורה סימן יב סעיף א סק ג'));
      });

      test('חיפוש ["יב", "סק", "ג"] מגיע ל-ס"ק ג דרך דילוג על סעיף', () async {
        final bookId = await buildDeepBook('משנה ברורה');

        final results = await repository.getTocEntriesForReference(
            bookId, 'משנה ברורה',
            queryTokens: ['יב', 'סק', 'ג']);

        expect(results, hasLength(1));
        expect(results.first['reference'],
            equals('משנה ברורה סימן יב סעיף א סק ג'));
        expect(results.first['level'], equals(3));
      });

      test('חיפוש ["יב", "ב"] מוצא סעיף ב ישירות', () async {
        final bookId = await buildDeepBook('משנה ברורה');

        final results = await repository.getTocEntriesForReference(
            bookId, 'משנה ברורה',
            queryTokens: ['יב', 'ב']);

        expect(results, hasLength(1));
        expect(results.first['reference'], equals('משנה ברורה סימן יב סעיף ב'));
        expect(results.first['level'], equals(2));
      });
    });

    // ── טרנספוזיציה של אותיות עבריות ────────────────────────────────────────

    group('SeforimRepository — טרנספוזיציה עברית', () {
      Future<int> buildTractateBook(String title) async {
        final catId = await createCategory();
        final bookId = await createBook(catId, title);
        await insertLines(bookId, List.generate(80, (i) => 'l$i'));

        // דפים: לט (39) ו-מ (40)
        await insertToc(bookId: bookId, lineIndex: 38, text: 'דף לט', level: 1);
        await insertToc(bookId: bookId, lineIndex: 40, text: 'דף מ', level: 1);

        await repository.updateTocEntryLineIdsByLineIndex(bookId);
        return bookId;
      }

      test('חיפוש "לט" מוצא "דף לט" ישירות', () async {
        final bookId = await buildTractateBook('שבת');

        final results = await repository
            .getTocEntriesForReference(bookId, 'שבת', queryTokens: ['לט']);

        expect(results, hasLength(1));
        expect(results.first['reference'], equals('שבת דף לט'));
      });

      test('חיפוש "טל" (טרנספוזיציה של לט) מוצא "דף לט"', () async {
        final bookId = await buildTractateBook('שבת');

        final results = await repository
            .getTocEntriesForReference(bookId, 'שבת', queryTokens: ['טל']);

        expect(results, hasLength(1),
            reason: '"טל" הוא טרנספוזיציה של "לט" — חייב למצוא את הדף');
        expect(results.first['reference'], equals('שבת דף לט'));
      });
    });

    test('הקאש מבוטל לספר ספציפי בלבד — שאר הספרים נשארים cached', () async {
      final bookA = await buildSampleBook('בראשית');
      final bookB = await buildSampleBook('שמות');

      // אחסון בקאש לשני הספרים.
      final aBefore =
          await repository.getTocEntriesForReference(bookA, 'בראשית');
      final bBefore = await repository.getTocEntriesForReference(bookB, 'שמות');
      expect(aBefore, hasLength(4));
      expect(bBefore, hasLength(4));

      // מוטציה רק ב-bookA.
      await repository.deleteBookTocEntries(bookA);

      // bookA — אחרי delete, TOC ריק (cache invalidated).
      final aAfter =
          await repository.getTocEntriesForReference(bookA, 'בראשית');
      expect(aAfter, isEmpty);

      // bookB — נשאר זהה (לא הושפע).
      final bAfter = await repository.getTocEntriesForReference(bookB, 'שמות');
      expect(bAfter, hasLength(4));
      expect(bAfter.map((r) => r['reference']).toList(),
          equals(bBefore.map((r) => r['reference']).toList()));
    });
  });

  // ── Fallback שטוח לכותרת עמוקה כשאין alt_toc ("הזוהר המתורגם דף לו") ────────
  group('SeforimRepository — fallback שטוח ל-TOC עמוק בלי alt_toc', () {
    // מבנה זהה ל"הזוהר המתורגם": ספר(L1) → פרשה(L2) → דף(L3), ללא alt_toc.
    Future<int> buildBuriedDafBook(String title) async {
      final catId = await createCategory();
      final bookId = await createBook(catId, title);
      await insertLines(bookId, ['l0', 'l1', 'l2', 'l3']);

      final bookNode =
          await insertToc(bookId: bookId, lineIndex: 0, text: title, level: 1);
      final parsha = await insertToc(
          bookId: bookId,
          lineIndex: 0,
          text: 'פרשת בראשית',
          level: 2,
          parentId: bookNode);
      await insertToc(
          bookId: bookId,
          lineIndex: 1,
          text: 'דף לו עמוד א',
          level: 3,
          parentId: parsha);
      await insertToc(
          bookId: bookId,
          lineIndex: 2,
          text: 'דף לז עמוד א',
          level: 3,
          parentId: parsha);

      await repository.updateTocEntryLineIdsByLineIndex(bookId);
      return bookId;
    }

    test('טוקן בודד "לו" מגיע ל"דף לו" העמוק כש-alt_toc חסר', () async {
      final bookId = await buildBuriedDafBook('הזוהר המתורגם בראשית');

      final results = await repository.getTocEntriesForReference(
          bookId, 'הזוהר המתורגם בראשית',
          queryTokens: ['לו']);

      // רק "דף לו" — ולא "דף לז" — מאשר שאין הצפה (ההגנה: הטוקן בעלה).
      expect(results, hasLength(1));
      expect(results.first['reference'], contains('דף לו עמוד א'));
      expect(results.first['reference'], isNot(contains('דף לז')));
      expect(results.first['level'], equals(3));
    });

    test('כש-ההיררכי מצליח ה-fallback לא נכנס — אין הזרקת "דף" מיותרת',
        () async {
      final bookId = await buildBuriedDafBook('הזוהר המתורגם בראשית');

      // "בראשית" תואם היררכית את צומת הספר (L1) → ההיררכי מחזיר אותו וה-fallback
      // נדלג. אסור שיופיעו ערכי ה"דף" העמוקים.
      final results = await repository.getTocEntriesForReference(
          bookId, 'הזוהר המתורגם בראשית',
          queryTokens: ['בראשית']);

      expect(results, hasLength(1));
      expect(results.first['level'], equals(1));
      expect(
        results.every((r) => !(r['reference'] as String).contains('דף')),
        isTrue,
      );
    });
  });
}
