import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// צ'בֺרן מונפש לפתיחה/סגירה.
///
/// מסתובב 180° (AnimatedRotation) בין מצב סגור (מטה) לפתוח (מעלה).
/// שימוש עקבי בכל מקום שיש שורה שפותחת תוכן.
class ExpandingChevron extends StatelessWidget {
  final bool isExpanded;

  /// כשאין תוכן לפתוח, הצ'בֺרן לא מוצג בכלל.
  final bool hasContent;
  final double? size;
  final Color? color;

  const ExpandingChevron({
    super.key,
    required this.isExpanded,
    this.hasContent = true,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasContent) return const SizedBox.shrink();
    return AnimatedRotation(
      turns: isExpanded ? 0.5 : 0.0,
      duration: AppMotion.duration(context, AppTokens.animNormal),
      curve: Curves.easeInOut,
      child: Icon(
        FluentIcons.chevron_down_24_regular,
        size: size,
        color: color,
      ),
    );
  }
}
