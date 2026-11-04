import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';

FindRefRankKey<String> _key(
  FindRefRankQuery query,
  String item,
  String title, {
  int? tier,
  required double order,
  Set<String> categoryTokens = const {},
}) {
  final match = query.titleMatch(title);
  return FindRefRankKey(
    item: item,
    normTitle: title,
    fuzzyBookMatch: false,
    exactMatch: match.exactMatch,
    startsWithMatch: match.startsWithMatch,
    titleWordMatches: match.titleWordMatches,
    citationMatch: true,
    bookRank: (foundationalTier: tier, eraOrder: 10),
    isOfficial: true,
    orderIndex: order,
    specificity: 1,
    reference: title,
    segment: 0,
    bookId: order.toInt(),
    categoryTokens: categoryTokens,
  );
}

/// מילת השאילתה ה-[i] מול הכותרת, בלי [FindRefRankQuery.titleMatch].
bool _titleWordAtPerCompare(FindRefRankQuery query, String title, int i) {
  final tokens = bookNameMatchForm(
    title,
  ).split(' ').where((t) => t.isNotEmpty).toList();
  final first = query.matchTokens.first;
  final at = first.length < 2
      ? 0
      : tokens.indexWhere((t) => t.startsWith(first));
  final index = (at < 0 ? 0 : at) + i;
  return index < tokens.length &&
      tokens[index].startsWith(query.matchTokens[i]);
}

void main() {
  final query = FindRefRankQuery(['רמבם', 'ספר', 'זמנים']);
  final a = _key(
    query,
    'A',
    'משנה תורה הלכות שבת',
    tier: 9,
    order: 0,
    categoryTokens: {'ספר', 'זמנים'},
  );
  final b = _key(
    query,
    'B',
    'קרית ספר על משנה תורה הלכות שבת',
    order: 1,
    categoryTokens: {'ספר', 'זמנים'},
  );
  final c = _key(
    query,
    'C',
    'קרית ספר על משנה תורה הלכות עירובין',
    order: 2,
  );
  final permutations = [
    [a, b, c],
    [a, c, b],
    [b, a, c],
    [b, c, a],
    [c, a, b],
    [c, b, a],
  ];

  test('התאמות קטגוריה ו-TOC שומרות על טרנזיטיביות ורלוונטיות', () {
    for (final compare in [compareFindRefRelevance, compareFindRefRank]) {
      for (final triple in permutations) {
        final [x, y, z] = triple;
        expect(compare(x, y, query), -compare(y, x, query));
        if (compare(x, y, query) <= 0 && compare(y, z, query) <= 0) {
          expect(compare(x, z, query), lessThanOrEqualTo(0));
        }
      }
    }
    expect(compareFindRefRelevance(a, b, query), lessThan(0));
    expect(compareFindRefRelevance(b, c, query), lessThan(0));
  });

  test('מיון ובחירה בגבול המכסה זהים בכל סדר קלט', () {
    for (final input in permutations) {
      final ranked = List.of(input)
        ..sort((x, y) => compareFindRefRank(x, y, query));
      expect(ranked.map((key) => key.item), ['A', 'B', 'C']);
      expect(ranked.take(2).map((key) => key.item), ['A', 'B']);
    }
  });

  test('ללא התאמות קטגוריה נשמר דירוג מילות הכותרת', () {
    final foundation = _key(
      query,
      'foundation',
      a.normTitle,
      tier: 9,
      order: 0,
    );
    expect(compareFindRefRelevance(c, foundation, query), lessThan(0));
  });

  test('מילות הכותרת שנקבעות פעם אחת זהות לבדיקה בכל השוואה', () {
    const queries = [
      ['רמבם', 'ספר', 'זמנים'],
      ['ירושלמי', 'מעשר', 'שני'],
      ['א', 'הלכות', 'שבת'],
      ['שוע', 'אוח', 'א'],
      ['הרמבם', 'הלכות', 'תפלה', 'ד'],
      ['בבא', 'קמא'],
      ['קיצור', 'שולחן', 'ערוך', 'סימן', 'א'],
    ];
    const titles = [
      'משנה תורה הלכות שבת',
      'תלמוד ירושלמי מעשר שני',
      'קרית ספר על משנה תורה הלכות שבת',
      'רמבם הלכות תפילה',
      'פני יהושע על בבא קמא',
      'בבא',
      'שולחן ערוך אורח חיים',
      'קיצור שולחן ערוך',
      'ספר ספר זמנים',
      '',
    ];
    for (final tokens in queries) {
      final query = FindRefRankQuery(tokens);
      for (final title in titles) {
        final matches = query.titleMatch(title).titleWordMatches;
        expect(matches, hasLength(tokens.length), reason: title);
        for (var i = 1; i < tokens.length; i++) {
          expect(
            matches[i],
            _titleWordAtPerCompare(query, title, i),
            reason: '$tokens / $title / $i',
          );
        }
      }
    }
    expect(
      FindRefRankQuery(['רמבם']).titleMatch('רמבם').titleWordMatches,
      isEmpty,
    );
  });
}
