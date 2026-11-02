import 'package:flutter_test/flutter_test.dart';
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
      'לאמר - דבר': 'לאמר  דבר',
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
}
