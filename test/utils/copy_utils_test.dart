import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

void main() {
  group('CopyUtils.applyCopyPreferences', () {
    test('מחליף שם הוי"ה כשההגדרה פעילה', () {
      final result = CopyUtils.applyCopyPreferences(
        text: 'ברוך אתה ה׳ ויהוה',
        replaceHolyNames: true,
      );

      expect(result, contains('יקוק'));
      expect(result, isNot(contains('יהוה')));
    });

    test("מחליף שם הוי\"ה בה' בסגנון hehApostrophe", () {
      final result = CopyUtils.applyCopyPreferences(
        text: 'ויאמר יהוה אל משה',
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.hehApostrophe,
      );

      expect(result, "ויאמר ה' אל משה");
    });

    test('משאיר טקסט ללא שינוי כשההגדרה כבויה', () {
      final result = CopyUtils.applyCopyPreferences(
        text: 'יהוה',
        replaceHolyNames: false,
      );

      expect(result, 'יהוה');
    });
  });

  group('CopyUtils.applyCopyPreferencesForClipboard', () {
    test('מקף מוקף רווחים שהוסתר בהעתקה אינו משאיר רווח כפול', () {
      const line =
          'וְטַבְּעוֹתָיו בְּיָדָיו — פָּטוּר, וְאִילּוּ הוֹצִיאָן כְּמוֹת שֶׁהֵן — חַיָּיב.';
      final result = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: line,
        htmlText: '<b>$line</b>',
        replaceHolyNames: false,
        profile: const TextDisplayProfile(
          nikud: MarkVisibility.hide,
          punctuation: MarkVisibility.hide,
        ),
      );

      const expected = 'וטבעותיו בידיו פטור ואילו הוציאן כמות שהן חייב.';
      expect(result.plainText, expected);
      expect(result.htmlText, '<b>$expected</b>');
    });

    test('שומר תגיות HTML כאשר שם הוי"ה נמצא בתוך text node יחיד', () {
      final result = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: 'יהוה',
        htmlText: '<b>יהוה</b>',
        replaceHolyNames: true,
      );

      expect(result.plainText, 'יקוק');
      expect(result.htmlText, '<b>יקוק</b>');
    });

    test('נופל ל-plain text כאשר HTML מפצל את שם הוי"ה בין תגיות', () {
      final result = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: 'יהוה',
        htmlText: 'י<b>הו</b>ה',
        replaceHolyNames: true,
      );

      expect(result.plainText, 'יקוק');
      expect(result.htmlText, 'יקוק');
    });

    test('שומר את ה-HTML כשמעבר שורה מיוצג ע"י <br>', () {
      final result = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: 'ויאמר יהוה\nאל משה',
        htmlText: 'ויאמר יהוה<br><b>אל משה</b>',
        replaceHolyNames: true,
      );

      expect(result.plainText, 'ויאמר יקוק\nאל משה');
      expect(result.htmlText, 'ויאמר יקוק<br><b>אל משה</b>');
    });

    test("סגנון ה' נשמר עקבי בין ה-plain text ל-HTML", () {
      final result = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: 'ויאמר יהוה',
        htmlText: '<b>ויאמר יהוה</b>',
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.hehApostrophe,
      );

      expect(result.plainText, "ויאמר ה'");
      expect(result.htmlText, "<b>ויאמר ה'</b>");
    });

    test('בחירה רב-שורתית בלי HTML אינה מפוענחת כ-HTML', () {
      CopyUtils.debugHtmlParseCount = 0;
      final result = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: 'בְּרֵאשִׁ֖ית בָּרָ֣א\nוַיֹּ֥אמֶר יהוה',
        htmlText: 'בְּרֵאשִׁ֖ית בָּרָ֣א\nוַיֹּ֥אמֶר יהוה',
        replaceHolyNames: true,
        removeNikud: true,
      );

      expect(result.plainText, 'בראשית ברא\nויאמר יקוק');
      expect(result.htmlText, 'בראשית ברא\nויאמר יקוק');
      expect(CopyUtils.debugHtmlParseCount, 0);
    });

    test('טקסט פשוט עם תווי HTML נשאר מקודד כבעבר', () {
      for (final (input, html) in [
        ('יהוה & משה\nאהרן', 'יקוק &amp; משה\nאהרן'),
        ('יהוה > משה', 'יקוק &gt; משה'),
        ('יהוה משה', 'יקוק&nbsp;משה'),
        ('יהוה\r\nמשה', 'יקוק\nמשה'),
      ]) {
        final result = CopyUtils.applyCopyPreferencesForClipboard(
          plainText: input,
          htmlText: input,
          replaceHolyNames: true,
        );
        expect(result.htmlText, html);
      }
    });
  });

  group('CopyUtils.buildClipboardItem', () {
    DataWriterItem build({required bool plainTextOnly}) =>
        CopyUtils.buildClipboardItem(
          plainText: 'שורה',
          htmlText: '<b>שורה</b>',
          fontFamily: 'David',
          fontSize: 20,
          plainTextOnly: plainTextOnly,
        );

    test('ברירת המחדל כותבת טקסט פשוט ו-HTML', () {
      expect(build(plainTextOnly: false).data, hasLength(2));
    });

    test('ללא עיצוב כותב טקסט פשוט בלבד — issue #1299', () {
      expect(build(plainTextOnly: true).data, hasLength(1));
    });
  });

  group('CopyUtils.buildStyledHtml', () {
    test('מעבר שורה = בלוק (Enter ב-Word), לא <br> רך — issue #943', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה א\nשורה ב',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, isNot(contains('<br>שורה ב')));
      expect(html, contains('>שורה א</div>'));
      expect(html, contains('font-family: David;'));
    });

    test('השורה האחרונה inline — בלי Enter מיותר בסוף ההדבקה', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה א\nשורה ב',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, endsWith('>שורה ב</span>'));
    });

    test('שורה ריקה באמצע נשמרת כפסקה ריקה', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה א\n\nשורה ב',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, contains('>שורה א</div>'));
      expect(html, contains('><br></div>'));
      expect(html, endsWith('>שורה ב</span>'));
    });

    test('שורה בודדת נשארת inline בלבד — ללא בלוקים', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, isNot(contains('<div')));
      expect(html, isNot(contains('<p ')));
      expect(html, contains('<span '));
      expect(html, endsWith('>שורה</span>'));
    });

    test('אינו עוטף ב-<html><body> (super_clipboard כבר מוסיף עטיפה זו)', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, isNot(contains('<html>')));
      expect(html, isNot(contains('<body>')));
      expect(html, isNot(contains('</body>')));
      expect(html, isNot(contains('</html>')));
    });
  });
}
