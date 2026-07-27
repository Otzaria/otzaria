import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

/// כללי אות-החיבור בכותרת ב"איתור מקורות": כשכותרת הספר נושאת ה' הידיעה
/// ("הקדמת", "הרמב"ם") או ו' החיבור ("וברכת כהנים") והמשתמש לא הקליד אותה,
/// הטוקן עדיין נחשב חלק משם הספר ואינו נשלח לחיפוש הכותרות הפנימיות.
///
/// רץ על מסלול ההתאמה האמיתי; ראו [seeded_reference_library.dart].

// --- נתוני אמת מ-seforim.db ---

/// הכותרת מסתיימת ב"וברכת כהנים" — ו' החיבור באמצע הכותרת.
const _rambamTefila = (
  id: 302,
  title: 'משנה תורה, הלכות תפילה וברכת כהנים',
  acronyms: ['רמב"ם', 'רמב"ם הלכות תפילה וברכת כהנים', 'תפילה וברכת כהנים'],
);

/// שתי מילים עם ו' החיבור באותה כותרת ("ומזוזה", "וספר").
const _rambamTefilin = (
  id: 303,
  title: 'משנה תורה, הלכות תפילין ומזוזה וספר תורה',
  acronyms: ['רמב"ם', 'רמב"ם הלכות תפילין ומזוזה וספר תורה'],
);

const _rambamMelachim = (
  id: 379,
  title: 'משנה תורה, הלכות מלכים ומלחמות',
  acronyms: ['רמב"ם', 'רמב"ם הלכות מלכים ומלחמות', 'רמב"ם מלכים ומלחמות'],
);

/// ו' פותחת את הכותרת — חלק מהשם ("ויקרא"), לא אות חיבור.
const _vayikraRabba = (
  id: 258,
  title: 'ויקרא רבה',
  acronyms: ['ויק"ר', 'ויקרא רבא', 'רבה'],
);

/// שני טוקנים עם ה' הידיעה באותה כותרת ("הקדמת", "הרמב"ם").
const _hakdamatHaRambam = (
  id: 516,
  title: 'הקדמת הרמב"ם למשנה',
  acronyms: ['הקדמת הרמבם למשנה', 'קדמת רמבם למשנה', 'רמבם'],
);

/// ערך TOC שקיים גם כשהשאילתה מזהה את הספר במלואו — כדי לוודא שהוא *לא*
/// נשלף כשלא נותרו טוקנים לחיפוש פנימי.
const _tocFor302 = {
  302: [
    {
      'reference': 'משנה תורה, הלכות תפילה וברכת כהנים פרק ג',
      'segment': 30,
      'level': 2,
    },
  ],
};

void main() {
  tearDown(resetSeededLibrary);

  group('ו\' החיבור בכותרת נחשבת חלק משם הספר', () {
    test('"רמב"ם ברכת כהנים" מוצא את הלכות תפילה וברכת כהנים', () async {
      // הבאג: "ברכת" בשאילתה לא הותאם ל"וברכת" בכותרת, נשאר כטוקן לחיפוש
      // פנימי, ולא נמצאה לו כותרת פנימית — כך שהשאילתה לא החזירה כלום.
      seedLibrary(const [_rambamTefila]);
      final titles = (await buildFindRefRepo().findRefs(
        'רמב"ם ברכת כהנים',
      )).map((r) => r.title).toList();

      expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
    });

    test('גם מילה אחת בלי ו\' מזהה את הספר ("רמב"ם ברכת")', () async {
      seedLibrary(const [_rambamTefila]);
      final titles = (await buildFindRefRepo().findRefs(
        'רמב"ם ברכת',
      )).map((r) => r.title).toList();

      expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
    });

    test('הקלדה *עם* ו\' ובלעדיה מחזירות אותן תוצאות', () async {
      seedLibrary(const [_rambamTefila]);
      final withVav = await buildFindRefRepo().findRefs('רמב"ם וברכת כהנים');
      final without = await buildFindRefRepo().findRefs('רמב"ם ברכת כהנים');

      expect(withVav, isNotEmpty);
      expect(
        without.map((r) => r.reference).toList(),
        withVav.map((r) => r.reference).toList(),
      );
    });

    test('כמה מילות-ו\' באותה כותרת ("מזוזה", "ספר תורה")', () async {
      seedLibrary(const [_rambamTefilin]);
      final repo = buildFindRefRepo();

      for (final query in const [
        'רמב"ם מזוזה',
        'רמב"ם ספר תורה',
        'רמב"ם תפילין מזוזה ספר תורה',
      ]) {
        final titles = (await repo.findRefs(query)).map((r) => r.title);
        expect(
          titles,
          contains('משנה תורה, הלכות תפילין ומזוזה וספר תורה'),
          reason: 'השאילתה "$query" לא מצאה את הספר',
        );
      }
    });

    test('"רמב"ם מלחמות" מוצא את הלכות מלכים ומלחמות', () async {
      seedLibrary(const [_rambamMelachim]);
      final titles = (await buildFindRefRepo().findRefs(
        'רמב"ם מלחמות',
      )).map((r) => r.title).toList();

      expect(titles, contains('משנה תורה, הלכות מלכים ומלחמות'));
    });

    test('שאילתה שמזהה את הספר במלואו לא שולפת כותרות פנימיות', () async {
      seedLibrary(const [_rambamTefila]);
      final seen = <List<String>?>[];
      final results = await buildFindRefRepo(
        tocEntries: _tocFor302,
        tocQueryTokensSeen: seen,
      ).findRefs('רמב"ם ברכת כהנים');

      expect(seen, isEmpty, reason: 'לא נותרו טוקנים לחיפוש פנימי');
      expect(
        results.map((r) => r.reference),
        contains('משנה תורה, הלכות תפילה וברכת כהנים'),
      );
    });
  });

  group('גבולות הכלל — מה *לא* נבלע', () {
    test('ו\' שפותחת את הכותרת אינה אות חיבור ("ויקרא" ≠ "יקרא")', () async {
      // "ויקרא" הוא שם, ולכן "יקרא" נשאר טוקן לחיפוש פנימי. אם ו' הייתה
      // נבלעת גם בטוקן הפותח, הספר היה מוחזר כתוצאת-ספר וחוסם את הערך הפנימי.
      seedLibrary(const [_vayikraRabba]);
      final seen = <List<String>?>[];
      final results = await buildFindRefRepo(
        tocQueryTokensSeen: seen,
        tocEntries: const {
          258: [
            {'reference': 'ויקרא רבה פרשה ב', 'segment': 20, 'level': 2},
          ],
        },
      ).findRefs('יקרא רבה');

      expect(
        seen.any((t) => t != null && t.contains('יקרא')),
        isTrue,
        reason: '"יקרא" חייב להישאר לחיפוש הכותרות הפנימיות',
      );
      expect(results.map((r) => r.reference), contains('ויקרא רבה פרשה ב'));
    });

    test('טוקן מיקום של אות בודדת לא נבלע ע"י מילת-ו\' בכותרת', () async {
      // "וברכת" באורך 6 — השארית "ברכת" ≠ "ב". הדרישה לאורך >= 3 בטוקן
      // הכותרת מבטיחה שארית באורך >= 2, כך שסימון מיקום נשאר לחיפוש הפנימי.
      seedLibrary(const [_rambamTefila]);
      final seen = <List<String>?>[];
      final results = await buildFindRefRepo(
        tocQueryTokensSeen: seen,
        tocEntries: const {
          302: [
            {
              'reference': 'משנה תורה, הלכות תפילה וברכת כהנים פרק ב',
              'segment': 20,
              'level': 2,
            },
          ],
        },
      ).findRefs('רמב"ם תפילה ב');

      expect(
        seen.any((t) => t != null && t.length == 1 && t.first == 'ב'),
        isTrue,
        reason: 'טוקן המיקום "ב" חייב להישאר לחיפוש הפנימי',
      );
      expect(
        results.map((r) => r.reference),
        contains('משנה תורה, הלכות תפילה וברכת כהנים פרק ב'),
      );
    });

    test('טוקן סעיף רגיל עדיין נשלח לחיפוש הפנימי', () async {
      seedLibrary(const [_rambamTefila]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(tocQueryTokensSeen: seen).findRefs('רמב"ם ברכת ג');

      expect(
        seen.any((t) => t != null && t.length == 1 && t.first == 'ג'),
        isTrue,
        reason: '"ברכת" נבלע לשם הספר, "ג" נשאר סעיף',
      );
    });
  });

  group('ה\' הידיעה — הכלל הקיים נשמר', () {
    test('"קדמת רמב"ם" מזהה את "הקדמת הרמב"ם למשנה" (ה\' בשני '
        'טוקנים)', () async {
      seedLibrary(const [_hakdamatHaRambam]);
      final seen = <List<String>?>[];
      final titles = (await buildFindRefRepo(
        tocQueryTokensSeen: seen,
      ).findRefs('קדמת רמב"ם')).map((r) => r.title).toList();

      expect(titles, contains('הקדמת הרמב"ם למשנה'));
      expect(seen, isEmpty, reason: 'שני הטוקנים נבלעו לשם הספר');
    });

    test('ה\' נבלעת גם בטוקן הפותח את הכותרת', () async {
      seedLibrary(const [_hakdamatHaRambam]);
      final titles = (await buildFindRefRepo().findRefs(
        'קדמת למשנה',
      )).map((r) => r.title).toList();

      expect(titles, contains('הקדמת הרמב"ם למשנה'));
    });
  });

  group('אות-חיבור בזנב ראש-התיבות', () {
    // ראשי-התיבות ב-DB נכתבים לעתים בלי אות-החיבור שבכותרת, ולכן הזנב שאחרי
    // השאילתה לא הותאם לכותרת, ה-hit לא סומן כ"מזהה את הספר במלואו" ונדחה —
    // בזמן שכל שאר הספרים מאותה משפחה כן הוחזרו.
    test(
      '"ברכת אברהם משנה" מחזיר גם את "שופר וסוכה ולולב" (ו\' בזנב)',
      () async {
        seedLibrary(const [
          // ראש-תיבות מדויק לשאילתה — הוא זה שעוצר את החיפוש בשלב הזה.
          (
            id: 5147,
            title: 'ברכת אברהם על משנה תורה, הלכות תפילין ומזוזה וספר תורה',
            acronyms: ['ברכת אברהם משנה', 'ברכת אברהם משנה תורה'],
          ),
          // זנב ("תורה") שמותאם לכותרת ישירות — עבד גם קודם.
          (
            id: 5149,
            title: 'ברכת אברהם על משנה תורה, הלכות תפילה וברכת כהנים',
            acronyms: [
              'ברכת אברהם משנה תורה',
              'ברכת אברהם משנה תורה הלכות תפילה וברכת כהנים',
            ],
          ),
          // זנב שמותאם רק דרך ו' החיבור: "סוכה" מול "וסוכה" בכותרת.
          (
            id: 5156,
            title: 'ברכת אברהם על משנה תורה, הלכות שופר וסוכה ולולב',
            acronyms: [
              'ברכת אברהם משנה תורה שופר סוכה ולולב',
              'ברכת אברהם שופר וסוכה ולולב',
            ],
          ),
        ]);

        final titles = (await buildFindRefRepo().findRefs(
          'ברכת אברהם משנה',
        )).map((r) => r.title).toSet();

        expect(
          titles,
          containsAll(<String>[
            'ברכת אברהם על משנה תורה, הלכות תפילין ומזוזה וספר תורה',
            'ברכת אברהם על משנה תורה, הלכות תפילה וברכת כהנים',
            'ברכת אברהם על משנה תורה, הלכות שופר וסוכה ולולב',
          ]),
        );
      },
    );

    test('"ספר מצוות" מחזיר גם את "ספר המצות הקצר" (ה\' בזנב)', () async {
      seedLibrary(const [
        // כותרות שמתחילות בשאילתה — הן ה-primary שעוצר את החיפוש.
        (id: 3889, title: 'ספר מצוות קטן', acronyms: ['סמ"ק']),
        (id: 3877, title: 'ספר מצוות גדול', acronyms: ['סמ"ג']),
        // הזנב "קצר" מותאם לכותרת רק דרך ה' הידיעה שב"הקצר".
        (
          id: 3885,
          title: 'ספר המצות הקצר',
          acronyms: ['ספר המצוות הקצר', 'ספר מצוות קצר'],
        ),
      ]);

      final titles = (await buildFindRefRepo().findRefs(
        'ספר מצוות',
      )).map((r) => r.title).toSet();

      expect(titles, contains('ספר מצוות קטן'));
      expect(titles, contains('ספר המצות הקצר'));
    });

    test('זנב שאינו מילת-כותרת עדיין אינו מזהה את הספר במלואו', () async {
      // "טור חושן" ⊂ "טור חושן משפט": "משפט" אינה בכותרת "טור" ואינה שארית של
      // מילת-כותרת, ולכן הסלחנות אינה מרחיבה אותו.
      seedLibrary(const [
        (id: 380, title: 'טור', acronyms: ['הטור', 'טור חושן משפט']),
      ]);
      final hit = ReferenceBooksCache.instance.search('טור חושן').single;

      expect(hit.matchRank, 4);
      expect(hit.acronymTailIsTitleWords, isFalse);
    });

    test('search מסמן acronymTailIsTitleWords כשהזנב מותאם דרך ו\'', () {
      seedLibrary(const [
        (
          id: 5224,
          title: 'השגות הראב"ד על משנה תורה, הלכות תפילה וברכת כהנים',
          acronyms: ['ראב"ד', 'ראב"ד על הרמב"ם הלכות ברכת כהנים'],
        ),
      ]);
      final hit = ReferenceBooksCache.instance.search('ראב"ד על הרמב"ם').single;

      expect(hit.matchRank, 4);
      expect(hit.acronymTailIsTitleWords, isTrue);
    });
  });

  group('תקרת חיפושי ה-TOC', () {
    test('ספר שהותאם דרך ו\' החיבור לא נחתך ע"י תקרת 50 החיפושים', () async {
      // 60 ספרים חולקים את ראש-התיבות "רמב"ם" והספר המכוון אחרון בסדר
      // הספרייה. בלי התאמת ו' ב-_prioritizeByTitleCoverage הוא היה מקבל ציון
      // כיסוי 0, נשאר במקום ה-61, והתקרה הייתה מונעת ממנו חיפוש TOC.
      seedLibrary([
        for (var i = 0; i < 60; i++)
          (
            id: 9000 + i,
            title: 'ספר מלית מספר $i',
            acronyms: const ['רמב"ם'],
          ),
        _rambamTefila,
      ]);

      final seen = <List<String>?>[];
      final results = await buildFindRefRepo(
        tocQueryTokensSeen: seen,
        tocEntries: const {
          302: [
            {
              'reference': 'משנה תורה, הלכות תפילה וברכת כהנים פרק ג',
              'segment': 30,
              'level': 2,
            },
          ],
        },
      ).findRefs('רמב"ם ברכת ג');

      expect(seen.length, lessThanOrEqualTo(50));
      expect(
        results.map((r) => r.reference),
        contains('משנה תורה, הלכות תפילה וברכת כהנים פרק ג'),
        reason: 'הספר המכוון חייב להיבדק בתוך התקרה',
      );
    });
  });
}
