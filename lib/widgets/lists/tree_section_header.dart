import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';

/// שורת כותרת של מקטע בעץ שאפשר לפתוח ולסגור, בתוך טבלה או רשימה עם עמודות.
///
/// השורה כולה לחיצה ומחליפה את המצב. החץ (סגנון עץ, DD-27) יושב בתחילת השורה,
/// ברוחב [leadingExtent], כך ששורות הילדים, שמשאירות אותו רוחב ריק בתחילתן,
/// מתיישרות לעמודות של הכותרת. [child] הוא תוכן השורה שאחרי החץ: כותרת
/// ועמודות, ובהן גם פקדים (למשל תיבות סימון) שלוחצים עליהם בלי לפתוח או לסגור.
///
/// מחליף ExpansionTile שעוטף Theme מקומי כדי להיראות כשורת טבלה (UI-091).
class TreeSectionHeader extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  /// רוחב אזור החץ בתחילת השורה.
  final double leadingExtent;

  /// ריפוד השורה, מסביב לחץ ולתוכן.
  final EdgeInsetsGeometry padding;

  const TreeSectionHeader({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
    this.leadingExtent = kMinInteractiveDimension,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            SizedBox(
              width: leadingExtent,
              child: Center(
                child: ExpandingChevron(
                  isExpanded: isExpanded,
                  style: ExpandingChevronStyle.tree,
                  size: AppTokens.iconMD,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
