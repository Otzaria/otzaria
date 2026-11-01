import 'package:flutter/foundation.dart';

/// מזהה חלון יציב, שאינו נגזר ממשאב של מערכת ההפעלה.
///
/// עדיף על שימוש ישיר ב-`viewId`, ב-HWND או במזהה [Workspace]:
///
/// * HWND ו-`viewId` **מתחלפים** בין הפעלות ואף בתוך אותה הפעלה, ולכן ערך
///   שנשמר לדיסק עם אחד מהם מצביע אחרי הפעלה מחדש על חלון אחר — או על כלום.
/// * מזהה שולחן עבודה מתאר *תוכן*, ולא את החלון שמציג אותו; אותו שולחן
///   עבודה יכול לעבור בין חלונות.
///
/// המזהה אינו מייצר את עצמו: הוא מתקבל מבחוץ, כדי שמקור אחד יהיה אחראי
/// לייחודיות.
@immutable
final class AppWindowId {
  const AppWindowId(this.value);

  final String value;

  /// החלון הראשי של התהליך.
  static const AppWindowId primary = AppWindowId('window-primary');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AppWindowId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  /// אינו חושף מידע מזהה — הערך הוא מזהה פנימי בלבד, ובטוח ללוגים.
  @override
  String toString() => 'AppWindowId($value)';
}
