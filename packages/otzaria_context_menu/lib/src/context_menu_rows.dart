part of 'context_menu_region.dart';

class _AppContextMenuPanel extends StatelessWidget {
  final List<AppContextMenuEntry> entries;
  final AppMenuMetrics metrics;
  final MenuPresentation presentation;
  final MenuStyle? menuStyle;
  final double maxWidth;
  final double maxHeight;
  final List<Widget> Function(BuildContext, List<AppContextMenuEntry>)
  buildChildren;

  const _AppContextMenuPanel({
    required this.presentation,
    super.key,
    required this.entries,
    required this.metrics,
    required this.menuStyle,
    required this.maxWidth,
    required this.maxHeight,
    required this.buildChildren,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FocusScope(
      skipTraversal: true,
      descendantsAreFocusable: false,
      child: Material(
        color:
            menuStyle?.backgroundColor?.resolve(const <WidgetState>{}) ??
            colorScheme.surfaceContainer,
        elevation:
            menuStyle?.elevation?.resolve(const <WidgetState>{})?.toDouble() ??
            3,
        shape:
            menuStyle?.shape?.resolve(const <WidgetState>{}) ??
            RoundedRectangleBorder(borderRadius: presentation.borderRadius),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: metrics.menuMinWidth,
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: SingleChildScrollView(
              padding: metrics.menuPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buildChildren(context, entries),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverableHighlightedRow extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final AppMenuMetrics metrics;
  final MenuPresentation presentation;

  const _HoverableHighlightedRow({
    required this.presentation,
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: presentation.borderRadius,
        child: Ink(
          height: metrics.itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: primary, width: 1.5),
            borderRadius: presentation.borderRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: metrics.fontSize,
                  color: primary,
                ),
              ),
              if (icon != null) ...[
                const Spacer(),
                const SizedBox(width: 6),
                Icon(icon, size: metrics.iconSize, color: primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AppContextMenuColorRow extends StatelessWidget {
  final List<AppContextMenuColorAction> actions;
  final AppMenuMetrics metrics;
  final double maxWidth;
  final VoidCallback closeMenu;

  const _AppContextMenuColorRow({
    required this.actions,
    required this.metrics,
    required this.maxWidth,
    required this.closeMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        key: const ValueKey('context-color-row'),
        height: metrics.itemHeight,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions)
                  Tooltip(
                    message: action.label,
                    child: Semantics(
                      button: true,
                      selected: action.selected,
                      label: action.label,
                      child: InkWell(
                        key: ValueKey('context-color-${action.id}'),
                        onTap: action.onTap == null
                            ? null
                            : () {
                                closeMenu();
                                action.onTap!.call();
                              },
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.square(
                          dimension: 32,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: action.icon == null
                                    ? action.color
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: action.selected
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant,
                                  width: action.selected ? 3 : 1,
                                ),
                              ),
                              child: action.icon == null
                                  ? null
                                  : Icon(
                                      action.icon,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                            ),
                          ),
                        ),
                      ),
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

class _AppContextMenuIconRow extends StatelessWidget {
  final List<AppContextMenuIconAction> actions;
  final AppMenuMetrics metrics;
  final MenuPresentation presentation;
  final MenuStyle menuStyle;
  final VoidCallback closeMenu;
  final List<MenuController> submenuControllers;

  const _AppContextMenuIconRow({
    required this.presentation,
    required this.actions,
    required this.metrics,
    required this.menuStyle,
    required this.closeMenu,
    required this.submenuControllers,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      // Center ממרכז את שורת האייקונים בלי להפוך את ה-Row ל-mainAxisSize.max
      // (max בתוך פאנל IntrinsicWidth שבר את הבחירה בעת פתיחת התפריט).
      child: Center(
        child: SingleChildScrollView(
          key: const ValueKey('context-icon-row-scroll'),
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, action) in actions.indexed)
                _IconRowButton(
                  presentation: presentation,
                  action: action,
                  metrics: metrics,
                  menuStyle: menuStyle,
                  closeMenu: closeMenu,
                  submenuController: submenuControllers[i],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconRowButton extends StatelessWidget {
  final AppContextMenuIconAction action;
  final AppMenuMetrics metrics;
  final MenuPresentation presentation;
  final MenuStyle menuStyle;
  final VoidCallback closeMenu;
  final MenuController submenuController;

  const _IconRowButton({
    required this.presentation,
    required this.action,
    required this.metrics,
    required this.menuStyle,
    required this.closeMenu,
    required this.submenuController,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSubmenu = action.submenuBuilder != null;
    final enabled = action.enabled && (action.onTap != null || hasSubmenu);
    final color = enabled
        ? colorScheme.onSurface
        : Theme.of(context).disabledColor;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          presentation.iconBuilder(
            context,
            action.icon,
            metrics.iconSize,
            color,
            false,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  action.label ?? action.tooltip ?? '',
                  style: TextStyle(fontSize: 11, color: color),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasSubmenu) presentation.downArrowBuilder(context, 12, color),
            ],
          ),
        ],
      ),
    );

    Widget button;
    if (hasSubmenu) {
      button = _IconRowSubmenu(
        presentation: presentation,
        action: action,
        metrics: metrics,
        menuStyle: menuStyle,
        closeMenu: closeMenu,
        controller: submenuController,
        enabled: enabled,
        // minWidth מאפשר גדילה עם textScaler; maxWidth מונע מ-label ארוך/טקסט
        // מוגדל מאוד להרחיב את הכפתורים מעבר לרוחב התפריט (הכיתוב נחתך במקום).
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, maxWidth: 96),
          child: content,
        ),
      );
    } else {
      button = InkWell(
        onTap: enabled
            ? () {
                closeMenu();
                action.onTap?.call();
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, maxWidth: 96),
          child: content,
        ),
      );
    }

    final tooltip = action.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      button = Tooltip(message: tooltip, child: button);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: button,
    );
  }
}

class _IconRowSubmenu extends StatefulWidget {
  final AppContextMenuIconAction action;
  final AppMenuMetrics metrics;
  final MenuPresentation presentation;
  final MenuStyle menuStyle;
  final VoidCallback closeMenu;
  final MenuController controller;
  final bool enabled;
  final Widget child;

  const _IconRowSubmenu({
    required this.presentation,
    required this.action,
    required this.metrics,
    required this.menuStyle,
    required this.closeMenu,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  @override
  State<_IconRowSubmenu> createState() => _IconRowSubmenuState();
}

class _IconRowSubmenuState extends State<_IconRowSubmenu> {
  List<AppContextMenuSubAction>? _entries;

  @override
  void didUpdateWidget(_IconRowSubmenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action ||
        oldWidget.controller != widget.controller) {
      _entries = oldWidget.controller.isOpen
          ? widget.action.submenuBuilder!()
          : null;
    }
  }

  void _toggle() {
    if (widget.controller.isOpen) {
      widget.controller.close();
      return;
    }
    // Direct links and other submenu entries can perform work. Build them
    // when requested, not once for every context-menu opening.
    final entries = widget.action.submenuBuilder!();
    setState(() => _entries = entries);
    widget.controller.open();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: widget.controller,
      style: widget.menuStyle,
      menuChildren: [
        for (final entry in _entries ?? const <AppContextMenuSubAction>[])
          MenuItemButton(
            requestFocusOnHover: false,
            style: buildAppSubmenuItemStyle(
              context,
              widget.metrics,
              presentation: widget.presentation,
            ),
            onPressed: entry.enabled
                ? () {
                    widget.closeMenu();
                    entry.onTap?.call();
                  }
                : null,
            child: buildAppMenuRowContent(
              context,
              widget.metrics,
              presentation: widget.presentation,
              label: entry.label,
              icon: entry.icon,
              enabled: entry.enabled,
            ),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: widget.enabled ? _toggle : null,
        borderRadius: BorderRadius.circular(8),
        child: widget.child,
      ),
    );
  }
}
