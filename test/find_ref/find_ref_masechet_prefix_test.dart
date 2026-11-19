import 'package:flutter_test/flutter_test.dart';
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
}
