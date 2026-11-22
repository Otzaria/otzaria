import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:share_plus/share_plus.dart';

/// שיתוף טקסט דרך גיליון השיתוף של המערכת. מופשט כדי שבדיקות יחליפו אותו
/// ב-fake ולא יפתחו גיליון אמיתי.
abstract interface class TextShareService {
  /// השירות שבו משתמשים הווידג'טים; בדיקות מחליפות ומחזירות בסיום.
  static TextShareService instance = const SharePlusTextShareService();

  /// האם גיליון שיתוף של המערכת מוצג בפלטפורמה: Android ו-iOS בלבד.
  /// בשולחן העבודה שיתוף הטקסט הוא העתקה, שכבר קיימת בתפריטים.
  static bool isAvailableOn(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// פותח את גיליון השיתוף עם [text]. [origin] הוא מלבן גלובלי שאליו מעוגן
  /// החלון הצף ב-iPad (בלעדיו הוא מופיע במרכז המסך).
  Future<void> shareText(String text, {Rect? origin});
}

/// המימוש האמיתי, על `share_plus`.
class SharePlusTextShareService implements TextShareService {
  const SharePlusTextShareService();

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }
}
