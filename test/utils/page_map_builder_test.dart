import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/page_map_builder.dart';

void main() {
  // ---------------------------------------------------------------------------
  // normalizeRef
  // ---------------------------------------------------------------------------
  group('normalizeRef', () {
    test('lowercases and trims', () {
      expect(normalizeRef('  Hello  '), 'hello');
    });

    test('collapses multiple spaces', () {
      expect(normalizeRef('a  b'), 'a b');
    });

    test('keeps slashes, dots, dashes', () {
      expect(normalizeRef('ברכות/ב.'), 'ברכות/ב.');
    });

    test('strips colons (amud-bet marker)', () {
      expect(normalizeRef('ב:'), 'ב');
    });

    test('strips other punctuation', () {
      expect(normalizeRef('ב"מ'), 'במ');
    });
  });

  // ---------------------------------------------------------------------------
  // hebrewNumeralValue – השומר שמונע ממילים להתחזות למספרי דף
  // ---------------------------------------------------------------------------
  group('hebrewNumeralValue', () {
    test('אות בודדת', () {
      expect(hebrewNumeralValue('א'), 1);
      expect(hebrewNumeralValue('ב'), 2);
      expect(hebrewNumeralValue('י'), 10);
      expect(hebrewNumeralValue('ת'), 400);
    });

    test('מספרים מורכבים בסדר יורד', () {
      expect(hebrewNumeralValue('כב'), 22);
      expect(hebrewNumeralValue('יא'), 11);
      expect(hebrewNumeralValue('טו'), 15);
      expect(hebrewNumeralValue('טז'), 16);
      expect(hebrewNumeralValue('קיז'), 117);
      expect(hebrewNumeralValue('תתקא'), 901);
    });

    test('אותיות סופיות מקבלות את אותו ערך', () {
      expect(hebrewNumeralValue('ך'), 20);
      expect(hebrewNumeralValue('ם'), 40);
      expect(hebrewNumeralValue('ן'), 50);
      expect(hebrewNumeralValue('ף'), 80);
      expect(hebrewNumeralValue('ץ'), 90);
    });

    test('ערכים עולים נדחים — אינם כתיב גימטריה', () {
      expect(hebrewNumeralValue('בכ'), isNull);
      expect(hebrewNumeralValue('אי'), isNull);
    });

    test('שמות מסכתות נדחים ואינם מתחזים למספרי דף', () {
      for (final name in ['שבת', 'נדה', 'סוכה', 'ביצה', 'יומא', 'סוטה']) {
        expect(hebrewNumeralValue(name), isNull, reason: name);
      }
    });

    test('מעל ארבע אותיות נדחה', () {
      expect(hebrewNumeralValue('הקדמה'), isNull);
      expect(hebrewNumeralValue('מאימתי'), isNull);
    });

    test('מחרוזת ריקה ותווים שאינם עבריים נדחים', () {
      expect(hebrewNumeralValue(''), isNull);
      expect(hebrewNumeralValue('ab'), isNull);
      expect(hebrewNumeralValue('כ2'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // canonicalDafKey – גישור בין כתיבי דף שונים
  // ---------------------------------------------------------------------------
  group('canonicalDafKey', () {
    test('נקודה = עמוד א, היעדר סימן = עמוד ב (הקולון הוסר בנרמול)', () {
      expect(canonicalDafKey('דף ב.'), '2a');
      expect(canonicalDafKey('דף ב'), '2b');
      expect(canonicalDafKey(normalizeRef('דף ב:')), '2b');
    });

    test('בלי הקידומת "דף" אין מפתח — כך סימנים ופרקים אינם דפים', () {
      for (final label in ['כב.', 'א.', 'ב.', 'כב-ב', 'כב', 'ב']) {
        expect(canonicalDafKey(label), isNull, reason: label);
      }
    });

    test('מילים שהגימטריה שלהן תקינה אינן מתחזות לדף', () {
      // כולן ערכי גימטריה חוקיים: תמיד=454, שם=340, תשא=701, ריטבא=221.
      for (final label in [
        'תמיד',
        'תמיד.',
        'שם',
        'שם.',
        'תשא.',
        'ריטבא',
        'פסח',
        'עמ א',
      ]) {
        expect(canonicalDafKey(label), isNull, reason: label);
      }
    });

    test('"דף" ו"עמוד" אינם נחשבים מספר הדף', () {
      expect(canonicalDafKey('עמוד א'), isNull);
      expect(canonicalDafKey('דף דף א'), isNull);
      expect(canonicalDafKey('דף'), isNull);
      expect(canonicalDafKey('דף.'), isNull);
    });

    test('מקפים שאינם ASCII מתקפלים ואינם נדבקים למספר', () {
      // בלי קיפול המקף "דף כב־א" היה נקרא "דף כבא" = דף 23.
      expect(canonicalDafKey(normalizeRef('דף כב־א')), '22a');
      expect(canonicalDafKey(normalizeRef('דף כב–א')), '22a');
      expect(canonicalDafKey(normalizeRef('דף כב—ב')), '22b');
    });

    test('כתיב מקף ("דף כב - א")', () {
      expect(canonicalDafKey('דף כב - א'), '22a');
      expect(canonicalDafKey('דף כב - ב'), '22b');
      expect(canonicalDafKey('דף כב-א'), '22a');
    });

    test('כתיב ע"א / ע"ב אחרי נרמול', () {
      expect(canonicalDafKey(normalizeRef('דף כב ע"א')), '22a');
      expect(canonicalDafKey(normalizeRef('דף כב ע"ב')), '22b');
    });

    test('כתיב "עמוד א" מלא', () {
      expect(canonicalDafKey('דף כב עמוד א'), '22a');
      expect(canonicalDafKey('דף כב עמוד ב'), '22b');
    });

    test('כל הכתיבים של אותו דף מתלכדים למפתח אחד', () {
      final keys = [
        'דף כב.',
        'דף כב - א',
        'דף כב ע"א',
        'דף כב עמוד א',
      ].map((s) => canonicalDafKey(normalizeRef(s))).toSet();
      expect(keys, {'22a'});
    });

    test('כותרות שאינן דף מוחזרות null', () {
      for (final label in [
        'הקדמה',
        'פרק ראשון - מאימתי',
        'סימן כב',
        'ברכות',
        'שבת',
        'סוכה',
        'תוכן העניינים',
        '',
      ]) {
        expect(canonicalDafKey(label), isNull, reason: '"$label"');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PageMap interpolation
  // ---------------------------------------------------------------------------
  group('PageMap', () {
    test('returns null when empty', () {
      final m = PageMap([], []);
      expect(m.textToPdf(0), isNull);
      expect(m.pdfToText(1), isNull);
      expect(m.hasReliableAnchors, isFalse);
    });

    test('single anchor – always returns that anchor', () {
      final m = PageMap([5], [20]);
      expect(m.textToPdf(0), 5);
      expect(m.textToPdf(20), 5);
      expect(m.textToPdf(100), 5);
      expect(m.pdfToText(1), 20);
      expect(m.pdfToText(5), 20);
      expect(m.pdfToText(99), 20);
      expect(m.hasReliableAnchors, isFalse);
    });

    test('exact anchor hits', () {
      final m = PageMap([1, 10, 20], [0, 100, 200]);
      expect(m.textToPdf(0), 1);
      expect(m.textToPdf(100), 10);
      expect(m.textToPdf(200), 20);
      expect(m.pdfToText(1), 0);
      expect(m.pdfToText(10), 100);
      expect(m.pdfToText(20), 200);
      expect(m.hasReliableAnchors, isTrue);
    });

    test('interpolates midpoint correctly', () {
      // Anchors: pdf[1,11] ↔ text[0,100]
      // Mid text=50 → pdf = 1 + 50*(10/100) = 6
      final m = PageMap([1, 11], [0, 100]);
      expect(m.textToPdf(50), 6);
      // Mid pdf=6 → text = 0 + 5*(100/10) = 50
      expect(m.pdfToText(6), 50);
    });

    test('clamps below first anchor', () {
      final m = PageMap([5, 10], [50, 100]);
      expect(m.textToPdf(10), 5); // below first text anchor
      expect(m.pdfToText(2), 50); // below first pdf anchor
    });

    test('clamps above last anchor', () {
      final m = PageMap([5, 10], [50, 100]);
      expect(m.textToPdf(200), 10); // above last text anchor
      expect(m.pdfToText(99), 100); // above last pdf anchor
    });
  });

  // ---------------------------------------------------------------------------
  // buildPageMapFromAnchors – full-path matching
  // ---------------------------------------------------------------------------
  group('buildPageMapFromAnchors – full-path match', () {
    test('matches when paths are identical', () {
      final pdf = [(page: 3, ref: 'ברכות/ב.')];
      final text = [(index: 0, ref: 'ברכות/ב.')];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3]);
      expect(m.textIndices, [0]);
    });

    test('no match when no ref or suffix exists in text', () {
      // PDF has "other/unknown" but text has no "unknown" leaf at all.
      final pdf = [(page: 3, ref: 'other/unknown')];
      final text = [(index: 0, ref: 'ברכות/ב.')];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, isEmpty);
    });

    test('skips duplicate pdf pages', () {
      final pdf = [
        (page: 3, ref: 'ברכות/ב.'),
        (page: 3, ref: 'ברכות/ג.'), // same page
      ];
      final text = [
        (index: 0, ref: 'ברכות/ב.'),
        (index: 50, ref: 'ברכות/ג.'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages.length, 1);
      expect(m.pdfPages.first, 3);
    });

    test('result is sorted by pdf page', () {
      // Supply in reverse order to verify sorting.
      final pdf = [
        (page: 10, ref: 'ג.'),
        (page: 3, ref: 'ב.'),
      ];
      final text = [
        (index: 90, ref: 'ג.'),
        (index: 0, ref: 'ב.'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3, 10]);
      expect(m.textIndices, [0, 90]);
    });
  });

  // ---------------------------------------------------------------------------
  // buildPageMapFromAnchors – suffix-path fallback (the new logic)
  // ---------------------------------------------------------------------------
  group('buildPageMapFromAnchors – suffix-path fallback', () {
    test('matches when PDF has extra top-level node (Gemara case)', () {
      // PDF outline: "תלמוד בבלי/ברכות/ב."
      // Text TOC:    "ברכות/ב."
      // "ברכות/ב." is a unique suffix → should match.
      final pdf = [
        (page: 3, ref: 'תלמוד בבלי/ברכות/ב.'),
        (page: 4, ref: 'תלמוד בבלי/ברכות/ב'), // amud bet (colon stripped)
        (page: 5, ref: 'תלמוד בבלי/ברכות/ג.'),
      ];
      final text = [
        (index: 0, ref: 'ברכות/ב.'),
        (index: 45, ref: 'ברכות/ב'),
        (index: 90, ref: 'ברכות/ג.'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3, 4, 5]);
      expect(m.textIndices, [0, 45, 90]);
    });

    test('ambiguous leaf is skipped, longer unique suffix is used', () {
      // "הקדמה" appears in both ברכות and שבת → leaf is ambiguous.
      // "ברכות/הקדמה" is unique → should be matched via 2-component suffix.
      final pdf = [
        (page: 2, ref: 'תלמוד בבלי/ברכות/הקדמה'),
        (page: 50, ref: 'תלמוד בבלי/שבת/הקדמה'),
      ];
      final text = [
        (index: 5, ref: 'ברכות/הקדמה'),
        (index: 500, ref: 'שבת/הקדמה'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [2, 50]);
      expect(m.textIndices, [5, 500]);
    });

    test('leaf shared across tractates is not used alone', () {
      // "א" is a leaf appearing in two tractates → ambiguous → must be skipped.
      final pdf = [(page: 1, ref: 'תלמוד בבלי/ברכות/א')];
      final text = [
        (index: 0, ref: 'ברכות/א'),
        (index: 999, ref: 'שבת/א'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      // "א" is ambiguous, "ברכות/א" is unique → should match via suffix
      expect(m.pdfPages, [1]);
      expect(m.textIndices, [0]);
    });

    test('fully ambiguous anchor produces no match', () {
      // Neither the full path nor any suffix is unique.
      final pdf = [(page: 7, ref: 'x/common')];
      final text = [
        (index: 10, ref: 'a/common'),
        (index: 20, ref: 'b/common'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, isEmpty);
    });

    test('full-path match takes priority over suffix match', () {
      // The PDF ref matches "ברכות/ב." exactly; there also happens to be a
      // different "שבת/ברכות/ב." in the text which shares the same suffix.
      // The full-path match should win.
      final pdf = [(page: 3, ref: 'ברכות/ב.')];
      final text = [
        (index: 0, ref: 'ברכות/ב.'), // exact match
        (index: 999, ref: 'שבת/ברכות/ב.'), // same suffix but different book
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3]);
      expect(m.textIndices, [0]); // exact match wins, not 999
    });
  });

  // ---------------------------------------------------------------------------
  // buildPageMapFromAnchors – שלב 3: התאמת דף קנונית
  // כל טסט כאן מגן על אי-רגרסיה: השלב פועל רק כשההתאמה לפי כותרות נכשלה.
  // ---------------------------------------------------------------------------
  group('buildPageMapFromAnchors – canonical daf fallback', () {
    test('מגשר בין מהדורות שכותבות את אותו דף אחרת', () {
      // PDF: "דף ב." / "דף ב" (קולון הוסר) — טקסט: "דף ב - א" / "דף ב - ב".
      // אף כותרת אינה זהה, ואף סיומת אינה משותפת → בלי שלב 3 אפס התאמות.
      final pdf = [
        (page: 1, ref: 'ברכות/דף ב.'),
        (page: 2, ref: 'ברכות/דף ב'),
        (page: 3, ref: 'ברכות/דף ג.'),
      ];
      final text = [
        (index: 2, ref: 'תלמוד בבלי - ברכות/פרק ראשון/דף ב - א'),
        (index: 13, ref: 'תלמוד בבלי - ברכות/פרק ראשון/דף ב - ב'),
        (index: 19, ref: 'תלמוד בבלי - ברכות/פרק ראשון/דף ג - א'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [1, 2, 3]);
      expect(m.textIndices, [2, 13, 19]);
      expect(m.hasReliableAnchors, isTrue);
    });

    test('גם בתוך שלב 3 התאמת הנתיב גוברת על מפתח הדף', () {
      // עוגן א מותאם לפי נתיב מלא (→0) ויש לו מתחרה עם אותו מפתח דף (→999);
      // עוגן ב מותאם רק לפי מפתח דף. שלב 3 רץ כי הנתיב לבדו נתן עוגן אחד.
      final pdf = [
        (page: 3, ref: 'ברכות/דף כב.'),
        (page: 8, ref: 'ברכות/דף כג.'),
      ];
      final text = [
        (index: 0, ref: 'ברכות/דף כב.'),
        (index: 999, ref: 'שבת/דף כב - א'),
        (index: 500, ref: 'אחר/דף כג - א'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3, 8]);
      expect(m.textIndices, [0, 500]);
    });

    test('גם בתוך שלב 3 התאמת הסיומת גוברת על מפתח הדף', () {
      final pdf = [
        (page: 3, ref: 'תלמוד בבלי/ברכות/דף כב.'),
        (page: 8, ref: 'תלמוד בבלי/ברכות/דף כג.'),
      ];
      final text = [
        (index: 40, ref: 'ברכות/דף כב.'), // סיומת חד-משמעית
        (index: 999, ref: 'אחר/דף כב - א'), // אותו מפתח דף
        (index: 500, ref: 'אחר/דף כג - א'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3, 8]);
      expect(m.textIndices, [40, 500]);
    });

    test('מפתח דף שאינו חד-משמעי נדחה', () {
      // אותו דף מופיע בשני מקומות בטקסט → אין ודאות → מדלגים.
      final pdf = [(page: 3, ref: 'דף כב.')];
      final text = [
        (index: 10, ref: 'א/דף כב - א'),
        (index: 20, ref: 'ב/דף כב - א'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, isEmpty);
    });

    test('ספר שאינו גמרא — השלב הוא no-op ואינו ממציא התאמות', () {
      final pdf = [
        (page: 2, ref: 'שולחן ערוך/הקדמה'),
        (page: 9, ref: 'שולחן ערוך/דיני נטילת ידיים'),
      ];
      final text = [
        (index: 5, ref: 'אורח חיים/פתיחה'),
        (index: 80, ref: 'אורח חיים/סדר היום'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, isEmpty);
    });

    test('ספר ממוספר בסימנים מול PDF ממוספר בדפים — אין מיפוי מדומה', () {
      // "א." בטקסט הוא מספר סימן. ללא דרישת הקידומת "דף" הוא היה נקשר ל"דף א."
      // ומייצר מפה "אמינה" ושגויה לגמרי, בלי שהמשתמש יקבל הודעה.
      final pdf = [
        (page: 5, ref: 'ספר/דף א.'),
        (page: 9, ref: 'ספר/דף ב.'),
        (page: 14, ref: 'ספר/דף ג.'),
      ];
      final text = [
        (index: 10, ref: 'אגרא דפרקא/א.'),
        (index: 90, ref: 'אגרא דפרקא/ב.'),
        (index: 160, ref: 'אגרא דפרקא/ג.'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, isEmpty);
    });

    test('שלב 3 אינו משנה מפה שכבר הותאמה במלואה לפי כותרות', () {
      // אותו קלט שמותאם 1:1 בשלב 1 — התוצאה חייבת להישאר זהה.
      final pdf = [
        (page: 1, ref: 'ברכות/דף ב.'),
        (page: 2, ref: 'ברכות/דף ב'),
        (page: 3, ref: 'ברכות/דף ג.'),
      ];
      final text = [
        (index: 1, ref: 'ברכות/דף ב.'),
        (index: 16, ref: 'ברכות/דף ב'),
        (index: 36, ref: 'ברכות/דף ג.'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [1, 2, 3]);
      expect(m.textIndices, [1, 16, 36]);
    });

    test('מיפוי חלקי-אך-שמיש אינו נפתח למפתחות דף — אפס רגרסיה', () {
      // שני עוגנים הותאמו לפי כותרות. השלישי אינו מותאם לפי נתיב (כתיב שונה)
      // אך מפתח הדף היה קושר אותו לאינדקס 5 ומעוות מפה שכבר עובדת.
      final pdf = [
        (page: 1, ref: 'ספר/פרק א'),
        (page: 20, ref: 'ספר/פרק ב'),
        (page: 30, ref: 'ספר/דף פו.'),
      ];
      final text = [
        (index: 0, ref: 'ספר/פרק א'),
        (index: 400, ref: 'ספר/פרק ב'),
        (index: 5, ref: 'נספח/דף פו - א'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [1, 20]);
      expect(m.textIndices, [0, 400]);
    });

    test('כשמפתחות הדף אינם מספיקים חוזרים למפת הכותרות ולא מרעים', () {
      // עוגן אחד לפי כותרת, ומפתח דף שאינו חד-משמעי → התוצאה נשארת העוגן הבודד.
      final pdf = [
        (page: 3, ref: 'ספר/פתיחה'),
        (page: 8, ref: 'ספר/דף ה.'),
      ];
      final text = [
        (index: 2, ref: 'ספר/פתיחה'),
        (index: 60, ref: 'א/דף ה.'),
        (index: 90, ref: 'ב/דף ה.'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);
      expect(m.pdfPages, [3]);
      expect(m.textIndices, [2]);
    });
  });

  // ---------------------------------------------------------------------------
  // End-to-end: interpolation over suffix-matched anchors
  // ---------------------------------------------------------------------------
  group('end-to-end navigation', () {
    test('Gemara-like scenario: text→pdf and pdf→text', () {
      // 3 dafs matched via suffix fallback.
      // Each daf has 2 amudim (alef + bet).
      // Text indices spaced 45 apart, PDF pages spaced 1 apart.
      final pdf = [
        (page: 3, ref: 'תלמוד בבלי/ברכות/ב.'),
        (page: 4, ref: 'תלמוד בבלי/ברכות/ב'),
        (page: 5, ref: 'תלמוד בבלי/ברכות/ג.'),
        (page: 6, ref: 'תלמוד בבלי/ברכות/ג'),
      ];
      final text = [
        (index: 0, ref: 'ברכות/ב.'),
        (index: 45, ref: 'ברכות/ב'),
        (index: 90, ref: 'ברכות/ג.'),
        (index: 135, ref: 'ברכות/ג'),
      ];
      final m = buildPageMapFromAnchors(pdf, text);

      // Exact anchor points
      expect(m.textToPdf(0), 3);
      expect(m.textToPdf(45), 4);
      expect(m.textToPdf(90), 5);
      expect(m.textToPdf(135), 6);

      // Midpoint interpolation: index 22 is halfway between 0 and 45
      expect(m.textToPdf(22), 3); // still on page 3 (rounds down)
      expect(m.textToPdf(23), 4); // crosses to page 4 (rounds up)

      expect(m.pdfToText(3), 0);
      expect(m.pdfToText(4), 45);
      expect(m.pdfToText(5), 90);
    });
  });
}
