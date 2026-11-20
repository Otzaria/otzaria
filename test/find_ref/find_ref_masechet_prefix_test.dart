import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

/// "מסכת" כמילת קישור באיתור מקורות (issue #5609). נתוני אמת מ-seforim.db.

const _yevamot = (
  id: 115,
  title: 'יבמות',
  acronyms: [
    'בבלי יבמות',
    'יב"מ',
    'יבמ"ת',
    "מס' יבמות",
    'מסכת יבמות',
    'תלמוד בבלי יבמות',
    'תלמוד יבמות',
  ],
);

const _akivaEigerYevamot = (
  id: 2673,
  title: 'חידושי רבי עקיבא איגר על מסכת יבמות',
  acronyms: [
    'חידושי הגרעא על מסכת יבמות',
    'חידושי רעקא יבמות',
    'רעקא יבמות',
    'רעקא על יבמות',
  ],
);

const _bartenuraPesachim = (
  id: 589,
  title: 'ברטנורא על משנה פסחים',
  acronyms: [
    'ברטנורא',
    'ברטנורא משנה פסחים',
    'ברטנורא על מסכת פסחים',
    'ברטנורה',
  ],
);

const _sofrim = (
  id: 1843,
  title: 'מסכת סופרים',
  acronyms: ['מס"ס', "מס' סופרים", 'סופרים'],
);

const _orHayasharSofrim = (
  id: 6465,
  title: 'אור הישר על מסכת סופרים',
  acronyms: ['אור הישר סופרים', 'אור הישר על סופרים', 'סופרים'],
);

const _paths = {
  115: 'תלמוד בבלי, סדר נשים',
  2673: 'תלמוד בבלי, אחרונים, חידושי רבי עקיבא איגר, סדר נשים',
  1843: 'תלמוד בבלי, מסכתות קטנות',
  6465: 'תלמוד בבלי, אחרונים, אור הישר, מסכתות קטנות',
};

void main() {
  tearDown(resetSeededLibrary);

  Future<List<String>> titlesFor(String query, List<SeedBook> books) async {
    seedLibrary(books, categoryPaths: _paths);
    return [for (final r in await buildFindRefRepo().findRefs(query)) r.title];
  }

  test('"מסכת יבמות" מחזיר את הגמרא לפני מפרש ששמו מכיל "מסכת"', () async {
    final titles = await titlesFor('מסכת יבמות', const [
      _akivaEigerYevamot,
      _yevamot,
    ]);

    expect(titles.first, 'יבמות');
    expect(titles, contains(_akivaEigerYevamot.title));
  });

  for (final query in ['ברטנורא פסחים', 'ברטנורא על פסחים']) {
    test('"$query" מתאים לכינוי "ברטנורא על מסכת פסחים"', () {
      seedLibrary(const [_bartenuraPesachim]);

      expect(ReferenceBooksCache.instance.search(query).single.matchRank, 3);
    });
  }

  test('ספר ששמו פותח ב"מסכת" נשאר ראשון בשמו המלא', () async {
    final titles = await titlesFor('מסכת סופרים', const [
      _orHayasharSofrim,
      _sofrim,
    ]);

    expect(titles.first, 'מסכת סופרים');
  });

  test('כינוי "מסכת X" אינו כינוי מדויק של "X" לבדו', () {
    seedLibrary(const [
      (id: 125, title: 'ביצה', acronyms: ['מסכת יום טוב', 'מסכת יו"ט']),
    ]);

    for (final query in ['יום טוב', 'יו"ט']) {
      final hits = ReferenceBooksCache.instance.search(query);
      expect(hits.where((h) => h.matchRank == 3), isEmpty, reason: query);
    }
  });

  test('"מסכת" לבדה אינה מושמטת', () {
    seedLibrary(const [
      (id: 1, title: 'ספר אחר', acronyms: ['מסכת']),
    ]);

    expect(ReferenceBooksCache.instance.search('מסכת').single.matchRank, 3);
  });

  test('"מס" נשארת מילה בשם הספר ובשאילתה', () {
    final rank = FindRefRankQuery(['הלכות', 'מס', 'שבח']);
    expect(rank.titleMatch('הלכות שבח').titleWordMatches, [true, false, false]);
    seedLibrary(const [
      (id: 1, title: 'חוקי שבח', acronyms: ['הלכות שבח']),
    ]);
    final hits = ReferenceBooksCache.instance.search('הלכות מס שבח');
    expect(hits.where((hit) => hit.matchesExactAlias), isEmpty);
  });

  test('משנה מדות נמצאת גם בקטלוג ישן לפי שני הכתיבים', () async {
    seedLibrary(
      const [
        (id: 89, title: 'משנה מדות', acronyms: ['מדות']),
        (id: 393, title: 'ספר המדות', acronyms: ['מדות', 'מידות']),
        (
          id: 6034,
          title: 'פירוש מיוחס לרבינו שמעיה על מסכת מדות',
          acronyms: <String>[],
        ),
      ],
      categoryPaths: const {89: 'משנה, סדר קדשים'},
    );

    final repo = buildFindRefRepo();
    for (final name in ['מדות', 'מידות']) {
      final results = await repo.findRefs('מסכת $name');
      expect(results.first.title, 'משנה מדות');
    }
  });

  test('גיבוי למסכת משנה שומר על כינוי מפורש ומוגבל לספרי משנה', () {
    seedLibrary(
      const [
        (id: 89, title: 'משנה מדות', acronyms: ['מדות']),
        (id: 1, title: 'ספר בעל כינוי', acronyms: ['מסכת מידות']),
        (id: 2, title: 'משנה תורה', acronyms: <String>[]),
      ],
      categoryPaths: const {
        89: 'משנה, סדר קדשים',
        2: 'הלכה, משנה תורה',
      },
    );

    final cache = ReferenceBooksCache.instance;
    expect(cache.search('מסכת מידות').first.bookId, 1);
    expect(
      cache.search('מסכת תורה').where((h) => h.matchesExactAlias),
      isEmpty,
    );
  });

  for (final (query, found, competing) in [
    (
      'רמב"ם מסכת מקואות',
      (
        id: 563,
        title: 'רמב"ם על משנה מקואות',
        acronyms: ['רמבם על מסכת מקואות'],
      ),
      (id: 373, title: 'משנה תורה, הלכות מקואות', acronyms: ['רמב"ם מקואות']),
    ),
    (
      'מהרש"א מסכת נדה',
      (
        id: 2939,
        title: 'מהרש"א - חידושי הלכות על מסכת נדה',
        acronyms: ['מהרשא על מסכת נדה'],
      ),
      (
        id: 2851,
        title: 'מהרש"א - חידושי אגדות על נדה',
        acronyms: ['מהרשא על נדה'],
      ),
    ),
  ]) {
    test('"$query" שומר כינוי שנמצא בהשמטת "על" בלבד', () async {
      seedLibrary([competing, found]);
      expect(
        ReferenceBooksCache.instance
            .search(query)
            .where((hit) => hit.matchesExactAlias)
            .map((hit) => hit.bookId),
        [found.id],
      );
      final results = await buildFindRefRepo().findRefs(query);
      expect(results.first.bookId, found.id);
    });
  }
}
