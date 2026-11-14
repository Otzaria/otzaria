import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';

import 'support/seeded_reference_library.dart';

FindRefRankKey<String> _key(
  FindRefRankQuery query,
  String title, {
  int? tier,
  required double order,
  bool direct = true,
  bool alias = true,
}) {
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
    orderIndex: order,
    specificity: 1,
    reference: title,
    segment: 0,
    bookId: order.toInt(),
    directNameMatch: direct,
    exactAliasMatch: direct && alias,
  );
}

void main() {
  // #4496: "רמב"ם" הוא כינוי מדויק גם של משנה תורה וגם של פירוש המשניות.
  final query = FindRefRankQuery(['רמבם']);
  final mishnehTorah = _key(query, 'משנה תורה הלכות שבת', tier: 9, order: 5);
  final onMishnah = _key(query, 'רמבם על משנה ברכות', order: 1);
  final indirectPrefix = _key(
    query,
    'רמבם לעם',
    order: 0,
    direct: false,
  );
  final indirectFoundation = _key(
    query,
    'משנה תורה הלכות ברכות',
    tier: 9,
    order: 2,
    direct: false,
  );
  // שם ישיר שאינו כינוי (פרק ב"ספר הזהר" ששמו "תוספות") אינו עוקף התחלת שם.
  final tosafot = FindRefRankQuery(['תוספות']);
  final zoharSection = _key(
    tosafot,
    'ספר הזהר תוספות',
    tier: 6,
    order: 0,
    alias: false,
  );
  final tosafotBerachot = _key(tosafot, 'תוספות על ברכות', order: 1);
  final directFoundation = _key(
    query,
    'ספר הזהר רמבם',
    tier: 6,
    order: 3,
    alias: false,
  );
  final keys = [
    mishnehTorah,
    onMishnah,
    directFoundation,
    indirectPrefix,
    indirectFoundation,
  ];

  test('בכינוי מדויק משותף ספר יסוד קודם לספר ששמו פותח בשאילתה', () {
    expect(
      compareFindRefRelevance(mishnehTorah, onMishnah, query),
      lessThan(0),
    );
    expect(
      compareFindRefRelevance(onMishnah, mishnehTorah, query),
      greaterThan(0),
    );
  });

  test('בלי כינוי מדויק התחלת השם עדיין קודמת ליסוד', () {
    expect(
      compareFindRefRelevance(indirectPrefix, indirectFoundation, query),
      lessThan(0),
    );
  });

  test('בשאילתה של שתי מילים הכלל אינו חל', () {
    final twoWords = FindRefRankQuery(['רמבם', 'שבת']);
    final otherHalacha = _key(
      twoWords,
      'משנה תורה הלכות ברכות',
      tier: 8,
      order: 0,
    );
    final mishnahShabbat = _key(twoWords, 'רמבם שבת על משנה', order: 1);
    expect(
      compareFindRefRelevance(mishnahShabbat, otherHalacha, twoWords),
      lessThan(0),
    );
  });

  test('ספר יסוד בשם ישיר שאינו כינוי לא עוקף התחלת שם', () {
    expect(
      compareFindRefRelevance(tosafotBerachot, zoharSection, tosafot),
      lessThan(0),
    );
  });

  test('ההשוואה טרנזיטיבית והמיון יציב בכל סדר קלט', () {
    for (final x in keys) {
      for (final y in keys) {
        final xy = compareFindRefRank(x, y, query);
        expect(xy, -compareFindRefRank(y, x, query));
        for (final z in keys) {
          if (xy <= 0 && compareFindRefRank(y, z, query) <= 0) {
            expect(compareFindRefRank(x, z, query), lessThanOrEqualTo(0));
          }
        }
      }
    }
    for (final input in [keys, keys.reversed.toList()]) {
      final ranked = List.of(input)
        ..sort((x, y) => compareFindRefRank(x, y, query));
      expect(ranked.map((k) => k.item), [
        mishnehTorah.item,
        onMishnah.item,
        directFoundation.item,
        indirectPrefix.item,
        indirectFoundation.item,
      ]);
    }
  });

  group('מסלול האיתור המלא', () {
    tearDown(resetSeededLibrary);

    test('"רמב"ם" מחזיר את משנה תורה לפני פירוש המשניות', () async {
      seedLibrary(
        const [
          (id: 556, title: 'רמב"ם על משנה ברכות', acronyms: ['רמב"ם']),
          (id: 308, title: 'משנה תורה, הלכות שבת', acronyms: ['רמב"ם']),
        ],
        categoryPaths: const {
          556: 'משנה, ראשונים, רמב"ם, סדר זרעים',
          308: 'הלכה, משנה תורה, ספר זמנים',
        },
      );
      for (final query in ['רמב"ם', 'רמבם']) {
        final results = await buildFindRefRepo().findRefs(query);
        expect(results.first.bookId, 308, reason: query);
      }
    });
  });
}
