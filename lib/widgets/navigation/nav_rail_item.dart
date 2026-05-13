// lib/widgets/nav_rail_item.dart
//
// NavRailItem — כפתור ניווט אנכי בסגנון Material 3.
//
// מממש את הסגנון של _buildNavButton ב-MainWindowScreen:
//  • אייקון (24px) מעל תווית
//  • Active Indicator: AnimatedContainer + AnimatedScale → secondaryContainer pill
//  • AnimatedSwitcher להחלפת regular ↔ filled
//  • AnimatedDefaultTextStyle לאנימציית צבע הטקסט
//  • תמיכה ב-Tooltip לקיצורי מקלדת
//

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

class NavRailItem extends StatelessWidget {
  /// אייקון רגיל (כשלא נבחר)
  final IconData icon;

  /// אייקון filled (כשנבחר) — אופציונלי
  final IconData? iconFilled;

  /// תווית מתחת לאייקון
  final String label;

  /// האם פריט זה נבחר
  final bool isSelected;

  /// Callback בעת לחיצה
  final VoidCallback onTap;

  /// טקסט Tooltip (לרוב קיצור מקלדת) — אופציונלי
  final String? tooltip;

  /// האם להדגיש את הפריט בגלל סיור מודרך
  final bool isTourHighlighted;

  /// מפתח לאזור המדויק שמסומן בסיור המודרך.
  final Key? tourTargetKey;

  /// מפתח לפריט הניווט כולו, כולל התווית.
  final Key? tourItemKey;

  const NavRailItem({
    super.key,
    required this.icon,
    this.iconFilled,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
    this.tourTargetKey,
    this.tourItemKey,
    this.isTourHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ── אייקון עם אנימציה regular ↔ filled ──────────────────────────────
    Widget iconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeInOutCubicEmphasized,
      switchOutCurve: Curves.easeInOutCubicEmphasized,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        isSelected && iconFilled != null ? iconFilled! : icon,
        key: ValueKey<bool>(isSelected),
        size: 24,
        color: NavItemColors.foreground(cs, isSelected),
      ),
    );

    if (tooltip != null) {
      iconWidget = Tooltip(
        preferBelow: false,
        message: tooltip!,
        child: iconWidget,
      );
    }

    return SizedBox(
      key: tourItemKey,
      width: 74,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Active Indicator ────────────────────────────────────────
            AnimatedScale(
              scale: isSelected ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubicEmphasized,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubicEmphasized,
                decoration: BoxDecoration(
                  color: isSelected
                      ? NavItemColors.indicator(cs, true)
                      : isTourHighlighted
                          ? NavItemColors.hover(cs)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  key: tourTargetKey,
                  onPressed: onTap,
                  icon: iconWidget,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    minimumSize: const Size(56, 25),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // ── תווית ──────────────────────────────────────────────────
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubicEmphasized,
              style: TextStyle(
                fontSize: 11,
                color: isTourHighlighted
                    ? cs.primary
                    : NavItemColors.foreground(cs, isSelected),
                fontWeight:
                    isTourHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
