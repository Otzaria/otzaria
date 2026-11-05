import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/edge_scrollbar_behavior.dart';

/// פס הגלילה במסך ההגדרות: חריג מתועד מהימין הקבוע (הערת בעל הפרויקט,
/// 4.11). הפס נשאר בקצה ה-end של שפת ההגדרות, כמו לפני הכלל: בעברית בשמאל,
/// ובאנגלית בימין.
abstract final class SettingsScrollbar {
  /// הצד הפיזי של הפס לפי כיוון ההגדרות במקום.
  static ScrollbarOrientation sideOf(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? ScrollbarOrientation.left
      : ScrollbarOrientation.right;

  /// כל רשימה מתחת ל-[child] מקבלת את הפס בצד של ההגדרות. פס מפורש
  /// (`AppScrollbar`) בתוך ההגדרות מקבל `side:` [sideOf].
  static Widget scope(BuildContext context, {required Widget child}) =>
      ScrollConfiguration(
        behavior: EdgeScrollbarBehavior(sideOf(context)),
        child: child,
      );
}
