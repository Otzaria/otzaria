import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/system_font_locator.dart';

void main() {
  group('גופן נבחר נמצא לפי השם בלי סריקת כל הגופנים (issue #2076)', () {
    test('שם קובץ או שם ברישום מזכירים את המשפחה', () {
      expect(
        SystemFontLocator.nameMentionsFamily(
          'FrankRuehlCLM-Bold',
          'Frank Ruehl CLM',
        ),
        isTrue,
      );
      // התקנה פר-משתמש: שם הקובץ שרירותי, שם הרישום נושא את המשפחה.
      expect(
        SystemFontLocator.nameMentionsFamily(
          'Guttman Yad-Brush (TrueType)',
          'Guttman Yad',
        ),
        isTrue,
      );
    });

    test('קובץ של משפחה אחרת אינו נקרא', () {
      expect(SystemFontLocator.nameMentionsFamily('arialbd', 'David'), isFalse);
      expect(SystemFontLocator.nameMentionsFamily('david', '  '), isFalse);
    });
  });
}
