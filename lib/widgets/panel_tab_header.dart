import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Header משותף לכל הפנלים עם טאב בר וכפתור סגירה.
class PanelTabHeader extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;
  final VoidCallback? onClose;
  final ValueChanged<int>? onTap;
  final double height;

  const PanelTabHeader({
    super.key,
    required this.controller,
    required this.tabs,
    this.onClose,
    this.onTap,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
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
                labelColor: colorScheme.primary,
                unselectedLabelColor:
                    colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: colorScheme.primary,
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(12),
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
