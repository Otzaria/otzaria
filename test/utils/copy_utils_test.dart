import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/copy_utils.dart';

void main() {
  group('CopyUtils.buildStyledHtml', () {
    test('מייצר בלוקים נפרדים לכל שורה בלי תגיות br', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה א\nשורה ב',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, contains('<div>שורה א</div><div>שורה ב</div>'));
      expect(html, isNot(contains('<br>')));
    });

    test('שומר שורה ריקה כבלוק נפרד', () {
      final html = CopyUtils.buildStyledHtml(
        htmlText: 'שורה א\n\nשורה ב',
        fontFamily: 'David',
        fontSize: 20,
      );

      expect(html, contains('<div>שורה א</div><div><br></div><div>שורה ב</div>'));
    });
  });
}
