import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

/// מסגרת אחת לכרטיסי התוצאה בחיפוש ובכלים (DD-11): צבע כרטיס, מסגרת
/// `outlineVariant` ומרווח [AppTokens.listItemGap] מתחת לכרטיס.
///
/// [child] הוא האזור הלחיץ (בדרך כלל [InkWell]) עם ריפוד
/// [AppTokens.cardPadding]; המסגרת היא ה-Material שעליו נצבע אפקט הלחיצה.
/// תוצאה שמוצגת בתצוגה המקדימה ([isPreviewed]) מקבלת רקע מסומן ומסגרת בצבע
/// ערכת הנושא.
class ResultCardFrame extends StatelessWidget {
  final bool isPreviewed;
  final Widget child;

  const ResultCardFrame({
    super.key,
    required this.child,
    this.isPreviewed = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.listItemGap),
      child: Material(
        color: isPreviewed
            ? AppSurfaces.selectedRow(cs)
            : AppSurfaces.card(context),
        shape: isPreviewed
            ? RoundedRectangleBorder(
                borderRadius: AppTokens.borderRadiusAll,
                side: BorderSide(color: cs.primary, width: 1.5),
              )
            : AppCard.shape(cs),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
