import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';

/// לחיצה על פריט ניווט שהוא מסך חייבת לסגור את פאנל הכלים — ה-scrim שלו מכסה
/// רק את אזור התוכן, ולכן בלי הסגירה הוא נשאר צף מעל המסך החדש.
void main() {
  group('shouldCloseToolsLauncherOnNavTap', () {
    test('כל שאר פריטי הניווט סוגרים את הפאנל', () {
      final closing = <int>[];
      for (var i = 0; i < 6; i++) {
        if (MainWindowScreenState.shouldCloseToolsLauncherOnNavTap(i)) {
          closing.add(i);
        }
      }
      // ספריה, איתור, עיון, חיפוש, הגדרות — הכול פרט לפריט "כלים".
      expect(closing, hasLength(5));
      expect(
        closing.contains(0),
        isTrue,
        reason: 'ספריה הוא הפריט הראשון, והבאג המקורי היה בו',
      );
    });

    test('אינדקס מחוץ לטווח אינו זורק', () {
      expect(
        MainWindowScreenState.shouldCloseToolsLauncherOnNavTap(-1),
        isFalse,
      );
      expect(
        MainWindowScreenState.shouldCloseToolsLauncherOnNavTap(99),
        isFalse,
      );
    });
  });
}
