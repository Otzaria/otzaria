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
// **שימוש:**
// ```dart
// NavRailItem(
//   icon: FluentIcons.library_24_regular,
//   iconFilled: FluentIcons.library_24_filled,
//   label: 'ספרייה',
//   isSelected: _currentIndex == 0,
//   onTap: () => _navigate(0),
//   tooltip: 'Ctrl+L',
// )
// ```

import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

class NavRailItem extends StatelessWidget {
  /// רוחב הפריט במצב רגיל ובמצב קומפקטי. ה-SizedBox העוטף את הסרגל חייב
  /// להשתמש באותו ערך, אחרת ייווצר overflow בין רוחב הסרגל לרוחב הפריטים.
  static const double width = 74;
  static const double compactWidth = 60;

  /// רוחב מינימלי לאינדיקטור הבחירה (ה-pill) — מצטמצם במצב קומפקטי כדי
  /// לשמור על יחס שוליים דומה לרוחב הסרגל.
  static const double _indicatorWidth = 56;
  static const double _compactIndicatorWidth = 44;

  /// אייקון רגיל (כשלא נבחר). חובה כשלא הועבר [imageAsset].
  final IconData? icon;

  /// אייקון filled (כשנבחר) — אופציונלי
  final IconData? iconFilled;

  /// נכס תמונה לשימוש במקום [icon]. מועדף אם קיים — תואם לכלים שמשתמשים
  /// בלוגו ייחודי (כמו "שמור וזכור") במקום באייקון Fluent.
  ///
  /// כשמשתמשים ב-imageAsset, ההנפשה regular↔filled לא רלוונטית (אותה
  /// תמונה לשני המצבים, רק הצבע משתנה).
  final String? imageAsset;

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

  /// מצמצם את רוחב הפריט ([compactWidth] במקום [width]).
  final bool compact;

  const NavRailItem({
    super.key,
    this.icon,
    this.iconFilled,
    this.imageAsset,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
    this.tourTargetKey,
    this.tourItemKey,
    this.isTourHighlighted = false,
    this.compact = false,
  }) : assert(
         icon != null || imageAsset != null,
         'NavRailItem requires either icon or imageAsset',
       );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final iconColor = isSelected
        ? cs.onSecondaryContainer
        : cs.onSurfaceVariant;

    // ── אייקון עם אנימציה regular ↔ filled ──────────────────────────────
    // עבור image-asset אין נפרד "filled" — מתחלף רק הצבע. עבור IconData
    // משתמשים ב-AnimatedSwitcher כדי לאניים regular↔filled.
    Widget iconWidget = imageAsset != null
        ? ImageIcon(AssetImage(imageAsset!), size: 24, color: iconColor)
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeInOutCubicEmphasized,
            switchOutCurve: Curves.easeInOutCubicEmphasized,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: _buildIcon(
              isSelected && iconFilled != null ? iconFilled! : icon!,
              iconColor,
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
      width: compact ? compactWidth : width,
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
                      ? cs.secondaryContainer
                      : isTourHighlighted
                      ? cs.primary.withAlpha((0.08 * 255).round())
                      : Colors.transparent,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: IconButton(
                  key: tourTargetKey,
                  onPressed: onTap,
                  icon: iconWidget,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    minimumSize: Size(
                      compact ? _compactIndicatorWidth : _indicatorWidth,
                      25,
                    ),
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
                color: isSelected
                    ? cs.onSecondaryContainer
                    : isTourHighlighted
                    ? cs.primary
                    : cs.onSurfaceVariant,
                fontWeight: isTourHighlighted
                    ? FontWeight.bold
                    : FontWeight.normal,
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

  Widget _buildIcon(IconData icon, Color color) {
    if (icon.fontPackage == OtzariaIcons.fontPackage) {
      return Icon(
        icon,
        key: ValueKey<bool>(isSelected),
        size: 24,
        color: color,
      );
    }
    return RtlIcon(
      icon,
      key: ValueKey<bool>(isSelected),
      size: 24,
      color: color,
    );
  }
}
