import 'package:flutter/material.dart';

/// התנהגות גלילה שמצמידה את פס הגלילה האנכי לקצה מסוים, במקום לקצה
/// ה-trailing שנקבע אוטומטית לפי כיוון הטקסט (בעברית — שמאל).
///
/// משכפלת את לוגיקת [MaterialScrollBehavior] (פס אנכי בדסקטופ בלבד)
/// ומוסיפה רק את [scrollbarOrientation]. שמור מרווח לפס בצד שנבחר,
/// אחרת הוא נצבע מעל התוכן.
class EdgeScrollbarBehavior extends MaterialScrollBehavior {
  const EdgeScrollbarBehavior(this.orientation);

  final ScrollbarOrientation orientation;

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
        return Scrollbar(
          controller: details.controller,
          scrollbarOrientation: orientation,
          child: child,
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return child;
    }
  }
}
