import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

/// issue #1317 — באנדרואיד המקלדת נפתחה מעצמה בכל כניסה למסך הספרייה, כי
/// שדה החיפוש קיבל פוקוס אוטומטי. במכשיר מגע פוקוס לשדה טקסט פותח מקלדת.
void main() {
  test(
    'פוקוס אוטומטי לשדה החיפוש רק בפלטפורמות עם מקלדת פיזית (issue #1317)',
    () {
      final defaults = ShortcutValidator.defaultShortcuts;
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.android, defaults),
        isFalse,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.iOS, defaults),
        isFalse,
      );
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
      expect(
        shouldAutofocusLibrarySearch(
          TargetPlatform.windows,
          ShortcutValidator.defaultShortcuts,
        ),
        isTrue,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, {
          'key-shortcut-open-settings': 's',
        }),
        isFalse,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, {
          'key-shortcut-copy-book-link': 'c',
        }),
        isTrue,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, {
          'key-shortcut-print': 'p',
        }),
        isTrue,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, {
          'key-shortcut-open-history': 'h',
        }),
        isTrue,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, {
          'key-shortcut-open-library-browser': 'l',
        }),
        isFalse,
      );
      expect(
        shouldAutofocusLibrarySearch(TargetPlatform.windows, {
          'key-shortcut-open-settings': 'ctrl+s',
        }),
        isTrue,
      );
    },
  );
}
