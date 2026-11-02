import 'package:otzaria/core/windowing/app_window_id.dart';

/// החלון שקיבל פוקוס אחרון — היעד של קישורי עומק כשאין חלון פעיל.
///
/// בזיכרון ולא בדיסק בכוונה: "אחרון שהיה פעיל" הוא נתון של ההפעלה הנוכחית.
abstract final class LastActiveWindow {
  static AppWindowId _id = AppWindowId.primary;

  static AppWindowId get id => _id;

  static void markActive(AppWindowId windowId) => _id = windowId;

  /// לבדיקות בלבד — מחזיר את המצב לברירת המחדל.
  static void resetForTest() => _id = AppWindowId.primary;
}
