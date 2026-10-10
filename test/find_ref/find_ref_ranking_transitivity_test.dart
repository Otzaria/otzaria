import 'package:flutter_test/flutter_test.dart';
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
    titleTokens: match.titleTokens,
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
}
