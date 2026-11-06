import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/utils/text/html_slice.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// "מעשה שמשון" לרמח"ל, שורה 72 — המקף נעלם והמילים נדבקו ל"אסיריחשק".
const _reported = 'כָּלוּא וְחָפְשִׁי בֵין אֲסִירֵי-חֵשֶׁק';

void main() {
  group('הסתרת פיסוק בין מילים מותירה רווח', () {
    test('המקף שבדיווח הופך לרווח, עם ניקוד ובלעדיו', () {
      expect(
        removePunctuation(_reported),
        'כָּלוּא וְחָפְשִׁי בֵין אֲסִירֵי חֵשֶׁק',
      );
      expect(
        TextRendererService.processText(
          _reported,
          const RenderSettings(removePunctuation: true, removeNikud: true),
        ),
        'כלוא וחפשי בין אסירי חשק',
      );
    });

    const cases = <String, String>{
      'אסירי-חשק': 'אסירי חשק',
      'אסירי–חשק': 'אסירי חשק',
      'אסירי—חשק': 'אסירי חשק',
      'א,ב;ג!ד?ה': 'א ב ג ד ה',
      'א,-ב': 'א ב',
      'פרקים 3-4': 'פרקים 3 4',
      'see-also': 'see also',
      // פיסוק שכבר צמוד לרווח, לתחילת השורה או לסופה — רק נמחק.
      'לאמר - דבר': 'לאמר דבר',
      'לאמר - - דבר': 'לאמר דבר',
      'לאמר <b>—</b> דבר': 'לאמר <b></b>דבר',
      'לאמר —&nbsp;דבר': 'לאמר &nbsp;דבר',
      'לאמר, דבר': 'לאמר דבר',
      '-שלום': 'שלום',
      'שלום-': 'שלום',
      'שלום.': 'שלום.',
      // סוגריים ותגים אינם מסתירים את המילים שמשני צדי הפיסוק.
      '(א),ב': '(א) ב',
      'א,(ב)': 'א (ב)',
      'א-<b>ב</b>': 'א <b>ב</b>',
      '<b>א</b>-ב': '<b>א</b> ב',
      'א-&#1489;': 'א &#1489;',
      'א-&nbsp;ב': 'א&nbsp;ב',
      'וכו\',ועוד': 'וכו\' ועוד',
      // ניקוד או גרשיים אחרי הפיסוק אינם תחילת מילה — רווח היה מנתק אותם.
      'א-ְב': 'אְב',
      'א,"ב': 'א"ב',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(removePunctuation(entry.key), entry.value);
      });
    }
  });

  group('מיפוי בחירה מהתצוגה בלי פיסוק', () {
    test('בחירה סביב מקף מוקף רווחים ממופה למקור', () {
      const line = 'בְּיָדָיו — פָּטוּר, וְאִילּוּ';
      final shown = removeVolwels(removePunctuation(line));
      expect(shown, 'בידיו פטור ואילו');
      final anchor = computeAnchorForSelection(
        rawLine: line,
        selectedText: shown,
        punctuationHidden: true,
      );
      expect(line.substring(anchor!.start, anchor.end), line);
      expect(
        sliceHtmlBySelection(html: '<b>$line</b>', selectedText: shown),
        isNotNull,
      );
    });

    test('html_slice מוצא את הבחירה עם הרווח ובלעדיו', () {
      const html = '<b>אֲסִירֵי</b>-חֵשֶׁק';
      expect(
        sliceHtmlBySelection(html: html, selectedText: 'אסירי חשק'),
        '<b>אסירי</b> חשק',
      );
      expect(
        sliceHtmlBySelection(html: html, selectedText: 'אֲסִירֵי-חֵשֶׁק'),
        '<b>אֲסִירֵי</b>-חֵשֶׁק',
      );
    });

    test('עוגן הערה מהתצוגה בלי פיסוק מכסה את המילים במקור', () {
      final shown = removeVolwels(removePunctuation(_reported));
      final selected = shown.substring(shown.indexOf('אסירי'));
      expect(selected, 'אסירי חשק');

      final anchor = computeAnchorForSelection(
        rawLine: _reported,
        selectedText: selected,
        selectionColumnHint: shown.indexOf(selected),
        punctuationHidden: true,
      );
      expect(
        _reported.substring(anchor!.start, anchor.end),
        'אֲסִירֵי-חֵשֶׁק',
      );
    });

    test('עוגן מהתצוגה עם הפיסוק מאותר באותו מקום', () {
      final range = locateAnchor(
        rawLine: _reported,
        anchorText: 'אֲסִירֵי-חֵשֶׁק',
      );
      expect(_reported.substring(range!.start, range.end), 'אֲסִירֵי-חֵשֶׁק');
    });

    test('הערה ישנה שנשמרה עם המילים הדבוקות עדיין מאותרת', () {
      final range = locateAnchor(rawLine: _reported, anchorText: 'אסיריחשק');
      expect(_reported.substring(range!.start, range.end), 'אֲסִירֵי-חֵשֶׁק');
      expect(lineContainsAnchorText(_reported, 'אסיריחשק'), isTrue);
      expect(lineContainsAnchorText(_reported, 'אסירי חשק'), isTrue);
      expect(lineContainsAnchorText(_reported, 'חשק כלוא'), isFalse);
    });
  });

  group('התאמה למקור עם פיסוק, מירכאות והערות קיימות', () {
    const raw = 'לפני אב-גד אחרי ואז אבגד סוף';
    for (final withHint in [false, true]) {
      test('עוגן ישן אינו קופץ למופע אחר, hint=$withHint', () {
        final range = locateAnchor(
          rawLine: raw,
          anchorText: 'אבגד',
          prefix: 'לפני ',
          suffix: ' אחרי ואז אבגד סוף',
          hintStart: withHint ? 5 : null,
          hintSourceLine: withHint ? raw : null,
        );
        expect((range!.start, range.end), (5, 10));
      });
    }

    test('רמז גולמי מכריע גם בלי הקשר בין שתי ההקרנות', () {
      final range = locateAnchor(
        rawLine: raw,
        anchorText: 'אבגד',
        hintStart: 5,
        hintSourceLine: raw,
      );
      expect((range!.start, range.end), (5, 10));
    });

    test('בלי הקשר או רמז נשמר המופע הראשון', () {
      final range = locateAnchor(rawLine: raw, anchorText: 'אבגד');
      expect((range!.start, range.end), (5, 10));
    });

    test('עוגן חדש יכול לבחור במילה השלמה או במילים המופרדות', () {
      final joined = locateAnchor(
        rawLine: raw,
        anchorText: 'אבגד',
        prefix: 'לפני אב גד אחרי ואז ',
        suffix: ' סוף',
        hintStart: 20,
        hintSourceLine: raw,
      );
      expect((joined!.start, joined.end), (20, 24));
      final separated = locateAnchor(rawLine: raw, anchorText: 'אב גד');
      expect((separated!.start, separated.end), (5, 10));
    });

    test('רמז בסוף או אחרי סוף מקור חלקי ממופה לגבול הגולמי', () {
      const line = 'תחילה <b>אָב</b> סוף אָב';
      const source = '<i>סוף אָב</i>';
      for (final hint in [source.length, source.length + 100]) {
        final range = locateAnchor(
          rawLine: line,
          anchorText: 'אב',
          hintStart: hint,
          hintSourceLine: source,
        );
        expect(
          (range!.start, range.end),
          (line.lastIndexOf('אָב'), line.length),
        );
      }
    });

    for (final text in ['אב",גד', 'אב״,גד', 'אב",ג', 'אב"-גד', 'א,"ב']) {
      test('ההקרנה מסכימה עם החלטת התצוגה על מירכאות: $text', () {
        final shown = removePunctuation(text);
        expect(projectLine(text).normalized, projectLine(shown).normalized);
        final anchor = computeAnchorForSelection(
          rawLine: text,
          selectedText: shown,
          punctuationHidden: true,
        );
        expect(anchor, isNotNull);
        expect(
          sliceHtmlBySelection(html: '<b>$text</b>', selectedText: shown),
          isNotNull,
        );
      });
    }

    for (final html in ['<b>אב-גד</b> אבגד', '<b>אב-גד</b> אב גד']) {
      test('שתי הקרנות עם עיצוב שונה נשארות לא חד משמעיות: $html', () {
        final selection = html.endsWith('אבגד') ? 'אבגד' : 'אב גד';
        expect(
          sliceHtmlBySelection(html: html, selectedText: selection),
          isNull,
        );
      });
    }
  });

  test('כינוי שם קדוש אינו מסתיר מופע אחר בעל עיצוב שונה', () {
    for (final html in [
      '<b>אמר</b> אדני ... אמר אד-ני',
      'אמר אד-ני ... <b>אמר</b> אדני',
    ]) {
      expect(
        sliceHtmlBySelection(html: html, selectedText: 'אמר אד-ני'),
        isNull,
      );
    }
  });

  test('רצפי פיסוק ארוכים שומרים על התוצאה בכל גבול', () {
    final run = '-' * 16000;
    for (final entry in <String, String>{
      'אב$runגד': 'אב גד',
      'אב$run': 'אב',
      '$runגד': 'גד',
      'אב$run*': 'אב*',
      'אב${'-<b></b>' * 2000}גד': 'אב ${'<b></b>' * 2000}גד',
      'אב$run&#1490;ד': 'אב &#1490;ד',
      'אב$run&nbsp;גד': 'אב&nbsp;גד',
    }.entries) {
      expect(removePunctuation(entry.key), entry.value);
    }
  });

  test('מירכאות במקור HTML מוכרעות לפני הסרת גבולות התגים', () {
    for (final html in [
      '<b>אב",ג</b>ד',
      '<b><i>אב",ג</i></b>ד',
      '<b title="אב">אב",ג</b>ד',
    ]) {
      final shown = removeHtmlTags(removePunctuation(html));
      expect(shown, 'אב"גד');
      expect(sliceHtmlBySelection(html: html, selectedText: shown), isNotNull);
      expect(
        sliceHtmlBySelection(html: html, selectedText: removeHtmlTags(html)),
        isNotNull,
      );
    }
    for (final entity in ['&quot;', '&#34;', '&#x22;']) {
      final html = '<b>אב$entity</b>,גד';
      final shown = removeHtmlTags(decodeHtmlEntities(removePunctuation(html)));
      expect(shown, 'אב"גד');
      expect(
        sliceHtmlBySelection(html: html, selectedText: 'אב"גד'),
        isNotNull,
      );
    }
  });

  test('רווח מפיסוק ומקף של שם קדוש יכולים להופיע באותה בחירה', () {
    expect(
      sliceHtmlBySelection(
        html: '<b>אב"</b>,גד אדני',
        selectedText: 'אב גד אד-ני',
      ),
      '<b>אב</b> גד אד-ני',
    );
  });

  test('מירכאות שנבחרו נשמרות גם כשכולן בצומת נפרד', () {
    expect(
      sliceHtmlBySelection(html: '<b>אב"</b>,גד', selectedText: 'אב",גד'),
      '<b>אב"</b>,גד',
    );
    expect(
      sliceHtmlBySelection(html: '<b>"</b>אב', selectedText: '"אב'),
      '"אב',
    );
  });

  test('גוף הערת שוליים אינו משתתף בהחלטה על מירכאות', () {
    const html = 'אב"<i class="footnote">ג</i>,גד';
    final shown = TextRendererService.processText(
      html,
      const RenderSettings(removePunctuation: true),
    );
    expect(removeHtmlTags(shown), 'אב גד');
    expect(sliceHtmlBySelection(html: html, selectedText: 'אב גד'), 'אב גד');
  });

  test('שורת הדיווח מהמסד ממופה מהתצוגה בחזרה למקור', () {
    const line = 'כָּלוּא וְחָפְשִׁי בֵין אֲסִירֵי-חֵשֶׁק';
    final shown = TextRendererService.processText(
      line,
      const RenderSettings(removePunctuation: true, removeNikud: true),
    );
    expect(shown, 'כלוא וחפשי בין אסירי חשק');
    const selected = 'אסירי חשק';
    final anchor = computeAnchorForSelection(
      rawLine: line,
      selectedText: selected,
      selectionColumnHint: shown.indexOf(selected),
      punctuationHidden: true,
    );
    expect(line.substring(anchor!.start, anchor.end), 'אֲסִירֵי-חֵשֶׁק');
    expect(
      sliceHtmlBySelection(html: '<b>$line</b>', selectedText: selected),
      '<b>אסירי חשק</b>',
    );
  });

  test('מירכאות ופיסוק ב-attribute נשמרים גם כשיש בו >', () {
    for (final html in [
      '<b title="a>b.,">אב</b>',
      "<b title='a>b\".,'>אב</b>",
    ]) {
      expect(stripNonAcronymQuotes(html), html);
      final sliced = sliceHtmlBySelection(html: html, selectedText: 'אב');
      expect(sliced, isNotNull);
      expect(
        html_parser.parseFragment(sliced!).querySelector('b')!.attributes,
        html_parser.parseFragment(html).querySelector('b')!.attributes,
      );
    }
  });
}
