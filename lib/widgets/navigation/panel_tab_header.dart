import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// טאב סטנדרטי לשימוש בכל פנלי האפליקציה.
/// כל ערכי הגודל והמרווחים מוגדרים כאן בלבד.
class PanelTab extends StatelessWidget {
  static const double _iconSize = 16;
  static const double _fontSize = 11;
  static const double _tabHeight = 44;
  static const EdgeInsets _iconMargin = EdgeInsets.only(bottom: 1);

  final IconData icon;
  final String label;

  const PanelTab({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      icon: Icon(icon, size: _iconSize),
      iconMargin: _iconMargin,
      height: _tabHeight,
      child: Text(label, style: const TextStyle(fontSize: _fontSize)),
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
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
        ),
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
                dividerColor: Colors.transparent,
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
      ),
    );
  }
}
