part of 'context_menu_region.dart';

extension _ContextMenuEntries on ContextMenuRegionState {
  List<Widget> _buildMenuPanelChildren(
    BuildContext context,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
    double maxWidth,
    Map<AppContextMenuEntry, MenuController> submenuControllers,
    Map<AppContextMenuEntry, List<MenuController>> iconRowControllers,
  ) {
    final contentMaxWidth = maxWidth - metrics.itemPadding.horizontal;
    return entries.map<Widget>((entry) {
      if (entry.colorRowActions != null) {
        return _AppContextMenuColorRow(
          actions: entry.colorRowActions!,
          metrics: metrics,
          maxWidth: maxWidth,
          closeMenu: _closeContextMenu,
        );
      }
      if (entry.iconRowActions != null) {
        return _AppContextMenuIconRow(
          presentation: presentation,
          actions: entry.iconRowActions!,
          metrics: metrics,
          menuStyle: _menuStyle(context, metrics),
          closeMenu: _closeContextMenu,
          submenuControllers: iconRowControllers[entry]!,
        );
      }

      if (entry.isDivider) {
        return SizedBox(
          height: metrics.dividerHeight,
          child: const Divider(height: 1),
        );
      }

      final submenu = _buildSubmenuEntry(
        context,
        entry,
        metrics,
        key: widget.menuItemKeysByLabel?[entry.label ?? ''],
        contentMaxWidth: contentMaxWidth,
        submenuMaxWidth: maxWidth,
        submenuControllers: submenuControllers,
      );
      if (submenu != null) return submenu;

      if (entry.isHighlighted) {
        return _HoverableHighlightedRow(
          presentation: presentation,
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          label: entry.label ?? '',
          icon: entry.icon,
          metrics: metrics,
          onTap: entry.enabled
              ? () {
                  _closeContextMenu();
                  entry.onTap?.call();
                }
              : null,
        );
      }

      return _buildLeafEntry(
        context,
        entry,
        metrics,
        key: widget.menuItemKeysByLabel?[entry.label ?? ''],
        contentMaxWidth: contentMaxWidth,
      );
    }).toList();
  }

  List<AppContextMenuEntry> _normalizeEntries(
    List<AppContextMenuEntry> entries,
  ) {
    final result = <AppContextMenuEntry>[];
    for (final e in entries) {
      if (e.isDivider) {
        if (result.isEmpty || result.last.isDivider) continue;
        result.add(e);
      } else {
        result.add(e);
      }
    }
    while (result.isNotEmpty && result.last.isDivider) {
      result.removeLast();
    }
    return result;
  }

  List<Widget> _buildSubmenuChildren(
    BuildContext context,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
    double maxWidth,
    VoidCallback rebuildSubmenu,
    int depth,
  ) {
    final submenuContentMaxWidth = maxWidth - metrics.itemPadding.horizontal;

    return entries.map((entry) {
      if (entry.colorRowActions != null) {
        return _AppContextMenuColorRow(
          actions: entry.colorRowActions!,
          metrics: metrics,
          maxWidth: maxWidth,
          closeMenu: _closeContextMenu,
        );
      }
      if (entry.isDivider) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1),
        );
      }

      final submenu = _buildSubmenuEntry(
        context,
        entry,
        metrics,
        key: null,
        contentMaxWidth: submenuContentMaxWidth,
        submenuMaxWidth: submenuContentMaxWidth,
        depth: depth,
      );
      if (submenu != null) return submenu;

      return _buildLeafEntry(
        context,
        entry,
        metrics,
        key: entry.key,
        contentMaxWidth: submenuContentMaxWidth,
        rebuildSubmenu: rebuildSubmenu,
      );
    }).toList();
  }

  /// פריט עם תת-תפריט — עצל (childrenBuilder) או מוכן (children); null אם
  /// הפריט אינו תת-תפריט. משמש גם לתפריט הראשי וגם לתתי-התפריטים.
  Widget? _buildSubmenuEntry(
    BuildContext context,
    AppContextMenuEntry entry,
    AppMenuMetrics metrics, {
    required Key? key,
    required double contentMaxWidth,
    required double submenuMaxWidth,
    Map<AppContextMenuEntry, MenuController>? submenuControllers,
    int depth = 0,
  }) {
    final childrenBuilder = entry.childrenBuilder;
    final rawChildren = entry.children;
    final List<AppContextMenuEntry> Function() entriesBuilder;
    var enabled = entry.enabled;
    if (childrenBuilder != null) {
      entriesBuilder = () => _normalizeEntries(childrenBuilder());
    } else if (rawChildren != null && rawChildren.isNotEmpty) {
      final normalizedChildren = _normalizeEntries(rawChildren);
      enabled &= hasEnabledAppContextMenuEntries(normalizedChildren);
      entriesBuilder = () => normalizedChildren;
    } else {
      return null;
    }

    if (!enabled) {
      return MenuItemButton(
        key: key,
        requestFocusOnHover: false,
        style: buildAppSubmenuItemStyle(
          context,
          metrics,
          presentation: presentation,
        ),
        onPressed: null,
        child: buildAppMenuRowContent(
          context,
          metrics,
          presentation: presentation,
          maxWidth: contentMaxWidth,
          label: entry.label ?? '',
          labelWidget: entry.labelWidget,
          icon: entry.icon,
          trailing: entry.trailing,
          isDestructive: entry.isDestructive,
          enabled: false,
        ),
      );
    }

    final controller = submenuControllers?[entry] ?? MenuController();
    _submenuControllers[controller] = depth;
    return _LazyAppSubmenuButton(
      presentation: presentation,
      key: key,
      entry: entry,
      entriesBuilder: entriesBuilder,
      metrics: metrics,
      maxWidth: submenuMaxWidth,
      menuStyle: _menuStyle(context, metrics),
      controller: controller,
      onControllerUnmounted: () => _submenuControllers.remove(controller),
      onOpen: submenuControllers == null
          ? null
          : () {
              for (final ctrl in submenuControllers.values) {
                if (ctrl != controller && ctrl.isOpen) ctrl.close();
              }
            },
      buildChildren: (submenuEntries, submenuMaxWidth, rebuildSubmenu) =>
          _buildSubmenuChildren(
            context,
            submenuEntries,
            metrics,
            submenuMaxWidth,
            rebuildSubmenu,
            depth + 1,
          ),
    );
  }

  Widget _buildLeafEntry(
    BuildContext context,
    AppContextMenuEntry entry,
    AppMenuMetrics metrics, {
    required Key? key,
    required double contentMaxWidth,
    VoidCallback? rebuildSubmenu,
  }) {
    final keepOpen = entry.keepOpen && rebuildSubmenu != null;
    return _wrapWithHoverPreview(
      entry,
      metrics,
      MenuItemButton(
        key: key,
        requestFocusOnHover: false,
        closeOnActivate: !keepOpen,
        style: buildAppSubmenuItemStyle(
          context,
          metrics,
          presentation: presentation,
        ),
        onPressed: !entry.enabled
            ? null
            : keepOpen
            ? () {
                entry.onTap?.call();
                rebuildSubmenu();
              }
            : () {
                _closeContextMenu();
                entry.onTap?.call();
              },
        child: buildAppMenuRowContent(
          context,
          metrics,
          presentation: presentation,
          maxWidth: contentMaxWidth,
          label: entry.label ?? '',
          labelWidget: entry.labelWidget,
          icon: entry.icon,
          trailing: entry.trailing,
          isSelected: entry.isSelected,
          isDestructive: entry.isDestructive,
          enabled: entry.enabled,
        ),
      ),
    );
  }

  Widget _wrapWithHoverPreview(
    AppContextMenuEntry entry,
    AppMenuMetrics metrics,
    Widget child,
  ) {
    final previewBuilder = entry.hoverPreviewBuilder;
    final wrapper = widget.previewWrapper;
    if (previewBuilder == null || wrapper == null || !entry.enabled) {
      return child;
    }
    return wrapper(context, previewBuilder, _closeContextMenu, child);
  }
}
