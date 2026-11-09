// SidebarNavItem — פריט ניווט לסיידבר בסגנון Material 3.

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/theme/app_motion.dart';

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

    final iconColor = isSelected
        ? cs.onSecondaryContainer
        : cs.onSurfaceVariant;

    // ── בניית ווידג'ט האייקון ──────────────────────────────────────────────
    final Widget iconWidget = imageAsset != null
        ? ImageIcon(AssetImage(imageAsset!), size: 20, color: iconColor)
        : AnimatedSwitcher(
            duration: AppMotion.duration(context, AppTokens.animPanelOpacity),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: RtlIcon(
              isSelected && iconFilled != null ? iconFilled! : icon!,
              key: ValueKey<bool>(isSelected),
              size: 20,
              color: iconColor,
            ),
          );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Semantics(
        selected: isSelected,
        child: Material(
          color: isSelected ? AppSurfaces.selectedRow(cs) : Colors.transparent,
          borderRadius: AppTokens.borderRadiusAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppTokens.borderRadiusAll,
            hoverColor: AppSurfaces.hoverRow(cs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: AppMotion.duration(
                        context,
                        AppTokens.animPanelOpacity,
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppSurfaces.onSelectedRow(cs)
                            : cs.onSurfaceVariant,
                      ),
                      child: Text(
                        label,
                      ),
                    ),
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
