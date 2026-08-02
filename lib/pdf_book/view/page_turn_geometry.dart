import 'dart:math';

/// ממפה מרחק גרירה מצטבר ל-progress של דפדוף. הקצה החופשי חוצה את הכפולה
/// כולה (פעמיים רוחב עמוד) בדפדוף מלא.
double pageTurnDragProgress({
  required double dragDx,
  required double directionSign,
  required double pageWidth,
}) {
  return (directionSign * dragDx / (2 * max(1.0, pageWidth)))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// החלטת שחרור: זריקה מהירה בכיוון הדפדוף משלימה אותו; זריקה נגדית מבטלת;
/// שחרור איטי מוכרע לפי מעבר מחצית הדרך.
bool shouldCommitPageTurn({
  required double velocity,
  required double progress,
  double flingVelocity = 600,
}) {
  return velocity > flingVelocity ||
      (velocity > -flingVelocity && progress >= 0.5);
}

/// עוצמת הקישוט הזמני של הדפדוף (צללים, קו קצה, סיבי נייר).
///
/// חייבת להתאפס בשני הקצוות: קישוט שנשאר בעוצמה מלאה בפריים האחרון "נופל"
/// בבת אחת כשהתצוגה החיה מחליפה את האנימציה, וזה נראה כקפיצה.
double pageTurnDecorationFade(double progress) =>
    sin(progress.clamp(0.0, 1.0) * pi).clamp(0.0, 1.0).toDouble();

/// רצועה אנכית אחת של הדף המתהפך, אחרי הקרנה למסך.
class PageTurnStrip {
  final double left;
  final double width;
  final double top;
  final double height;
  final double u0;
  final double u1;
  final bool showsFront;

  /// עוצמת ההטיה של הרצועה ביחס למסך (0 = שטוחה, 1 = ניצבת) — להצללה.
  final double tilt;

  /// מרחק יחסי מהשדרה (0 = שדרה, 1 = קצה חופשי).
  final double distance;

  const PageTurnStrip({
    required this.left,
    required this.width,
    required this.top,
    required this.height,
    required this.u0,
    required this.u1,
    required this.showsFront,
    required this.tilt,
    required this.distance,
  });
}

/// גאומטריית דפדוף: הדף ממודל כיריעה גמישה הצירית בשדרה — הקצה החופשי
/// מוביל את הסיבוב (curl), וחלקים מורמים מוגדלים בהקרנה פרספקטיבית.
class PageTurnGeometry {
  static const int stripCount = 42;

  /// זווית ההתעקלות המרבית (רדיאנים) בין השדרה לקצה החופשי באמצע הדפדוף.
  static const double _maxBend = 0.8;

  /// עומק הפרספקטיבה: הגדלה מרבית של ~19% כשהדף ניצב מול המצלמה.
  static const double _perspectiveLift = 0.16;

  final List<PageTurnStrip> strips;
  final double minX;
  final double maxX;
  final double freeEdgeX;
  final double freeEdgeTop;
  final double freeEdgeBottom;
  final double shadeStrength;
  final bool hasBackStrips;

  const PageTurnGeometry._({
    required this.strips,
    required this.minX,
    required this.maxX,
    required this.freeEdgeX,
    required this.freeEdgeTop,
    required this.freeEdgeBottom,
    required this.shadeStrength,
    required this.hasBackStrips,
  });

  factory PageTurnGeometry.compute({
    required double spineX,
    required double pageWidth,
    required double height,
    required double progress,
    required bool turnLeftPage,
  }) {
    final theta = progress.clamp(0.0, 1.0) * pi;
    // ההתעקלות מתאפסת בקצוות כדי שהדף ינחת שטוח, ומוגבלת כך שהקצה לא
    // יעבור את מישור הנחיתה (זווית π).
    final bend = min(_maxBend * sin(theta), pi - theta);
    final sideSign = turnLeftPage ? 1.0 : -1.0;
    final centerY = height / 2;

    double x3d(double u) {
      if (bend < 1e-4) return pageWidth * u * cos(theta);
      return pageWidth / bend * (sin(theta + bend * u) - sin(theta));
    }

    double z3d(double u) {
      if (bend < 1e-4) return pageWidth * u * sin(theta);
      return pageWidth / bend * (cos(theta) - cos(theta + bend * u));
    }

    double kOf(double u) =>
        1.0 / (1.0 - _perspectiveLift * (z3d(u) / pageWidth).clamp(0.0, 1.0));

    double screenX(double u, double k) => spineX - sideSign * x3d(u) * k;

    final strips = <PageTurnStrip>[];
    var minX = spineX;
    var maxX = spineX;
    var hasBackStrips = false;

    for (var i = 0; i < stripCount; i++) {
      final u0 = i / stripCount;
      final u1 = (i + 1) / stripCount;
      final uMid = (u0 + u1) / 2;
      final x0 = screenX(u0, kOf(u0));
      final x1 = screenX(u1, kOf(u1));
      final alphaMid = theta + bend * uMid;
      final kMid = kOf(uMid);
      final halfHeight = centerY * kMid;
      final showsFront = alphaMid <= pi / 2;
      if (!showsFront) hasBackStrips = true;

      strips.add(
        PageTurnStrip(
          left: min(x0, x1),
          width: (x1 - x0).abs(),
          top: centerY - halfHeight,
          height: halfHeight * 2,
          u0: u0,
          u1: u1,
          showsFront: showsFront,
          tilt: sin(alphaMid).clamp(0.0, 1.0),
          distance: uMid,
        ),
      );
      minX = min(minX, min(x0, x1));
      maxX = max(maxX, max(x0, x1));
    }

    final edgeK = kOf(1);
    final edgeHalfHeight = centerY * edgeK;
    return PageTurnGeometry._(
      strips: strips,
      minX: minX,
      maxX: maxX,
      freeEdgeX: screenX(1, edgeK),
      freeEdgeTop: centerY - edgeHalfHeight,
      freeEdgeBottom: centerY + edgeHalfHeight,
      shadeStrength: pageTurnDecorationFade(progress),
      hasBackStrips: hasBackStrips,
    );
  }

  /// הקצה האחורי של היריעה — הגבול שבו העמוד החדש כבר נחשף.
  double trailingX(bool turnLeftPage) => turnLeftPage ? minX : maxX;

  /// הקצה הקדמי — עד לשם היריעה כבר מכסה את העמוד הישן.
  double leadingX(bool turnLeftPage) => turnLeftPage ? maxX : minX;
}
