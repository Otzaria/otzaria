import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/library_browser.dart';

/// issue #1317 — באנדרואיד המקלדת נפתחה מעצמה בכל כניסה למסך הספרייה, כי
/// שדה החיפוש קיבל פוקוס אוטומטי. במכשיר מגע פוקוס לשדה טקסט פותח מקלדת.
void main() {
  test('פוקוס אוטומטי לשדה החיפוש רק בפלטפורמות עם מקלדת פיזית', () {
    expect(shouldAutofocusLibrarySearch(TargetPlatform.android), isFalse);
    expect(shouldAutofocusLibrarySearch(TargetPlatform.iOS), isFalse);
    expect(shouldAutofocusLibrarySearch(TargetPlatform.windows), isTrue);
    expect(shouldAutofocusLibrarySearch(TargetPlatform.linux), isTrue);
    expect(shouldAutofocusLibrarySearch(TargetPlatform.macOS), isTrue);
  });
}
