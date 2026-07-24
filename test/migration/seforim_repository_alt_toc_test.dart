// בדיקות ל-SeforimRepository.getAltTocEntriesForReference — החיפוש ה**שטוח**
// בכותרות-המשנה (AltToc).
//
// רקע: כותרות-המשנה ב"טור" יושבות תחת שם החלק ("חושן משפט" → "הלכות הלואה").
// שם החלק נבלע לרוב בזיהוי שם הספר, ולכן חיפוש היררכי משורש החלק לא היה מגיע
// לכותרות-המשנה. החיפוש השטוח מאתר ערך לפי כל טוקני השאילתה בנתיב המלא, עם
// תנאי "הטוקן האחרון בעלה" שמונע הצפה.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('alt-toc-test-');
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

  /// בונה ספר "טור" עם מבנה AltToc דו-רמתי:
  ///   חלק "חושן משפט" → "הלכות הלואה", "הלכות דיינים"
  ///   חלק "אורח חיים" → "הלכות ציצית"
  /// מחזיר את bookId.
  Future<int> buildTurWithAltToc() async {
    final catId = await repository.insertCategory(
      const Category(title: 'הלכה', parentId: null, level: 0),
    );
    final bookId = await repository.insertExternalContentBook(
      categoryId: catId,
      title: 'טור',
      filePath: '/tmp/tur.txt',
      fileType: 'txt',
      fileSize: 0,
      lastModified: 0,
      isPersonal: false,
    );

    final db = await database.database;

    Future<int> tocText(String text) async {
      db.execute('INSERT INTO tocText (text) VALUES (?)', [text]);
      return db.lastInsertRowId;
    }

    db.execute(
      "INSERT INTO alt_toc_structure (bookId, key, title) VALUES (?, 'Tur', 'Tur')",
      [bookId],
    );
    final structureId = db.lastInsertRowId;

    Future<int> altEntry({
      required int textId,
      required int level,
      int? parentId,
    }) async {
      db.execute(
        'INSERT INTO alt_toc_entry (structureId, parentId, textId, level) '
        'VALUES (?, ?, ?, ?)',
        [structureId, parentId, textId, level],
      );
      return db.lastInsertRowId;
    }

    final hoshen = await altEntry(textId: await tocText('חושן משפט'), level: 0);
    final orach = await altEntry(textId: await tocText('אורח חיים'), level: 0);
    await altEntry(
      textId: await tocText('הלכות הלואה'),
      level: 1,
      parentId: hoshen,
    );
    await altEntry(
      textId: await tocText('הלכות דיינים'),
      level: 1,
      parentId: hoshen,
    );
    await altEntry(
      textId: await tocText('הלכות ציצית'),
      level: 1,
      parentId: orach,
    );

    return bookId;
  }

  group('SeforimRepository.getAltTocEntriesForReference (flat)', () {
    test('כותרת-משנה נמצאת גם בלי שם החלק — "הלכות הלואה"', () async {
      final bookId = await buildTurWithAltToc();

      final results = await repository.getAltTocEntriesForReference(
        bookId,
        'טור',
        queryTokens: const ['הלכות', 'הלואה'],
      );

      expect(
        results.map((r) => r['reference']),
        equals(['חושן משפט הלכות הלואה']),
      );
    });

    test('מילה ייחודית של כותרת-המשנה לבדה — "ציצית"', () async {
      final bookId = await buildTurWithAltToc();

      final results = await repository.getAltTocEntriesForReference(
        bookId,
        'טור',
        queryTokens: const ['ציצית'],
      );

      expect(
        results.map((r) => r['reference']),
        equals(['אורח חיים הלכות ציצית']),
      );
    });

    test(
      'אנטי-הצפה: שם החלק לבדו מחזיר את החלק, לא את כל הכותרות שתחתיו',
      () async {
        final bookId = await buildTurWithAltToc();

        final results = await repository.getAltTocEntriesForReference(
          bookId,
          'טור',
          queryTokens: const ['חושן'],
        );

        // רק החלק "חושן משפט" — לא "הלכות הלואה"/"הלכות דיינים" שתחתיו.
        expect(results.map((r) => r['reference']), equals(['חושן משפט']));
      },
    );

    test('שאילתה רב-מילתית מלאה (חלק + כותרת) — מאותרת', () async {
      final bookId = await buildTurWithAltToc();

      final results = await repository.getAltTocEntriesForReference(
        bookId,
        'טור',
        queryTokens: const ['חושן', 'משפט', 'הלכות', 'דיינים'],
      );

      expect(
        results.map((r) => r['reference']),
        equals(['חושן משפט הלכות דיינים']),
      );
    });

    test('queryTokens ריק/null מחזיר ריק', () async {
      final bookId = await buildTurWithAltToc();

      expect(
        await repository.getAltTocEntriesForReference(bookId, 'טור'),
        isEmpty,
      );
      expect(
        await repository.getAltTocEntriesForReference(
          bookId,
          'טור',
          queryTokens: const [],
        ),
        isEmpty,
      );
    });
  });
}
