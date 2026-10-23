import 'package:flutter_test/flutter_test.dart';

import 'support/seeded_reference_library.dart';

/// issue #2707 — "שו"ת פנים מאירות חלק א סי' מז": רוב ספרי השו"ת אינם נושאים
/// "שו"ת" בשמם, והקידומת לבדה זוהתה כשם ספר.
void main() {
  tearDown(resetSeededLibrary);

  const books = <SeedBook>[
    (id: 6328, title: 'פנים מאירות חלק א', acronyms: []),
    (id: 5730, title: 'שו"ת מהרי"ל', acronyms: []),
    (id: 6371, title: 'שות מהראל צינץ', acronyms: []),
    (id: 6361, title: 'שות בית דוד', acronyms: []),
    (id: 6225, title: 'בית הלוי חלק א', acronyms: []),
  ];

  test('קידומת "שו"ת" שאינה בשם הספר נשמטת מזיהוי הספר', () async {
    seedLibrary(books);
    final seen = <List<String>?>[];
    final refs = await buildFindRefRepo(
      tocQueryTokensSeen: seen,
      tocEntries: {
        6328: [
          {
            'reference': 'פנים מאירות חלק א שאלה מז',
            'segment': 354,
            'level': 2,
          },
        ],
      },
    ).findRefs('שו"ת פנים מאירות חלק א סי\' מז');

    expect(refs.first.reference, 'פנים מאירות חלק א שאלה מז');
    expect(seen.single, ['סי', 'מז']);
  });

  test('ספר ששמו פותח ב"שו"ת" מזוהה עם הקידומת', () async {
    seedLibrary(books);
    final seen = <List<String>?>[];
    final refs = await buildFindRefRepo(
      tocQueryTokensSeen: seen,
      tocEntries: {
        5730: [
          {'reference': 'שו"ת מהרי"ל תשובה ה', 'segment': 216, 'level': 1},
        ],
      },
    ).findRefs('שו"ת מהרי"ל סימן ה');

    expect(refs.first.reference, 'שו"ת מהרי"ל תשובה ה');
    expect(seen.first, ['סימן', 'ה']);
  });

  test('הקידומת נשמטת גם כשהיא ומילה אחריה פותחות שם של ספר אחר', () async {
    seedLibrary(books);
    final refs = await buildFindRefRepo(
      tocEntries: {
        6225: [
          {'reference': 'בית הלוי חלק א סימן ב', 'segment': 24, 'level': 2},
        ],
      },
    ).findRefs('שו"ת בית הלוי חלק א סימן ב');

    expect(refs.first.reference, 'בית הלוי חלק א סימן ב');
  });
}
