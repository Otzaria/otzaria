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
      expect(p.normalized, 'ובו ט סעיפים: יתגבר כארי');
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
  });
}
