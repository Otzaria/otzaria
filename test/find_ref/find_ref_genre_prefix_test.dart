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
    (id: 3901, title: 'ב"ח', acronyms: []),
    (
      id: 2321,
      title: 'הגהות הב"ח על רי"ף תענית',
      acronyms: ['תשובות הבח על רי"ף תענית'],
    ),
    (id: 2325, title: 'הגהות הב"ח על רי"ף מכות', acronyms: ['הבח']),
    (
      id: 5797,
      title: 'תשובות בית חדש',
      acronyms: ['שו"ת בית חדש', 'תשובות בח'],
    ),
    (
      id: 5786,
      title: 'תשובות הרדב"ז חלק ה',
      acronyms: ['שות רדבז ח ה', 'תשובות רדבז חלק ה'],
    ),
    (id: 5788, title: 'תשובות הרדב"ז חלק ד', acronyms: []),
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

  // issue #5504
  test('"שו"ת" מאתר ספר שבשמו ובכינויו "תשובות"', () async {
    seedLibrary(books);
    final repo = buildFindRefRepo();
    for (final query in ['שו"ת הב"ח', 'שו"ת ב"ח']) {
      final refs = await repo.findRefs(query);
      expect(
        refs.map((r) => r.reference),
        ['תשובות בית חדש'],
        reason: query,
      );
    }
  });

  test('"תשובות" לא גובר על כינוי מדויק של כל השאילתה עם "שו"ת"', () async {
    seedLibrary(books);
    final refs = await buildFindRefRepo().findRefs('שו"ת רדבז ח ה');

    expect(refs.first.reference, 'תשובות הרדב"ז חלק ה');
  });

  test(
    '"תשובות" בלי הקידומת אינו מצטמצם לחלקים שיש להם כינוי "שו"ת"',
    () async {
      seedLibrary(const [
        (id: 6197, title: 'אבני נזר אבן העזר', acronyms: []),
        (id: 6198, title: 'אבני נזר אורח חיים', acronyms: []),
        (
          id: 6199,
          title: 'אבני נזר חושן משפט',
          acronyms: ['שו"ת אבני נזר', 'שו"ת אבני נזר חו"מ'],
        ),
        (
          id: 6200,
          title: 'אבני נזר יורה דעה',
          acronyms: ['שו"ת אבני נזר יו"ד'],
        ),
      ]);
      final refs = await buildFindRefRepo().findRefs('תשובות אבני נזר');

      expect(refs.map((r) => r.reference), hasLength(4));
    },
  );

  test('"תשובות" לא גובר על כינוי "שו"ת" שעוד מוקלד', () async {
    seedLibrary(const [
      (id: 5782, title: 'תשובות רבי עקיבא איגר החדשות', acronyms: ['שות רעקא']),
      (
        id: 5801,
        title: 'תשובות רבי עקיבא איגר תניינא',
        acronyms: ['שו"ת רע"א תנינא', 'תשובות רעא תניינא'],
      ),
      (id: 5807, title: 'תשובות רבי עקיבא איגר', acronyms: ['תשובות רעא']),
    ]);
    final refs = await buildFindRefRepo().findRefs('שו"ת רעא תני');

    expect(refs.first.reference, 'תשובות רבי עקיבא איגר תניינא');
  });
}
