// אייקון בשורת תפריט (לחיצה ימנית ותפריט שלוש הנקודות).

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/misc/menu_badge_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// אייקוני האותיות והקישורים מציירים את הסימן שלהם בתוך עיגול קטן, ולכן ב-18px
/// הם נקראים פחות מאייקון רגיל. הם מוצגים בגודל הציור המלא (24px, פי 4/3),
/// וזה הגודל המרבי שנכנס בשורה: גובה השורה 36, והרווח לטקסט 8 נשאר.
const double kLetterLinkMenuIconScale = 24 / 18;

/// אייקון בשורת תפריט שתופס תמיד תא של [size] × [size], כך שהגדלת אייקון
/// אות או קישור לא משנה את פריסת השורה ואת חישוב רוחב התפריט.
class AppMenuIcon extends StatelessWidget {
  const AppMenuIcon(
    this.icon, {
    super.key,
    required this.size,
    this.color,
    this.mirrorForRtl = true,
  });

  final IconData icon;
  final double size;
  final Color? color;

  /// האם לשקף חיצי ניווט של Fluent בממשק RTL ([RtlIcon]). שורת האייקונים
  /// שבראש תפריט הקליק הימני מציירת `Icon` רגיל.
  final bool mirrorForRtl;

  @override
  Widget build(BuildContext context) {
    if (!isLetterOrLinkIcon(icon)) {
      return mirrorForRtl
          ? RtlIcon(icon, size: size, color: color)
          : Icon(icon, size: size, color: color);
    }
    final enlarged = size * kLetterLinkMenuIconScale;
    return SizedBox.square(
      dimension: size,
      child: OverflowBox(
        minWidth: enlarged,
        maxWidth: enlarged,
        minHeight: enlarged,
        maxHeight: enlarged,
        child: Icon(icon, size: enlarged, color: color),
      ),
    );
  }
}
