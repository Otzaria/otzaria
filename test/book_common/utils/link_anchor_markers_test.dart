import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

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
  group('כותרת הערה אינה מכפילה מספר רשומה סותר (issue #1979)', () {
    // באר הגולה, שו"ע או"ח תרס"ד: הסימן המודפס [ג] מפנה לרשומה שה-heRef שלה
    // מסתיים ב-ד, כי לפניה הערה ללא מספר ([•]).
    Link beerHagolah(
      String? label, {
      String heRef = 'באר הגולה על שולחן ערוך אורח חיים תרסד, ד',
    }) => _anchorLink(
      heRef: heRef,
      path2: 'באר הגולה על שולחן ערוך אורח חיים',
      anchorStart: 12,
      anchorLabel: label,
    );
    const reference = 'באר הגולה על שולחן ערוך אורח חיים, תרסד, ד';

    test('סימן מודפס ששונה ממספר הרשומה — המספר מושמט', () {
      expect(
        anchoredLinkTitle(beerHagolah('ג'), '[ג]', reference),
        '[ג] באר הגולה על שולחן ערוך אורח חיים, תרסד',
      );
    });

    test('סימן שזהה למספר הרשומה — ללא שינוי', () {
      expect(
        anchoredLinkTitle(beerHagolah('ד'), '[ד]', reference),
        '[ד] $reference',
      );
      expect(
        anchoredLinkTitle(beerHagolah(null), '[ד]', reference),
        '[ד] $reference',
      );
    });

    test('סימן שאינו אות (•) — ללא שינוי', () {
      expect(
        anchoredLinkTitle(beerHagolah('•'), '[•]', reference),
        '[•] $reference',
      );
    });

    test('כתובת שאינה מסתיימת במספר הרשומה — הסימן אינו נוגע בה', () {
      expect(
        anchoredLinkTitle(beerHagolah('ג'), '[ג]', 'באר הגולה, תרסד'),
        '[ג] באר הגולה, תרסד',
      );
    });
  });

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

    test('תווית ♦ מוחלפת ביהלום גיאומטרי שאינו אימוג\'י', () {
      final link = _anchorLink(
        heRef: 'עטרת זקנים על שולחן ערוך אורח חיים א, א',
        path2: 'עטרת זקנים על שולחן ערוך אורח חיים',
        anchorStart: 10,
        anchorLabel: '♦',
      );
      expect(anchorMarkerLetter(link), '◆');
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

    test('אופסט גולמי (anchorOffsetsAreRaw) מוזרק כמו האופסט הגלוי שלו', () {
      // "עולם": גולמי 20 (תגים ו-&amp; נספרים), גלוי 9 (entity ו-'&' בודד = תו).
      const line = '<b>שלום</b> &amp; & עולם';
      String inject(int start, {required bool raw}) => injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: [
          Link(
            heRef: 'מפרש א, ג',
            index1: 1,
            path2: 'מפרש',
            index2: 1,
            connectionType: 'commentary',
            anchorStart: start,
            anchorOffsetsAreRaw: raw,
            anchorLabel: 'ג',
          ),
        ],
        styleIndexByCommentator: const {'מפרש': 0},
      );
      final fromRaw = inject(20, raw: true);
      expect(fromRaw, inject(9, raw: false));
      expect(
        fromRaw,
        endsWith('<span class="link-anchor link-anchor-0">(ג)</span>עולם'),
      );
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

    test('הסוגריים נקבעים בווריאנט של המפרש ולא בשם הספר', () {
      // אותו מפרש בדיוק, בשני אינדקסי-וריאנט — הסוגריים משתנים איתו.
      String markerFor(int styleIndex) => injectLinkAnchorMarkers(
        rawLine: 'לפני טקסט',
        anchorLinks: [
          _anchorLink(
            heRef: 'מפרש, סימן א, סעיף א אות א',
            path2: 'מפרש',
            anchorStart: 5,
            anchorLabel: 'א',
          ),
        ],
        styleIndexByCommentator: {'מפרש': styleIndex},
      );

      for (var index = 0; index < kLinkAnchorVariants.length; index++) {
        final delimiter = kLinkAnchorVariants[index].delimiter;
        expect(
          markerFor(index),
          contains(
            '<span class="link-anchor link-anchor-$index">'
            '${delimiter.open}א${delimiter.close}</span>',
          ),
          reason: 'אינדקס $index',
        );
      }
    });

    test('כל שלושת סוגי הסוגריים נפלטים בפועל', () {
      final emitted = <String>{};
      for (var index = 0; index < kLinkAnchorVariants.length; index++) {
        emitted.add(kLinkAnchorVariants[index].delimiter.wrap('א'));
      }
      expect(emitted, containsAll(const ['(א)', '[א]', '{א}']));
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
          '<a class="link-anchor-range" '
          'href="otzaria://anchor?ref=12_0&range=1">',
        ),
      );
      // בלי lineIndex — נשאר span לא-אינטראקטיבי.
      final passive = injectLinkAnchorMarkers(
        rawLine: 'תחילה ציטוט ארוך מאוד וסוף',
        anchorLinks: [citation],
        styleIndexByCommentator: const {'שמות': 2},
      );
      expect(passive, contains('<span class="link-anchor-range">'));
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
      String markerOf(String path2) {
        final index = styles[path2]!;
        return '<span class="link-anchor link-anchor-$index">'
            '${wrapLinkAnchorLetter('א', index)}</span>';
      }

      expect(result, contains(markerOf(bhg.path2)));
      expect(result, contains(markerOf(baerHetev.path2)));
      // העוגן של באר היטב (41) יושב אחרי "יתגבר " — לפני "כארי".
      final hetevMarker = markerOf(baerHetev.path2);
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

    test('עוגן-טווח (ציטוט) נעטף בגבולות מדויקים', () {
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
      expect(result, 'אב<span class="link-anchor-range">ג ד</span>ה');
    });

    test('ציטוטי לינקר לספרי יעד שונים מקבלים מחלקה זהה (עיצוב אחיד)', () {
      Link citation(String target, int start, int end) => Link(
        heRef: '$target א',
        index1: 4,
        path2: target,
        index2: 1,
        connectionType: 'linker',
        anchorStart: start,
        anchorEnd: end,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבג דהו זחט',
        anchorLinks: [citation('שבת', 0, 3), citation('גיטין', 4, 7)],
        // ווריאנטים שונים במפה — אסור שידלפו לטווחים.
        styleIndexByCommentator: const {'שבת': 3, 'גיטין': 2},
        lineIndex: 5,
      );
      expect(
        result,
        '<a class="link-anchor-range" href="otzaria://anchor?ref=5_0&range=1">'
        'אבג</a> '
        '<a class="link-anchor-range" href="otzaria://anchor?ref=5_1&range=1">'
        'דהו</a> זחט',
      );
      expect(result, isNot(contains(RegExp(r'link-anchor-\d'))));
    });

    test('סמן-אות של מפרש כן שומר על הווריאנט הטיפוגרפי', () {
      final commentary = _anchorLink(
        heRef: 'משנה ברורה, א, ב',
        path2: 'משנה ברורה',
        anchorStart: 2,
        anchorLabel: 'ב',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבג',
        anchorLinks: [commentary],
        styleIndexByCommentator: const {'משנה ברורה': 4},
      );
      expect(result, 'אב<span class="link-anchor link-anchor-4">(ב)</span>ג');
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
        'א<b><span class="link-anchor-range">ב</span></b>'
        '<span class="link-anchor-range">ג</span>ד',
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

    test('ציטוט לינקר מדולג בכותרות בכל הרמות', () {
      final citation = Link(
        heRef: 'ברכות ב ב',
        index1: 4,
        path2: 'ברכות',
        index2: 1,
        connectionType: 'linker',
        anchorStart: 4,
        anchorEnd: 8,
      );

      for (var level = 1; level <= 6; level++) {
        final raw = '<h$level>אבגד הוזח טיכל</h$level>';
        expect(
          injectLinkAnchorMarkers(
            rawLine: raw,
            anchorLinks: [citation],
            styleIndexByCommentator: const {'ברכות': 0},
            lineIndex: 5,
          ),
          raw,
          reason: 'h$level אינה מקבלת ציטוט לינקר',
        );
      }
    });

    test('בכותרת מדולג רק הלינקר — סמן מפרש נשאר, והאינדקסים לא זזים', () {
      final citation = Link(
        heRef: 'ברכות ב ב',
        index1: 4,
        path2: 'ברכות',
        index2: 1,
        connectionType: 'linker',
        anchorStart: 0,
        anchorEnd: 2,
      );
      final commentary = _anchorLink(
        heRef: 'משנה ברורה, א, ב',
        path2: 'משנה ברורה',
        anchorStart: 2,
        anchorLabel: 'ב',
      );
      final result = injectLinkAnchorMarkers(
        rawLine: '<h2>אבג</h2>',
        anchorLinks: [citation, commentary],
        styleIndexByCommentator: const {'ברכות': 3, 'משנה ברורה': 4},
        lineIndex: 5,
      );
      expect(result, isNot(contains('link-anchor-range')));
      // ref=5_1 ולא 5_0: הדילוג שומר על מיקום הקישור ב-anchorLinks, שלפיו
      // הריחוף/הלחיצה מאתרים אותו.
      expect(
        result,
        '<h2>אב'
        '<a class="link-anchor link-anchor-4" href="otzaria://anchor?ref=5_1">'
        '(ב)</a>ג</h2>',
      );
    });

    test('ציטוט לינקר בשורה רגילה נשאר', () {
      final citation = Link(
        heRef: 'ברכות ב ב',
        index1: 4,
        path2: 'ברכות',
        index2: 1,
        connectionType: 'linker',
        anchorStart: 0,
        anchorEnd: 3,
      );
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבג דה',
        anchorLinks: [citation],
        styleIndexByCommentator: const {'ברכות': 0},
        lineIndex: 5,
      );
      expect(result, contains('link-anchor-range'));
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

  group('injectLinkAnchorMarkers rangesOnly', () {
    Link rangeLink() => Link(
      heRef: 'בראשית א, א',
      index1: 1,
      path2: 'בראשית',
      index2: 1,
      connectionType: 'linker',
      anchorStart: 2,
      anchorEnd: 6,
    );

    Link pointLink() => Link(
      heRef: 'רש"י על בראשית א, א',
      index1: 1,
      path2: 'רש"י על בראשית',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: 8,
      anchorLabel: 'א',
    );

    test('משאיר את ציטוט הלינקר ומדלג על סמן האות', () {
      final html = injectLinkAnchorMarkers(
        rawLine: 'אבגדהוזחטי',
        anchorLinks: [rangeLink(), pointLink()],
        styleIndexByCommentator: const {},
        lineIndex: 0,
        rangesOnly: true,
      );
      expect(html, contains('link-anchor-range'));
      expect(html, contains('otzaria://anchor?ref=0_0&range=1'));
      expect(html, isNot(contains('(א)')));
    });

    test('בלי rangesOnly שני הסימונים מוזרקים', () {
      final html = injectLinkAnchorMarkers(
        rawLine: 'אבגדהוזחטי',
        anchorLinks: [rangeLink(), pointLink()],
        styleIndexByCommentator: const {},
        lineIndex: 0,
      );
      expect(html, contains('link-anchor-range'));
      expect(html, contains('(א)'));
    });
  });

  group('המרת אופסטים זהה לפירוק נאיבי של השורה', () {
    // תג (גם לא סגור) = 0 תווים; entity עד 8 תווים = 1; כל יחידת קוד אחרת = 1.
    final token = RegExp(r'<[^>]*>?|&[^;]{0,8};|[\s\S]');
    const pieces = [
      'א',
      'ב',
      ' ',
      'x',
      '<b>',
      '</b>',
      '<i class="q">',
      '</i>',
      '&amp;',
      '&',
      ';',
      '<',
      '>',
      '&#1488;',
      '&toolongentity;',
      '\u{1F600}',
      '</',
    ];
    Link point(int start, {bool raw = false}) => Link(
      heRef: 'מפרש א, ג',
      index1: 1,
      path2: 'מפרש',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: start,
      anchorOffsetsAreRaw: raw,
      anchorLabel: 'ג',
    );
    String inject(String line, Link link) => injectLinkAnchorMarkers(
      rawLine: line,
      anchorLinks: [link],
      styleIndexByCommentator: const {'מפרש': 0},
    );
    final marker = inject('', point(0));

    test('2,000 שורות אקראיות', () {
      final random = Random(42);
      for (var n = 0; n < 2000; n++) {
        final html = [
          for (var k = random.nextInt(25); k > 0; k--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        final tokens = token.allMatches(html).toList();
        final visible = [
          for (final t in tokens)
            if (t[0]![0] != '<') t,
        ];
        final count = visible.length;
        String naiveInsert(int at) {
          final out = StringBuffer();
          var seen = 0;
          var done = false;
          for (final t in tokens) {
            if (!done && !t[0]!.startsWith('</') && seen >= at) {
              out.write(marker);
              done = true;
            }
            out.write(t[0]);
            if (t[0]![0] != '<') seen++;
          }
          if (!done) out.write(marker);
          return out.toString();
        }

        for (var a = 0; a <= count + 1; a++) {
          expect(inject(html, point(a)), naiveInsert(a), reason: '$html @$a');
          for (var b = a - 1; b <= count + 1; b++) {
            final rawStart = a < count ? visible[a].start : html.length;
            final rawEnd = b <= 0
                ? 0
                : (b <= count ? visible[b - 1].end : html.length);
            final expected = b <= a || rawStart >= rawEnd
                ? html
                : wrapHtmlRanges(html, [
                    HtmlWrapRange(
                      start: rawStart,
                      end: rawEnd,
                      openTag: '[',
                      closeTag: ']',
                    ),
                  ]);
            expect(
              wrapVisibleRange(
                html: html,
                start: a,
                end: b,
                openTag: '[',
                closeTag: ']',
              ),
              expected,
              reason: '$html [$a,$b)',
            );
          }
        }
        for (var r = 0; r <= html.length + 1; r++) {
          final before = visible.where((t) => t.start < r).length;
          expect(
            inject(html, point(r, raw: true)),
            naiveInsert(before),
            reason: '$html raw@$r',
          );
        }
      }
    });
  });

  test('טווח יחיד בתחילת שורה ארוכה שומר על אותו פלט', () {
    final line = '<b>אבגד</b>${List.filled(25000, 'מילה <b>ו</b>עוד ').join()}';
    final link = Link(
      heRef: 'ספר א, ב',
      index1: 1,
      path2: 'ספר',
      index2: 1,
      connectionType: 'linker',
      anchorStart: 0,
      anchorEnd: 4,
    );
    String baseline(String open, String close) => wrapHtmlRanges(line, [
      HtmlWrapRange(start: 3, end: 7, openTag: open, closeTag: close),
    ]);
    String wrap() => wrapVisibleRange(
      html: line,
      start: 0,
      end: 4,
      openTag: '[',
      closeTag: ']',
    );
    String inject() => injectLinkAnchorMarkers(
      rawLine: line,
      anchorLinks: [link],
      styleIndexByCommentator: const {},
    );
    expect(wrap(), baseline('[', ']'));
    expect(inject(), baseline('<span class="link-anchor-range">', '</span>'));
  });

  test('טווחים יחידים ורבים שומרים גבולות entity ו-surrogate וקלט פגום', () {
    const line = '<b>א&amp;😀ב</b><broken';
    Link range(int start, int end, {bool raw = false}) => Link(
      heRef: 'ספר א, ב',
      index1: 1,
      path2: 'ספר',
      index2: 1,
      connectionType: 'linker',
      anchorStart: start,
      anchorEnd: end,
      anchorOffsetsAreRaw: raw,
    );
    String expected(List<(int, int)> ranges) => wrapHtmlRanges(line, [
      for (final (start, end) in ranges)
        HtmlWrapRange(
          start: start,
          end: end,
          openTag: '<span class="link-anchor-range">',
          closeTag: '</span>',
        ),
    ]);
    String inject(List<Link> links) => injectLinkAnchorMarkers(
      rawLine: line,
      anchorLinks: links,
      styleIndexByCommentator: const {},
    );

    // בתוך entity שני האופסטים הגולמיים מתכנסים לאותו אופסט גלוי.
    expect(inject([range(5, 8, raw: true)]), line);
    expect(inject([range(1, 3)]), expected([(4, 10)]));
    // הטווח הראשון מחוץ לשורה; התג הלא סגור בסוף נשמר בטווח שחורג מהסוף.
    expect(
      inject([range(30, 40), range(1, 3), range(3, 30)]),
      expected([(4, 10), (10, line.length)]),
    );
    expect(
      inject([
        range(5, 8, raw: true),
        range(4, 10, raw: true),
        range(10, 99, raw: true),
      ]),
      expected([(4, 10), (10, 12)]),
    );
  });

  test('מפה מוגבלת כוללת סוף טווח מוקדם גם כשהטווח המאוחר מופיע קודם', () {
    final line = '<b>אב</b>${List.filled(2000, 'ג').join()}';
    final link = Link(
      heRef: 'ספר א, ב',
      index1: 1,
      path2: 'ספר',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: 1000,
      anchorEnd: 2000,
      anchorSpans: const [
        LinkAnchorSpan(start: 1, end: 2),
        LinkAnchorSpan(start: 0, end: 1),
      ],
    );
    expect(
      injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: [link],
        styleIndexByCommentator: const {},
      ),
      wrapHtmlRanges(line, [
        for (final start in [4, 3])
          HtmlWrapRange(
            start: start,
            end: start + 1,
            openTag: '<span class="link-anchor-range">',
            closeTag: '</span>',
          ),
      ]),
    );
  });

  test('מפה מוגבלת מערבת אופסט גולמי בתוך entity וטווח שחוצה surrogate', () {
    const line = '&amp;<b>😀ב</b><broken';
    Link range(int start, int end, {bool raw = false}) => Link(
      heRef: 'ספר א, ב',
      index1: 1,
      path2: 'ספר',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: start,
      anchorEnd: end,
      anchorOffsetsAreRaw: raw,
    );
    expect(
      injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: [range(0, 1, raw: true), range(1, 2)],
        styleIndexByCommentator: const {},
      ),
      wrapHtmlRanges(line, [
        for (final (start, end) in [(0, 5), (8, 9)])
          HtmlWrapRange(
            start: start,
            end: end,
            openTag: '<span class="link-anchor-range">',
            closeTag: '</span>',
          ),
      ]),
    );
  });

  test('300 עוגני טווח בשורה ארוכה שומרים על אותו פלט', () {
    final line = List.filled(50000, 'אבגד ').join();
    Link range(int i) => Link(
      heRef: 'ספר א, ב',
      index1: 1,
      path2: 'ספר $i',
      index2: 1,
      connectionType: 'linker',
      anchorStart: 1000 + i * 700,
      anchorEnd: 1004 + i * 700,
    );
    final links = [for (var i = 0; i < 300; i++) range(i)];
    expect(
      injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: links,
        styleIndexByCommentator: const {},
        lineIndex: 0,
      ),
      wrapHtmlRanges(line, [
        for (var i = 0; i < links.length; i++)
          HtmlWrapRange(
            start: links[i].anchorStart!,
            end: links[i].anchorEnd!,
            openTag:
                '<a class="link-anchor-range" '
                'href="otzaria://anchor?ref=0_$i&range=1">',
            closeTag: '</a>',
          ),
      ]),
    );
  });

  test(
    'עוגן שמכסה <sup> שלם עוטף את ה-sup מבחוץ, וה-sup מוצג מורם (#2358)',
    () {
      const line = 'טקסט<sup>4</sup> עוד<sup>5</sup> סוף';
      Link note(int index) {
        final start = line.indexOf('<sup>', index == 0 ? 0 : 16);
        return Link(
          heRef: 'הערות $index',
          index1: 1,
          path2: 'הערות',
          index2: index + 1,
          connectionType: 'commentary',
          anchorStart: start,
          anchorEnd: line.indexOf('</sup>', start) + '</sup>'.length,
          anchorOffsetsAreRaw: true,
        );
      }

      final html = injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: [note(0), note(1)],
        styleIndexByCommentator: const {},
        lineIndex: 0,
      );
      expect(
        html,
        'טקסט<a class="link-anchor-range" href="otzaria://anchor?ref=0_0&range=1">'
        '<sup>4</sup></a> עוד'
        '<a class="link-anchor-range" href="otzaria://anchor?ref=0_1&range=1">'
        '<sup>5</sup></a> סוף',
      );
      final rendered = TextRendererService.processText(
        html,
        const RenderSettings(),
      );
      expect(rendered, isNot(contains('<sup')));
      expect(RegExp('class="raised-sup"').allMatches(rendered), hasLength(2));
    },
  );

  for (final rawOffsets in [false, true]) {
    test('טווח שחוצה שני sup אינו מורחב ($rawOffsets)', () {
      const line = 'לפני<sup>1</sup> טקסט רגיל <sup>2</sup>אחרי';
      final start = line.indexOf('1');
      final end = line.indexOf('2') + 1;
      final html = injectLinkAnchorMarkers(
        rawLine: line,
        anchorLinks: [
          Link(
            heRef: 'הערות א',
            index1: 1,
            path2: 'הערות',
            index2: 1,
            connectionType: 'commentary',
            anchorStart: rawOffsets ? line.indexOf('<sup>') : 4,
            anchorEnd: rawOffsets ? line.lastIndexOf('</sup>') + 6 : 17,
            anchorOffsetsAreRaw: rawOffsets,
          ),
        ],
        styleIndexByCommentator: const {},
        lineIndex: 0,
      );
      expect(
        html,
        wrapHtmlRanges(line, [
          HtmlWrapRange(
            start: start,
            end: end,
            openTag:
                '<a class="link-anchor-range" '
                'href="otzaria://anchor?ref=0_0&range=1">',
            closeTag: '</a>',
          ),
        ]),
      );
    });
  }
}
