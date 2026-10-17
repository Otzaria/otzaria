import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

/// מיקוד אוטומטי של שדה החיפוש בכניסה למסך הספרייה — שולחני בלבד.
///
/// שתי הכניסות לספרייה ב-MainWindowScreen משתמשות במדיניות המשותפת הזאת.
void main() {
  group('shouldAutofocusLibrarySearch', () {
    final defaults = ShortcutValidator.defaultShortcuts;

    test('במובייל השדה אינו ממוקד — המקלדת לא נפתחת בכל כניסה', () {
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.android, defaults),
        isFalse,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.iOS, defaults),
        isFalse,
      );
    });

    test('בשולחני השדה ממוקד — המשתמש מקליד מיד', () {
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, defaults),
        isTrue,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.linux, defaults),
        isTrue,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.macOS, defaults),
        isTrue,
      );
    });
  });
}
