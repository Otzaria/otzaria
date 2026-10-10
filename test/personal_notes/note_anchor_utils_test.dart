import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  group('projectLine', () {
    test('מסיר תגיות HTML וניקוד ומכווץ רווחים', () {
      const raw = '<b>וַיֹּאמֶר</b>   יְהוָה';
      final p = projectLine(raw);
      expect(p.normalized, 'ויאמר יהוה');
      // אורך המפה תמיד גדול ב-1 מאורך הטקסט המנורמל.
      expect(p.rawIndex.length, p.normalized.length + 1);
    });

    test('המיפוי מצביע חזרה לתווים הנכונים בשורה הגולמית', () {
      const raw = 'אבג <i>דהו</i> זחט';
      final p = projectLine(raw);
      expect(p.normalized, 'אבג דהו זחט');
      // התו 'ד' במנורמל (אינדקס 4) צריך להצביע על 'ד' הגולמי.
      final dNorm = p.normalized.indexOf('ד');
      expect(raw[p.rawIndex[dNorm]], 'ד');
    });

    test('מקף עברי (־) הופך לרווח, עקבי עם normalizeAnchorText', () {
      const raw = 'כל־ישראל';
      final p = projectLine(raw);
      expect(p.normalized, 'כל ישראל');
      expect(normalizeAnchorText('כל־ישראל'), 'כל ישראל');
      // ולכן בחירה עם מקף נמצאת מול שורה עם מקף.
      final range = locateAnchor(rawLine: raw, anchorText: 'כל ישראל');
      expect(range, isNotNull);
    });

    test('<br> נחשב רווח — בחירה שחוצה אותו מאותרת (תרחיש שו"ע)', () {
      // בשו"ע כותרת הסעיף מופרדת מהגוף ב-<br>; ברינדור זה רווח/שורה חדשה,
      // ולכן הבחירה כוללת רווח שם — חייב להתאים לעיגון.
      const raw = '<b>ובו ט סעיפים:</b><br>יתגבר כארי';
      final p = projectLine(raw);
      expect(p.normalized, 'ובו ט סעיפים יתגבר כארי');
      // הטקסט שנבחר (\n מ-<br>) מנורמל לרווח ונמצא בעיגון.
      final range = locateAnchor(rawLine: raw, anchorText: 'סעיפים:\nיתגבר');
      expect(range, isNotNull);
    });
  });

  group('locateAnchor', () {
    test('מאתר ביטוי פשוט ומחזיר טווח גולמי תקין', () {
      const raw = 'וַיֹּאמֶר יְהוָה אֶל מֹשֶׁה לֵּאמֹר';
      final range = locateAnchor(rawLine: raw, anchorText: 'אל משה');
      expect(range, isNotNull);
      final sub = raw.substring(range!.start, range.end);
      expect(normalizeAnchorText(sub), 'אל משה');
    });

    test('משתמש ב-prefix כדי לבחור את המופע הנכון כשהטקסט חוזר', () {
      const raw = 'משה אמר משה דיבר משה הלך';
      // ללא הקשר — נבחר המופע הראשון; עם prefix מתאים — המופע השני.
      final range = locateAnchor(
        rawLine: raw,
        anchorText: 'משה',
        prefix: 'אמר ',
      );
      expect(range, isNotNull);
      expect(range!.start, raw.indexOf('משה', 1));
    });

    test('מחזיר null כשהביטוי אינו קיים בשורה', () {
      const raw = 'אבג דהו';
      expect(locateAnchor(rawLine: raw, anchorText: 'זחט'), isNull);
    });
  });

  group('computeAnchorForSelection', () {
    test('מחזיר offset והקשר עבור טקסט שנבחר', () {
      const raw = 'בראשית ברא אלהים את השמים ואת הארץ';
      final anchor = computeAnchorForSelection(
        rawLine: raw,
        selectedText: 'אלהים את',
      );
      expect(anchor, isNotNull);
      final sub = raw.substring(anchor!.start, anchor.end);
      expect(normalizeAnchorText(sub), 'אלהים את');
      expect(anchor.prefix.endsWith('ברא '), isTrue);
      expect(anchor.suffix.startsWith(' השמים'), isTrue);
    });

    test('selectionColumnHint בוחר את המופע הקרוב, לא תמיד הראשון', () {
      const raw = 'משה משה משה';
      // עמודת התחלה ~8 = המופע השלישי.
      final anchor = computeAnchorForSelection(
        rawLine: raw,
        selectedText: 'משה',
        selectionColumnHint: 8,
      );
      expect(anchor, isNotNull);
      expect(anchor!.start, raw.lastIndexOf('משה'));
    });

    test('ללא רמז נבחר המופע הראשון', () {
      const raw = 'משה משה משה';
      final anchor = computeAnchorForSelection(
        rawLine: raw,
        selectedText: 'משה',
      );
      expect(anchor!.start, 0);
    });
  });

  group('עיגון כשהפיסוק מוסתר בתצוגה (issue #1518)', () {
    const raw =
        'אָמַר רַבִּי יוֹחָנָן, מַאי דִּכְתִיב? "וַיֹּאמֶר" - לְעוֹלָם.';
    final shown = removePunctuation(raw);

    test('בחירה מהטקסט המוצג נמצאת בשורה הגולמית', () {
      final start = shown.indexOf('יוֹחָנָן');
      final selected = shown.substring(start, shown.indexOf('דִּכְתִיב') + 9);
      final anchor = computeAnchorForSelection(
        rawLine: raw,
        selectedText: selected,
      );
      expect(anchor, isNotNull);
      final sub = raw.substring(anchor!.start, anchor.end);
      expect(sub, 'יוֹחָנָן, מַאי דִּכְתִיב');
    });

    test('כשהפיסוק מוצג, רמז העמודה בוחר את המופע שנבחר בפועל', () {
      const line =
          'א, ב, ג, ד, ה, ו, ז, ח, ט, י, כ, ל, מ, נ, ס, ע, פ, צ, ק, ר, '
          'אמר רבא בר אמר רבא';
      final anchor = computeAnchorForSelection(
        rawLine: line,
        selectedText: 'אמר רבא',
        selectionColumnHint: line.indexOf('אמר רבא'),
      );
      expect(anchor!.start, line.indexOf('אמר רבא'));
    });

    test('כשהפיסוק מוסתר, רמז העמודה בוחר את המופע השני', () {
      final line = '${List.filled(40, 'א,').join()} מילה משהו מילה';
      final shownLine = removePunctuation(line);
      final anchor = computeAnchorForSelection(
        rawLine: line,
        selectedText: 'מילה',
        selectionColumnHint: shownLine.lastIndexOf('מילה'),
        punctuationHidden: true,
      );
      expect(anchor!.start, line.lastIndexOf('מילה'));
    });

    test('רמז העמודה סופר גם גרשיים שנשמרים בראשי תיבות', () {
      final line = '${List.filled(40, 'רש"י ').join()}מילה משהו מילה';
      final shownLine = removePunctuation(line);
      final anchor = computeAnchorForSelection(
        rawLine: line,
        selectedText: 'מילה',
        selectionColumnHint: shownLine.lastIndexOf('מילה'),
        punctuationHidden: true,
      );
      expect(anchor!.start, line.lastIndexOf('מילה'));
    });

    test('עוגן שנשמר כשהפיסוק הוצג נמצא גם כשהוא מוסתר', () {
      final range = locateAnchor(
        rawLine: raw,
        anchorText: 'מאי דכתיב? "ויאמר"',
      );
      expect(range, isNotNull);
      expect(raw.substring(range!.start, range.end), startsWith('מַאי'));
    });
  });

  group('wrapHtmlRanges', () {
    test('עוטף טווח יחיד בתגיות', () {
      final result = wrapHtmlRanges('אבגדה', const [
        HtmlWrapRange(start: 1, end: 3, openTag: '<u>', closeTag: '</u>'),
      ]);
      expect(result, 'א<u>בג</u>דה');
    });

    test('מדלג על טווחים חופפים (הראשון מנצח)', () {
      final result = wrapHtmlRanges('אבגדה', const [
        HtmlWrapRange(start: 0, end: 3, openTag: '<a>', closeTag: '</a>'),
        HtmlWrapRange(start: 2, end: 4, openTag: '<b>', closeTag: '</b>'),
      ]);
      expect(result, '<a>אבג</a>דה');
    });

    test('טווח שנפתח בתגית מאוזנת עוטף אותה ולא מוצלב', () {
      final result = wrapHtmlRanges('<b>אב</b> גד', const [
        HtmlWrapRange(start: 0, end: 12, openTag: '<a>', closeTag: '</a>'),
      ]);
      expect(result, '<a><b>אב</b> גד</a>');
    });

    test('עיטוף בקפיצות ל-< זהה לסריקה תו-תו (perf)', () {
      const pieces = [
        'א',
        'בג ',
        '<b>',
        '</b>',
        '<a href="x">',
        '</a>',
        '<br/>',
        '<i data-c></i>',
        '<a title="x>y">',
        '&lt;',
        '\u{1F600}',
        '<',
        '>',
        '/',
        'ד',
      ];
      final rnd = Random(7);
      for (var n = 0; n < 2000; n++) {
        final text = [
          for (var k = rnd.nextInt(12); k >= 0; k--)
            pieces[rnd.nextInt(pieces.length)],
        ].join();
        final start = rnd.nextInt(text.length);
        final end = start + 1 + rnd.nextInt(text.length - start);
        final expected =
            text.substring(0, start) +
            _oldAppendWrapped(text, start, end, '<m>', '</m>') +
            text.substring(end);
        expect(
          wrapHtmlRanges(text, [
            HtmlWrapRange(
              start: start,
              end: end,
              openTag: '<m>',
              closeTag: '</m>',
            ),
          ]),
          expected,
          reason: '$text [$start,$end)',
        );
      }
    });

    test('גבולות הטווח בתוך תגיות וישויות זהים לסריקה תו-תו', () {
      const lines = [
        'אב<b>גד</b>הו',
        'אב<a title="x>y">גד</a>הו',
        'אב<i data-c></i><br/>גד',
        'אב<b גד<',
        'אב</b>גד<b>הו',
        'אב&lt;😀גד\uD800\uDC00',
      ];
      for (final text in lines) {
        for (var start = 0; start < text.length; start++) {
          for (var end = start + 1; end <= text.length; end++) {
            expect(
              wrapHtmlRanges(text, [
                HtmlWrapRange(
                  start: start,
                  end: end,
                  openTag: '<m>',
                  closeTag: '</m>',
                ),
              ]),
              text.substring(0, start) +
                  _oldAppendWrapped(text, start, end, '<m>', '</m>') +
                  text.substring(end),
              reason: '$text [$start,$end)',
            );
          }
        }
      }
    });

    test('טווחים קצרים בשורה ארוכה נשמרים גם כשהתגיות מחוץ לטווח', () {
      final body = List.filled(400000, 'א').join();
      for (final suffix in ['', '<b>סוף</b>', '<']) {
        final text = body + suffix;
        final ranges = [
          for (var i = 0; i < 43; i++)
            HtmlWrapRange(
              start: i * 9000 + 1,
              end: i * 9000 + 11,
              openTag: '<m>',
              closeTag: '</m>',
            ),
        ];
        final expected = StringBuffer();
        var cursor = 0;
        for (final range in ranges) {
          expected
            ..write(text.substring(cursor, range.start))
            ..write('<m>')
            ..write(text.substring(range.start, range.end))
            ..write('</m>');
          cursor = range.end;
        }
        expected.write(text.substring(cursor));
        expect(wrapHtmlRanges(text, ranges), expected.toString());
      }
    });
  });
}

/// אורקל עצמאי לשקילות: סריקה תו-תו בלי חיתוך הטווח לפני עיטופו.
String _oldAppendWrapped(
  String text,
  int start,
  int end,
  String openTag,
  String closeTag,
) {
  final buffer = StringBuffer();
  final boundaries = <int>{};
  final openStack = <int>[];
  var i = start;
  while (i < end) {
    if (text[i] != '<') {
      i++;
      continue;
    }
    final gt = text.indexOf('>', i);
    final tagEnd = (gt < 0 || gt >= end) ? end - 1 : gt;
    final isClose = i + 1 < end && text[i + 1] == '/';
    final isSelfClose = tagEnd > i && text[tagEnd - 1] == '/';
    if (isClose) {
      if (openStack.isNotEmpty) {
        openStack.removeLast();
      } else {
        boundaries.add(i);
      }
    } else if (!isSelfClose) {
      openStack.add(i);
    }
    i = tagEnd + 1;
  }
  boundaries.addAll(openStack);
  var wrapOpen = false;
  i = start;
  while (i < end) {
    if (text[i] == '<') {
      final gt = text.indexOf('>', i);
      final tagEnd = (gt < 0 || gt >= end) ? end - 1 : gt;
      final isBoundary = boundaries.contains(i);
      final isOpening =
          i + 1 < end && text[i + 1] != '/' && text[tagEnd - 1] != '/';
      if (isBoundary && wrapOpen) {
        buffer.write(closeTag);
        wrapOpen = false;
      } else if (!isBoundary && isOpening && !wrapOpen) {
        buffer.write(openTag);
        wrapOpen = true;
      }
      buffer.write(text.substring(i, tagEnd + 1));
      i = tagEnd + 1;
    } else {
      if (!wrapOpen) {
        buffer.write(openTag);
        wrapOpen = true;
      }
      buffer.write(text[i]);
      i++;
    }
  }
  if (wrapOpen) buffer.write(closeTag);
  return buffer.toString();
}
