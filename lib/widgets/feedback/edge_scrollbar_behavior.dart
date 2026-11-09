import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';

/// התנהגות הגלילה של אוצריא: פס הגלילה האנכי בצד פיזי קבוע, ולא בקצה
/// ה-trailing שנקבע לפי כיוון הטקסט (בעברית — שמאל), ברצועה משלו כשיש מה
/// לגלול ([ScrollbarGutter]).
///
/// [EdgeScrollbarBehavior.right] היא ה-`scrollBehavior` של ה-MaterialApp,
/// ולכן חלה על כל רשימה באפליקציה, גם בדיאלוגים. צד שמאל רק בחריג מתועד
/// (חלונית צד משמאל לתוכן, `AdaptiveSidePane`).
///
/// משכפלת את לוגיקת [MaterialScrollBehavior] (פס אנכי בדסקטופ בלבד).
class EdgeScrollbarBehavior extends MaterialScrollBehavior {
  const EdgeScrollbarBehavior(this.orientation, {this.reserveGutter = true});

  /// פס בקצה ימין — הצד של כל פסי הגלילה, כמו מחווני אזור הקריאה.
  const EdgeScrollbarBehavior.right({this.reserveGutter = true})
    : orientation = ScrollbarOrientation.right;

  final ScrollbarOrientation orientation;

  /// false: הפס בלבד, לאזור ששומר בעצמו רצועה קבועה לפס.
  final bool reserveGutter;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical) {
      return child;
    }
    switch (getPlatform(context)) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return ScrollbarGutter(
          controller: details.controller,
          side: orientation,
          reserveGutter: reserveGutter && !_isTextFieldScrollable(context),
          child: child,
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return child;
    }
  }

  /// האם אזור הגלילה הוא של שדה טקסט ([EditableText] רב-שורות). שדה כזה מקבל
  /// את הפס בלי רצועה: רצועה שנפתחת כשהטקסט עובר את maxLines הייתה מצמצמת את
  /// עמודת הטקסט באמצע ההקלדה, וכל הטקסט היה נשבר מחדש. [context] הוא של
  /// ה-Scrollable, והחיפוש נעצר ב-Scrollable חיצוני: שדה טקסט לא מכיל רשימות.
  static bool _isTextFieldScrollable(BuildContext context) {
    var found = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditableText) {
        found = true;
        return false;
      }
      return widget is! Scrollable;
    });
    return found;
  }
}
