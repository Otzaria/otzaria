import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מסגרת משותפת לכרטיסי תוצאות החיפוש (מנוע מובנה, סמנטי וספק חיצוני).
///
/// הכרטיס נושא צבע כרטיס מובחן מרקע הרשימה, ובתוצאה שמוצגת בתצוגה
/// המקדימה — מסגרת בצבע ערכת הנושא ורקע מסומן. ה-[child] הוא האזור הלחיץ
/// ([InkWell]); המסגרת היא ה-Material שעליו נצבע אפקט הלחיצה.
class SearchResultCardFrame extends StatelessWidget {
  final bool isPreviewed;
  final Widget child;

  /// הרווח מתחת לכרטיס.
  final double gap;

  const SearchResultCardFrame({
    super.key,
    required this.child,
    this.isPreviewed = false,
    this.gap = AppTokens.spaceMD,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Material(
        color: isPreviewed
            ? Color.alphaBlend(
                cs.primaryContainer.withValues(alpha: 0.35),
                AppSurfaces.card(context),
              )
            : AppSurfaces.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(
            color: isPreviewed ? cs.primary : cs.outlineVariant,
            width: isPreviewed ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// מספר התוצאה בראש הכרטיס.
class SearchResultRankBadge extends StatelessWidget {
  final int rank;

  const SearchResultRankBadge({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          '$rank',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: AppTokens.fontLG,
          ),
        ),
      ),
    );
  }
}
