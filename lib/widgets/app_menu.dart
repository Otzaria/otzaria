import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
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
  final String? label;
  final IconData? icon;
  final bool enabled;
  final bool isDivider;
  final bool isDestructive;
  final VoidCallback? onTap;

  /// תת-פריטים לתפריט משנה
  final List<AppContextMenuEntry>? children;

  const AppContextMenuEntry({
    required this.label,
    this.icon,
    this.enabled = true,
    this.isDestructive = false,
    this.onTap,
    this.children,
  }) : isDivider = false;

  const AppContextMenuEntry.divider()
      : label = null,
        icon = null,
        enabled = false,
        isDivider = true,
        isDestructive = false,
        onTap = null,
        children = null;
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
  IconData? icon,
  Widget? trailing,
  bool isSelected = false,
  bool isDestructive = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  // M3: selectedContainer = primaryContainer (ללא גבול, ממלא שורה שלמה)
  final selectedBackground =
      colorScheme.primaryContainer.withValues(alpha: 0.95);
  final foregroundColor = isDestructive
      ? colorScheme.error
      : isSelected
          ? colorScheme.onPrimaryContainer
          : colorScheme.onSurface;

  return Container(
    constraints: BoxConstraints(
      minWidth: metrics.menuMinWidth,
      minHeight: metrics.itemHeight,
    ),
    // צבע מלא שורה — ללא עיגול פינות וללא גבול
    color: isSelected ? selectedBackground : null,
    padding: metrics.itemPadding,
    alignment: AlignmentDirectional.centerStart,
    child: Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        if (icon != null) ...[
          Icon(icon, size: metrics.iconSize, color: foregroundColor),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: metrics.fontSize,
              fontWeight: isSelected ? FontWeight.w600 : metrics.itemFontWeight,
              color: foregroundColor,
            ),
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
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
          const SizedBox(width: 8),
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
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppPopupMenuItem<T>(
  BuildContext context,
  AppMenuEntry<T> entry,
  AppMenuMetrics metrics,
  T? selectedValue,
) {
  final isSelected = selectedValue != null && entry.value == selectedValue;

  return PopupMenuItem<T>(
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
      menuStyle: const MenuStyle(
        alignment: AlignmentDirectional(-1.0, -1.0),
      ),
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

class AppContextMenuRegion extends StatelessWidget {
  final Widget child;
  final List<AppContextMenuEntry> Function(BuildContext) menuBuilder;

  const AppContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == 2) {
          // Secondary mouse button (right-click)
          _showContextMenu(context, event.position);
        }
      },
      child: child,
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, Offset globalPosition) async {
    final entries = menuBuilder(context);
    if (entries.isEmpty) return;

    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    await showMenu<_ContextMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _buildMenuItems(context, entries, metrics),
    ).then((action) => action?.call());
  }

  List<PopupMenuEntry<_ContextMenuAction>> _buildMenuItems(
    BuildContext context,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
  ) {
    // סינון: לא להתחיל/לסיים בהפרד, ולא שני מפרידים רצופים
    final normalized = _normalizeEntries(entries);
    return normalized.map((entry) {
      if (entry.isDivider) {
        return const PopupMenuDivider();
      }
      if (entry.children != null && entry.children!.isNotEmpty) {
        return _buildSubmenuItem(context, entry, metrics);
      }
      return _buildMenuItem(context, entry, metrics);
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

  PopupMenuEntry<_ContextMenuAction> _buildMenuItem(
    BuildContext context,
    AppContextMenuEntry entry,
    AppMenuMetrics metrics,
  ) {
    return PopupMenuItem<_ContextMenuAction>(
      value: entry.onTap,
      enabled: entry.enabled,
      height: metrics.itemHeight,
      padding: EdgeInsets.zero,
      child: _buildAppMenuRowContent(
        context,
        metrics,
        label: entry.label ?? '',
        icon: entry.icon,
        isDestructive: entry.isDestructive,
      ),
    );
  }

  PopupMenuEntry<_ContextMenuAction> _buildSubmenuItem(
    BuildContext context,
    AppContextMenuEntry entry,
    AppMenuMetrics metrics,
  ) {
    final subChildren = entry.children!
        .where((c) => !c.isDivider)
        .map((child) => MenuItemButton(
              leadingIcon: child.icon != null
                  ? Icon(child.icon, size: metrics.iconSize)
                  : null,
              style: buildAppSubmenuItemStyle(context, metrics),
              onPressed: child.enabled ? child.onTap : null,
              child: Text(
                child.label ?? '',
                textDirection: TextDirection.rtl,
              ),
            ))
        .toList();

    return buildAppCustomPopupMenuItem<_ContextMenuAction>(
      context: context,
      metrics: metrics,
      height: metrics.itemHeight,
      child: SubmenuButton(
        menuChildren: subChildren,
        style: buildAppSubmenuItemStyle(context, metrics),
        menuStyle: const MenuStyle(
          // פתיחה בצד — לא מעל התפריט הראשי
          alignment: AlignmentDirectional(-1.0, -1.0),
        ),
        child: _buildAppMenuRowContent(
          context,
          metrics,
          label: entry.label ?? '',
          icon: entry.icon,
        ),
      ),
    );
  }
}

/// טיפוס פנימי — callback של פריט תפריט הקשר
typedef _ContextMenuAction = VoidCallback?;

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
