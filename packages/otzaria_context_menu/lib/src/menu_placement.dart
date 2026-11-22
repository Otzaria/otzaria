import 'dart:math' as math;
import 'dart:ui';

/// איפה התפריט ביחס לאצבע שפתחה אותו.
enum TouchMenuSide {
  /// מעל האצבע.
  above,

  /// לצד האצבע (בצד שלפי כיוון הקריאה, ואם אין מקום — בצד השני).
  beside,

  /// מתחת לאצבע, במרחק שהיא לא מכסה אותו.
  below,

  /// אין מקום שהאצבע לא מכסה (תפריט גבוה במסך קטן): הפתיחה הרגילה.
  fallback,
}

/// מיקום תפריט הקשר שנפתח באצבע.
typedef TouchMenuPlacement = ({Offset topLeft, TouchMenuSide side});

/// רדיוס האזור שהאצבע מכסה סביב נקודת הנגיעה: חצי מנקודת מגע טיפוסית
/// (כ-48) ועוד מרווח, כדי שגם קצה האצבע לא יסתיר את הפריט הקרוב.
const double kFingerClearance = 32;

/// מחשבת היכן לפתוח תפריט בגודל [panel] כשהאצבע נוגעת ב-[anchor] בתוך
/// [overlay]. הסדר: מעל האצבע, ואם אין מקום — לצדה, ואם אין — מתחתיה
/// (רק כשהוא נכנס כולו בלי שהאצבע תכסה אותו). כשאין שום מקום כזה חוזרת
/// לפתיחה הרגילה (בצד הגדול יותר, בתוך המסך).
TouchMenuPlacement placeMenuAwayFromFinger({
  required Size overlay,
  required Offset anchor,
  required Size panel,
  required bool isRtl,
  double screenPadding = 8,
  double clearance = kFingerClearance,
}) {
  final pad = screenPadding;
  double clampX(double x) =>
      x.clamp(pad, math.max(pad, overlay.width - panel.width - pad)).toDouble();
  double clampY(double y) => y
      .clamp(pad, math.max(pad, overlay.height - panel.height - pad))
      .toDouble();

  // בציר האופקי התפריט צמוד לנקודת הנגיעה בקצה ההתחלה לפי כיוון הקריאה
  // (RTL גדל שמאלה), והופך רק כשאין מקום — כמו בפתיחה הרגילה.
  final double alignedLeft;
  if (isRtl) {
    final grownLeft = anchor.dx - panel.width;
    alignedLeft = grownLeft >= pad ? grownLeft : anchor.dx;
  } else {
    alignedLeft = anchor.dx + panel.width <= overlay.width - pad
        ? anchor.dx
        : anchor.dx - panel.width;
  }

  final aboveTop = anchor.dy - clearance - panel.height;
  if (aboveTop >= pad) {
    return (
      topLeft: Offset(clampX(alignedLeft), aboveTop),
      side: TouchMenuSide.above,
    );
  }

  // לצד האצבע: הפריט הראשון בגובה הנגיעה בערך, הרוחב מופרד במרווח.
  final leftOfFinger = anchor.dx - clearance - panel.width;
  final rightOfFinger = anchor.dx + clearance;
  final fitsLeft = leftOfFinger >= pad;
  final fitsRight = rightOfFinger + panel.width <= overlay.width - pad;
  final sideLeft = switch ((isRtl, fitsLeft, fitsRight)) {
    (_, false, false) => null,
    (_, true, false) => leftOfFinger,
    (_, false, true) => rightOfFinger,
    (true, true, true) => leftOfFinger,
    (false, true, true) => rightOfFinger,
  };
  if (sideLeft != null) {
    return (
      topLeft: Offset(sideLeft, clampY(anchor.dy - clearance)),
      side: TouchMenuSide.beside,
    );
  }

  final belowTop = anchor.dy + clearance;
  if (belowTop + panel.height <= overlay.height - pad) {
    return (
      topLeft: Offset(clampX(alignedLeft), belowTop),
      side: TouchMenuSide.below,
    );
  }

  final opensAbove =
      anchor.dy > overlay.height - anchor.dy &&
      overlay.height - anchor.dy < panel.height;
  return (
    topLeft: Offset(
      clampX(alignedLeft),
      clampY(opensAbove ? anchor.dy - panel.height : anchor.dy),
    ),
    side: TouchMenuSide.fallback,
  );
}
