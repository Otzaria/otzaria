import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

import '../support/search_engine_test_init.dart';
import '../text_book/utils/literal_pattern_test_helper.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('normalizeLiteralQuery', () {
    test('מסיר ניקוד', () {
      expect(normalizeLiteralQuery('הֲרֵעֹתִי'), 'הרעתי');
    });

    test('ממיר מקף עברי לרווח — זהה לניקוי התוכן', () {
      expect(normalizeLiteralQuery('אשר־שמע'), 'אשר שמע');
    });

    test('ממיר פסק לרווח', () {
      expect(normalizeLiteralQuery('אשר ׀ שמע'), 'אשר שמע');
    });

    test('מכווץ רצפי רווח ומקצץ', () {
      expect(normalizeLiteralQuery('  שמע   ישראל  '), 'שמע ישראל');
    });
  });

  group('stripWordBoundaryWrapper', () {
    test('התאמה חלקית מוצאת מילה בתוך מילה, מלאה לא', () {
      const line = 'את השמים ואת הארץ';
      expect(literalPattern('שמים').hasMatch(line), isFalse);
      expect(
        literalPattern('שמים', wholeWord: false).hasMatch(line),
        isTrue,
      );
    });

    test('התאמה חלקית עדיין מוצאת מילה שלמה', () {
      expect(
        literalPattern('שמים', wholeWord: false).hasMatch('את שמים וארץ'),
        isTrue,
      );
    });

    test('שומרת על סובלנות לניקוד ולגרשיים', () {
      expect(
        literalPattern('הרעתי', wholeWord: false).hasMatch('וְהַרֵעֹתִי'),
        isTrue,
      );
      expect(
        literalPattern('רשי', wholeWord: false).hasMatch('שיטת רש״י'),
        isFalse,
      );
      expect(
        literalPattern('רשי', wholeWord: false).hasMatch('שיטת רשי'),
        isTrue,
      );
    });

    test('גבול פנימי בין מילים נשמר בהתאמה חלקית', () {
      final pattern = literalPattern('שמע ישראל', wholeWord: false);
      expect(pattern.hasMatch('ושמע ישראלים'), isTrue);
      expect(pattern.hasMatch('שמעישראל'), isFalse);
    });

    test('חותכת את ה-(?! האחרון, לא כזה שבתוך הביטוי', () {
      // תג HTML במפריד בין מילים מכיל (?! משלו — חיתוך לפי המופע הראשון
      // היה קוטע את הביטוי באמצע.
      const source = r'(?<![א-ת])(?:אב<(?!br)[^>]*>גד)(?![א-ת])';
      expect(stripWordBoundaryWrapper(source), r'(?:אב<(?!br)[^>]*>גד)');
    });

    test('מחזירה null כשהמבנה אינו מזוהה', () {
      expect(stripWordBoundaryWrapper('אבג'), isNull);
      expect(stripWordBoundaryWrapper('(?<![א-ת])(?:אבג)'), isNull);
    });
  });

  group('buildLiteralPattern — התאמה חלקית (issue #1546)', () {
    bool partialHas(String query, String line) =>
        buildLiteralPattern(query, wholeWord: false)!.regExp.hasMatch(line);

    test('אות סופית בסוף השאילתה מתאימה גם לצורה הרגילה', () {
      expect(partialHas('מלך', 'ויאמר המלכים'), isTrue);
      expect(partialHas('שלום', 'ויהי שלומו'), isTrue);
      expect(partialHas('ארץ', 'ארצות'), isTrue);
      expect(partialHas('ברית עולם', 'ברית עולמים'), isTrue);
    });

    test('הצורה הסופית עצמה עדיין נמצאת', () {
      expect(partialHas('מלך', 'ויאמר המלך'), isTrue);
    });

    test('בלי הכיוון ההפוך: אות רגילה אינה מתאימה לסופית', () {
      expect(partialHas('מלכ', 'ויאמר המלך'), isFalse);
    });

    test('אות סופית באמצע השאילתה אינה משתנה', () {
      expect(partialHas('מלך ישראל', 'מלכ ישראל'), isFalse);
    });

    test('אות בודדת נמצאת כמילה שלמה ולא בתוך מילה', () {
      expect(partialHas('פ', 'סוף פסוק פ'), isTrue);
      expect(partialHas('פ', 'סוף פסוק'), isFalse);
    });

    test('במילים שלמות אין שינוי', () {
      final pattern = buildLiteralPattern('מלך', wholeWord: true)!.regExp;
      expect(pattern.hasMatch('ויאמר המלכים'), isFalse);
      expect(pattern.hasMatch('ויאמר מלך'), isTrue);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  group('buildLiteralPattern — מילה שלמה בודקת את הביטוי לפני הגבול', () {
    const queries = ['שבת', 'אמר רבי', 'ויש אומרים', 'רשי', 'מלך', 'ה׳', 'א'];
    const lines = [
      'אמר רבי יוחנן שבת שבתון ובשבת',
      'וְיֵשׁ אוֹמְרִים שֶׁבַּשַּׁבָּת אָמַר רַבִּי',
      'שיטת רש״י ורשי ורש"י, ורשי\'',
      'ויאמר המלך מלכים מלך־ישראל',
      'ה׳ אלקים וה\' ה״ א אא א־ב',
      '<b>שבת</b> שב<i>ת</i> ש"בת',
    ];

    test('הביטוי נבדק לפני ה-lookbehind', () {
      for (final q in queries) {
        final p = buildLiteralPattern(q)!;
        expect(p.source, startsWith('(?='), reason: q);
        expect(p.regExp.pattern, p.source, reason: q);
      }
    });

    test('ההתאמות זהות לתבנית המנוע המקורית', () {
      for (final q in queries) {
        final source = buildLiteralPattern(q)!.source;
        final original = source.substring(source.indexOf('(?<!'));
        expect(stripWordBoundaryWrapper(original), isNotNull, reason: q);
        List<(int, int)> spans(RegExp re) => [
          for (final line in lines)
            for (final m in re.allMatches(line)) (m.start, m.end),
        ];
        expect(
          spans(compileLiteralPattern(source)),
          spans(compileLiteralPattern(original)),
          reason: q,
        );
      }
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  group('literalQueryWordEdges', () {
    test('מזהה רווח בקצוות, ולא בשאילתה ריקה', () {
      expect(literalQueryWordEdges('כם '), (start: false, end: true));
      expect(literalQueryWordEdges('  וה'), (start: true, end: false));
      expect(literalQueryWordEdges(' אב גד '), (start: true, end: true));
      expect(literalQueryWordEdges('אב גד'), (start: false, end: false));
      expect(literalQueryWordEdges('   '), (start: false, end: false));
    });
  });

  group('buildLiteralPattern — רווח בקצה בהתאמה חלקית (issue #2679)', () {
    List<String> partialWords(String query, String line) => [
      for (final m in buildLiteralPattern(
        query,
        wholeWord: false,
      )!.regExp.allMatches(line))
        _wordAt(line, m.start),
    ];

    const line = 'לכם כמה הכמות עליכם ובהם וההר והם שווה';

    test('רווח בסוף: רק מילים שמסתיימות בצירוף', () {
      expect(partialWords('כם', line), ['לכם', 'כמה', 'הכמות', 'עליכם']);
      expect(partialWords('כם ', line), ['לכם', 'עליכם']);
    });

    test('רווח בהתחלה: רק מילים שמתחילות בצירוף', () {
      expect(partialWords('וה', line), ['וההר', 'והם', 'שווה']);
      expect(partialWords(' וה', line), ['וההר', 'והם']);
    });

    test('רווח בשני הצדדים: מילה שלמה', () {
      expect(partialWords(' והם ', line), ['והם']);
      expect(partialWords(' הם ', 'הם ובהם הםם'), ['הם']);
    });

    test('רווח בסוף משאיר אות סופית סופית', () {
      expect(partialWords('מלך', 'המלכים מלך'), ['המלכים', 'מלך']);
      expect(partialWords('מלך ', 'המלכים המלך'), ['המלך']);
    });

    test('ביטוי של כמה מילים מעוגן רק בקצה המסומן', () {
      expect(partialWords('שמע ישראל ', 'ושמע ישראלים ושמע ישראל'), [
        'ושמע',
      ]);
    });

    test('במילים שלמות ובאות אחת הרווח אינו משנה', () {
      for (final q in ['כם', 'פ']) {
        expect(
          buildLiteralPattern(' $q ', wholeWord: true)!.source,
          buildLiteralPattern(q, wholeWord: true)!.source,
        );
      }
      expect(
        buildLiteralPattern('פ ', wholeWord: false)!.source,
        buildLiteralPattern('פ', wholeWord: false)!.source,
      );
      expect(buildLiteralPattern('   ', wholeWord: false), isNull);
    });

    test('ההדגשה בגוף הספר מוצאת בדיוק את ההתאמות של החיפוש', () {
      const lines = [
        line,
        'וְהָיָה לָכֶם הַמֶּלֶךְ וְהַמְּלָכִים',
        'ושמע ישראלים ושמע ישראל',
        'אמר הרמב"ם כך והרמב״ם',
        'לכם1 לכםabc לכם',
      ];
      for (final q in [
        'כם ',
        ' וה',
        ' והם ',
        'מלך ',
        'שמע ישראל ',
        'מב ',
        ' רמב',
      ]) {
        for (final l in lines) {
          final clean = utils.removeVolwels(l);
          // ההדגשה מחזירה טווח לכל מילה שבהתאמה.
          final search = [
            for (final m in buildLiteralPattern(
              q,
              wholeWord: false,
            )!.regExp.allMatches(clean))
              for (final w in RegExp(r'\S+').allMatches(m.group(0)!))
                (m.start + w.start, m.start + w.end),
          ];
          final highlight = [
            for (final r in utils.computeHighlightRanges(
              clean,
              q,
              partialWordMatch: true,
            ))
              (r.first, r.last),
          ];
          expect(highlight, search, reason: '"$q" ב-"$clean"');
        }
      }
    });

    test('תג HTML צמוד לקצה אינו גבול מילה, כמו בטקסט הנקי של החיפוש', () {
      for (final (q, html) in [
        (' הא', '<b>ו</b>הארץ'),
        ('וה ', '<b>וה</b>ארץ'),
        (' הא', '<b>ו</b> הארץ'),
        ('וה ', '<b>וה</b> ארץ'),
      ]) {
        final clean = utils.stripHtmlIfNeeded(html);
        final searchFound = buildLiteralPattern(
          q,
          wholeWord: false,
        )!.regExp.hasMatch(clean);
        final highlighted = utils
            .computeHighlightRanges(html, q, partialWordMatch: true)
            .isNotEmpty;
        expect(highlighted, searchFound, reason: '"$q" ב-"$html"');
      }
    });

    test('שאילתת /regex/ אינה מסוננת לפי רווח בקצה', () {
      expect(
        utils.computeHighlightRanges('אב ג', ' /אב/ ', partialWordMatch: true),
        utils.computeHighlightRanges('אב ג', '/אב/', partialWordMatch: true),
      );
      expect(
        utils.computeHighlightRanges('אב ג', '/אב/', partialWordMatch: true),
        isNotEmpty,
      );
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}

String _wordAt(String line, int offset) {
  final start = line.lastIndexOf(' ', offset) + 1;
  final end = line.indexOf(' ', offset);
  return line.substring(start, end < 0 ? line.length : end);
}
