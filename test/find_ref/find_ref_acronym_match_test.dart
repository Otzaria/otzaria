import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import 'support/seeded_reference_library.dart';

/// התאמת ספר לפי ראשי-תיבות ב"איתור מקורות" — במיוחד שאילתה שהיא *תחילית*
/// של ראש-תיבות ארוך יותר. רץ על מסלול ההתאמה האמיתי; ראו
/// [seeded_reference_library.dart].

// --- נתוני אמת מ-seforim.db (ראשי-התיבות בסדר הטעינה: ORDER BY term) ---

const _rambamTefila = (
  id: 302,
  title: 'משנה תורה, הלכות תפילה וברכת כהנים',
  acronyms: [
    'משנ"ת',
    'משנ"ת הלכות תפילה וברכת כהנים',
    'משנ"ת תפילה וברכת כהנים',
    'רמב"ם',
    'רמב"ם הל\' תפילה וברכת כהנים',
    'רמב"ם הלכות תפילה וברכת כהנים',
    'רמב"ם תפילה וברכת כהנים',
    'תפילה וברכת כהנים',
  ],
);

const _rambamSederTefila = (
  id: 307,
  title: 'משנה תורה, סדר התפילה',
  acronyms: [
    'משנ"ת הלכות תפילה',
    'משנ"ת תפילה',
    'משנה תורה הלכות תפילה',
    'רמב"ם',
    'רמב"ם הל\' תפילה',
    'רמב"ם הלכות תפילה',
    'רמב"ם תפילה',
  ],
);

const _tur = (
  id: 380,
  title: 'טור',
  acronyms: [
    'ארבעה טורים',
    'הטור',
    'טור או"ח',
    'טור חו"מ',
    'טור חושן משפט',
    'טור יו"ד',
    'טור יורה דעה',
  ],
);

const _rashiBereshit = (
  id: 3695,
  title: 'רש"י על בראשית',
  acronyms: ['רש"י', 'רש"י על ספר בראשית', 'רשי על בראשית'],
);

const _rashiBereshitRabba = (
  id: 3113,
  title: 'רש"י על בראשית רבה',
  acronyms: ['רש"י בראשית רבה', 'רשי על בראשית רבה'],
);

void main() {
  tearDown(resetSeededLibrary);

  group('findRefs — כתיב מלא וחסר (issue #1310)', () {
    test('"רמב״ם תפלה" מחזיר גם את הלכות תפילה, לא רק את סדר התפילה', () async {
      // ל"סדר התפילה" יש כינוי בכתיב חסר ("רמב״ם תפלה"), ולהלכות תפילה רק
      // כינויים בכתיב מלא — ולכן הכתיב החסר החזיר את הספר הלא נכון לבדו.
      seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final titles = (await buildFindRefRepo().findRefs(
        'רמב״ם תפלה',
      )).map((r) => r.title).toList();

      expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
    });

    test('"חדושי" מוצא ספר שכתוב "חידושי", ולהיפך', () async {
      seedLibrary(const [
        (id: 9001, title: 'חידושי הלכות', acronyms: []),
        (id: 9002, title: 'חדושי אגדות', acronyms: []),
      ]);
      final repo = buildFindRefRepo();
      expect(
        (await repo.findRefs('חדושי')).map((r) => r.title),
        contains('חידושי הלכות'),
      );
      expect(
        (await buildFindRefRepo().findRefs('חידושי')).map((r) => r.title),
        contains('חדושי אגדות'),
      );
    });

    test(
      'אותה מילה אחרי טעינה מחדש של הספרייה מוצאת את הספרים החדשים',
      () async {
        // מסננת אוצר-המילים ממטמנת את הספרים לכל מילת שאילתה. מטמון ששרד
        // טעינה מחדש היה משבית את ההתאמה המקורבת בשקט.
        seedLibrary(const [(id: 9001, title: 'חידושי הלכות', acronyms: [])]);
        expect(
          (await buildFindRefRepo().findRefs('חדושי')).map((r) => r.title),
          contains('חידושי הלכות'),
        );

        resetSeededLibrary();
        seedLibrary(const [(id: 9002, title: 'חידושי אגדות', acronyms: [])]);
        expect(
          (await buildFindRefRepo().findRefs('חדושי')).map((r) => r.title),
          contains('חידושי אגדות'),
        );
      },
    );
  });

  group('findRefs — ראש-תיבות שהוא תחילית של ראש-תיבות ארוך יותר', () {
    test('"רמב״ם תפילה" מחזיר גם את הלכות תפילה וברכת כהנים וגם את סדר '
        'התפילה', () async {
      // הבאג המדווח: ל"משנה תורה, סדר התפילה" יש ראש-תיבות *מדויק* "רמב"ם תפילה"
      // (rank 3), ולכן החיפוש נעצר עליו; "משנה תורה, הלכות תפילה וברכת כהנים"
      // הותאם רק כתחילית של "רמב"ם תפילה וברכת כהנים" (rank 4) ונזרק כליל.
      seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final results = await buildFindRefRepo().findRefs('רמב״ם תפילה');
      final titles = results.map((r) => r.title).toList();

      expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
      expect(titles, contains('משנה תורה, סדר התפילה'));
    });

    test('גרשיים יוניקוד (״) וגרשיים ASCII (") מחזירים אותן תוצאות', () async {
      seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final unicode = await buildFindRefRepo().findRefs('רמב״ם תפילה');
      final ascii = await buildFindRefRepo().findRefs('רמב"ם תפילה');

      expect(
        ascii.map((r) => r.reference).toList(),
        unicode.map((r) => r.reference).toList(),
      );
    });

    test('כל ספרי "חידושי רע"א" מוחזרים, לא רק זה שיש לו ראש-התיבות '
        'המדויק', () async {
      // ל"על מסכת תענית" יש ראש-תיבות מדויק "חידושי רע"א"; לשאר הספרים יש רק
      // ראשי-תיבות ארוכים יותר שהשאילתה היא תחילית שלהם.
      seedLibrary(const [
        (
          id: 2661,
          title: 'חידושי רבי עקיבא איגר על מסכת תענית',
          acronyms: [
            'חידושי רבי עקיבא איגר תענית',
            'חידושי רע"א',
            'חידושי רע"א על תענית',
            'חידושי רעא על מסכת תענית',
          ],
        ),
        (
          id: 2667,
          title: 'חידושי רבי עקיבא איגר על מסכת ראש השנה',
          acronyms: [
            'חידושי רע"א ראש השנה',
            'חידושי רעא על מסכת ראש השנה',
            'חידושי רעא על ראש השנה',
          ],
        ),
        (
          id: 4429,
          title: 'חידושי רבי עקיבא איגר על משנה תורה, הלכות יסודי התורה',
          acronyms: [
            'חידושי רבי עקיבא איגר יסודי התורה',
            'חידושי רעא על משנה תורה, הלכות יסודי התורה',
          ],
        ),
      ]);

      final titles = (await buildFindRefRepo().findRefs(
        'חידושי רע"א',
      )).map((r) => r.title).toSet();

      expect(titles, contains('חידושי רבי עקיבא איגר על מסכת תענית'));
      expect(titles, contains('חידושי רבי עקיבא איגר על מסכת ראש השנה'));
      expect(
        titles,
        contains('חידושי רבי עקיבא איגר על משנה תורה, הלכות יסודי התורה'),
      );
    });

    test('"רש"י בראשית" לא מוסתר ע"י "רש"י על בראשית רבה"', () async {
      // ל"בראשית רבה" יש ראש-תיבות "רש"י בראשית רבה" שהשאילתה היא תחילית שלו
      // וזנבו ("רבה") הוא מילת-כותרת. הקבלה שלו אסור לה לעצור את החיפוש בשלב
      // הזה — "רש"י על בראשית" נמצא רק בשלב של טוקן אחד ("רש"י" + "בראשית"
      // מהכותרת), והיה נעלם.
      seedLibrary(const [_rashiBereshit, _rashiBereshitRabba]);
      final titles = (await buildFindRefRepo().findRefs(
        'רש"י בראשית',
      )).map((r) => r.title).toList();

      expect(titles, contains('רש"י על בראשית'));
      expect(titles, contains('רש"י על בראשית רבה'));
    });

    test(
      '"טור חושן" עדיין יורד לכותרות הפנימיות ולא הופך לתוצאת-ספר',
      () async {
        // "טור חושן" הוא תחילית של ראש-התיבות "טור חושן משפט", אבל "משפט" אינה
        // מילה בכותרת "טור" — כלומר ההמשך הוא כותרת פנימית. אם הספר היה מוחזר
        // כתוצאת-ספר, ה-reference הקצר ("טור") היה גם *חוסם* את התוצאה הפנימית
        // ב-_suppressDeeperVariants.
        seedLibrary(const [_tur]);
        final seen = <List<String>?>[];
        final results = await buildFindRefRepo(
          tocQueryTokensSeen: seen,
          tocEntries: const {
            380: [
              {'reference': 'טור חושן משפט', 'segment': 5, 'level': 1},
            ],
          },
        ).findRefs('טור חושן');

        expect(
          seen.any((t) => t != null && t.length == 1 && t.first == 'חושן'),
          isTrue,
          reason: 'ה-TOC חייב להיחפש לפי טוקן הסעיף "חושן"',
        );
        expect(results.map((r) => r.reference), contains('טור חושן משפט'));
        expect(
          results.map((r) => r.reference),
          isNot(contains('טור')),
          reason: 'תוצאת-ספר קצרה הייתה חוסמת את התוצאה הפנימית',
        );
      },
    );

    test('"טור אורח חיים יב" — שם החלק המלא מגיע לחיפוש ה-TOC', () async {
      // ל"אורח חיים" אין ראש-תיבות מאוית ב-DB (רק "טור או״ח"), ולכן השאילתה
      // יורדת ל-"טור" בלבד ושתי מילות החלק נשארות לחיפוש הפנימי.
      seedLibrary(const [_tur]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(
        tocQueryTokensSeen: seen,
      ).findRefs('טור אורח חיים יב');

      expect(
        seen.any((t) => listEquals(t, const ['אורח', 'חיים', 'יב'])),
        isTrue,
      );
    });

    test('"טור יורה דעה יב" — שם החלק מגיע לחיפוש ה-TOC ולא נבלע', () async {
      // "טור יורה דעה" הוא ראש-תיבות *מלא* של הספר "טור" (rank 3), אבל
      // "יורה דעה" הוא חלק פנימי שלו. בליעת שלושת הטוקנים השאירה רק "יב",
      // שנחפש משורש ה-TOC (שם יושבים שמות החלקים) ולכן לא נמצא כלל.
      seedLibrary(const [_tur]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(
        tocQueryTokensSeen: seen,
      ).findRefs('טור יורה דעה יב');

      expect(
        seen.any((t) => listEquals(t, const ['יורה', 'דעה', 'יב'])),
        isTrue,
        reason: 'ה-TOC חייב להיחפש עם שם החלק, לא רק עם "יב"',
      );
    });

    test('"טור יו״ד יב" — ראש-התיבות של החלק מגיע לחיפוש ה-TOC', () async {
      seedLibrary(const [_tur]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(tocQueryTokensSeen: seen).findRefs('טור יו"ד יב');

      expect(
        seen.any((t) => listEquals(t, const ['יוד', 'יב'])),
        isTrue,
        reason: '"יו״ד" מזהה את החלק "יורה דעה" ולכן חייב להישלח ל-TOC',
      );
    });

    test('ראש-תיבות שכולו שם הספר אינו מוסיף טוקני-חלק', () async {
      // "שוע אוח" מזהה את *כותרת* הספר במלואה — אין כאן חלק פנימי, ולכן
      // חיפוש ה-TOC נשאר על טוקן הסימן בלבד.
      seedLibrary(const [
        (
          id: 2,
          title: 'שולחן ערוך אורח חיים',
          acronyms: ['שו"ע או"ח', 'שו"ע'],
        ),
      ]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(tocQueryTokensSeen: seen).findRefs('שו"ע או"ח יב');

      expect(seen, isNotEmpty);
      for (final tokens in seen) {
        expect(tokens, equals(const ['יב']));
      }
    });

    test(
      'שאילתת מילה אחת ("רמב"ם") מחזירה את כל הספרים בלי חיפוש TOC',
      () async {
        seedLibrary(const [_rambamTefila, _rambamSederTefila]);
        final seen = <List<String>?>[];
        final titles = (await buildFindRefRepo(
          tocQueryTokensSeen: seen,
        ).findRefs('רמב"ם')).map((r) => r.title).toSet();

        expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
        expect(titles, contains('משנה תורה, סדר התפילה'));
        expect(seen, isEmpty);
      },
    );
  });

  group('ReferenceBooksCache.search — דירוג התאמת ראשי תיבות', () {
    test('ראש-תיבות מדויק מקבל rank 3', () {
      seedLibrary(const [_rambamSederTefila]);
      final hit = ReferenceBooksCache.instance.search('רמב"ם תפילה').single;

      expect(hit.bookId, 307);
      expect(hit.matchRank, 3);
    });

    test('שאילתה בת תו אחד עדיין מתאימה לפי ראש-תיבות', () {
      // מסננת הביגרמים אינה חלה על שאילתה קצרה מ-2 תווים, ולולאת הביטויים
      // ב-findRefs יורדת עד טוקן בודד — אסור שהמסננת תחסום אותו.
      seedLibrary(const [
        (id: 401, title: 'שולחן ערוך אורח חיים', acronyms: ['ק']),
      ]);
      final hit = ReferenceBooksCache.instance.search('ק').single;

      expect(hit.bookId, 401);
      expect(hit.matchRank, 3);
    });

    test('תחילית שכל זנבה מילות-כותרת → rank 4 עם '
        'acronymTailIsTitleWords', () async {
      seedLibrary(const [_rambamTefila]);
      final hit = ReferenceBooksCache.instance.search('רמב"ם תפילה').single;

      expect(hit.matchRank, 4);
      expect(
        hit.matchedTerm,
        normalizeForFindRefMatch('רמב"ם תפילה וברכת כהנים'),
      );
      expect(hit.acronymTailIsTitleWords, isTrue);
    });

    test('תחילית שזנבה כותרת פנימית → rank 4 בלי '
        'acronymTailIsTitleWords', () {
      seedLibrary(const [_tur]);
      final hit = ReferenceBooksCache.instance.search('טור חושן').single;

      expect(hit.matchRank, 4);
      expect(hit.acronymTailIsTitleWords, isFalse);
    });

    test('התאמת התחילית נמדדת במילים שלמות — "רמב"ם תפיל" אינו זיהוי '
        'מלא', () {
      seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final hits = ReferenceBooksCache.instance.search('רמב"ם תפיל');

      expect(hits, isNotEmpty);
      for (final hit in hits) {
        expect(hit.acronymTailIsTitleWords, isFalse, reason: hit.title);
      }
    });

    test('מונח "contains" שנסרק ראשון אינו מקבע rank 5 ומונע את התאמת '
        'התחילית', () {
      // ל"הלכות יסודי התורה" יש גם ראש-תיבות עם ו' החיבור ("ורמב"ם יסודי
      // התורה") שנסרק ראשון ורק *מכיל* את השאילתה, וגם "רמב"ם יסודי התורה"
      // שהוא תחילית אמיתית שלה.
      seedLibrary(const [
        (
          id: 296,
          title: 'משנה תורה, הלכות יסודי התורה',
          acronyms: [
            'ורמב"ם הלכות יסודי התורה',
            'ורמב"ם יסודי התורה',
            'רמב"ם הל\' יסודי התורה',
            'רמב"ם הלכות יסודי התורה',
            'רמב"ם יסודי התורה',
          ],
        ),
      ]);
      final hit = ReferenceBooksCache.instance.search('רמב"ם יסודי').single;

      expect(hit.matchRank, 4);
      expect(hit.acronymTailIsTitleWords, isTrue);
    });
  });
}
