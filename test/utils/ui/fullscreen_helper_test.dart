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

    // כלים ותוספים חיים ככרטיסיות בעיון, ולכן הם נופלים תחת אותו כלל:
    // מסך מלא מותר רק כשיש כרטיסיה פתוחה.
    test('מתיר בכלים/תוספים דרך כרטיסיית עיון פתוחה', () {
      expect(FullscreenHelper.isContextAllowed(Screen.reading, true), isTrue);
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

  group('FullscreenHelper macOS behavior', () {
    test('ב-macOS מסך מלא לא מסתיר את כרום האפליקציה', () {
      expect(
        FullscreenHelper.shouldUseImmersiveLayout(
          platform: TargetPlatform.macOS,
          isFullscreen: true,
          screen: Screen.reading,
          hasOpenTabs: true,
        ),
        isFalse,
      );
    });

    test('ב-macOS ניווט לספרייה לא יוצא ממסך מלא', () {
      expect(
        FullscreenHelper.shouldExitFullscreenOnNavigation(
          platform: TargetPlatform.macOS,
          isFullscreen: true,
          screen: Screen.library,
          hasOpenTabs: true,
        ),
        isFalse,
      );
    });

    test('בפלטפורמות אחרות מסך מלא אימרסיבי נשאר תלוי-הקשר', () {
      expect(
        FullscreenHelper.shouldUseImmersiveLayout(
          platform: TargetPlatform.windows,
          isFullscreen: true,
          screen: Screen.reading,
          hasOpenTabs: true,
        ),
        isTrue,
      );
      expect(
        FullscreenHelper.shouldExitFullscreenOnNavigation(
          platform: TargetPlatform.windows,
          isFullscreen: true,
          screen: Screen.library,
          hasOpenTabs: true,
        ),
        isTrue,
      );
    });
  });
}
