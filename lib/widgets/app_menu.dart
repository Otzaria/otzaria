import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/inputs/app_input_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AppMenuEntry — נתוני פריט בתפריט
// ═══════════════════════════════════════════════════════════════════════════

class AppMenuEntry<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
  final bool isDestructive;
  final Widget? trailing;

  const AppMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.isDestructive = false,
    this.trailing,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// AppContextMenuEntry — פריט בתפריט הקשר (right-click)
// ═══════════════════════════════════════════════════════════════════════════

class AppContextMenuEntry {
  final Key? key;
  final String? label;
  final Widget? labelWidget;
  final IconData? icon;
  final bool enabled;
  final bool isDivider;
  final bool isDestructive;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// תת-פריטים לתפריט משנה
  final List<AppContextMenuEntry>? children;

  /// בנייה עצלה של תת-פריטים לתפריט משנה.
  final List<AppContextMenuEntry> Function()? childrenBuilder;

  const AppContextMenuEntry({
    required this.label,
    this.key,
    this.labelWidget,
    this.icon,
    this.enabled = true,
    this.isDestructive = false,
    this.onTap,
    this.trailing,
    this.children,
    this.childrenBuilder,
  }) : isDivider = false;

  const AppContextMenuEntry.divider()
      : key = null,
        label = null,
        labelWidget = null,
        icon = null,
        enabled = false,
        isDivider = true,
        isDestructive = false,
        onTap = null,
        trailing = null,
        children = null,
        childrenBuilder = null;
}

bool _hasEnabledAppContextMenuEntries(List<AppContextMenuEntry> entries) {
  return entries.any((entry) => !entry.isDivider);
}

// ═══════════════════════════════════════════════════════════════════════════
// AppPopupMenuButton — כפתור שפותח תפריט
// ═══════════════════════════════════════════════════════════════════════════

class AppPopupMenuButton<T> extends StatefulWidget {
  final List<AppMenuEntry<T>>? entries;
  final List<PopupMenuEntry<T>> Function(BuildContext context)? itemBuilder;
  final ValueChanged<T>? onSelected;
  final Widget? child;
  final Widget? icon;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final PopupMenuPosition position;
  final Offset offset;
  final bool enabled;
  final T? initialValue;

  const AppPopupMenuButton({
    super.key,
    this.entries,
    this.itemBuilder,
    this.onSelected,
    this.child,
    this.icon,
    this.tooltip,
    this.padding,
    this.constraints,
    this.position = PopupMenuPosition.under,
    this.offset = const Offset(0, 4),
    this.enabled = true,
    this.initialValue,
  });

  @override
  State<AppPopupMenuButton<T>> createState() => _AppPopupMenuButtonState<T>();
}

class _AppPopupMenuButtonState<T> extends State<AppPopupMenuButton<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  bool get _isTouchMode {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  bool get _hasCompactConstraints {
    final constraints = widget.constraints;
    if (constraints == null) return false;
    final minWidth = constraints.minWidth;
    final maxWidth = constraints.maxWidth;
    final minHeight = constraints.minHeight;
    final maxHeight = constraints.maxHeight;
    final width = minWidth > 0 ? minWidth : maxWidth;
    final height = minHeight > 0 ? minHeight : maxHeight;
    return width > 0 && width <= 40 && height > 0 && height <= 40;
  }

  List<PopupMenuEntry<T>> _buildItems(
    BuildContext context,
    AppMenuMetrics metrics,
  ) {
    return widget.itemBuilder?.call(context) ??
        widget.entries!
            .map<PopupMenuEntry<T>>(
              (entry) => buildAppPopupMenuItem<T>(
                context,
                entry,
                metrics,
                widget.initialValue,
              ),
            )
            .toList();
  }

  Future<void> _showAdaptiveMenu() async {
    if (!widget.enabled) return;
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;

    final selected = await showAnchoredAppMenu<T>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (metrics) => _buildItems(context, metrics),
      position: widget.position,
      offset: widget.offset,
    );

    if (selected != null) {
      widget.onSelected?.call(selected);
    }
  }

  Future<void> showMenu() => _showAdaptiveMenu();

  @override
  Widget build(BuildContext context) {
    assert(widget.entries != null || widget.itemBuilder != null);

    Widget trigger;
    if (widget.child != null) {
      trigger = InkWell(
        onTap: widget.enabled ? _showAdaptiveMenu : null,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        child: widget.child,
      );
    } else if (_isTouchMode &&
        widget.tooltip != null &&
        !_hasCompactConstraints) {
      trigger = TextButton.icon(
        onPressed: widget.enabled ? _showAdaptiveMenu : null,
        icon: widget.icon ?? const Icon(FluentIcons.more_vertical_24_regular),
        label: Text(
          widget.tooltip!,
          textDirection: TextDirection.rtl,
        ),
      );
    } else {
      trigger = IconButton(
        onPressed: widget.enabled ? _showAdaptiveMenu : null,
        padding: widget.padding ?? EdgeInsets.zero,
        constraints: widget.constraints,
        tooltip: widget.tooltip,
        icon: widget.icon ?? const Icon(FluentIcons.more_vertical_24_regular),
      );
    }

    if (widget.child == null &&
        widget.constraints != null &&
        trigger is! IconButton) {
      trigger = ConstrainedBox(
        constraints: widget.constraints!,
        child: Center(child: trigger),
      );
    }

    return KeyedSubtree(
      key: _anchorKey,
      child: trigger,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// showAnchoredAppMenu — פתיחת תפריט עוגן לרכיב קיים
// ═══════════════════════════════════════════════════════════════════════════

Future<T?> showAnchoredAppMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<PopupMenuEntry<T>> Function(AppMenuMetrics metrics)
      itemsBuilder,
  PopupMenuPosition position = PopupMenuPosition.under,
  Offset offset = const Offset(0, 4),
}) async {
  final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false);
  final items = itemsBuilder(metrics);
  if (items.isEmpty) return null;

  final renderBox = anchorContext.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final targetRect = MatrixUtils.transformRect(
    renderBox.getTransformTo(overlay),
    Offset.zero & renderBox.size,
  );

  final menuHeight = items.fold<double>(
        metrics.menuPadding.vertical,
        (sum, item) => sum + item.height,
      ) +
      8;
  final spaceAbove = targetRect.top;
  final spaceBelow = overlay.size.height - targetRect.bottom;
  final preferBelow = position == PopupMenuPosition.under;
  final shouldOpenBelow = preferBelow
      ? (spaceBelow >= menuHeight || spaceBelow >= spaceAbove)
      : !(spaceAbove >= menuHeight || spaceAbove >= spaceBelow);

  final anchorTop = shouldOpenBelow
      ? targetRect.bottom + offset.dy
      : (targetRect.top - menuHeight - offset.dy).clamp(
          0.0,
          overlay.size.height,
        );

  final anchorRect = RelativeRect.fromRect(
    Rect.fromLTWH(targetRect.left, anchorTop, targetRect.width, 0),
    Offset.zero & overlay.size,
  );

  return showMenu<T>(
    context: context,
    position: anchorRect,
    items: items,
    // מינימום רוחב תואם רוחב הטריגר — סעיף 4
    constraints: BoxConstraints(minWidth: targetRect.width),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// _buildAppMenuRowContent — בניית שורת תוכן בתפריט
//
// שינויים:
// • הרקע הנבחר ממלא שורה שלמה (ללא borderRadius, ללא גבול)
// • סימן ✓ תמיד מופיע לפריט נבחר
// ═══════════════════════════════════════════════════════════════════════════

Widget _buildAppMenuRowContent(
  BuildContext context,
  AppMenuMetrics metrics, {
  required String label,
  double? maxWidth,
  Widget? labelWidget,
  IconData? icon,
  Widget? trailing,
  bool isSelected = false,
  bool isDestructive = false,
  bool enabled = true,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  // M3: selectedContainer = primaryContainer (ללא גבול, ממלא שורה שלמה)
  final selectedBackground =
      colorScheme.primaryContainer.withValues(alpha: 0.95);
  final foregroundColor = !enabled
      ? colorScheme.onSurface.withValues(alpha: 0.38)
      : isDestructive
          ? colorScheme.error
          : isSelected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurface;

  final hasTrailingWidget = isSelected || trailing != null;
  final labelMaxWidth = _calculateAppMenuLabelMaxWidth(
    metrics,
    maxWidth: maxWidth,
    hasLeadingIcon: icon != null,
    hasTrailingWidget: hasTrailingWidget,
  );
  final labelTextStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: metrics.fontSize,
    fontWeight: isSelected ? FontWeight.w600 : metrics.itemFontWeight,
    color: foregroundColor,
  );
  final labelChild = labelWidget ??
      Text(
        label,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textDirection: TextDirection.rtl,
      );

  final row = Row(
    mainAxisSize: trailing != null ? MainAxisSize.max : MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: metrics.iconSize, color: foregroundColor),
        const SizedBox(width: 8),
      ],
      Directionality(
        textDirection: TextDirection.rtl,
        child: DefaultTextStyle.merge(
          style: labelTextStyle,
          child: labelMaxWidth == null
              ? labelChild
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMaxWidth),
                  child: labelChild,
                ),
        ),
      ),
      // סימן ✓ לפריט נבחר (תמיד, בכל סוג תפריט)
      if (isSelected) ...[
        const SizedBox(width: 8),
        Icon(
          FluentIcons.checkmark_24_regular,
          size: metrics.iconSize,
          color: foregroundColor,
        ),
      ] else if (trailing != null) ...[
        const Spacer(),
        IconTheme.merge(
          data: IconThemeData(
            size: metrics.iconSize,
            color: foregroundColor,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor),
            child: trailing,
          ),
        ),
      ],
    ],
  );

  return Container(
    constraints: BoxConstraints(
      minWidth: metrics.menuMinWidth,
      minHeight: metrics.itemHeight,
    ),
    // צבע מלא שורה — ללא עיגול פינות וללא גבול
    color: isSelected ? selectedBackground : null,
    padding: metrics.itemPadding,
    alignment: AlignmentDirectional.centerStart,
    child: row,
  );
}

double? _calculateAppMenuLabelMaxWidth(
  AppMenuMetrics metrics, {
  required double? maxWidth,
  required bool hasLeadingIcon,
  required bool hasTrailingWidget,
}) {
  if (maxWidth == null) return null;

  final occupiedWidth = metrics.itemPadding.horizontal +
      (hasLeadingIcon ? metrics.iconSize + 8 : 0) +
      (hasTrailingWidget ? metrics.iconSize + 8 : 0);
  final availableWidth = maxWidth - occupiedWidth;
  if (availableWidth <= 0) return null;

  return availableWidth;
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppPopupMenuItem<T>(BuildContext context,
    AppMenuEntry<T> entry, AppMenuMetrics metrics, T? selectedValue,
    {Key? key}) {
  final isSelected = selectedValue != null && entry.value == selectedValue;

  return PopupMenuItem<T>(
    key: key,
    value: entry.value,
    enabled: entry.enabled,
    height: metrics.itemHeight,
    // padding: EdgeInsets.zero — הריפוד מנוהל ב-_buildAppMenuRowContent
    // כדי שהצבע הנבחר יכסה שורה שלמה
    padding: EdgeInsets.zero,
    child: _buildAppMenuRowContent(
      context,
      metrics,
      label: entry.label,
      icon: entry.icon,
      trailing: entry.trailing,
      isSelected: isSelected,
      isDestructive: entry.isDestructive,
      enabled: entry.enabled,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppCustomPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppCustomPopupMenuItem<T>({
  required BuildContext context,
  required AppMenuMetrics metrics,
  required Widget child,
  bool enabled = false,
  double? height,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return PopupMenuItem<T>(
    enabled: enabled,
    height: height ?? metrics.itemHeight,
    padding: padding,
    child: child,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppSubmenuItemStyle
// ═══════════════════════════════════════════════════════════════════════════

ButtonStyle buildAppSubmenuItemStyle(
  BuildContext context,
  AppMenuMetrics metrics,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return ButtonStyle(
    padding: WidgetStatePropertyAll(metrics.itemPadding),
    minimumSize:
        WidgetStatePropertyAll(Size(metrics.menuMinWidth, metrics.itemHeight)),
    visualDensity: metrics.visualDensity,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.itemBorderRadius),
      ),
    ),
    alignment: Alignment.centerRight,
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: 'Roboto',
        fontSize: metrics.fontSize,
        fontWeight: metrics.itemFontWeight,
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.38);
      }
      return colorScheme.onSurface;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.38);
      }
      return colorScheme.onSurface;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return colorScheme.onSurface.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.pressed)) {
        return colorScheme.onSurface.withValues(alpha: 0.12);
      }
      return null;
    }),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppSubmenuPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppSubmenuPopupMenuItem<T>({
  required BuildContext context,
  required AppMenuMetrics metrics,
  required String label,
  IconData? icon,
  required List<Widget> menuChildren,
}) {
  return buildAppCustomPopupMenuItem<T>(
    context: context,
    metrics: metrics,
    child: SubmenuButton(
      menuChildren: menuChildren,
      style: buildAppSubmenuItemStyle(context, metrics),
      child: _buildAppMenuRowContent(
        context,
        metrics,
        label: label,
        icon: icon,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// showAppMenu — הצגת תפריט במיקום מוחלט
// ═══════════════════════════════════════════════════════════════════════════

Future<T?> showAppMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<AppMenuEntry<T>> entries,
}) {
  final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false);
  return showMenu<T>(
    context: context,
    position: position,
    items: entries
        .map<PopupMenuEntry<T>>(
          (entry) => buildAppPopupMenuItem<T>(context, entry, metrics, null),
        )
        .toList(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// AppContextMenuRegion — תפריט הקשר (right-click) בסגנון האפליקציה
//
// שימוש:
//   AppContextMenuRegion(
//     menuBuilder: (context) => [
//       AppContextMenuEntry(label: 'העתק', icon: FluentIcons.copy_24_regular, onTap: ...),
//       const AppContextMenuEntry.divider(),
//       AppContextMenuEntry(
//         label: 'מפרשים',
//         icon: FluentIcons.book_24_regular,
//         children: [...],
//       ),
//     ],
//     child: myWidget,
//   )
// ═══════════════════════════════════════════════════════════════════════════

class AppContextMenuRegion extends StatefulWidget {
  final Widget child;
  final List<AppContextMenuEntry> Function(BuildContext) menuBuilder;
  final Map<String, GlobalKey>? menuItemKeysByLabel;

  const AppContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.menuItemKeysByLabel,
  });

  @override
  State<AppContextMenuRegion> createState() => _AppContextMenuRegionState();
}

class _AppContextMenuRegionState extends State<AppContextMenuRegion> {
  static const double _contextMenuScreenPadding = 8;
  static const double _contextMenuMaxWidth = 320;

  bool _isMenuOpen = false;
  bool _isMenuVisible = false;
  OverlayEntry? _menuOverlayEntry;
  final GlobalKey _menuPanelKey = GlobalKey();
  Offset? _currentMenuOffset;
  double? _menuAnchorX;

  bool get _supportsLongPressContextMenu {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  @override
  void dispose() {
    _removeContextMenuOverlay();
    super.dispose();
  }

  void _removeContextMenuOverlay() {
    _menuOverlayEntry?.remove();
    _menuOverlayEntry = null;
    _currentMenuOffset = null;
    _menuAnchorX = null;
    _isMenuVisible = false;
  }

  void _closeContextMenu() {
    _removeContextMenuOverlay();
    if (_isMenuOpen && mounted) {
      setState(() => _isMenuOpen = false);
    }
  }

  void closeMenu() {
    _closeContextMenu();
  }

  Future<void> showMenu() async {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    await _openContextMenu(renderObject.localToGlobal(renderObject.size.center(
      Offset.zero,
    )));
  }

  double _resolveContextMenuMaxWidth(
    double overlayWidth,
    AppMenuMetrics metrics,
  ) {
    final availableWidth = overlayWidth - (_contextMenuScreenPadding * 2);
    return availableWidth
        .clamp(metrics.menuMinWidth, _contextMenuMaxWidth)
        .toDouble();
  }

  bool _isPointerInsideMenu(Offset globalPosition) {
    final renderObject = _menuPanelKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final menuRect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
    return menuRect.contains(globalPosition);
  }

  Offset _calculateMenuOffset(
    RenderBox overlayRenderBox,
    Offset overlayPosition,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
  ) {
    final estimatedHeight = entries.fold<double>(
          metrics.menuPadding.vertical,
          (sum, entry) =>
              sum +
              (entry.isDivider ? metrics.dividerHeight : metrics.itemHeight),
        ) +
        8;
    final spaceAbove = overlayPosition.dy;
    final spaceBelow = overlayRenderBox.size.height - overlayPosition.dy;
    final shouldOpenAbove =
        spaceBelow < estimatedHeight && spaceAbove > spaceBelow;
    final dx = overlayPosition.dx
        .clamp(_contextMenuScreenPadding,
            overlayRenderBox.size.width - _contextMenuScreenPadding)
        .toDouble();
    final rawDy = shouldOpenAbove
        ? overlayPosition.dy - estimatedHeight
        : overlayPosition.dy;
    final maxDy = (overlayRenderBox.size.height -
            metrics.itemHeight -
            _contextMenuScreenPadding)
        .clamp(_contextMenuScreenPadding, double.infinity)
        .toDouble();
    final dy = rawDy.clamp(_contextMenuScreenPadding, maxDy).toDouble();

    return Offset(dx, dy);
  }

  void _repositionContextMenuWithinOverlay(Size overlaySize) {
    final renderObject = _menuPanelKey.currentContext?.findRenderObject();
    final currentOffset = _currentMenuOffset;
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        currentOffset == null ||
        _menuOverlayEntry == null) {
      return;
    }

    final panelSize = renderObject.size;
    final maxDx =
        (overlaySize.width - panelSize.width - _contextMenuScreenPadding)
            .clamp(_contextMenuScreenPadding, double.infinity)
            .toDouble();
    final maxDy =
        (overlaySize.height - panelSize.height - _contextMenuScreenPadding)
            .clamp(_contextMenuScreenPadding, double.infinity)
            .toDouble();

    // RTL: right-align menu with anchor X; fall back to left-align if no space
    final anchorX = _menuAnchorX ?? currentOffset.dx;
    final rtlDx = anchorX - panelSize.width;
    final targetDx = rtlDx >= _contextMenuScreenPadding ? rtlDx : anchorX;

    final adjustedOffset = Offset(
      targetDx.clamp(_contextMenuScreenPadding, maxDx).toDouble(),
      currentOffset.dy.clamp(_contextMenuScreenPadding, maxDy).toDouble(),
    );

    _currentMenuOffset = adjustedOffset;
    _isMenuVisible = true;
    _menuOverlayEntry?.markNeedsBuild();
  }

  Future<void> _openContextMenu(Offset globalPosition) async {
    final entries = _normalizeEntries(widget.menuBuilder(context));
    if (entries.isEmpty) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayRenderObject = overlay.context.findRenderObject();
    if (overlayRenderObject is! RenderBox || !overlayRenderObject.hasSize) {
      return;
    }

    final overlayPosition = overlayRenderObject.globalToLocal(globalPosition);
    if (!overlayPosition.dx.isFinite || !overlayPosition.dy.isFinite) return;
    _menuAnchorX = overlayPosition.dx;
    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final menuOffset = _calculateMenuOffset(
      overlayRenderObject,
      overlayPosition,
      entries,
      metrics,
    );
    final menuStyle = _menuStyle(context, metrics);
    final maxMenuWidth = _resolveContextMenuMaxWidth(
      overlayRenderObject.size.width,
      metrics,
    );
    final maxMenuHeight = (overlayRenderObject.size.height -
            menuOffset.dy -
            _contextMenuScreenPadding)
        .clamp(metrics.itemHeight, double.infinity)
        .toDouble();

    // Create controllers once per menu open — stable across overlay rebuilds
    final submenuControllers = <AppContextMenuEntry, MenuController>{
      for (final entry in entries)
        if (((entry.children != null && entry.children!.isNotEmpty) ||
                entry.childrenBuilder != null) &&
            entry.enabled)
          entry: MenuController(),
    };

    _removeContextMenuOverlay();
    _currentMenuOffset = menuOffset;

    _menuOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final currentMenuOffset = _currentMenuOffset ?? menuOffset;
        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeContextMenu,
                child: const SizedBox.expand(),
              ),
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  if (event.buttons != kSecondaryButton) {
                    return;
                  }
                  if (_isPointerInsideMenu(event.position)) {
                    return;
                  }
                  _closeContextMenu();
                },
                child: const SizedBox.expand(),
              ),
              Positioned(
                left: currentMenuOffset.dx,
                top: currentMenuOffset.dy,
                child: Visibility(
                  visible: _isMenuVisible,
                  maintainSize: false,
                  maintainAnimation: false,
                  maintainState: true,
                  child: _AppContextMenuPanel(
                    key: _menuPanelKey,
                    entries: entries,
                    metrics: metrics,
                    menuStyle: menuStyle,
                    maxWidth: maxMenuWidth,
                    maxHeight: maxMenuHeight,
                    buildChildren: (panelContext, panelEntries) =>
                        _buildMenuPanelChildren(
                      panelContext,
                      panelEntries,
                      metrics,
                      maxMenuWidth,
                      submenuControllers,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    setState(() => _isMenuOpen = true);
    overlay.insert(_menuOverlayEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isMenuOpen) return;
      _repositionContextMenuWithinOverlay(overlayRenderObject.size);
    });
  }

  MenuStyle _menuStyle(BuildContext context, AppMenuMetrics metrics) {
    final themeStyle = Theme.of(context).menuTheme.style;
    // alignment: Alignment.topLeft — מציב את הפינה השמאלית-עליונה של תת-התפריט
    // בנקודת הכפתור (קצה ימין של הכפתור), כך שהתפריט נפתח ימינה.
    // Flutter יהפוך אוטומטית שמאלה אם אין מקום בצד ימין.
    return (themeStyle ?? const MenuStyle()).copyWith(
      alignment: Alignment.topLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPressStart: (details) {
        if (_supportsLongPressContextMenu) {
          _openContextMenu(details.globalPosition);
        }
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == 2) {
            _openContextMenu(event.position);
          }
        },
        child: widget.child,
      ),
    );
  }

  List<Widget> _buildMenuPanelChildren(
    BuildContext context,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
    double maxWidth,
    Map<AppContextMenuEntry, MenuController> submenuControllers,
  ) {
    return entries.map<Widget>((entry) {
      if (entry.isDivider) {
        return SizedBox(
          height: metrics.dividerHeight,
          child: const Divider(height: 1),
        );
      }

      if (entry.childrenBuilder != null) {
        if (!entry.enabled) {
          return MenuItemButton(
            key: widget.menuItemKeysByLabel?[entry.label ?? ''],
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: _buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: maxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        final controller = submenuControllers[entry];
        return _LazyAppSubmenuButton(
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          entry: entry,
          entriesBuilder: () => _normalizeEntries(entry.childrenBuilder!()),
          metrics: metrics,
          maxWidth: maxWidth,
          menuStyle: _menuStyle(context, metrics),
          controller: controller,
          onOpen: () {
            for (final ctrl in submenuControllers.values) {
              if (ctrl != controller && ctrl.isOpen) ctrl.close();
            }
          },
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
            context,
            submenuEntries,
            metrics,
            submenuMaxWidth,
          ),
        );
      }

      final rawChildren = entry.children;
      if (rawChildren != null && rawChildren.isNotEmpty) {
        final normalizedChildren = _normalizeEntries(rawChildren);
        final hasEnabledChildren =
            _hasEnabledAppContextMenuEntries(normalizedChildren);
        if (!entry.enabled || !hasEnabledChildren) {
          return MenuItemButton(
            key: widget.menuItemKeysByLabel?[entry.label ?? ''],
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: _buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: maxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        final controller = submenuControllers[entry];
        return _LazyAppSubmenuButton(
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          entry: entry,
          entriesBuilder: () => normalizedChildren,
          metrics: metrics,
          maxWidth: maxWidth,
          menuStyle: _menuStyle(context, metrics),
          controller: controller,
          onOpen: () {
            for (final ctrl in submenuControllers.values) {
              if (ctrl != controller && ctrl.isOpen) ctrl.close();
            }
          },
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
            context,
            submenuEntries,
            metrics,
            submenuMaxWidth,
          ),
        );
      }

      return MenuItemButton(
        key: widget.menuItemKeysByLabel?[entry.label ?? ''],
        style: buildAppSubmenuItemStyle(context, metrics),
        onPressed: entry.enabled
            ? () {
                _closeContextMenu();
                entry.onTap?.call();
              }
            : null,
        child: _buildAppMenuRowContent(
          context,
          metrics,
          maxWidth: maxWidth,
          label: entry.label ?? '',
          labelWidget: entry.labelWidget,
          icon: entry.icon,
          trailing: entry.trailing,
          isDestructive: entry.isDestructive,
          enabled: entry.enabled,
        ),
      );
    }).toList();
  }

  List<AppContextMenuEntry> _normalizeEntries(
      List<AppContextMenuEntry> entries) {
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
  ) {
    final submenuContentMaxWidth = maxWidth - metrics.itemPadding.horizontal;

    return entries.map((entry) {
      if (entry.isDivider) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1),
        );
      }

      if (entry.childrenBuilder != null) {
        if (!entry.enabled) {
          return MenuItemButton(
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: _buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: submenuContentMaxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        return _LazyAppSubmenuButton(
          entry: entry,
          entriesBuilder: () => _normalizeEntries(entry.childrenBuilder!()),
          metrics: metrics,
          maxWidth: submenuContentMaxWidth,
          menuStyle: _menuStyle(context, metrics),
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
            context,
            submenuEntries,
            metrics,
            submenuMaxWidth,
          ),
        );
      }

      final rawChildren = entry.children;
      if (rawChildren != null && rawChildren.isNotEmpty) {
        final normalizedChildren = _normalizeEntries(rawChildren);
        final hasEnabledChildren =
            _hasEnabledAppContextMenuEntries(normalizedChildren);
        if (!entry.enabled || !hasEnabledChildren) {
          return MenuItemButton(
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: _buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: submenuContentMaxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        return _LazyAppSubmenuButton(
          entry: entry,
          entriesBuilder: () => normalizedChildren,
          metrics: metrics,
          maxWidth: submenuContentMaxWidth,
          menuStyle: _menuStyle(context, metrics),
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
            context,
            submenuEntries,
            metrics,
            submenuMaxWidth,
          ),
        );
      }

      return MenuItemButton(
        key: entry.key,
        style: buildAppSubmenuItemStyle(context, metrics),
        onPressed: entry.enabled
            ? () {
                _closeContextMenu();
                entry.onTap?.call();
              }
            : null,
        child: _buildAppMenuRowContent(
          context,
          metrics,
          maxWidth: submenuContentMaxWidth,
          label: entry.label ?? '',
          labelWidget: entry.labelWidget,
          icon: entry.icon,
          trailing: entry.trailing,
          isDestructive: entry.isDestructive,
          enabled: entry.enabled,
        ),
      );
    }).toList();
  }
}

class _LazyAppSubmenuButton extends StatefulWidget {
  final AppContextMenuEntry entry;
  final List<AppContextMenuEntry> Function() entriesBuilder;
  final AppMenuMetrics metrics;
  final double maxWidth;
  final MenuStyle menuStyle;
  final MenuController? controller;
  final VoidCallback? onOpen;
  final List<Widget> Function(List<AppContextMenuEntry>, double) buildChildren;

  const _LazyAppSubmenuButton({
    super.key,
    required this.entry,
    required this.entriesBuilder,
    required this.metrics,
    required this.maxWidth,
    required this.menuStyle,
    required this.buildChildren,
    this.controller,
    this.onOpen,
  });

  @override
  State<_LazyAppSubmenuButton> createState() => _LazyAppSubmenuButtonState();
}

class _LazyAppSubmenuButtonState extends State<_LazyAppSubmenuButton> {
  List<AppContextMenuEntry>? _entries;
  List<Widget>? _menuChildren;
  bool? _hasEnabledChildren;
  bool? _openToRight;

  @override
  void initState() {
    super.initState();
    // טעינה מוקדמת של הילדים כדי למנוע תפריט ריק
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuChildren == null) {
        _ensureMenuChildrenLoaded();
      }
    });
  }

  void openSubmenu([VoidCallback? afterOpen]) {
    if (_menuChildren == null) {
      _ensureMenuChildrenLoaded();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller?.open();
        afterOpen?.call();
      });
    } else {
      widget.controller?.open();
      afterOpen?.call();
    }
  }

  void _ensureMenuChildrenLoaded() {
    if (_menuChildren != null) {
      return;
    }

    final entries = _entries ??= widget.entriesBuilder();
    final hasEnabledChildren = _hasEnabledAppContextMenuEntries(entries);
    setState(() {
      _hasEnabledChildren = hasEnabledChildren;
      _openToRight = _shouldOpenToRight();
      _menuChildren = hasEnabledChildren
          ? widget.buildChildren(entries, widget.maxWidth)
          : const <Widget>[];
    });
  }

  bool _shouldOpenToRight() {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayRenderObject = overlay?.context.findRenderObject();
    final itemRenderObject = context.findRenderObject();
    if (overlayRenderObject is! RenderBox ||
        itemRenderObject is! RenderBox ||
        !overlayRenderObject.hasSize ||
        !itemRenderObject.hasSize) {
      return !isRtl;
    }

    final itemRect = MatrixUtils.transformRect(
      itemRenderObject.getTransformTo(overlayRenderObject),
      Offset.zero & itemRenderObject.size,
    );
    final spaceLeft = itemRect.left;
    final spaceRight = overlayRenderObject.size.width - itemRect.right;

    if (isRtl) {
      return spaceLeft < widget.maxWidth && spaceRight > spaceLeft;
    }
    return !(spaceRight < widget.maxWidth && spaceLeft > spaceRight);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final openToRight = _openToRight ?? !isRtl;
    final menuTextDirection =
        openToRight ? TextDirection.ltr : TextDirection.rtl;
    final submenuAlignment =
        openToRight ? Alignment.topRight : Alignment.topLeft;
    final contentTextDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final submenuArrow = widget.entry.trailing ??
        Icon(
          isRtl
              ? FluentIcons.chevron_right_16_regular
              : FluentIcons.chevron_left_16_regular,
          size: widget.metrics.iconSize,
        );
    final menuChildren = (_menuChildren ?? const <Widget>[])
        .map(
          (child) => Directionality(
            textDirection: contentTextDirection,
            child: child,
          ),
        )
        .toList();

    if (_hasEnabledChildren == false) {
      return MenuItemButton(
        style: buildAppSubmenuItemStyle(context, widget.metrics),
        onPressed: null,
        child: _buildAppMenuRowContent(
          context,
          widget.metrics,
          maxWidth: widget.maxWidth,
          label: widget.entry.label ?? '',
          labelWidget: widget.entry.labelWidget,
          icon: widget.entry.icon,
          trailing: widget.entry.trailing,
          isDestructive: widget.entry.isDestructive,
          enabled: false,
        ),
      );
    }

    final submenuButton = MouseRegion(
      onEnter: (_) => _ensureMenuChildrenLoaded(),
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (_) => _ensureMenuChildrenLoaded(),
        child: SubmenuButton(
          controller: widget.controller,
          onOpen: () {
            _ensureMenuChildrenLoaded();
            final shouldOpenToRight = _shouldOpenToRight();
            if (_openToRight != shouldOpenToRight) {
              setState(() => _openToRight = shouldOpenToRight);
            }
            widget.onOpen?.call();
          },
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          style: buildAppSubmenuItemStyle(context, widget.metrics),
          menuStyle: widget.menuStyle.copyWith(
            alignment: submenuAlignment,
          ),
          menuChildren: menuChildren,
          child: Directionality(
            textDirection: contentTextDirection,
            child: _buildAppMenuRowContent(
              context,
              widget.metrics,
              maxWidth: widget.maxWidth,
              label: widget.entry.label ?? '',
              labelWidget: widget.entry.labelWidget,
              icon: widget.entry.icon,
              trailing: submenuArrow,
              isDestructive: widget.entry.isDestructive,
              enabled: widget.entry.enabled,
            ),
          ),
        ),
      ),
    );

    return Directionality(
      textDirection: menuTextDirection,
      child: submenuButton,
    );
  }
}

class _AppContextMenuPanel extends StatelessWidget {
  final List<AppContextMenuEntry> entries;
  final AppMenuMetrics metrics;
  final MenuStyle? menuStyle;
  final double maxWidth;
  final double maxHeight;
  final List<Widget> Function(BuildContext, List<AppContextMenuEntry>)
      buildChildren;

  const _AppContextMenuPanel({
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
        child: Material(
          color: menuStyle?.backgroundColor?.resolve(const <WidgetState>{}) ??
              colorScheme.surfaceContainer,
          elevation: menuStyle?.elevation
                  ?.resolve(const <WidgetState>{})?.toDouble() ??
              3,
          shape: menuStyle?.shape?.resolve(const <WidgetState>{}) ??
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.menuBorderRadius),
              ),
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
        ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AppSelectionField — שדה-בחירה (trigger לתפריט נפתח)
//
// עיצוב: זהה לשורת הטריגר של DropdownMenu עם חיפוש
// • ללא גבול במצב רגיל
// • גבול עדין בעת hover
// ═══════════════════════════════════════════════════════════════════════════

const double _dropdownFieldRadius = AppInputTokens.compactRadius;
const double _dropdownFieldIdleFillAlpha = AppInputTokens.unfocusedAlpha;
const double _dropdownFieldDisabledFillAlpha = AppInputTokens.disabledAlpha;
const double _dropdownFieldHoverFillAlpha = 0.10;
const double _dropdownFieldBorderWidth = 1.4;
const double _dropdownFieldMinHeight = 40.0;
const EdgeInsets _dropdownFieldContentPadding =
    EdgeInsets.symmetric(horizontal: 10, vertical: 5);

Color _dropdownFieldBorderColor(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return theme.brightness == Brightness.light
      ? cs.primary.withValues(alpha: 0.22)
      : cs.primary.withValues(alpha: 0.40);
}

class AppSelectionField extends StatefulWidget {
  final Widget child;
  final InputDecoration? decoration;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool isSelected;
  final FocusNode? focusNode;

  /// `null` = ברירת מחדל (40px/20px), `true` = compact (36px/20px), `false` = רגיל (48px/28px)
  final bool? slim;

  const AppSelectionField({
    super.key,
    required this.child,
    this.decoration,
    this.enabled = true,
    this.onTap,
    this.leading,
    this.isSelected = false,
    this.focusNode,
    this.slim,
  });

  @override
  State<AppSelectionField> createState() => _AppSelectionFieldState();
}

class _AppSelectionFieldState extends State<AppSelectionField> {
  bool _isHovering = false;
  bool _isFocused = false;

  static const Duration _animDuration = Duration(milliseconds: 120);

  double get _effectiveRadius =>
      widget.slim == false ? 28.0 : _dropdownFieldRadius;

  double get _effectiveMinHeight {
    if (widget.slim == false) return 48.0;
    if (widget.slim == true) return 36.0;
    return _dropdownFieldMinHeight;
  }

  BoxDecoration _buildFieldDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _effectiveRadius;

    if (_isFocused && widget.enabled) {
      return BoxDecoration(
        color: cs.onSurface.withValues(alpha: _dropdownFieldHoverFillAlpha),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: _dropdownFieldBorderColor(context),
          width: _dropdownFieldBorderWidth,
        ),
      );
    }
    if (_isHovering && widget.enabled) {
      return BoxDecoration(
        color: cs.onSurface.withValues(alpha: _dropdownFieldHoverFillAlpha),
        borderRadius: BorderRadius.circular(r),
      );
    }
    return BoxDecoration(
      color: cs.onSurface.withValues(
        alpha: widget.enabled
            ? _dropdownFieldIdleFillAlpha
            : _dropdownFieldDisabledFillAlpha,
      ),
      borderRadius: BorderRadius.circular(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentPadding =
        widget.decoration?.contentPadding ?? _dropdownFieldContentPadding;

    final content = Padding(
      padding: contentPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 8),
          ],
          Flexible(child: widget.child),
          // ללא חץ — המראה הוויזואלי של הכרטיס מספיק כ-affordance
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: _animDuration,
        curve: Curves.easeOut,
        decoration: _buildFieldDecoration(context),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            focusNode: widget.focusNode,
            canRequestFocus: widget.enabled,
            onFocusChange: (isFocused) {
              if (_isFocused != isFocused) {
                setState(() => _isFocused = isFocused);
              }
            },
            borderRadius: BorderRadius.circular(_effectiveRadius),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: _effectiveMinHeight),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AppDropdownField — שדה בחירה עם תפריט נפתח
//
// • enableSearch: false → AppSelectionField + popup menu
// • enableSearch: true  → DropdownMenu עם חיפוש + auto-select בפתיחה
//   ההבדל היחיד: האם ניתן להקליד ולסנן
// ═══════════════════════════════════════════════════════════════════════════

class AppDropdownField<T> extends StatefulWidget {
  final T? value;
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T?>? onSelected;
  final InputDecoration? decoration;
  final bool enabled;
  final bool isExpanded;
  final bool enableSearch;
  final Widget Function(BuildContext context, T? value)? selectedBuilder;
  final String Function(T value)? labelBuilder;

  const AppDropdownField({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.decoration,
    this.enabled = true,
    this.isExpanded = true,
    this.enableSearch = false,
    this.selectedBuilder,
    this.labelBuilder,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  final GlobalKey _selectionAnchorKey = GlobalKey();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final MenuController _menuController;
  String _menuVisibleText = '';
  bool _isSyncingControllerText = false;
  bool _restoreTextAfterNavigation = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedLabel);
    _controller.addListener(_handleControllerChanged);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
    _menuController = MenuController();
    _menuVisibleText = _controller.text;
  }

  @override
  void didUpdateWidget(covariant AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.entries != widget.entries) {
      _setControllerText(_selectedLabel);
      _menuVisibleText = _selectedLabel;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (_isSyncingControllerText) return;

    if (widget.enableSearch &&
        _restoreTextAfterNavigation &&
        _menuController.isOpen) {
      _restoreTextAfterNavigation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_menuController.isOpen) return;
        _setControllerText(
          _menuVisibleText,
          selection: TextSelection.collapsed(offset: _menuVisibleText.length),
        );
      });
      return;
    }

    _menuVisibleText = _controller.text;
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      // בחירת כל הטקסט אוטומטית בפתיחה — סעיף 6
      Future.microtask(() {
        if (mounted && _focusNode.hasFocus) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
          _menuVisibleText = _controller.text;
        }
      });
      return;
    }
    if (_controller.text != _selectedLabel) {
      _restoreSelectedText();
    }
  }

  void _restoreSelectedText() {
    final selectedLabel = _selectedLabel;
    _setControllerText(selectedLabel);
    _menuVisibleText = selectedLabel;
  }

  void _setControllerText(
    String text, {
    TextSelection? selection,
  }) {
    _isSyncingControllerText = true;
    _controller.value = TextEditingValue(
      text: text,
      selection: selection ?? TextSelection.collapsed(offset: text.length),
    );
    _isSyncingControllerText = false;
  }

  String get _selectedLabel {
    if (widget.value == null) return '';
    for (final entry in widget.entries) {
      if (entry.value == widget.value) return entry.label;
    }
    if (widget.labelBuilder != null) {
      return widget.labelBuilder!(widget.value as T);
    }
    return '';
  }

  AppMenuEntry<T>? get _selectedEntry {
    if (widget.value == null) return null;
    for (final entry in widget.entries) {
      if (entry.value == widget.value) return entry;
    }
    return null;
  }

  Future<void> _openSelectionMenu() async {
    if (!widget.enabled ||
        widget.onSelected == null ||
        widget.entries.isEmpty) {
      return;
    }
    final anchorContext = _selectionAnchorKey.currentContext;
    if (anchorContext == null) return;

    final selected = await showAnchoredAppMenu<T>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (metrics) => widget.entries
          .map<PopupMenuEntry<T>>(
            (entry) => buildAppPopupMenuItem<T>(
              context,
              entry,
              metrics,
              widget.value,
            ),
          )
          .toList(),
    );

    if (!mounted) return;

    _focusNode.requestFocus();
    if (selected != null) {
      widget.onSelected?.call(selected);
    }
  }

  void _openSearchMenu() {
    if (!_menuController.isOpen) {
      _menuVisibleText = _controller.text;
      _menuController.open();
    }
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  KeyEventResult _handleSearchFieldKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isActivateKey = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;

    if (!_menuController.isOpen &&
        (key == LogicalKeyboardKey.space || isActivateKey)) {
      _openSearchMenu();
      return KeyEventResult.handled;
    }

    if (_menuController.isOpen &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      _menuVisibleText = _controller.text;
      _restoreTextAfterNavigation = true;
      return KeyEventResult.ignored;
    }

    if (_menuController.isOpen && key == LogicalKeyboardKey.escape) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _menuController.isOpen) return;
        _restoreSelectedText();
        _focusNode.requestFocus();
      });
    }

    return KeyEventResult.ignored;
  }

  InputDecorationTheme _buildDecorationTheme(
    BuildContext context,
    AppMenuMetrics metrics,
  ) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = _dropdownFieldBorderColor(context);
    final isCompact = metrics.compactMenus;
    final r = AppInputTokens.radius(isCompact);
    final minH = AppInputTokens.height(isCompact);

    return InputDecorationTheme(
      filled: true,
      fillColor: cs.onSurface.withValues(
        alpha: widget.enabled
            ? AppInputTokens.unfocusedAlpha
            : AppInputTokens.disabledAlpha,
      ),
      isDense: true,
      contentPadding: _dropdownFieldContentPadding,
      constraints: BoxConstraints(minHeight: minH),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(
          color: borderColor,
          width: _dropdownFieldBorderWidth,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: metrics.fontSize,
      ),
    );
  }

  InputDecoration _buildSearchFieldDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFocus = _focusNode.hasFocus;

    // קבלת metrics כדי לדעת אם compact
    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final isCompact = metrics.compactMenus;

    // גובה, פונט ורדיוס תלויים ב-compact mode - משתמשים ב-AppInputTokens
    final fieldHeight = AppInputTokens.height(isCompact);
    final fieldFontSize = AppInputTokens.fontSize(isCompact);
    final fieldRadius = AppInputTokens.radius(isCompact);
    final iconSize = AppInputTokens.iconSize(isCompact);
    final minWidth = AppInputTokens.prefixMinWidth(isCompact);

    return InputDecoration(
      hintText: widget.decoration?.hintText ?? widget.decoration?.labelText,
      hintStyle: TextStyle(
        fontSize: fieldFontSize,
        color: cs.onSurfaceVariant,
        height: 1.0,
      ),
      filled: true,
      isDense: true,
      fillColor: hasFocus
          ? cs.primary.withValues(alpha: AppInputTokens.focusedAlpha)
          : cs.onSurface.withValues(alpha: AppInputTokens.unfocusedAlpha),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceXS, vertical: 0),
      constraints: BoxConstraints(minHeight: fieldHeight),
      prefixIcon: Icon(
        FluentIcons.search_24_regular,
        size: iconSize,
        color: hasFocus ? cs.primary : cs.onSurfaceVariant,
      ),
      prefixIconConstraints: BoxConstraints(
        minWidth: minWidth,
        minHeight: fieldHeight,
      ),
      suffixIcon: const SizedBox.shrink(),
      suffixIconConstraints: BoxConstraints(
        minWidth: AppInputTokens.suffixMinWidth(isCompact),
        minHeight: fieldHeight,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide.none,
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final isCompact = metrics.compactMenus;
    final effectiveEnabled = widget.enabled &&
        widget.onSelected != null &&
        widget.entries.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    final width = widget.isExpanded ? double.infinity : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth =
            width == double.infinity && constraints.hasBoundedWidth
                ? constraints.maxWidth
                : width;

        // ── מצב ללא חיפוש: AppSelectionField + popup ──────────────────────
        if (!widget.enableSearch) {
          final selectedEntry = _selectedEntry;
          final displayText =
              widget.selectedBuilder?.call(context, widget.value) ??
                  Text(
                    _selectedLabel,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: metrics.fontSize,
                      fontWeight: metrics.itemFontWeight,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  );

          final fieldContent = selectedEntry?.icon == null
              ? displayText
              : Row(
                  children: [
                    Icon(
                      selectedEntry!.icon,
                      size: metrics.iconSize,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: displayText),
                  ],
                );

          return SizedBox(
            width: resolvedWidth,
            child: KeyedSubtree(
              key: _selectionAnchorKey,
              child: AppSelectionField(
                enabled: effectiveEnabled,
                focusNode: _focusNode,
                onTap: _openSelectionMenu,
                decoration: widget.decoration,
                isSelected: widget.value != null,
                slim: isCompact ? true : false,
                child: SizedBox(
                  width: double.infinity,
                  child: fieldContent,
                ),
              ),
            ),
          );
        }

        // ── מצב עם חיפוש: DropdownMenu ────────────────────────────────────
        return SizedBox(
          width: resolvedWidth,
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _handleSearchFieldKeyEvent,
            child: DropdownMenu<T>(
              controller: _controller,
              focusNode: _focusNode,
              menuController: _menuController,
              enabled: effectiveEnabled,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap:
                  true, // auto-select בפתיחה (דרך _handleFocusChanged)
              initialSelection: widget.value,
              menuHeight:
                  (metrics.itemHeight * 8) + metrics.menuPadding.vertical,
              width: resolvedWidth,
              showTrailingIcon: false,
              textStyle: TextStyle(
                fontFamily: 'Roboto',
                fontSize: AppInputTokens.fontSize(metrics.compactMenus),
                fontWeight: metrics.itemFontWeight,
                color: cs.onSurface,
                height: 1.0,
              ),
              inputDecorationTheme: _buildDecorationTheme(context, metrics),
              decorationBuilder: (context, _) =>
                  _buildSearchFieldDecoration(context),
              leadingIcon: null,
              trailingIcon: null,
              selectedTrailingIcon: null,
              dropdownMenuEntries: widget.entries.map((entry) {
                final isSelected = entry.value == widget.value;
                return DropdownMenuEntry<T>(
                  value: entry.value,
                  label: entry.label,
                  labelWidget: _buildAppMenuRowContent(
                    context,
                    metrics,
                    label: entry.label,
                    icon: entry.icon,
                    trailing: entry.trailing,
                    isSelected: isSelected,
                    isDestructive: entry.isDestructive,
                    enabled: entry.enabled,
                  ),
                  enabled: entry.enabled,
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    minimumSize: WidgetStatePropertyAll(
                      Size(metrics.menuMinWidth, metrics.itemHeight),
                    ),
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                  ),
                );
              }).toList(),
              onSelected: (value) {
                if (value == null) {
                  _restoreSelectedText();
                  return;
                }
                final selectedEntry = widget.entries
                    .where((entry) => entry.value == value)
                    .firstOrNull;
                _menuVisibleText = selectedEntry?.label ?? _selectedLabel;
                widget.onSelected?.call(value);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _focusNode.requestFocus();
                });
              },
            ),
          ),
        );
      },
    );
  }
}
