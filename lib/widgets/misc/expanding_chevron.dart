import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// כיוון החץ של [ExpandingChevron] (DD-27).
enum ExpandingChevronStyle {
  /// אקורדיון: למטה כשסגור, למעלה כשפתוח.
  accordion,

  /// עץ: לכיוון הקריאה כשסגור (ב-RTL שמאלה), למטה כשפתוח.
  tree,
}

/// חץ מונפש לפתיחה/סגירה, אחד לכל שורה שפותחת תוכן. מכריז לקורא מסך אם
/// התוכן מורחב.
class ExpandingChevron extends StatelessWidget {
  final bool isExpanded;
  final ExpandingChevronStyle style;

  /// כשאין תוכן לפתוח, החץ לא מוצג בכלל.
  final bool hasContent;
  final double? size;
  final Color? color;

  const ExpandingChevron({
    super.key,
    required this.isExpanded,
    this.style = ExpandingChevronStyle.accordion,
    this.hasContent = true,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasContent) return const SizedBox.shrink();
    final double turns;
    switch (style) {
      case ExpandingChevronStyle.accordion:
        turns = isExpanded ? 0.5 : 0.0;
      case ExpandingChevronStyle.tree:
        // החץ למטה מסתובב רבע סיבוב לכיוון הקריאה: עם השעון לשמאל ב-RTL.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        turns = isExpanded ? 0.0 : (rtl ? 0.25 : -0.25);
    }
    // המצב נקלט ברכיב הלחיץ שמכיל את החץ (שורה או כפתור).
    return Semantics(
      expanded: isExpanded,
      child: AnimatedRotation(
        turns: turns,
        duration: AppMotion.duration(context, AppTokens.animNormal),
        curve: Curves.easeInOut,
        child: Icon(
          FluentIcons.chevron_down_24_regular,
          size: size,
          color: color,
        ),
      ),
    );
  }
}
