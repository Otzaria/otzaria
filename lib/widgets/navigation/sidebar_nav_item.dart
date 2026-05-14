// lib/widgets/sidebar_nav_item.dart
//
// SidebarNavItem — פריט ניווט לסיידבר בסגנון Material 3.
//
// מממש את הסגנון המשותף ל-SettingsScreen ו-MoreScreen:
//  • רקע secondaryContainer כשנבחר (pill עגול)
//  • אייקון filled כשנבחר, regular כשלא
//  • תמיכה ב-imageAsset (עבור אייקונים מקובץ)
//  • hover / pressed states דרך InkWell
//  • אנימציה חלקה של החלפת אייקון (AnimatedSwitcher)
//
// **שימוש:**
// ```dart
// SidebarNavItem(
//   icon: FluentIcons.calendar_24_regular,
//   iconFilled: FluentIcons.calendar_24_filled,
//   label: 'לוח שנה',
//   isSelected: _selectedIndex == 0,
//   onTap: () => _changeTab(0),
// )
//
// // עם imageAsset:
// SidebarNavItem(
//   imageAsset: 'assets/icon/שמור וזכור שחור ריק.png',
//   label: 'שמור וזכור',
//   isSelected: _selectedIndex == 1,
//   onTap: () => _changeTab(1),
// )
// ```

import 'package:flutter/material.dart';

class SidebarNavItem extends StatelessWidget {
  /// אייקון רגיל (כשלא נבחר) — חובה אם לא מסופק [imageAsset]
  final IconData? icon;

  /// אייקון filled (כשנבחר) — אופציונלי; אם null משתמש ב-[icon]
  final IconData? iconFilled;

  /// נתיב לאסט אייקון (חלופה ל-[icon]) — למשל 'assets/icon/foo.png'
  final String? imageAsset;

  /// טקסט התווית
  final String label;

  /// האם פריט זה נבחר כרגע
  final bool isSelected;

  /// Callback בעת לחיצה
  final VoidCallback onTap;

  /// ריפוד אנכי (ברירת מחדל: 2)
  final double verticalPadding;

  const SidebarNavItem({
    super.key,
    this.icon,
    this.iconFilled,
    this.imageAsset,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.verticalPadding = 2,
  }) : assert(
          icon != null || imageAsset != null,
          'SidebarNavItem: חייב לספק icon או imageAsset',
        );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final iconColor =
        isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    // ── בניית ווידג'ט האייקון ──────────────────────────────────────────────
    final Widget iconWidget = imageAsset != null
        ? ImageIcon(AssetImage(imageAsset!), size: 20, color: iconColor)
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              isSelected && iconFilled != null ? iconFilled! : icon!,
              key: ValueKey<bool>(isSelected),
              size: 20,
              color: iconColor,
            ),
          );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Material(
        color: isSelected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    child: Text(label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// TopNavItem — פריט ניווט עליון בסגנון הישן של מסך הכלים.
///
/// מתאים לשורת בחירה אופקית:
///  • אייקון מעל הטקסט
///  • רקע secondaryContainer כשנבחר
///  • אנימציית החלפת אייקון regular ↔ filled
///  • hover / pressed states דרך InkWell
class TopNavItem extends StatelessWidget {
  final IconData? icon;
  final IconData? iconFilled;
  final String? imageAsset;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double? width;

  const TopNavItem({
    super.key,
    this.icon,
    this.iconFilled,
    this.imageAsset,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.width,
  }) : assert(
          icon != null || imageAsset != null,
          'TopNavItem: חייב לספק icon או imageAsset',
        );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor =
        isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final textColor =
        isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final animatedTextStyle = TextStyle(
      fontSize: 14,
      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      color: textColor,
    );
    final reservedTextStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textColor,
    );
    final textDirection = Directionality.of(context);
    final textPainter = TextPainter(
      text: TextSpan(text: label, style: reservedTextStyle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    final textWidth = textPainter.width.ceilToDouble();

    final Widget iconWidget = imageAsset != null
        ? ImageIcon(
            AssetImage(imageAsset!),
            size: 20,
            color: iconColor,
          )
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeInOutCubicEmphasized,
            switchOutCurve: Curves.easeInOutCubicEmphasized,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              isSelected && iconFilled != null ? iconFilled! : icon!,
              key: ValueKey<bool>(isSelected),
              size: 20,
              color: iconColor,
            ),
          );

    return SizedBox(
      width: width,
      child: Material(
        color: isSelected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  const SizedBox(height: 4),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: textWidth,
                        child: Opacity(
                          opacity: 0,
                          child: Text(
                            label,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: reservedTextStyle,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: textWidth,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: animatedTextStyle,
                          child: Text(
                            label,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
