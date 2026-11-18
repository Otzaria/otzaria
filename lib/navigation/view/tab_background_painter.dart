import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

const double _tabBottomBleed = 1.0;
const double _tabFlareRadius = 15.0;

class TabBackgroundPainter extends CustomPainter {
  final Color color;

  /// מסגרת סביב גוף הכרטיסיה (בלי הכנפיים התחתונות), לבחירה מרובה.
  final Color? borderColor;

  /// קו סביב הכרטיסיה כולה, כולל הכנפיים, שנפגש בקו התחתון של השורה.
  final Color? flareOutline;

  /// גובה גוף הכרטיסיה, שממורכז בגובה הסרגל.
  final double bodyHeight;

  const TabBackgroundPainter(
    this.color, {
    required this.bodyHeight,
    this.borderColor,
    this.flareOutline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    const topRadius = AppTokens.radius;
    const bottomRadius = _tabFlareRadius;

    // הצורה יושבת בתוך הגבולות, מ-[topInset] ועד `size.height`, ומוסיפה רק
    // [_tabBottomBleed] מתחת לסרגל — ראו [_topBarHeight]. המירכוז נעשה כאן ולא
    // בפריסה, כי ה-widget מקבל את כל גובה הסרגל והכרטיסיה נמוכה ממנו.
    final topInset = math.max(0.0, (size.height - bodyHeight) / 2);

    path.moveTo(-bottomRadius, size.height + _tabBottomBleed);
    path.lineTo(-bottomRadius, size.height);

    path.arcToPoint(
      Offset(0, size.height - bottomRadius),
      radius: const Radius.circular(bottomRadius),
      clockwise: false,
    );

    path.lineTo(0, topInset + topRadius);

    path.arcToPoint(
      Offset(topRadius, topInset),
      radius: const Radius.circular(topRadius),
    );

    path.lineTo(size.width - topRadius, topInset);

    path.arcToPoint(
      Offset(size.width, topInset + topRadius),
      radius: const Radius.circular(topRadius),
    );

    path.lineTo(size.width, size.height - bottomRadius);

    path.arcToPoint(
      Offset(size.width + bottomRadius, size.height),
      radius: const Radius.circular(bottomRadius),
      clockwise: false,
    );

    path.lineTo(size.width + bottomRadius, size.height + _tabBottomBleed);

    path.close();
    canvas.drawPath(path, paint);

    final flare = flareOutline;
    if (flare != null) {
      // אותה צורה בלי הבסיס, חצי קו פנימה. הקו של השורה הוא מסגרת ה-Container
      // שמכווצת את התוכן, ולכן הוא יושב מיד מתחת לצייר: הכנפיים נגמרות בתוכו.
      const i = AppTokens.borderThin / 2;
      final h = size.height;
      final outline = Path()
        ..moveTo(-bottomRadius, h + i)
        ..arcToPoint(
          Offset(i, h - bottomRadius),
          radius: const Radius.circular(bottomRadius),
          clockwise: false,
        )
        ..lineTo(i, topInset + topRadius)
        ..arcToPoint(
          Offset(topRadius, topInset + i),
          radius: const Radius.circular(topRadius - i),
        )
        ..lineTo(size.width - topRadius, topInset + i)
        ..arcToPoint(
          Offset(size.width - i, topInset + topRadius),
          radius: const Radius.circular(topRadius - i),
        )
        ..lineTo(size.width - i, h - bottomRadius)
        ..arcToPoint(
          Offset(size.width + bottomRadius, h + i),
          radius: const Radius.circular(bottomRadius),
          clockwise: false,
        );
      canvas.drawPath(
        outline,
        Paint()
          ..color = flare
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppTokens.borderThin,
      );
    }

    final border = borderColor;
    if (border == null) return;
    const inset = AppTokens.multiSelectedBorderWidth / 2;
    final outline = Path()
      ..moveTo(inset, size.height)
      ..lineTo(inset, topInset + topRadius)
      ..arcToPoint(
        Offset(topRadius, topInset + inset),
        radius: const Radius.circular(topRadius - inset),
      )
      ..lineTo(size.width - topRadius, topInset + inset)
      ..arcToPoint(
        Offset(size.width - inset, topInset + topRadius),
        radius: const Radius.circular(topRadius - inset),
      )
      ..lineTo(size.width - inset, size.height);
    canvas.drawPath(
      outline,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.multiSelectedBorderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant TabBackgroundPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.bodyHeight != bodyHeight ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.flareOutline != flareOutline;
}
