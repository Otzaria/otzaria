import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';

FindRefRankKey<String> _key(FindRefRankQuery query, String title, int? tier) {
  final match = query.titleMatch(title);
  return FindRefRankKey(
    item: title,
    normTitle: title,
    fuzzyBookMatch: false,
    exactMatch: match.exactMatch,
    startsWithMatch: match.startsWithMatch,
    titleWordMatches: match.titleWordMatches,
    citationMatch: true,
    bookRank: (foundationalTier: tier, eraOrder: 10),
    isOfficial: true,
    orderIndex: 5000,
    specificity: 1,
    reference: title,
    segment: 0,
    bookId: tier ?? 0,
    categoryTokens: const {},
  );
}

/// מסדר משנה (2), בבלי (3), ירושלמי (4) ומפרש לפי [tokens] ומחזיר את הסדר.
List<String> _rank(List<String> tokens, {required int bookTokenCount}) {
  final query = FindRefRankQuery(
    tokens,
    preferBavli: queryEndsWithBareNumber(
      tokens,
      bookTokenCount: bookTokenCount,
    ),
  );
  // כותרות זהות, כדי שרק ה-tier יכריע.
  final keys = [
    _key(query, 'ירושלמי', 4),
    _key(query, 'מפרש', null),
    _key(query, 'משנה', 2),
    _key(query, 'בבלי', 3),
  ]..sort((a, b) => compareFindRefRelevance(a, b, query));
  return [for (final k in keys) k.item];
}

void main() {
  group('queryEndsWithBareNumber', () {
    test('מספר עברי בודד אחרי שם או כינוי שזוהה', () {
      for (final tokens in [
        ['סוכה', 'ג'],
        ['שבת', 'יג'],
        ['שבת', 'קנז'],
        ['בבא', 'קמא', 'ג'],
        ['רה', 'ג'],
        ['בק', 'ג'],
        ['מועד', 'קטן', 'ג'],
      ]) {
        expect(
          queryEndsWithBareNumber(tokens, bookTokenCount: tokens.length - 1),
          isTrue,
          reason: tokens.join(' '),
        );
      }
    });

    test('לא מספר, או יותר מטוקן אחד אחרי שם הספר', () {
      for (final (tokens, bookTokenCount) in [
        (['סוכה'], 1),
        (['סוכה', 'פרק', 'ג'], 1),
        (['שבת', 'משנה', 'ג'], 1),
        (['בבא', 'מציעא'], 2),
        (['ברכות', 'א'], 1),
        (['סוכה', 'ג', 'ב'], 1),
        (['שבת', 'יג', 'ג'], 1),
        (['שבת', 'קנז', 'ג'], 1),
        (['בבא', 'קמא', 'יג', 'ג'], 2),
        (['רה', 'יג', 'ג'], 1),
        (<String>[], 0),
      ]) {
        expect(
          queryEndsWithBareNumber(tokens, bookTokenCount: bookTokenCount),
          isFalse,
          reason: tokens.join(' '),
        );
      }
    });
  });

  group('#3229: בבלי לפני משנה כשמספר בודד', () {
    test('"סוכה ג" — בבלי, משנה, ירושלמי, מפרש', () {
      expect(_rank(['סוכה', 'ג'], bookTokenCount: 1), [
        'בבלי',
        'משנה',
        'ירושלמי',
        'מפרש',
      ]);
    });

    test('"סוכה פרק ג" ו"סוכה" — הסדר הרגיל של ה-tiers', () {
      const regular = ['משנה', 'בבלי', 'ירושלמי', 'מפרש'];
      expect(_rank(['סוכה', 'פרק', 'ג'], bookTokenCount: 1), regular);
      expect(_rank(['סוכה'], bookTokenCount: 1), regular);
    });

    test('"משנה סוכה ג" — שם הספר המפורש גובר על הכלל', () {
      final query = FindRefRankQuery(['משנה', 'סוכה', 'ג']);
      final mishna = _key(query, 'משנה סוכה', 2);
      final bavli = _key(query, 'סוכה', 3);
      expect(compareFindRefRelevance(mishna, bavli, query), lessThan(0));
    });

    test('ההשוואה טרנזיטיבית ואנטי-סימטרית', () {
      final query = FindRefRankQuery(['סוכה', 'ג'], preferBavli: true);
      final keys = [
        for (final tier in [null, for (var tier = 1; tier <= 10; tier++) tier])
          _key(query, 'x', tier),
      ];
      for (final x in keys) {
        for (final y in keys) {
          expect(
            compareFindRefRelevance(x, y, query).sign,
            -compareFindRefRelevance(y, x, query).sign,
          );
          for (final z in keys) {
            if (compareFindRefRelevance(x, y, query) <= 0 &&
                compareFindRefRelevance(y, z, query) <= 0) {
              expect(
                compareFindRefRelevance(x, z, query),
                lessThanOrEqualTo(0),
              );
            }
          }
        }
      }
    });
  });
}
