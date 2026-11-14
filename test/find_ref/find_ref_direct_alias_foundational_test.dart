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
  final query = FindRefRankQuery(['רמבם'], aliasFoundationalTiers: {9});
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
  final withoutAlias = _key(
    query,
    'משנה תורה הלכות תפילה',
    tier: 9,
    order: 4,
    alias: false,
  );
  final keys = [
    withoutAlias,
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

  test('ספרים באותה קבוצת יסוד נשארים בסדר הספרייה גם בלי כינוי', () {
    expect(
      compareFindRefRelevance(withoutAlias, mishnehTorah, query),
      lessThan(0),
    );
    expect(
      compareFindRefRelevance(mishnehTorah, withoutAlias, query),
      greaterThan(0),
    );
    expect(
      compareFindRefRelevance(withoutAlias, directFoundation, query),
      lessThan(0),
    );
  });

  test('בלי כינוי מדויק התחלת השם עדיין קודמת ליסוד', () {
    expect(
      compareFindRefRelevance(indirectPrefix, indirectFoundation, query),
      lessThan(0),
    );
  });

  test('בשאילתה של שתי מילים הכלל אינו חל', () {
    final twoWords = FindRefRankQuery(
      ['רמבם', 'שבת'],
      aliasFoundationalTiers: {8},
    );
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
        withoutAlias.item,
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
    test('כינויים חלקיים אינם משנים את סדר המשנה או את גבול המכסה', () async {
      final books = <SeedBook>[
        for (var i = 0; i < 22; i++)
          (id: i + 1, title: 'משנה מסכת $i', acronyms: i >= 20 ? ['משנה'] : []),
      ];
      seedLibrary(
        books,
        categoryPaths: {
          for (final book in books) book.id: 'משנה, סדר מועד',
        },
      );
      final results = await buildFindRefRepo().findRefs('משנה');
      expect(results.map((r) => r.bookId), List.generate(20, (i) => i + 1));
    });

    test('כינויים חלקיים משאירים את מסכתות הירושלמי יחד לפני הביאור', () async {
      final books = <SeedBook>[
        (id: 100, title: 'ירושלמי מבואר ומפורש על ברכות', acronyms: []),
        for (var i = 0; i < 22; i++)
          (
            id: i + 1,
            title: 'תלמוד ירושלמי מסכת $i',
            acronyms: i >= 20 ? ['ירושלמי'] : [],
          ),
      ];
      seedLibrary(
        books,
        categoryPaths: {
          100: 'תלמוד ירושלמי, מחברי זמננו',
          for (final book in books.skip(1)) book.id: 'תלמוד ירושלמי, סדר זרעים',
        },
      );
      final results = await buildFindRefRepo().findRefs('ירושלמי');
      expect(
        results.take(20).map((r) => r.bookId),
        List.generate(20, (i) => i + 1),
      );
    });

    test(
      'כינויים חלקיים אינם מקדימים חושן משפט לשאר חלקי שולחן ערוך',
      () async {
        seedLibrary(
          const [
            (
              id: 382,
              title: 'שולחן ערוך, אורח חיים',
              acronyms: ['שוע אורח חיים'],
            ),
            (
              id: 383,
              title: 'שולחן ערוך, יורה דעה',
              acronyms: ['שוע יורה דעה'],
            ),
            (
              id: 384,
              title: 'שולחן ערוך, אבן העזר',
              acronyms: ['שוע אבן העזר'],
            ),
            (
              id: 385,
              title: 'שולחן ערוך, חושן משפט',
              acronyms: ['שוע', 'שוע חומ'],
            ),
          ],
          categoryPaths: const {
            382: 'הלכה, שולחן ערוך',
            383: 'הלכה, שולחן ערוך',
            384: 'הלכה, שולחן ערוך',
            385: 'הלכה, שולחן ערוך',
          },
        );
        final results = await buildFindRefRepo().findRefs('שוע');
        expect(results.map((r) => r.bookId), [382, 383, 384, 385]);
        final specific = await buildFindRefRepo().findRefs('שוע יורה דעה');
        expect(specific.first.bookId, 383);
      },
    );
  });
}
