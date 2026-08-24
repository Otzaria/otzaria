import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/copy_utils.dart';

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

    test('משאיר טקסט ללא שינוי כשההגדרה כבויה', () {
      final result = CopyUtils.applyCopyPreferences(
        text: 'יהוה',
        replaceHolyNames: false,
      );

      expect(result, 'יהוה');
    });
  });

  group('CopyUtils.applyCopyPreferencesForClipboard', () {
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
