import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

/// שלב זיהוי הספר: כל הצירופים והטוקן שאחרי שם הספר נענים מסריקה אחת של
/// הקטלוג, והתוצאה זהה ל-[ReferenceBooksCache.search] לכל שאילתה בנפרד.
void main() {
  const books = <SeedBook>[
    (id: 1, title: 'ברכות', acronyms: []),
    (id: 2, title: 'שולחן ערוך, אורח חיים', acronyms: ['שוע אוח', 'שו"ע או"ח']),
    (id: 3, title: 'משנה ברורה', acronyms: ['מ"ב', 'משנ"ב']),
    (id: 4, title: 'ברכת אברהם', acronyms: []),
    (id: 5, title: 'פסקי הרא"ש על ברכות', acronyms: ['רא"ש ברכות']),
    (id: 6, title: 'אור זרוע', acronyms: []),
  ];

  setUp(() => seedLibrary(books));
  tearDown(resetSeededLibrary);

  for (final query in [
    'ברכות ב עמוד',
    'שוע אוח א',
    'מב א ב ג',
    'ברכות',
    'אור',
  ]) {
    test('"$query" סורק את הקטלוג פעם אחת בלבד', () async {
      final before = ReferenceBooksCache.debugCatalogScans;
      await buildFindRefRepo().findRefs(query);
      expect(ReferenceBooksCache.debugCatalogScans - before, 1);
    });
  }

  test('תוצאות הסריקה המשותפת זהות ל-search נפרד לכל שאילתה', () {
    final cache = ReferenceBooksCache.instance;
    const queries = ['ברכות ב', 'ברכות', 'ב', 'שוע אוח', 'אוח', 'ר', 'בר'];
    final batch = cache.searchBatch(queries, limit: 1000);
    for (final query in queries) {
      for (final limit in [1, 2, 3, 50, 1000]) {
        String describe(List<ReferenceBookHit> hits) => [
          for (final h in hits)
            '${h.bookId}:${h.matchRank}:${h.matchedTerm}:'
                '${h.acronymTailIsTitleWords}',
        ].join(',');
        expect(
          describe(batch.hitsFor(query, limit: limit)!),
          describe(cache.search(query, limit: limit)),
          reason: '"$query" limit=$limit',
        );
      }
    }
    expect(batch.hitsFor('לא נכלל', limit: 50), isNull);
  });

  test('טוקני הכותרת מגיעים מחושבים מראש מהמטמון', () {
    final cache = ReferenceBooksCache.instance;
    final first = cache.search('פסקי').single;
    final second = cache.search('פסקי הראש').single;

    expect(first.titleTokens, ['פסקי', 'הראש', 'על', 'ברכות']);
    expect(identical(first.titleTokens, second.titleTokens), isTrue);
    expect(first.titleMatchTokens, containsAll(['הראש', 'ראש', 'ברכות']));
  });

  test('hasExactTitle שקול לדירוג 0 ב-search', () {
    const tokens = ['ברכות', 'ברכת', 'אור', 'אור זרוע', 'מב', 'לא קיים'];
    final batch = ReferenceBooksCache.instance.searchBatch(
      const ['ב'],
      limit: 50,
      exactTitles: tokens.toSet(),
    );
    for (final token in tokens) {
      expect(
        batch.hasExactTitle(token),
        ReferenceBooksCache.instance.search(token).any((h) => h.matchRank == 0),
        reason: token,
      );
    }
    expect(batch.hasExactTitle('שולחן'), isNull);
  });

  test('בחירת k הטובים שווה למיון מלא וחיתוך', () {
    // בלי חיתוך — מיון מלא; זה ה"אורקל" שהבחירה החלקית חייבת לשחזר.
    final all = ReferenceBooksCache.instance.search('ב', limit: 1000);
    final starts = [
      for (final h in all)
        if (h.matchRank <= 1) h.bookId,
    ];
    final contains = [
      for (final h in all)
        if (h.matchRank > 1) h.bookId,
    ];
    expect(starts, isNotEmpty);
    expect(contains, isNotEmpty);

    // הלוגיקה המקורית של החיתוך, כולל המכסה ל"מכיל" (issue #839).
    List<int> expected(int limit) {
      final merged = [...starts, ...contains];
      if (merged.length <= limit) return merged;
      if (starts.length >= limit && contains.isNotEmpty) {
        var reserve = 10 < contains.length ? 10 : contains.length;
        if (reserve >= limit) reserve = limit - 1;
        return [...starts.take(limit - reserve), ...contains.take(reserve)];
      }
      return merged.take(limit).toList();
    }

    for (var k = 1; k <= all.length; k++) {
      final top = ReferenceBooksCache.instance.searchBatch(
        const ['ב'],
        limit: k,
      );
      expect(
        top.hitsFor('ב', limit: k)!.map((h) => h.bookId).toList(),
        expected(k),
        reason: 'k=$k',
      );
    }
  });
}
