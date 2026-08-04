// Regression tests for SeforimRepository.rebuildLineTocForBook.
//
// Core behaviors under test:
//  1. ספר שמתחיל בשורה ריקה לפני h1 — rebuildLineTocForBook לא קורס.
//  2. שורות לפני heading ראשון לא נמצאות ב-line_toc.
//  3. שורות מאחרי heading ראשון ממופות ל-tocEntry הנכון.
//  4. ספר שמתחיל ישירות ב-h1 — כל שורה נמצאת ב-line_toc.
//  5. ספר עם מספר headings — כל שורה ממופה ל-heading האחרון שקדם לה.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rebuild-line-toc-test-');
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

  /// יוצר ספר ומחזיר את ה-bookId שלו.
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

  /// מוסיף רשימת שורות לספר (תוכן — content — הוא סמן בלבד לבדיקה).
  Future<void> insertLines(int bookId, List<String> contents) async {
    for (int i = 0; i < contents.length; i++) {
      await repository.insertLine(
        Line(id: 0, bookId: bookId, lineIndex: i, content: contents[i]),
      );
    }
  }

  /// מוסיף tocEntry ומחזיר את ה-id שלו.
  Future<int> insertToc(int bookId, int lineIndex) => repository.insertTocEntry(
    TocEntry(
      id: 0,
      bookId: bookId,
      parentId: null,
      text: 'פרק $lineIndex',
      level: 1,
      lineIndex: lineIndex,
      lineId: null,
      isLastChild: true,
      hasChildren: false,
    ),
  );

  /// מחזיר כמה שורות ממופות ב-line_toc לספר נתון.
  Future<List<Map<String, Object?>>> getLineTocRows(int bookId) async {
    final db = await database.database;
    return db
        .select(
          '''SELECT lt.lineId, lt.tocEntryId
         FROM line_toc lt
         JOIN line l ON l.id = lt.lineId
         WHERE l.bookId = ?
         ORDER BY l.lineIndex''',
          [bookId],
        )
        .toMapList();
  }

  // ── tests ─────────────────────────────────────────────────────────────────

  test('1. ספר עם שורה ריקה לפני h1 — rebuildLineTocForBook לא קורס', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 1');

    // index 0 = שורה ריקה לפני heading ראשון
    // index 1 = h1 (heading)
    // index 2 = תוכן
    await insertLines(bookId, ['', '<h1>פרק א</h1>', 'תוכן']);
    await insertToc(bookId, 1); // heading בשורה 1

    await repository.updateTocEntryLineIdsByLineIndex(bookId);

    // await ישיר — אם הקריאה תזרוק, הטסט ייכשל טבעית.
    // returnsNormally לא מחכה ל-Future הפנימי ולכן לא מזהה קריסה אסינכרונית.
    await repository.rebuildLineTocForBook(bookId);
  });

  test('2. שורות לפני heading ראשון לא נמצאות ב-line_toc', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 2');

    await insertLines(bookId, ['שורה ריקה', '<h1>פרק א</h1>', 'תוכן']);
    await insertToc(bookId, 1);

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    await repository.rebuildLineTocForBook(bookId);

    final rows = await getLineTocRows(bookId);
    // שורה 0 (לפני heading) — לא אמורה להופיע
    final lineIds = rows.map((r) => r['lineId']).toSet();
    final db = await database.database;
    final line0Id = db
        .select('SELECT id FROM line WHERE bookId=? AND lineIndex=0', [bookId])
        .toMapList()
        .first['id'];
    expect(
      lineIds,
      isNot(contains(line0Id)),
      reason: 'שורה לפני heading ראשון לא אמורה להיות ב-line_toc',
    );
  });

  test('3. שורות מאחרי heading ממופות ל-tocEntry הנכון', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 3');

    await insertLines(bookId, ['פתיח', '<h1>פרק א</h1>', 'תוכן א']);
    final tocId = await insertToc(bookId, 1);

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    await repository.rebuildLineTocForBook(bookId);

    final rows = await getLineTocRows(bookId);
    // שורות 1 ו-2 אמורות להיות ממופות ל-tocEntry שיצרנו
    expect(rows, hasLength(2), reason: '2 שורות (heading + תוכן) ב-line_toc');
    for (final row in rows) {
      expect(row['tocEntryId'], equals(tocId));
    }
  });

  test('4. ספר שמתחיל ב-h1 — כל שורה קיימת ב-line_toc', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 4');

    await insertLines(bookId, ['<h1>פרק א</h1>', 'שורה 1', 'שורה 2']);
    await insertToc(bookId, 0); // heading בשורה 0

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    await repository.rebuildLineTocForBook(bookId);

    final rows = await getLineTocRows(bookId);
    expect(rows, hasLength(3), reason: 'כל 3 שורות אמורות להיות ב-line_toc');
  });

  test('5. מספר headings — כל שורה ממופה ל-heading האחרון שקדם לה', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 5');

    // line 0: h1, line 1: תוכן, line 2: h2, line 3: תוכן
    await insertLines(bookId, [
      '<h1>פרק א</h1>',
      'תוכן א',
      '<h1>פרק ב</h1>',
      'תוכן ב',
    ]);
    final toc1 = await insertToc(bookId, 0);
    final toc2 = await insertToc(bookId, 2);

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    await repository.rebuildLineTocForBook(bookId);

    final rows = await getLineTocRows(bookId);
    expect(rows, hasLength(4));

    // שורות 0+1 → toc1, שורות 2+3 → toc2
    expect(rows[0]['tocEntryId'], equals(toc1));
    expect(rows[1]['tocEntryId'], equals(toc1));
    expect(rows[2]['tocEntryId'], equals(toc2));
    expect(rows[3]['tocEntryId'], equals(toc2));
  });
  test('6. כותרות באותה שורה מוכרעות דטרמיניסטית לטובת העמוקה', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 6');
    await insertLines(bookId, ['<h1>פרק</h1>', 'תוכן']);

    final shallowId = await insertToc(bookId, 0);
    final deepId = await repository.insertTocEntry(
      TocEntry(
        id: 0,
        bookId: bookId,
        parentId: shallowId,
        text: 'סעיף',
        level: 2,
        lineIndex: 0,
        lineId: null,
        isLastChild: true,
        hasChildren: false,
      ),
    );

    await repository.updateTocEntryLineIdsByLineIndex(bookId);
    await repository.rebuildLineTocForBook(bookId);

    final rows = await getLineTocRows(bookId);
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['tocEntryId']), everyElement(deepId));
  });

  test('7. parent מקומי חסר מבטל את טרנזקציית הכנסת ה-TOC', () async {
    final catId = await createCategory();
    final bookId = await createBook(catId, 'ספר 7');

    await expectLater(
      repository.insertGeneratedTocEntries(bookId, [
        TocEntry(
          id: 1,
          bookId: bookId,
          parentId: 999,
          text: 'ילד יתום',
          level: 2,
          lineIndex: 0,
          lineId: null,
          isLastChild: false,
          hasChildren: false,
        ),
      ]),
      throwsA(isA<StateError>()),
    );

    final db = await database.database;
    final count = db
        .select(
          'SELECT COUNT(*) AS count FROM tocEntry WHERE bookId = ?',
          [bookId],
        )
        .toMapList()
        .single['count'];
    expect(count, 0);
  });
}
