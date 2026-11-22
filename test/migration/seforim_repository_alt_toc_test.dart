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

  group('AltToc פר-ספר מתוך הקאש הגלובלי', () {
    Future<void> attachGlobalIndex() async {
      final build = repository.beginAltTocFlatIndex();
      while (!await build.step()) {}
      repository.attachAltTocIndex(build.index);
    }

    const queries = [
      ['הלכות', 'הלואה'],
      ['ציצית'],
      ['חושן'],
      ['חושן', 'משפט', 'הלכות', 'דיינים'],
    ];

    test('מחזיר בדיוק את מה שהבנייה הפר-ספר מחזירה', () async {
      final bookId = await buildTurWithAltToc();
      final perBook = [
        for (final q in queries)
          await repository.getAltTocEntriesForReference(
            bookId,
            'טור',
            queryTokens: q,
          ),
      ];

      await attachGlobalIndex();

      for (var i = 0; i < queries.length; i++) {
        expect(
          await repository.getAltTocEntriesForReference(
            bookId,
            'טור',
            queryTokens: queries[i],
          ),
          perBook[i],
          reason: '${queries[i]}',
        );
      }
    });

    test('אחרי החיבור הספר נקרא מהקאש ולא מהמסד', () async {
      final bookId = await buildTurWithAltToc();
      await attachGlobalIndex();

      final db = await database.database;
      db.execute("INSERT INTO tocText (text) VALUES ('הלכות שבת')");
      db.execute(
        'INSERT INTO alt_toc_entry (structureId, parentId, textId, level) '
        'SELECT id, NULL, ?, 0 FROM alt_toc_structure LIMIT 1',
        [db.lastInsertRowId],
      );

      expect(
        await repository.getAltTocEntriesForReference(
          bookId,
          'טור',
          queryTokens: const ['שבת'],
        ),
        isEmpty,
      );
    });
  });

  // issue #5748 — "טור או"ח שח ו": לטור אין כינוי "טור אורח חיים", והחלק מגיע
  // בראשי תיבות.
  group('ראשי תיבות של החלק בסעיפי השולחן ערוך שבטור', () {
    Future<int> buildTurSeifim() async {
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
      db.execute(
        'INSERT INTO alt_toc_structure (bookId, key, title) '
        "VALUES (?, 'ShulchanArukhSeifim', 'סעיפי שולחן ערוך')",
        [bookId],
      );
      final structureId = db.lastInsertRowId;
      int? add(String text, int level, int? parentId) {
        db.execute('INSERT OR IGNORE INTO tocText (text) VALUES (?)', [text]);
        final textId = db.select('SELECT id FROM tocText WHERE text = ?', [
          text,
        ]).single['id'];
        db.execute(
          'INSERT INTO alt_toc_entry (structureId, parentId, textId, level) '
          'VALUES (?, ?, ?, ?)',
          [structureId, parentId, textId, level],
        );
        return db.lastInsertRowId;
      }

      for (final part in ['אורח חיים', 'חושן משפט']) {
        final root = add(part, 0, null);
        add('סעיף ו', 2, add('סימן שח', 1, root));
        add('סעיף א', 2, add('סימן א', 1, root));
        add('סעיף א', 2, add('סימן ב', 1, root));
      }
      return bookId;
    }

    Future<List<Object?>> references(int bookId, List<String> tokens) async =>
        (await repository.getAltTocEntriesForReference(
          bookId,
          'טור',
          queryTokens: tokens,
        )).map((r) => r['reference']).toList();

    for (final withIndex in [false, true]) {
      test(withIndex ? 'מהקאש הגלובלי' : 'מהבנייה הפר-ספר', () async {
        final bookId = await buildTurSeifim();
        if (withIndex) {
          final build = repository.beginAltTocFlatIndex();
          while (!await build.step()) {}
          repository.attachAltTocIndex(build.index);
        }

        expect(await references(bookId, ['אוח', 'שח', 'ו']), [
          'אורח חיים סימן שח סעיף ו',
        ]);
        expect(await references(bookId, ['שח', 'ו']), hasLength(2));
        for (final tokens in [
          ['אוח', 'א', 'א'],
          ['אוח', 'סימן', 'א', 'סעיף', 'א'],
          ['אורח', 'חיים', 'א', 'א'],
        ]) {
          expect(await references(bookId, tokens), [
            'אורח חיים סימן א סעיף א',
          ]);
        }
      });
    }
  });
}
