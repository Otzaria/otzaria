import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:path/path.dart' as path;

/// הקאש הגלובלי של ה-AltToc: מה שנגזר מהשרשרת זהה למה שנגזר מהנתיב המלא,
/// וההתאמה המהירה זהה ל-[altTocFlatMatches] על כל ערך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> tokensOf(String reference) => normalizeForFindRefMatch(
    reference,
  ).split(' ').where((t) => t.isNotEmpty).toList();

  String? dafNumberIn(List<String> tokens) {
    final at = tokens.lastIndexOf('דף');
    return at >= 0 && at + 1 < tokens.length ? tokens[at + 1] : null;
  }

  const queries = [
    ['סעיף', 'א'],
    ['סעיף'],
    ['פרק', 'א'],
    ['דף', 'יב'],
    ['דף', 'יב', 'א'],
    ['דף', 'יב', 'ב'],
    ['פרק', 'דף', 'יב'],
    ['שבת', 'דף', 'ג'],
    ['הלכות', 'שבת'],
    ['ספר', 'א', 'סימן'],
    ['ג'],
    ['אין', 'כזה'],
    // כתיב מלא, ומילים משם הספר המארח.
    ['הילכות', 'שבת'],
    ['חידושי', 'הרן', 'פסחים', 'ב', 'ב'],
    ['חידושי', 'הרן', 'פסחים', 'ב', 'א'],
    ['רבינו', 'דוד', 'פסחים', 'ב', 'ב'],
    ['חידושי', 'הרן', 'ב', 'ב'],
    ['חידושי', 'הרן', 'פסחים', 'עא'],
    ['סעיף', 'א', 'שבת'],
    ['סעיף', 'שבת'],
    ['פרק', 'דף', 'יב', 'ספר', 'א'],
    ['סימנ', 'חמש', 'ספר'],
    ['סימן', 'חמש', 'ספר', 'חמש'],
  ];

  /// [altTocFlatMatches] על כל ערך, עם שם הספר המארח והכתיב החלופי.
  List<int> bruteForce(AltTocFlatIndex index, List<String> q, {int? max}) {
    final dafCitation = parseDafCitationFromDafToken(q);
    return altTocFlatMatchesAll((variants) {
      final hostWords = <String, Set<String>>{};
      return [
        for (var i = 0; i < index.length; i++)
          if (altTocFlatMatches(
            index.refTokensOf(i),
            q,
            maxRefTokens: max,
            dafCitation: dafCitation,
            hostTitleWords: hostWords.putIfAbsent(
              index.bookOf(i).title,
              () => altTocHostTitleWords(
                q,
                tokensOf(index.bookOf(i).title),
                variants: variants,
              ),
            ),
            variants: variants,
          ))
            i,
      ];
    });
  }

  void expectConsistent(AltTocFlatIndex index) {
    final references = AltTocQualifiedReferences(index);
    for (var i = 0; i < index.length; i++) {
      final reference = index.referenceOf(i);
      final tokens = index.refTokensOf(i);
      expect(tokens, tokensOf(reference), reason: reference);
      expect(index.refTokenCountOf(i), tokens.length);
      expect(index.refMasks[i], altTocTokenMask(tokens));
      expect(index.dafNumberOf(i), dafNumberIn(tokens), reason: reference);
      expect(
        references.of(i),
        qualifyAltTocReference(index.bookOf(i).title, reference),
      );
    }
    for (final q in queries) {
      for (final max in [null, 2]) {
        expect(
          matchAltTocFlatIndex(index, q, maxRefTokens: max),
          bruteForce(index, q, max: max),
          reason: '$q max=$max',
        );
      }
    }
  }

  group('קאש קטן', () {
    late Directory tempDir;
    late MyDatabase database;
    late SeforimRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('alt-toc-index-');
      database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
      repository = SeforimRepository(database);
      await repository.ensureInitialized();
    });

    tearDown(() async {
      database.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<AltTocFlatIndex> build({int chunk = 2}) async {
      final build = repository.beginAltTocFlatIndex(
        rowsPerStep: chunk,
        textsPerStep: chunk,
        linesPerStep: chunk,
      );
      while (!await build.step()) {}
      return build.index;
    }

    /// שלושה ספרים: טקסט ריק באמצע שרשרת, "דף" שהמספר שלו אצל הילד, טקסט
    /// שמתחיל בשם הספר, הורה חסר, הורה שמזהה גדול משל הילד ושורה חסרה.
    Future<List<int>> seed() async {
      final categoryId = await repository.insertCategory(
        const Category(title: 'קטגוריה', parentId: null, level: 0),
      );
      Future<int> book(String title) => repository.insertExternalContentBook(
        categoryId: categoryId,
        title: title,
        filePath: '/tmp/$title.txt',
        fileType: 'txt',
        fileSize: 0,
        lastModified: 0,
        isPersonal: false,
      );
      final a = await book('ספר א');
      final b = await book('שבת');
      final c = await book('ספר חמש');
      final lines = [
        for (var i = 0; i < 10; i++)
          await repository.insertLine(
            Line(id: 0, bookId: a, lineIndex: i, content: 'שורה $i'),
          ),
      ];
      final db = await database.database;
      db.execute(
        "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, ?, 'a')",
        [a],
      );
      db.execute(
        "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (2, ?, 'b')",
        [b],
      );
      db.execute(
        "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (3, ?, 'c')",
        [c],
      );
      var textId = 100;
      void entry(
        int id,
        int structure,
        String text,
        int level, {
        int? parent,
        int? line,
      }) {
        db.execute('INSERT OR IGNORE INTO tocText (id, text) VALUES (?, ?)', [
          ++textId,
          text,
        ]);
        final stored = db.select('SELECT id FROM tocText WHERE text = ?', [
          text,
        ]).first['id'];
        db.execute(
          'INSERT INTO alt_toc_entry '
          '(id, structureId, parentId, textId, level, lineId) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [id, structure, parent, stored, level, line],
        );
      }

      entry(1, 1, 'פרק א', 0, line: lines[2]);
      entry(2, 1, 'דף', 1, parent: 1);
      entry(3, 1, 'יב.', 2, parent: 2, line: lines[5]);
      entry(4, 1, 'יב:', 2, parent: 2, line: lines[6]);
      entry(5, 1, '', 1, parent: 1);
      entry(6, 1, 'סעיף ב', 2, parent: 5, line: lines[7]);
      entry(7, 1, 'ספר א סימן ג', 0, line: lines[1]);
      entry(8, 1, 'סעיף א', 1, parent: 7, line: lines[3]);
      entry(9, 1, 'הלכות שבת', 1, parent: 9999);
      entry(10, 1, 'סעיף א', 1, parent: 12, line: lines[8]);
      entry(12, 1, 'פרק ב דף יב', 0, line: 99999);
      entry(13, 2, 'דף ג', 0);
      entry(14, 2, 'א', 1, parent: 13);
      entry(15, 2, 'סעיף א', 1, parent: 13);
      // נתיב הורה קצר משם הספר: צירוף השם תלוי בטקסט של כל ילד.
      entry(20, 3, 'ספר', 0);
      entry(21, 3, 'חמש', 1, parent: 20);
      entry(22, 3, 'סימן', 1, parent: 20);
      entry(23, 3, 'חמשה', 1, parent: 20);
      entry(24, 3, 'חמש סימן', 1, parent: 20);
      return lines;
    }

    test('הנגזרות מהשרשרת זהות לנגזרות מהנתיב, וההתאמה זהה', () async {
      await seed();
      final index = await build();
      expect(index.length, 19);
      expectConsistent(index);

      final byId = {
        for (var i = 0; i < index.length; i++)
          index.flatRowOf(i)['reference']: i,
      };
      // הנתיב של ערך תחת טקסט ריק נשמר כפי שהיה — עם רווח כפול.
      expect(byId.containsKey('פרק א  סעיף ב'), isTrue);
      expect(index.parentOf(byId['הלכות שבת']!), -1);
      expect(index.referenceOf(byId['פרק ב דף יב סעיף א']!), isNotEmpty);
      expect(index.segmentOf(byId['פרק א דף יב.']!), 5);
      expect(index.segmentOf(byId['פרק ב דף יב']!), 0);
      expect(index.dafNumberOf(byId['פרק א דף יב.']!), 'יב');
      expect(index.dafNumberOf(byId['פרק א דף']!), isNull);

      List<String> matched(List<String> query) => [
        for (final i in matchAltTocFlatIndex(index, query))
          index.referenceOf(i),
      ];
      expect(matched(['הילכות', 'שבת']), ['הלכות שבת']);
      // "שבת" משם הספר, כשהערך עצמו מכסה שתי מילים.
      expect(matched(['סעיף', 'א', 'שבת']), ['דף ג סעיף א']);
      expect(matched(['סעיף', 'שבת']), isEmpty);
      expect(
        matchAltTocFlatIndex(index, ['סעיף', 'א', 'שבת'], maxRefTokens: 9),
        isEmpty,
      );
    });

    test('התאמת אבות נשמרת בין אחים גם כשההורה מופיע אחריהם', () async {
      await seed();
      final db = await database.database;
      final longQuery = [for (var i = 0; i < 31; i++) 'מבחן$i'];
      for (final (id, parent, text, level) in [
        (200, 204, 'שבת ראשונה', 2),
        (201, 204, 'כותרת אחרת', 2),
        (202, 203, 'שבת שניה', 1),
        (203, null, 'הלכות', 0),
        (204, 206, 'הלכות', 1),
        (205, 204, 'שבת שלישית', 2),
        (206, null, 'שורש', 0),
        (207, null, longQuery.take(29).join(' '), 0),
        (208, 207, longQuery[29], 1),
        (209, 208, longQuery[30], 2),
      ]) {
        db.execute('INSERT OR IGNORE INTO tocText (id, text) VALUES (?, ?)', [
          id,
          text,
        ]);
        db.execute(
          'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level) '
          'VALUES (?, 1, ?, (SELECT id FROM tocText WHERE text = ?), ?)',
          [id, parent, text, level],
        );
      }
      final index = await build();
      const query = ['שורש', 'הלכות', 'שבת'];
      expect(
        [
          for (final i in matchAltTocFlatIndex(index, query))
            index.referenceOf(i),
        ],
        ['שורש הלכות שבת ראשונה', 'שורש הלכות שבת שלישית'],
      );
      for (final query in [longQuery.take(30).toList(), longQuery]) {
        final result = matchAltTocFlatIndex(index, query);
        expect(result, bruteForce(index, query));
        expect(result, hasLength(query.length == 30 ? 2 : 1));
      }
    });

    test('חיפוש קומפקטי שומר סדר אחרי פינוי LRU וביטול חיצוני', () async {
      final lines = await seed();
      final db = await database.database;
      final textId = db
          .select("SELECT id FROM tocText WHERE text = 'פרק א'")
          .first['id'];
      final otherTextId = db
          .select("SELECT id FROM tocText WHERE text = 'הלכות שבת'")
          .first['id'];
      for (var structure = 1; structure <= 3; structure++) {
        db.execute(
          'WITH RECURSIVE numbers(n) AS (SELECT 0 UNION ALL '
          'SELECT n + 1 FROM numbers WHERE n < 17999) '
          'INSERT INTO alt_toc_entry (id, structureId, textId, level, lineId) '
          'SELECT ? + n, ?, CASE WHEN n % 2 = 0 THEN ? ELSE ? END, n % 3, ? FROM numbers',
          [
            structure * 100000,
            structure,
            textId,
            otherTextId,
            structure == 1 ? lines[2] : null,
          ],
        );
      }
      db.execute("INSERT INTO tocText(text) VALUES ('מבוא')");
      final intro = db.lastInsertRowId;
      final firstBook = db
          .select('SELECT bookId FROM alt_toc_structure WHERE id = 1')
          .first['bookId'];
      db.execute(
        'INSERT INTO tocEntry (bookId, textId, level, lineId, lineIndex) VALUES (?, ?, 0, ?, 0)',
        [firstBook, intro, lines[0]],
      );
      final index = await build(chunk: 5000);
      final books = {
        for (var i = 0; i < index.length; i++)
          index.bookOf(i).id: index.bookOf(i),
      };
      final expected = <int, List<Map<String, dynamic>>>{};
      for (final book in books.values) {
        expected[book.id] = await repository.getAltTocEntriesForReference(
          book.id,
          book.title,
          queryTokens: ['פרק'],
        );
      }
      expect(repository.debugAltTocCacheEntryCount, lessThanOrEqualTo(50000));
      expect(repository.debugAltTocCachedBookIds, books.keys.skip(1));
      final first = books.values.first;
      expect(
        await repository.getAltTocEntriesForReference(
          first.id,
          first.title,
          queryTokens: ['פרק'],
        ),
        expected[first.id],
      );
      expect(repository.debugAltTocCachedBookIds, [books.keys.last, first.id]);

      await repository.invalidateTocCacheIfChangedExternally();
      repository.attachAltTocIndex(index);
      for (final book in books.values) {
        expect(
          await repository.getAltTocEntriesForReference(
            book.id,
            book.title,
            queryTokens: ['איןכזהטוקן'],
          ),
          isEmpty,
        );
      }
      expect(index.debugSortedBookCount, 0);
      final oracle = SeforimRepository(database);
      for (var repeat = 0; repeat < 2; repeat++) {
        for (final book in books.values) {
          expect(
            await repository.getAltTocEntriesForReference(
              book.id,
              book.title,
              queryTokens: ['פרק'],
            ),
            expected[book.id],
          );
          for (final query in queries) {
            expect(
              await repository.getAltTocEntriesForReference(
                book.id,
                book.title,
                queryTokens: query,
              ),
              await oracle.getAltTocEntriesForReference(
                book.id,
                book.title,
                queryTokens: query,
              ),
            );
          }
          expect(
            await repository.getTocEntriesForReference(
              book.id,
              book.title,
              queryTokens: ['דף', 'יב'],
            ),
            isEmpty,
          );
        }
      }
      expect(repository.debugAltTocCacheEntryCount, 0);
      expect(repository.debugAltTocCachedBookIds, isEmpty);
      expect(index.debugSortedBookCount, books.length);

      final external = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
      addTearDown(external.close);
      (await external.database).execute(
        "UPDATE tocText SET text = 'פרק חדש' WHERE id = ?",
        [textId],
      );
      await repository.invalidateTocCacheIfChangedExternally();
      final fresh = SeforimRepository(database);
      expect(
        await repository.getAltTocEntriesForReference(
          first.id,
          first.title,
          queryTokens: ['חדש'],
        ),
        await fresh.getAltTocEntriesForReference(
          first.id,
          first.title,
          queryTokens: ['חדש'],
        ),
      );
      expect(repository.debugAltTocCacheEntryCount, greaterThan(0));
    });

    test('ספר קטן עם מיקומים גלובליים מפוזרים שומר סדר והתאמות', () async {
      await seed();
      final db = await database.database;
      final aText = db
          .select("SELECT id FROM tocText WHERE text = 'פרק א'")
          .first['id'];
      final cText = db
          .select("SELECT id FROM tocText WHERE text = 'חמש'")
          .first['id'];
      db.execute(
        'WITH RECURSIVE numbers(n) AS (SELECT 0 UNION ALL '
        'SELECT n + 1 FROM numbers WHERE n < 1999) '
        'INSERT INTO alt_toc_entry (id, structureId, textId, level) '
        'SELECT 100000 + n, 1, ?, 0 FROM numbers',
        [aText],
      );
      db.execute(
        'INSERT INTO alt_toc_entry (id, structureId, textId, level) '
        'VALUES (400000, 3, ?, 0)',
        [cText],
      );
      final bookId =
          db
                  .select('SELECT bookId FROM alt_toc_structure WHERE id = 3')
                  .first['bookId']
              as int;
      final expected = await repository.getAltTocEntriesForReference(
        bookId,
        'ספר חמש',
        queryTokens: ['חמש'],
      );
      final index = await build(chunk: 1000);
      repository.attachAltTocIndex(index);
      expect(
        await repository.getAltTocEntriesForReference(
          bookId,
          'ספר חמש',
          queryTokens: ['חמש'],
        ),
        expected,
      );
      expect(index.debugSortedBookCount, 1);
      expect(
        await repository.getAltTocEntriesForReference(
          bookId,
          'ספר חמש',
          queryTokens: ['חמש'],
        ),
        expected,
      );
      expect(repository.debugAltTocCacheEntryCount, 0);
      expectConsistent(index);
    });

    test('שורות צרות (JOIN) ושורות עם תוכן (אינדקס) נותנות אותו קאש', () async {
      await seed();
      List<Map<String, dynamic>> rows(AltTocFlatIndex index) => [
        for (var i = 0; i < index.length; i++) index.flatRowOf(i),
      ];
      final withContent = rows(await build());

      final db = await database.database;
      db.execute('ALTER TABLE line DROP COLUMN content');
      final narrow = rows(await build(chunk: 100));
      expect(narrow, withContent);
    });

    test('בלי ערכי AltToc הקאש ריק', () async {
      expect((await build()).length, 0);
    });
  });

  final dbPath = Platform.environment['OTZARIA_BENCH_DB'];
  test(
    'מסד אמיתי: הנגזרות וההתאמה זהות על כל הערכים',
    () async {
      final repository = SeforimRepository(
        MyDatabase.withPath(dbPath!, readOnly: true, official: true),
      );
      await repository.ensureInitialized();
      addTearDown(repository.database.close);
      final build = repository.beginAltTocFlatIndex();
      while (!await build.step()) {}
      final index = build.index;
      expect(index.length, greaterThan(0));
      for (var i = 0; i < index.length; i++) {
        final tokens = index.refTokensOf(i);
        if (tokens.length != index.refTokenCountOf(i) ||
            index.dafNumberOf(i) != dafNumberIn(tokens) ||
            !listEquals(tokens, tokensOf(index.referenceOf(i)))) {
          fail('entry $i differs');
        }
      }
      for (final q in [
        ...queries,
        ['דף', 'ב'],
        ['דף', 'ב', 'א'],
        ['דף', 'ה', 'ב'],
        ['מאימתי', 'דף', 'ב'],
        ['סעיף', 'ב'],
      ]) {
        expect(
          matchAltTocFlatIndex(index, q),
          bruteForce(index, q),
          reason: '$q',
        );
      }
    },
    skip: dbPath == null || dbPath.isEmpty,
    timeout: const Timeout.factor(10),
  );
}

bool listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
