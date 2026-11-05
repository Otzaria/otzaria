import 'package:flutter/material.dart';

/// תוויות סרגל הניווט התחתון בטלפון (review-r3, q-bottom-bar).
///
/// תווית לכל יעד, כל עוד התווית הארוכה נכנסת ברוחב של יעד אחד. רק כשהיא לא
/// נכנסת — במסך צר מאוד, בגודל טקסט גדול או עם כלים מוצמדים — NavigationBar
/// היה שובר אותה לשתי שורות, ואז התווית מוצגת רק ליעד הנבחר.
///
/// ההחלטה נמדדת ולא לפי רוחב קבוע: TextPainter בסגנון התווית של הסרגל ובגודל
/// הטקסט של המשתמש, ולכן היא נכונה בעברית ובאנגלית ובכל גופן.
abstract final class BottomNavLabels {
  /// NavigationBar מגביל את גודל הטקסט בתוויות ל־1.3
  /// (`_kMaxLabelTextScaleFactor` ב־navigation_bar.dart של Flutter). המדידה
  /// מגבילה באותה תקרה.
  static const double maxLabelTextScale = 1.3;

  /// האם כל [labels] נכנסות בשורה אחת ברוחב של יעד, בסרגל ברוחב [barWidth].
  static bool allFit(
    BuildContext context, {
    required double barWidth,
    required List<String> labels,
  }) {
    if (labels.isEmpty) return true;
    // NavigationBar עוטף את היעדים ב־SafeArea, והיעדים מתחלקים ברוחב שווה.
    final padding = MediaQuery.paddingOf(context);
    final perDestination =
        (barWidth - padding.left - padding.right) / labels.length;
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxLabelTextScale);
    final direction = Directionality.of(context);
    final styles = _labelStyles(context);
    for (final label in labels) {
      for (final style in styles) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: direction,
          textScaler: textScaler,
        )..layout();
        final width = painter.maxIntrinsicWidth;
        painter.dispose();
        if (width > perDestination) return false;
      }
    }
    return true;
  }

  /// תווית לכל יעד כשכולן נכנסות; אחרת רק ליעד הנבחר.
  static NavigationDestinationLabelBehavior behaviorFor(
    BuildContext context, {
    required double barWidth,
    required List<String> labels,
  }) => allFit(context, barWidth: barWidth, labels: labels)
      ? NavigationDestinationLabelBehavior.alwaysShow
      : NavigationDestinationLabelBehavior.onlyShowSelected;

  /// סגנון התווית כמו ש־NavigationBar פותר אותו: מערכת הנושא של הסרגל, ואם
  /// אין — labelMedium (ברירת המחדל של M3). יעד נבחר ויעד שלא נבחר נמדדים
  /// שניהם, למקרה שהמשקל שונה ביניהם.
  static List<TextStyle?> _labelStyles(BuildContext context) {
    final themed = NavigationBarTheme.of(context).labelTextStyle;
    final fallback = Theme.of(context).textTheme.labelMedium;
    return [
      themed?.resolve(const {WidgetState.selected}) ?? fallback,
      themed?.resolve(const {}) ?? fallback,
    ];
  }
}
