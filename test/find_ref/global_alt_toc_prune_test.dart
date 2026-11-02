import 'dart:io';
import 'dart:math';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';
import 'support/seeded_reference_library.dart';

/// בחירת התאמות ה-AltToc הגלובלי לפני שהן חוזרות לדירוג: הרשימה הסופית
/// חייבת להיות זהה לזו שבלי החיתוך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const neutral = (foundationalTier: null, eraOrder: 5) as FindRefBookRank;

  AltTocResultKey key(
    int bookId,
    String reference, {
    int segment = 0,
    String? title,
  }) => (
    bookId: bookId,
    title: title ?? 'ספר $bookId',
    segment: segment,
    reference: reference,
  );

  List<String> select(
    List<AltTocResultKey> matches, {
    bool suppressDescendants = true,
    List<AltTocResultKey> occupied = const [],
    List<AltTocResultKey> replaceable = const [],
    Set<int> hiddenBookIds = const {},
    List<String> queryTokens = const ['פרשת'],
    int perBookCap = findRefMaxResultCap,
    int limit = 1 << 30,
    int substringQuota = 0,
    FindRefBookRank? Function(int bookId, String title)? rankOf,
  }) => [
    for (final m in selectGlobalAltTocMatches<AltTocResultKey>(
      matches,
      request: GlobalAltTocRequest(
        queryTokens: queryTokens,
        maxRefTokens: suppressDescendants ? null : 9,
        occupied: occupied,
        replaceable: replaceable,
        hiddenBookIds: hiddenBookIds,
        perBookCap: perBookCap,
        substringQuota: substringQuota,
        limit: limit,
      ),
      bookIdOf: (m) => m.bookId,
      bookTitleOf: (m) => m.title,
      orderIndexOf: (m) => m.bookId.toDouble(),
      segmentOf: (m) => m.segment as int,
      referenceOf: (m) => m.reference,
      rankOf: rankOf ?? (_, _) => neutral,
    ))
      '${m.bookId}:${m.reference}',
  ];

  test('צאצא של התאמה באותו ספר מוסר; ספר אחר וגבול מילה לא', () {
    expect(
      select([
        key(1, 'פרשת נח', segment: 1),
        key(1, 'פרשת נח עליה א', segment: 2),
        key(1, 'פרשת נחמו', segment: 3),
        key(2, 'פרשת נח עליה א', segment: 1),
      ]),
      ['1:פרשת נח', '1:פרשת נחמו', '2:פרשת נח עליה א'],
    );
  });

  test('בלי סינון צאצאים (מסלול מילה אחת) כל ההתאמות נשמרות', () {
    expect(
      select([
        key(1, 'נח', segment: 1),
        key(1, 'נח א', segment: 2),
      ], suppressDescendants: false),
      ['1:נח', '1:נח א'],
    );
  });

  test('אב שנזרק ככפילות אינו מסתיר את צאצאיו', () {
    // האב חולק שורה עם תוצאה שכבר נאספה (TOC באותו ספר) — הדירוג זורק אותו.
    expect(
      select(
        [
          key(1, 'פרשת נח', segment: 10),
          key(1, 'פרשת נח עליה א', segment: 11),
        ],
        occupied: [key(1, 'ספר 1 פרק ו', segment: 10)],
      ),
      ['1:פרשת נח עליה א'],
    );
    // וכך גם מול התאמה גלובלית קודמת באותה שורה.
    expect(
      select([
        key(1, 'הפטרה', segment: 5),
        key(1, 'פרשת נח', segment: 5),
        key(1, 'פרשת נח עליה א', segment: 6),
      ]),
      ['1:הפטרה', '1:פרשת נח עליה א'],
    );
  });

  test('תקרה פר-ספר לפי סדר הדירוג בתוך הספר, בלי לגעת בספר אחר', () {
    expect(
      select(
        [
          key(1, 'סעיף א ארוך מאוד', segment: 1),
          key(1, 'סעיף א דף ב', segment: 9),
          key(1, 'סעיף א', segment: 5),
          key(1, 'סעיף א', segment: 3),
          key(2, 'סעיף א ארוך מאוד', segment: 1),
        ],
        queryTokens: const ['סעיף', 'א'],
        suppressDescendants: false,
        perBookCap: 2,
      ),
      ['1:סעיף א', '1:סעיף א דף ב', '2:סעיף א ארוך מאוד'],
      reason: 'הכפילות נזרקת ושתי הקצרות נשמרות',
    );
    expect(
      select(
        [
          key(1, 'עא ארוך', segment: 1),
          key(1, 'דף עא', segment: 2),
          key(1, 'עא', segment: 3),
        ],
        queryTokens: const ['שבת', 'עא', 'ב'],
        suppressDescendants: false,
        perBookCap: 1,
      ),
      ['1:דף עא'],
      reason: 'בציון דף, ערך עם "דף" קודם גם כשהוא ארוך יותר',
    );
  });

  test('רק הראשונות בדירוג: ספר יסוד מאוחר בסדר קודם לספרים מוקדמים', () {
    final matches = [
      for (var book = 1; book <= 4; book++)
        for (var i = 0; i < 3; i++) key(book, 'סימן $i', segment: i),
    ];
    expect(
      select(
        matches,
        limit: 4,
        rankOf: (id, _) =>
            id == 4 ? (foundationalTier: 1, eraOrder: 5) : neutral,
      ),
      ['4:סימן 0', '4:סימן 1', '4:סימן 2', '1:סימן 0'],
    );
  });

  test('ספר בלי דירוג ידוע נשלח במלואו, מעבר לתקרה', () {
    final matches = [
      for (var book = 1; book <= 3; book++)
        for (var i = 0; i < 3; i++) key(book, 'סימן $i', segment: i),
    ];
    expect(
      select(matches, limit: 2, rankOf: (id, _) => id == 3 ? null : neutral),
      ['1:סימן 0', '1:סימן 1', '3:סימן 0', '3:סימן 1', '3:סימן 2'],
    );
  });

  test('התאמה שמחליפה התאמה חלקית שכבר נאספה נשלחת גם מעבר לתקרה', () {
    final matches = [
      for (var book = 1; book <= 3; book++) key(book, 'פרק א', segment: 7),
    ];
    expect(
      select(matches, limit: 1, replaceable: [key(3, 'ספר 3 פרק', segment: 7)]),
      ['1:פרק א', '3:פרק א'],
    );
  });

  test('המחליפה של התאמה חלקית נשלחת מעבר לתקרה, והמתנגשת אחריה נזרקת', () {
    expect(
      select(
        [
          key(2, 'סימן א', segment: 1),
          key(2, 'סימן ב', segment: 2),
          key(2, 'סימן ג ארוך', segment: 7),
          key(2, 'פרק', segment: 9),
        ],
        perBookCap: 2,
        replaceable: [key(2, 'פרק', segment: 7)],
      ),
      ['2:סימן א', '2:סימן ב', '2:סימן ג ארוך'],
      reason: 'השלישית מחליפה (segment 7); "פרק" כבר תפוס ואינו תופס מקום',
    );
  });

  test('צאצאי דף המדורגים לפני האב אינם תופסים את מכסת הספר', () {
    final matches = [
      key(1, 'כרך א', segment: 0),
      for (var i = 1; i <= 250; i++) key(1, 'כרך א דף $i', segment: i),
      key(1, 'חלק א כרך אחר', segment: 999),
    ];
    expect(
      select(matches, queryTokens: const ['כרך', 'א'], perBookCap: 2),
      ['1:כרך א', '1:חלק א כרך אחר'],
    );
  });

  test('ספר מוסתר אינו נבחר ואינו תופס מקום', () {
    final matches = [
      for (var book = 1; book <= 3; book++) key(book, 'פרק א', segment: 1),
    ];
    expect(select(matches, limit: 2, hiddenBookIds: {1}), [
      '2:פרק א',
      '3:פרק א',
    ]);
  });

  test('מכסת תת-המחרוזת נשמרת מעבר לתקרה', () {
    final matches = [
      for (var book = 1; book <= 3; book++)
        key(book, 'נח', segment: 1, title: book == 3 ? 'על נח' : 'ספר $book'),
    ];
    expect(
      select(
        matches,
        queryTokens: const ['נח'],
        suppressDescendants: false,
        limit: 1,
        substringQuota: 1,
      ),
      ['1:נח', '3:נח'],
    );
  });

  test('מסכת הטוקנים אינה פוסלת ערך שמכיל את כל טוקני השאילתה', () {
    final random = Random(7);
    const vocabulary = ['א', 'ב', 'סעיף', 'סימן', 'דף', 'עא', 'נח', 'פרשת'];
    for (var i = 0; i < 2000; i++) {
      final ref = [
        for (var j = 0; j < 1 + random.nextInt(6); j++)
          vocabulary[random.nextInt(vocabulary.length)],
      ];
      final query = [
        for (var j = 0; j < 1 + random.nextInt(3); j++)
          vocabulary[random.nextInt(vocabulary.length)],
      ];
      if (!altTocFlatMatches(ref, query)) continue;
      final queryMask = altTocTokenMask(query);
      expect(altTocTokenMask(ref) & queryMask, queryMask);
    }
  });

  group('הרשימה הסופית זהה עם חיתוך ב-worker ובלעדיו', () {
    tearDown(resetSeededLibrary);

    Map<String, dynamic> row(
      int bookId,
      String reference,
      int segment, {
      double? order,
      String? title,
    }) => {
      'bookId': bookId,
      'bookTitle': title ?? 'ספר $bookId',
      'bookOrderIndex': order ?? bookId.toDouble(),
      'reference': reference,
      'segment': segment,
      'level': reference.split(' ').length,
      'dbLineId': segment,
    };

    List<Map<String, dynamic>> matching(
      List<Map<String, dynamic>> rows,
      GlobalAltTocRequest request,
      bool matchTokens,
    ) => [
      for (final r in rows)
        if (!matchTokens ||
            altTocFlatMatches(
              normalizeForFindRefMatch(r['reference'] as String).split(' '),
              request.queryTokens,
              maxRefTokens: request.maxRefTokens,
            ))
          r,
    ];

    Future<List<DbReferenceResult>> search(
      String query,
      List<Map<String, dynamic>> rows,
      Map<int, List<Map<String, dynamic>>> tocByBookId,
      Future<List<Map<String, dynamic>>> Function(GlobalAltTocRequest) global,
    ) async {
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        getAltStructureBookIds: () async => [
          for (final r in rows) r['bookId'] as int,
        ],
        getTocEntriesForReference: (id, title, {queryTokens}) async =>
            tocByBookId[id] ?? const [],
        getAltTocEntriesForReference: (id, title, {queryTokens}) async =>
            const [],
        searchAltTocFlatEntries: global,
        getCategoryPath: (_) async => 'ספרייה',
      );
      addTearDown(repo.dispose);
      return repo.findRefs(query);
    }

    /// [oracle] = הדירוג של main על כל ההתאמות הגולמיות (`_dedupeRefs`,
    /// `suppressDeeperVariants`, `_rankResults`), בלי הבחירה ב-worker. תקרת
    /// הגיוון נגזרת גם היא מהדירוג של main: לכל ספר לבדו, הראשונות שלו.
    /// אחרת — מסלול הייצור: [selectGlobalAltTocMatches] כמו ב-worker.
    Future<List<String>> run(
      String query,
      List<Map<String, dynamic>> rows, {
      required bool oracle,
      Map<int, List<Map<String, dynamic>>> tocByBookId = const {},
      List<int>? sentRows,
      bool matchTokens = true,
    }) async {
      Future<List<Map<String, dynamic>>> oracleRows(
        GlobalAltTocRequest request,
      ) async {
        final matched = matching(rows, request, matchTokens);
        sentRows?.add(matched.length);
        if (request.perBookCap >= findRefMaxResultCap) return matched;
        final keep = <(int, int)>{};
        for (final id in {for (final r in matched) r['bookId'] as int}) {
          final own = [
            for (final r in matched)
              if (r['bookId'] == id) r,
          ];
          final ranked = await search(
            query,
            own,
            tocByBookId,
            (_) async => own,
          );
          keep.addAll(
            ranked
                .where((r) => r.isAltToc && r.bookId == id)
                .take(request.perBookCap)
                .map((r) => (r.bookId, r.segment.toInt())),
          );
        }
        return [
          for (final r in matched)
            if (keep.contains((r['bookId'] as int, r['segment'] as int))) r,
        ];
      }

      final results = await search(
        query,
        rows,
        tocByBookId,
        oracle
            ? oracleRows
            : (request) async {
                final selected = selectGlobalAltTocMatches(
                  matching(rows, request, matchTokens),
                  request: request,
                  bookIdOf: (r) => r['bookId'] as int,
                  bookTitleOf: (r) => r['bookTitle'] as String,
                  orderIndexOf: (r) => r['bookOrderIndex'] as double,
                  segmentOf: (r) => r['segment'] as int,
                  referenceOf: (r) => qualifyAltTocReference(
                    r['bookTitle'] as String,
                    r['reference'] as String,
                  ),
                );
                sentRows?.add(selected.length);
                return selected;
              },
      );
      return [
        for (final r in results) '${r.bookId}|${r.reference}|${r.segment}',
      ];
    }

    test('צאצאים באותו ספר ובספר אחר', () async {
      seedLibrary(const [
        (id: 1, title: 'ספר אחר', acronyms: []),
        (id: 5, title: 'ספר 5', acronyms: []),
        (id: 6, title: 'ספר 6', acronyms: []),
      ]);
      final rows = [
        row(5, 'פרשת נח', 0),
        row(5, 'פרשת נח עליה א', 3),
        row(5, 'פרשת נח עליה ב', 7),
        row(6, 'פרשת נח עליה ג', 2),
      ];
      final expected = await run('פרשת נח', rows, oracle: true);
      expect(expected, hasLength(2));
      expect(await run('פרשת נח', rows, oracle: false), expected);
    });

    test('אב שהתנגש בשורת TOC של אותו ספר — צאצאיו נשארים', () async {
      // כמו "לך לך": הספר עצמו תואם, ה-TOC שלו ברמה 1 חולק שורה עם האב.
      seedLibrary(const [(id: 5, title: 'פרשת השבוע', acronyms: [])]);
      final toc = {
        5: [
          {'reference': 'פרשת השבוע נח', 'segment': 10, 'level': 1},
        ],
      };
      final rows = [
        row(5, 'פרשת נח', 10, title: 'פרשת השבוע'),
        row(5, 'פרשת נח עליה א', 11, title: 'פרשת השבוע'),
        row(5, 'פרשת נח עליה ב', 12, title: 'פרשת השבוע'),
      ];
      final expected = await run(
        'פרשת נח',
        rows,
        oracle: true,
        tocByBookId: toc,
      );
      expect(expected, contains('5|פרשת השבוע פרשת נח עליה א|11'));
      expect(
        await run('פרשת נח', rows, oracle: false, tocByBookId: toc),
        expected,
      );
    });

    test('שורת TOC חלקית אינה חוסמת AltToc מלא לאותה שורה', () async {
      seedLibrary(const [(id: 5, title: 'ספר חמש', acronyms: [])]);
      final toc = {
        5: [
          {
            'reference': 'ספר חמש פרק',
            'segment': 10,
            'level': 1,
            'partialMatch': true,
          },
        ],
      };
      final rows = [
        row(5, 'פרק א', 10, title: 'ספר חמש'),
        row(5, 'פרק ב סימן א', 20, title: 'ספר חמש'),
      ];
      final expected = await run(
        'ספר חמש פרק א',
        rows,
        oracle: true,
        tocByBookId: toc,
        matchTokens: false,
      );
      expect(expected.first, '5|ספר חמש פרק א|10');
      expect(
        await run(
          'ספר חמש פרק א',
          rows,
          oracle: false,
          tocByBookId: toc,
          matchTokens: false,
        ),
        expected,
      );
    });

    test('ציון דף בלי שם ספר שומר את "דף ב:" בירושלמי', () async {
      // כמו בירושלמי: "דף א:" ו-"דף ב." מכילים "דף" ו-"ב", ובאותו אורך.
      seedLibrary(const [
        (id: 140, title: 'תלמוד ירושלמי ברכות', acronyms: []),
        (id: 141, title: 'תלמוד ירושלמי פאה', acronyms: []),
      ]);
      final rows = [
        for (final (id, title) in [
          (140, 'תלמוד ירושלמי ברכות'),
          (141, 'תלמוד ירושלמי פאה'),
        ]) ...[
          row(id, 'מאימתי דף א:', id * 10 + 1, title: title),
          row(id, 'מאימתי דף ב.', id * 10 + 2, title: title),
          row(id, 'מאימתי דף ב:', id * 10 + 3, title: title),
        ],
      ];
      for (final query in ['מאימתי דף ב', 'דף ב']) {
        final results = await run(query, rows, oracle: false);
        expect(results, await run(query, rows, oracle: true), reason: query);
        expect(results, contains('140|תלמוד ירושלמי ברכות מאימתי דף ב:|1403'));
        expect(results, contains('141|תלמוד ירושלמי פאה מאימתי דף ב:|1413'));
      }
    });

    test('בלי שם ספר: מעט שורות לכל ספר, וספר יסוד מאוחר בסדר ראשון', () async {
      seedLibrary(
        const [
          (id: 1, title: 'ספר אחר', acronyms: []),
          (id: 6, title: 'ספר 6', acronyms: []),
          (id: 7, title: 'ספר 7', acronyms: []),
        ],
        categoryPaths: {7: 'תנ"ך, תורה'},
      );
      final rows = [
        for (var i = 0; i < 600; i++) row(6, 'סימן $i סעיף א', i, order: 1),
        for (var i = 0; i < 50; i++) row(7, 'פרק $i סעיף א', 1000 + i),
      ];
      final results = await run('סעיף א', rows, oracle: false);
      expect(results, await run('סעיף א', rows, oracle: true));
      expect(results.first, startsWith('7|'));
      expect(
        results.where((r) => r.startsWith('6|')),
        hasLength(globalAltTocDiversityCap),
      );
    });

    /// ספרייה סינתטית: הרבה ספרים באותו orderIndex ובאותו דור, ספרי יסוד
    /// ומפרשים מתויגים, כפילויות וצאצאים — ו-segment ייחודי, כדי שהדירוג
    /// המלא יהיה חד-משמעי.
    ({
      List<SeedBook> books,
      Map<int, String> paths,
      List<Map<String, dynamic>> rows,
    })
    library(int seed) {
      final random = Random(seed);
      const letters = ['א', 'ב', 'יא', 'קכג', 'שמ', 'ג', 'תקעא'];
      final books = <SeedBook>[];
      final paths = <int, String>{};
      final rows = <Map<String, dynamic>>[];
      var segment = 1;
      for (var i = 1; i <= 70; i++) {
        final id = 100 + i;
        final title = i % 9 == 0 ? 'חיבור על נח $i' : 'חיבור $i';
        books.add((id: id, title: title, acronyms: const []));
        paths[id] = switch (i % 7) {
          0 => 'תנ"ך, תורה',
          1 => 'הלכה, אחרונים',
          2 => 'הלכה, ראשונים',
          _ => 'ספרייה',
        };
        // ספרי "על נח" מזוהים בשם ומוסיפים שורת ספר; orderIndex משלהם מונע
        // שוויון מלא בין שתיים כאלה.
        final order = i % 9 == 0 ? 10.0 + i : (i % 4).toDouble();
        Map<String, dynamic> add(String reference) => row(
          id,
          reference,
          segment++,
          order: order,
          title: title,
        );
        for (var j = random.nextInt(12); j > 0; j--) {
          final siman = letters[random.nextInt(letters.length)];
          final dafMark = random.nextBool() ? 'דף ' : '';
          rows
            ..add(add('סימן $siman סעיף א'))
            ..add(add('סימן $siman סעיף א הגה'))
            ..add(add('שבת $dafMark עא ב'));
          if (random.nextInt(4) == 0) {
            final duplicate = add('סימן $siman סעיף א');
            rows.add({...duplicate, 'segment': duplicate['segment'] - 1});
          }
        }
        for (final reference in ['נח', 'פרשת נח', 'הפטרת נח']) {
          if (random.nextInt(3) > 0) rows.add(add(reference));
        }
      }
      return (books: books, paths: paths, rows: rows);
    }

    for (final seed in [1, 2, 3, 4, 5]) {
      test(
        'ספרייה סינתטית $seed: דירוג כל ההתאמות ואז 100 = חיתוך ב-worker',
        () async {
          final lib = library(seed);
          seedLibrary(lib.books, categoryPaths: lib.paths);
          for (final query in ['סעיף א', 'סימן קכג', 'שבת עא ב', 'נח']) {
            final rawCount = <int>[];
            final sent = <int>[];
            final expected = await run(
              query,
              lib.rows,
              oracle: true,
              sentRows: rawCount,
            );
            final truncated = await run(
              query,
              lib.rows,
              oracle: false,
              sentRows: sent,
            );
            expect(truncated, expected, reason: query);
            expect(expected, isNotEmpty, reason: query);
            expect(
              sent.single,
              lessThanOrEqualTo(
                findRefMaxResultCap + findRefSubstringTailQuota,
              ),
              reason: '$query: ה-worker שולח רק את מה שיכול להיות מוצג',
            );
            if (query == 'סעיף א') {
              expect(
                rawCount.single,
                greaterThan(sent.single),
                reason: 'החיתוך פעל',
              );
            }
          }
        },
      );
    }
  });

  group('ב-worker', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_alt_prune');
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // ב-Windows שחרור ה-handle של ה-worker אינו מיידי אחרי kill.
      }
    });

    Future<FindRefDbIsolate> seedWorker({int books = 1}) async {
      final dbPath = path.join(tempDir.path, 'seforim.db');
      final database = MyDatabase.withPath(dbPath);
      final db = await database.database;
      db.execute(
        "INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)",
      );
      db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
      db.execute(
        "INSERT INTO tocText (id, text) VALUES (1, 'פרשה נח'), "
        "(2, 'עליה א'), (3, 'פרשה נחמה')",
      );
      for (var b = 1; b <= books; b++) {
        db.execute(
          'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
          'filePath, fileType) VALUES (?, 7, 1, ?, ?, ?, ?)',
          [b, 'ספר $b', b, '/b/$b.txt', 'txt'],
        );
        final line = b * 100;
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) VALUES '
          "(?, ?, 0, 'שורה'), (?, ?, 1, 'שורה'), (?, ?, 2, 'שורה')",
          [line, b, line + 1, b, line + 2, b],
        );
        db.execute(
          'INSERT INTO alt_toc_structure (id, bookId, key) VALUES (?, ?, ?)',
          [b, b, 'p'],
        );
        final entry = b * 1000;
        db.execute(
          'INSERT INTO alt_toc_entry '
          '(id, structureId, parentId, textId, level, lineId) VALUES '
          '(?, ?, NULL, 1, 1, ?), (?, ?, ?, 2, 2, ?), (?, ?, NULL, 3, 1, ?)',
          [
            entry, b, line, //
            entry + 1, b, entry, line + 1, //
            entry + 2, b, line + 2,
          ],
        );
      }
      database.close();
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);
      return isolate;
    }

    List<String> refs(List<Map<String, dynamic>> rows) => [
      for (final row in rows) '${row['bookId']}:${row['reference']}',
    ];

    test('חיפוש רב-מילי אינו מחזיר צאצאים של התאמה', () async {
      final isolate = await seedWorker();
      final all = refs(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה'], maxRefTokens: 9),
        ),
      );
      expect(all, hasLength(3), reason: 'בלי סינון צאצאים: $all');
      expect(all.where((r) => r.startsWith('1:פרשה נח ')), isNotEmpty);

      final multiWord = refs(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
      );
      expect(multiWord, ['1:פרשה נח', '1:פרשה נחמה']);
    });

    test('טבלת דירוג הספרים נשלחת פעם אחת ומשמשת גם את הבקשות הבאות', () async {
      final isolate = await seedWorker(books: 3);
      final ranks = {
        for (var b = 1; b <= 3; b++)
          b: (
            title: 'ספר $b',
            rank: b == 3
                ? (foundationalTier: 1, eraOrder: 5)
                : (foundationalTier: null, eraOrder: 5),
          ),
      };
      GlobalAltTocRequest request() => GlobalAltTocRequest(
        queryTokens: const ['פרשה'],
        bookRanks: ranks,
        perBookCap: 1,
        limit: 2,
      );
      final first = refs(await isolate.searchAltTocFlat(request()));
      expect(first, ['3:פרשה נח', '1:פרשה נח']);
      expect(refs(await isolate.searchAltTocFlat(request())), first);
      expect(
        refs(
          await isolate.searchAltTocFlat(
            const GlobalAltTocRequest(
              queryTokens: ['פרשה'],
              perBookCap: 1,
              limit: 2,
            ),
          ),
        ),
        ['1:פרשה נח', '2:פרשה נח', '3:פרשה נח'],
        reason: 'בלי דירוג ידוע כל הספרים נשלחים',
      );
    });

    test(
      'בקשה שנשאה את הטבלה ובוטלה בתור — הבאה מקבלת תשובה בלי דירוג, והטבלה נשלחת שוב',
      () async {
        final isolate = await seedWorker(books: 3);
        final ranks = {
          for (var b = 1; b <= 3; b++)
            b: (
              title: 'ספר $b',
              rank: b == 3
                  ? (foundationalTier: 1, eraOrder: 5)
                  : (foundationalTier: null, eraOrder: 5),
            ),
        };
        GlobalAltTocRequest request() => GlobalAltTocRequest(
          queryTokens: const ['פרשה'],
          bookRanks: ranks,
          perBookCap: 1,
          limit: 2,
        );
        final scope = FindRefDbIsolate.allocateSearchScope();
        addTearDown(() => FindRefDbIsolate.releaseSearchScope(scope));
        FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 5);
        await expectLater(
          isolate.searchAltTocFlat(
            request(),
            searchScope: scope,
            searchEpoch: 1,
          ),
          throwsA(isA<FindRefQueryCancelled>()),
        );

        Future<List<String>> search() async => refs(
          await isolate.searchAltTocFlat(
            request(),
            searchScope: scope,
            searchEpoch: 5,
          ),
        );
        expect(
          await search(),
          ['1:פרשה נח', '2:פרשה נח', '3:פרשה נח'],
          reason: 'הטבלה לא הגיעה: כל הספרים נשלחים, והתוצאה נשארת נכונה',
        );
        expect(await search(), ['3:פרשה נח', '1:פרשה נח']);
      },
    );
  });
}
