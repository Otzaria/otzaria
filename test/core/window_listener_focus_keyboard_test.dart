import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/window_listener.dart';

/// issue #1071 — onWindowFocus קרא ל-clearState() שמוחק את *כל* ה-handlers
/// של HardwareKeyboard, ואיתם מאזין ה-Ctrl+C של המפרשים בצורת הדף: אחרי
/// יציאה מהחלון וחזרה, העתקה במקלדת ממפרש הציגה "אנא בחר טקסט להעתקה"
/// לצמיתות (תפריט ההקשר המשיך לעבוד — הוא אינו תלוי ב-handler).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KeyDownEvent keyDown(
    PhysicalKeyboardKey physical,
    LogicalKeyboardKey logical,
  ) => KeyDownEvent(
    physicalKey: physical,
    logicalKey: logical,
    timeStamp: Duration.zero,
  );

  KeyUpEvent keyUp(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
      KeyUpEvent(
        physicalKey: physical,
        logicalKey: logical,
        timeStamp: Duration.zero,
      );

  test('onWindowFocus משחרר מקש תקוע ואינו מוחק handlers רשומים', () {
    final keyboard = HardwareKeyboard.instance;

    // מקש "תקוע": KeyDown שלא קיבל KeyUp (הוחזק בזמן מעבר חלון).
    keyboard.handleKeyEvent(
      keyDown(PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA),
    );
    expect(keyboard.physicalKeysPressed, contains(PhysicalKeyboardKey.keyA));

    var handlerCalled = false;
    bool handler(KeyEvent event) {
      handlerCalled = true;
      return false;
    }

    keyboard.addHandler(handler);
    addTearDown(() => keyboard.removeHandler(handler));

    AppWindowListener().onWindowFocus();

    expect(
      keyboard.physicalKeysPressed,
      isEmpty,
      reason: 'המקש התקוע חייב להשתחרר — ההגנה המקורית של onWindowFocus',
    );

    handlerCalled = false;
    keyboard.handleKeyEvent(
      keyDown(PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB),
    );
    keyboard.handleKeyEvent(
      keyUp(PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB),
    );
    expect(
      handlerCalled,
      isTrue,
      reason:
          'handler שנרשם לפני onWindowFocus חייב להמשיך לקבל '
          'אירועים — issue #1071',
    );
  });
}
