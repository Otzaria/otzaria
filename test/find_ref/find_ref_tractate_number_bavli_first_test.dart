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
List<String> _rank(List<String> tokens) {
  final query = FindRefRankQuery(tokens);
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
    test('מספר עברי בודד אחרי שם', () {
      expect(queryEndsWithBareNumber(['סוכה', 'ג']), isTrue);
      expect(queryEndsWithBareNumber(['שבת', 'יג']), isTrue);
      expect(queryEndsWithBareNumber(['שבת', 'קנז']), isTrue);
      expect(queryEndsWithBareNumber(['בבא', 'קמא', 'ג']), isTrue);
      expect(queryEndsWithBareNumber(['רה', 'ג']), isTrue);
    });

    test('לא מספר, או מספר אחרי מילת מבנה', () {
      expect(queryEndsWithBareNumber(['סוכה']), isFalse);
      expect(queryEndsWithBareNumber(['סוכה', 'פרק', 'ג']), isFalse);
      expect(queryEndsWithBareNumber(['שבת', 'משנה', 'ג']), isFalse);
      expect(queryEndsWithBareNumber(['בבא', 'מציעא']), isFalse);
      // בבלי מתחיל בדף ב, לכן "א" הוא פרק; שני מספרים הם משנה או עמוד.
      expect(queryEndsWithBareNumber(['ברכות', 'א']), isFalse);
      expect(queryEndsWithBareNumber(['סוכה', 'ג', 'ב']), isFalse);
    });
  });

  group('#3229: בבלי לפני משנה כשמספר בודד', () {
    test('"סוכה ג" — בבלי, משנה, ירושלמי, מפרש', () {
      expect(_rank(['סוכה', 'ג']), ['בבלי', 'משנה', 'ירושלמי', 'מפרש']);
    });

    test('"סוכה פרק ג" ו"סוכה" — הסדר הרגיל של ה-tiers', () {
      const regular = ['משנה', 'בבלי', 'ירושלמי', 'מפרש'];
      expect(_rank(['סוכה', 'פרק', 'ג']), regular);
      expect(_rank(['סוכה']), regular);
    });

    test('"משנה סוכה ג" — שם הספר המפורש גובר על הכלל', () {
      final query = FindRefRankQuery(['משנה', 'סוכה', 'ג']);
      final mishna = _key(query, 'משנה סוכה', 2);
      final bavli = _key(query, 'סוכה', 3);
      expect(compareFindRefRelevance(mishna, bavli, query), lessThan(0));
    });

    test('ההשוואה טרנזיטיבית ואנטי-סימטרית', () {
      final query = FindRefRankQuery(['סוכה', 'ג']);
      final keys = [
        for (final tier in [null, 2, 3, 4]) _key(query, 'x', tier),
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
