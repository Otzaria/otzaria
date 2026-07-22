import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FullscreenHelper.systemUiModeForFullscreen', () {
    test('מסך מלא בוחר immersiveSticky - מסתיר את שורת המצב', () {
      expect(
        FullscreenHelper.systemUiModeForFullscreen(true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('יציאה ממסך מלא בוחרת edgeToEdge - משיבה את שורת המצב', () {
      expect(
        FullscreenHelper.systemUiModeForFullscreen(false),
        SystemUiMode.edgeToEdge,
      );
    });
  });
  group('FullscreenHelper.isContextAllowed', () {
    test('מתיר בעיון כשיש טאב פתוח', () {
      expect(FullscreenHelper.isContextAllowed(Screen.reading, true), isTrue);
    });

    test('חוסם בעיון ללא טאבים פתוחים', () {
      expect(FullscreenHelper.isContextAllowed(Screen.reading, false), isFalse);
    });

    test('מתיר בכלים/תוספים ללא תלות בטאבים', () {
      expect(FullscreenHelper.isContextAllowed(Screen.more, false), isTrue);
      expect(FullscreenHelper.isContextAllowed(Screen.more, true), isTrue);
    });

    test('חוסם בספרייה/חיפוש/איתור/הגדרות', () {
      for (final screen in [
        Screen.library,
        Screen.find,
        Screen.search,
        Screen.settings,
      ]) {
        expect(
          FullscreenHelper.isContextAllowed(screen, true),
          isFalse,
          reason: '$screen should not allow fullscreen',
        );
      }
    });
  });
}
