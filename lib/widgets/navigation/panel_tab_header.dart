import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// טאב סטנדרטי לשימוש בכל פנלי האפליקציה.
/// כל ערכי הגודל והמרווחים מוגדרים ב-AppTokens.
/// כאשר [label] הוא null — מוצג אייקון בלבד (מצב compact).
class PanelTab extends StatelessWidget {
  final IconData icon;
  final String? label;

  const PanelTab({
    super.key,
    required this.icon,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final lbl = label;
    if (lbl == null) {
      return Tab(
        icon: Icon(icon, size: AppTokens.panelTabIconSize),
        height: AppTokens.panelTabHeight,
      );
    }
    return Tab(
      icon: Icon(icon, size: AppTokens.panelTabIconSize),
      iconMargin: AppTokens.panelTabIconMargin,
      height: AppTokens.panelTabHeight,
      child: Text(lbl,
          style: const TextStyle(fontSize: AppTokens.panelTabFontSize)),
    );
  }
}

/// Header משותף לכל הפנלים עם טאב בר וכפתור סגירה.
class PanelTabHeader extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;
  final VoidCallback? onClose;
  final ValueChanged<int>? onTap;

  const PanelTabHeader({
    super.key,
    required this.controller,
    required this.tabs,
    this.onClose,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: AppTokens.panelTabHeight,
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: controller,
              tabs: tabs,
              labelColor: NavItemColors.foreground(colorScheme, true),
              unselectedLabelColor:
                  NavItemColors.foreground(colorScheme, false),
              indicatorColor: NavItemColors.foreground(colorScheme, true),
              splashBorderRadius: BorderRadius.circular(AppTokens.radiusMD),
              onTap: onTap,
            ),
          ),
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
