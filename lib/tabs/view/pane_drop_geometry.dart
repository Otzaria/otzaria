import 'dart:ui';

/// המקום המזערי שחייב להישאר לכל חלונית — בפיצול ובגרירת המפריד כאחד.
const double kMinPaneExtent = 140;

/// הצד שאליו נכנסת הכרטיסייה הנגררת בפיצול.
enum PaneDropSide {
  /// החלונית הראשונה — הימנית ב-RTL.
  start,

  /// החלונית השנייה — השמאלית ב-RTL.
  end,
}

/// לאיזה צד תיכנס כרטיסייה שהמצביע נמצא ב-[localPosition].
///
/// המסך מחולק בקו האמצע: חצי המסך שמצביעים אליו הוא הצד שיתקבל, כך
/// שהחיווי מראה בדיוק את המקום שהספר יתפוס.
PaneDropSide dropSideFor({
  required Offset localPosition,
  required Size size,
  required TextDirection textDirection,
}) {
  if (size.width <= 0) return PaneDropSide.start;

  final pastMiddle = localPosition.dx >= size.width / 2;
  final onLeadingHalf = textDirection == TextDirection.rtl
      ? pastMiddle
      : !pastMiddle;
  return onLeadingHalf ? PaneDropSide.start : PaneDropSide.end;
}

/// האם יש מקום לפצל שטח בגודל [size] לשתי חלוניות קריאות.
bool canSplitPane(Size size) => size.width >= kMinPaneExtent * 2;

/// המלבן שהכרטיסייה הנגררת תתפוס — הבסיס לחיווי הוויזואלי.
Rect previewRectFor({
  required PaneDropSide side,
  required Size size,
  required TextDirection textDirection,
}) {
  final onLeft =
      (side == PaneDropSide.start) == (textDirection == TextDirection.ltr);
  return Rect.fromLTWH(
    onLeft ? 0 : size.width / 2,
    0,
    size.width / 2,
    size.height,
  );
}
