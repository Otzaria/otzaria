import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';

Link _anchorLink({
  required String heRef,
  required String path2,
  int? anchorStart,
  String? anchorLabel,
}) {
  return Link(
    heRef: heRef,
    index1: 4,
    path2: path2,
    index2: 1,
    connectionType: 'commentary',
    anchorStart: anchorStart,
    anchorEnd: null,
    anchorLabel: anchorLabel,
  );
}

void main() {
  group('anchorMarkerLetter', () {
    test('מעדיף את התווית השמורה במסד', () {
      final link = _anchorLink(
        heRef: 'באר הגולה על שולחן ערוך אורח חיים א, ב',
        path2: 'באר הגולה על שולחן ערוך אורח חיים',
        anchorStart: 35,
        anchorLabel: 'א',
      );
      expect(anchorMarkerLetter(link), 'א');
    });

    test('נגזר מהרכיב האחרון של heRef כשאין תווית', () {
      final link = _anchorLink(
        heRef: 'טורי זהב על שולחן ערוך אורח חיים א, ז',
        path2: 'טורי זהב על שולחן ערוך אורח חיים',
        anchorStart: 35,
      );
      expect(anchorMarkerLetter(link), 'ז');
    });

    test('גרשיים בתוך האות נשמרים בתצוגה', () {
      final link = _anchorLink(
        heRef: 'משנה ברורה,  א, קכ"ט',
        path2: 'משנה ברורה',
        anchorStart: 10,
      );
      expect(anchorMarkerLetter(link), 'קכ"ט');
    });

    test('רכיב אחרון שאינו גימטריה — אין אות', () {
      final link = _anchorLink(
        heRef: 'פירוש כלשהו, פסקה ארוכה מאוד שאינה אות',
        path2: 'פירוש כלשהו',
        anchorStart: 5,
      );
      expect(anchorMarkerLetter(link), isNull);
    });
  });

  group('injectLinkAnchorMarkers', () {
    // שורת שולחן ערוך או"ח א:א כפי שהיא שמורה במסד (הקטע הרלוונטי): התגים
    // המקוריים של ספריא אינם נספרים כתווים גלויים, והעוגן של באר הגולה יושב
    // באופסט גלוי 35 — מיד לפני "יתגבר".
    const saLine =
        '(א) <b>דין השכמת הבוקר. ובו ט סעיפים:</b> '
        '<i data-commentator="Be\'er HaGolah" data-label="א" data-order="1"></i>'
        '<i data-commentator="Turei Zahav" data-order="1"></i>יתגבר '
        '<i data-commentator="Ba\'er Hetev" data-order="1"></i>כארי לעמוד בבוקר';

    test('סמן מוזרק בדיוק לפני המילה המעוגנת, בתוך תוכן אמיתי', () {
      final bhg = _anchorLink(
        heRef: 'באר הגולה על שולחן ערוך אורח חיים א, א',
        path2: 'באר הגולה על שולחן ערוך אורח חיים',
        anchorStart: 35,
        anchorLabel: 'א',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: saLine,
        anchorLinks: [bhg],
        styleIndexByCommentator: const {
          'באר הגולה על שולחן ערוך אורח חיים': 0,
        },
      );
      expect(
        result,
        contains('<span class="link-anchor link-anchor-0">(א)</span>'),
      );
      // הסמן נכנס צמוד לפני "יתגבר" — בלי אף תו גלוי בין הסמן למילה
      // (רק תגי itag בלתי-נראים מותרים בתווך).
      final markerIndex = result.indexOf('<span class="link-anchor');
      final wordIndex = result.indexOf('יתגבר');
      expect(markerIndex, lessThan(wordIndex));
      final between = result.substring(
        markerIndex +
            '<span class="link-anchor link-anchor-0">(א)</span>'.length,
        wordIndex,
      );
      expect(between.replaceAll(RegExp(r'<[^>]*>'), ''), isEmpty);
    });

    test('עם lineIndex הסמן נפלט כ-<a> עם href של line_index', () {
      final bhg = _anchorLink(
        heRef: 'באר הגולה על שולחן ערוך אורח חיים א, א',
        path2: 'באר הגולה על שולחן ערוך אורח חיים',
        anchorStart: 35,
        anchorLabel: 'א',
      );
      final baerHetev = _anchorLink(
        heRef: 'באר היטב אורח חיים א, א',
        path2: 'באר היטב אורח חיים',
        anchorStart: 41,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: saLine,
        anchorLinks: [bhg, baerHetev],
        styleIndexByCommentator: const {
          'באר הגולה על שולחן ערוך אורח חיים': 0,
          'באר היטב אורח חיים': 1,
        },
        lineIndex: 7,
      );
      // הקישור הראשון (i=0) והשני (i=1) בשורה 7 — href מקודד line_index.
      expect(
        result,
        contains(
          '<a class="link-anchor link-anchor-0" href="otzaria://anchor?ref=7_0">(א)</a>',
        ),
      );
      expect(result, contains('href="otzaria://anchor?ref=7_1"'));
      expect(result, isNot(contains('<span class="link-anchor')));
    });

    test('עוגן-טווח עם lineIndex נפלט כ-<a> עם range=1 (לחיצה מנווטת)', () {
      final citation = Link(
        heRef: 'שמות כט, מג',
        index1: 4,
        path2: 'שמות',
        index2: 100,
        connectionType: 'linker',
        anchorStart: 5,
        anchorEnd: 9,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'תחילה ציטוט ארוך מאוד וסוף',
        anchorLinks: [citation],
        styleIndexByCommentator: const {'שמות': 2},
        lineIndex: 12,
      );
      expect(
        result,
        contains(
          '<a class="link-anchor-range link-anchor-2" '
          'href="otzaria://anchor?ref=12_0&range=1">',
        ),
      );
      // בלי lineIndex — נשאר span לא-אינטראקטיבי.
      final passive = injectLinkAnchorMarkers(
        rawLine: 'תחילה ציטוט ארוך מאוד וסוף',
        anchorLinks: [citation],
        styleIndexByCommentator: const {'שמות': 2},
      );
      expect(
        passive,
        contains('<span class="link-anchor-range link-anchor-2">'),
      );
      expect(passive, isNot(contains('href=')));
    });

    test('activeIndex מסמן את העוגן הפעיל במחלקת link-anchor-active', () {
      final bhg = _anchorLink(
        heRef: 'באר הגולה על שולחן ערוך אורח חיים א, א',
        path2: 'באר הגולה על שולחן ערוך אורח חיים',
        anchorStart: 35,
        anchorLabel: 'א',
      );
      final baerHetev = _anchorLink(
        heRef: 'באר היטב אורח חיים א, א',
        path2: 'באר היטב אורח חיים',
        anchorStart: 41,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: saLine,
        anchorLinks: [bhg, baerHetev],
        styleIndexByCommentator: const {
          'באר הגולה על שולחן ערוך אורח חיים': 0,
          'באר היטב אורח חיים': 1,
        },
        lineIndex: 7,
        activeIndex: 1,
      );
      // רק העוגן השני (i=1) מקבל link-anchor-active.
      expect(result, contains('link-anchor-1 link-anchor-active'));
      expect(result, isNot(contains('link-anchor-0 link-anchor-active')));
    });

    test('כמה מפרשים באותה שורה — סגנון שונה לכל אחד', () {
      final bhg = _anchorLink(
        heRef: 'באר הגולה על שולחן ערוך אורח חיים א, א',
        path2: 'באר הגולה על שולחן ערוך אורח חיים',
        anchorStart: 35,
        anchorLabel: 'א',
      );
      final baerHetev = _anchorLink(
        heRef: 'באר היטב אורח חיים א, א',
        path2: 'באר היטב אורח חיים',
        anchorStart: 41,
      );
      final styles = anchorStyleIndexByCommentator([bhg, baerHetev]);
      expect(styles.values.toSet().length, 2);

      final result = injectLinkAnchorMarkers(
        rawLine: saLine,
        anchorLinks: [bhg, baerHetev],
        styleIndexByCommentator: styles,
      );
      expect(result, contains('link-anchor-${styles[bhg.path2]}">(א)</span>'));
      expect(
        result,
        contains('link-anchor-${styles[baerHetev.path2]}">(א)</span>'),
      );
      // העוגן של באר היטב (41) יושב אחרי "יתגבר " — לפני "כארי".
      final hetevMarker =
          '<span class="link-anchor link-anchor-${styles[baerHetev.path2]}">(א)</span>';
      expect(result.indexOf(hetevMarker), lessThan(result.indexOf('כארי')));
      expect(result.indexOf(hetevMarker), greaterThan(result.indexOf('יתגבר')));
    });

    test('סגנון מפרש נשאר זהה כשנטענים מפרשים נוספים', () {
      final target = _anchorLink(
        heRef: 'מפרש ב, א',
        path2: 'מפרש',
        anchorStart: 1,
      );
      final before = anchorStyleIndexByCommentator([target]);
      final after = anchorStyleIndexByCommentator([
        _anchorLink(
          heRef: 'א א, א',
          path2: 'א',
          anchorStart: 1,
        ),
        target,
        _anchorLink(
          heRef: 'ת א, א',
          path2: 'ת',
          anchorStart: 1,
        ),
      ]);

      expect(after[target.path2], before[target.path2]);
    });

    test('entity נספר כתו גלוי אחד', () {
      const line = 'אב&nbsp;גד';
      final link = _anchorLink(
        heRef: 'ספר כלשהו א, ב',
        path2: 'ספר כלשהו',
        anchorStart: 3,
        anchorLabel: 'ב',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: [link],
        styleIndexByCommentator: const {'ספר כלשהו': 1},
      );
      expect(
        result,
        'אב&nbsp;<span class="link-anchor link-anchor-1">(ב)</span>גד',
      );
    });

    test('עוגן מעבר לאורך השורה נצמד לסוף', () {
      final link = _anchorLink(
        heRef: 'ספר כלשהו א, ג',
        path2: 'ספר כלשהו',
        anchorStart: 999,
        anchorLabel: 'ג',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבג',
        anchorLinks: [link],
        styleIndexByCommentator: const {'ספר כלשהו': 0},
      );
      expect(result, 'אבג<span class="link-anchor link-anchor-0">(ג)</span>');
    });

    test('סמן על גבול אלמנט נכנס אחרי תג הסגירה, לא בתוכו', () {
      final link = _anchorLink(
        heRef: 'ספר כלשהו א, א',
        path2: 'ספר כלשהו',
        anchorStart: 2,
        anchorLabel: 'א',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: '<b>אב</b>גד',
        anchorLinks: [link],
        styleIndexByCommentator: const {'ספר כלשהו': 0},
      );
      // הסמן שייך ל"ג" שמחוץ ל-<b> — בתוך התג הוא היה יורש את ההדגשה
      // (או את הקליק, אם התג הסוגר הוא <a>).
      expect(
        result,
        '<b>אב</b><span class="link-anchor link-anchor-0">(א)</span>גד',
      );
    });

    test('הסמנים נפלטים כ-span ולא כ-sup (כמה sup בפסקת RTL מתהפכים)', () {
      final first = _anchorLink(
        heRef: 'ספר ראשון א, א',
        path2: 'ספר ראשון',
        anchorStart: 0,
        anchorLabel: 'א',
      );
      final second = _anchorLink(
        heRef: 'ספר שני א, ב',
        path2: 'ספר שני',
        anchorStart: 3,
        anchorLabel: 'ב',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אב גד',
        anchorLinks: [first, second],
        styleIndexByCommentator: const {'ספר ראשון': 0, 'ספר שני': 1},
      );
      expect(result, isNot(contains('<sup')));
      // סדר האותיות הלוגי נשמר: (א) לפני (ב).
      expect(result.indexOf('(א)'), lessThan(result.indexOf('(ב)')));
    });

    test('עוגן-טווח (ציטוט) נעטף בקו תחתון בגבולות מדויקים', () {
      final quote = Link(
        heRef: 'בראשית פרק א פסוק א',
        index1: 4,
        path2: 'בראשית',
        index2: 1,
        connectionType: 'quotation',
        anchorStart: 2,
        anchorEnd: 5,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבג דה',
        anchorLinks: [quote],
        styleIndexByCommentator: const {'בראשית': 1},
      );
      expect(
        result,
        'אב<span class="link-anchor-range link-anchor-1">ג ד</span>ה',
      );
    });

    test('עוגן-טווח שחוצה גבול תג נסגר ונפתח מחדש (קינון תקין)', () {
      final quote = Link(
        heRef: 'תהלים פרק כג',
        index1: 4,
        path2: 'תהלים',
        index2: 1,
        connectionType: 'quotation',
        anchorStart: 1,
        anchorEnd: 3,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'א<b>ב</b>גד',
        anchorLinks: [quote],
        styleIndexByCommentator: const {'תהלים': 0},
      );
      // הטווח [1,3) מתחיל בתוך <b> ומסתיים אחריו — העטיפה נסגרת לפני </b>
      // ונפתחת מחדש, כך שה-HTML נשאר מקונן כדין.
      expect(
        result,
        'א<b><span class="link-anchor-range link-anchor-0">ב</span></b>'
        '<span class="link-anchor-range link-anchor-0">ג</span>ד',
      );
    });

    test('קישור עם כמה עוגנים (anchorSpans) מציג את כולם', () {
      final link = Link(
        heRef: 'שערי תשובה על שולחן ערוך אורח חיים רצ, א',
        index1: 4,
        path2: 'שערי תשובה על שולחן ערוך אורח חיים',
        index2: 1,
        connectionType: 'commentary',
        anchorStart: 2,
        anchorLabel: 'א',
        anchorSpans: const [
          LinkAnchorSpan(start: 2, label: 'א'),
          LinkAnchorSpan(start: 5, label: 'א'),
        ],
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אב גד הו',
        anchorLinks: [link],
        styleIndexByCommentator: const {
          'שערי תשובה על שולחן ערוך אורח חיים': 1,
        },
      );
      expect(
        RegExp('link-anchor-1">\\(א\\)</span>').allMatches(result).length,
        2,
      );
    });

    test('wrapVisibleRange עוטף טווח בקטע פאנל (הדגשת ציטוט)', () {
      final result = wrapVisibleRange(
        html: 'אמר רבי ותלד בן ששי ליעקב',
        start: 8,
        end: 19,
        openTag: '<span class="link-anchor-range">',
        closeTag: '</span>',
      );
      expect(
        result,
        'אמר רבי <span class="link-anchor-range">ותלד בן ששי</span> ליעקב',
      );
    });

    test('שורה בלי עוגנים חוזרת כמות שהיא', () {
      expect(
        injectLinkAnchorMarkers(
          rawLine: saLine,
          anchorLinks: const [],
          styleIndexByCommentator: const {},
        ),
        saLine,
      );
    });
  });
}
