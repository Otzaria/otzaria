import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/ui/commentary_pane_policy.dart';

void main() {
  group('shouldAutoOpenCommentaryPane', () {
    test('נפתח כשההגדרה דולקת, המצב נתמך, יש מפרשים והפאנל סגור', () {
      expect(
        shouldAutoOpenCommentaryPane(
          settingEnabled: true,
          isSupportedMode: true,
          hasSelectedCommentators: true,
          alreadyAutoOpened: false,
          paneAlreadyOpen: false,
        ),
        isTrue,
      );
    });

    test('ההגדרה כבויה → לא נפתח', () {
      expect(
        shouldAutoOpenCommentaryPane(
          settingEnabled: false,
          isSupportedMode: true,
          hasSelectedCommentators: true,
          alreadyAutoOpened: false,
          paneAlreadyOpen: false,
        ),
        isFalse,
      );
    });

    test('אין מפרשים נבחרים → לא נפתח', () {
      expect(
        shouldAutoOpenCommentaryPane(
          settingEnabled: true,
          isSupportedMode: true,
          hasSelectedCommentators: false,
          alreadyAutoOpened: false,
          paneAlreadyOpen: false,
        ),
        isFalse,
      );
    });

    test('מצב לא נתמך (מפרשים מתחת/צורת הדף) → לא נפתח', () {
      expect(
        shouldAutoOpenCommentaryPane(
          settingEnabled: true,
          isSupportedMode: false,
          hasSelectedCommentators: true,
          alreadyAutoOpened: false,
          paneAlreadyOpen: false,
        ),
        isFalse,
      );
    });

    test('כבר נפתח אוטומטית (כולל אחרי סגירה ידנית) → לא נפתח שוב', () {
      expect(
        shouldAutoOpenCommentaryPane(
          settingEnabled: true,
          isSupportedMode: true,
          hasSelectedCommentators: true,
          alreadyAutoOpened: true,
          paneAlreadyOpen: false,
        ),
        isFalse,
      );
    });

    test('הפאנל כבר פתוח (קישורים/הערות) → לא דורסים אוטומטית', () {
      expect(
        shouldAutoOpenCommentaryPane(
          settingEnabled: true,
          isSupportedMode: true,
          hasSelectedCommentators: true,
          alreadyAutoOpened: false,
          paneAlreadyOpen: true,
        ),
        isFalse,
      );
    });
  });
}
