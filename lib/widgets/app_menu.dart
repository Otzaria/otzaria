import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

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
            .map((entry) => buildAppPopupMenuItem(context, entry, metrics))
            .toList();
  }

  double _estimateMenuHeight(
    List<PopupMenuEntry<T>> items,
    AppMenuMetrics metrics,
  ) {
    return items.fold<double>(
          metrics.menuPadding.vertical,
          (sum, item) => sum + item.height,
        ) +
        8;
  }

  Future<void> _showAdaptiveMenu() async {
    if (!widget.enabled) return;
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;

    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final items = _buildItems(context, metrics);
    if (items.isEmpty) return;

    final renderBox = anchorContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final targetRect = MatrixUtils.transformRect(
      renderBox.getTransformTo(overlay),
      Offset.zero & renderBox.size,
    );

    final menuHeight = _estimateMenuHeight(items, metrics);
    final spaceAbove = targetRect.top;
    final spaceBelow = overlay.size.height - targetRect.bottom;
    final preferBelow = widget.position == PopupMenuPosition.under;
    final shouldOpenBelow = preferBelow
        ? (spaceBelow >= menuHeight || spaceBelow >= spaceAbove)
        : !(spaceAbove >= menuHeight || spaceAbove >= spaceBelow);

    final anchorTop = shouldOpenBelow
        ? targetRect.bottom + widget.offset.dy
        : (targetRect.top - menuHeight - widget.offset.dy).clamp(
            0.0,
            overlay.size.height,
          );

    final anchorRect = RelativeRect.fromRect(
      Rect.fromLTWH(targetRect.left, anchorTop, targetRect.width, 0),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<T>(
      context: context,
      position: anchorRect,
      items: items,
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

PopupMenuItem<T> buildAppPopupMenuItem<T>(
  BuildContext context,
  AppMenuEntry<T> entry,
  AppMenuMetrics metrics,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final foregroundColor =
      entry.isDestructive ? colorScheme.error : colorScheme.onSurface;

  return PopupMenuItem<T>(
    value: entry.value,
    enabled: entry.enabled,
    height: metrics.itemHeight,
    padding: metrics.itemPadding,
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: metrics.menuMinWidth),
      child: Row(
        children: [
          if (entry.icon != null) ...[
            Icon(entry.icon, size: metrics.iconSize, color: foregroundColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              entry.label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: metrics.fontSize,
                fontWeight: FontWeight.w400,
                color: foregroundColor,
              ),
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
            ),
          ),
          if (entry.trailing != null) ...[
            const SizedBox(width: 8),
            entry.trailing!,
          ],
        ],
      ),
    ),
  );
}

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
        .map((entry) => buildAppPopupMenuItem(context, entry, metrics))
        .toList(),
  );
}

class AppDropdownField<T> extends StatefulWidget {
  final T? value;
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T?>? onSelected;
  final InputDecoration? decoration;
  final bool enabled;
  final bool isExpanded;
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
    this.selectedBuilder,
    this.labelBuilder,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedLabel);
  }

  @override
  void didUpdateWidget(covariant AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.entries != widget.entries) {
      _controller.value = TextEditingValue(
        text: _selectedLabel,
        selection: TextSelection.collapsed(offset: _selectedLabel.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _selectedLabel {
    if (widget.value == null) return '';
    for (final entry in widget.entries) {
      if (entry.value == widget.value) {
        return entry.label;
      }
    }
    if (widget.labelBuilder != null) {
      return widget.labelBuilder!(widget.value as T);
    }
    return '';
  }

  InputDecorationTheme _buildDecorationTheme(
    BuildContext context,
    AppMenuMetrics metrics,
  ) {
    final cs = Theme.of(context).colorScheme;
    final decoration = widget.decoration;
    final radius = decoration?.border is OutlineInputBorder
        ? ((decoration!.border as OutlineInputBorder)
                .borderRadius
                .resolve(Directionality.of(context))
                .topLeft
                .x)
            .clamp(12.0, 28.0)
        : 20.0;
    final fillColor = decoration?.fillColor ??
        cs.onSurface.withValues(alpha: widget.enabled ? 0.07 : 0.04);
    final contentPadding = decoration?.contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    final enabledBorder = decoration?.enabledBorder ??
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        );
    final focusedBorder = decoration?.focusedBorder ??
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: cs.primary.withValues(alpha: 0.8),
            width: 1.4,
          ),
        );

    return InputDecorationTheme(
      filled: decoration?.filled ?? true,
      fillColor: fillColor,
      isDense: decoration?.isDense ?? true,
      contentPadding: contentPadding,
      border: decoration?.border ?? enabledBorder,
      enabledBorder: enabledBorder,
      focusedBorder: focusedBorder,
      disabledBorder: decoration?.disabledBorder ?? enabledBorder,
      hintStyle: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: metrics.fontSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
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

        return SizedBox(
          width: resolvedWidth,
          child: DropdownMenu<T>(
            controller: _controller,
            enabled: effectiveEnabled,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            initialSelection: widget.value,
            menuHeight: (metrics.itemHeight * 8) + metrics.menuPadding.vertical,
            width: resolvedWidth,
            textStyle: TextStyle(
              fontFamily: 'Roboto',
              fontSize: metrics.fontSize,
              fontWeight: FontWeight.w400,
              color: cs.onSurface,
            ),
            inputDecorationTheme: _buildDecorationTheme(context, metrics),
            hintText: widget.decoration?.hintText,
            label: widget.decoration?.labelText != null
                ? Text(
                    widget.decoration!.labelText!,
                    textDirection: TextDirection.rtl,
                  )
                : widget.decoration?.label,
            leadingIcon: null,
            trailingIcon: Icon(
              FluentIcons.chevron_down_24_regular,
              size: metrics.iconSize,
            ),
            selectedTrailingIcon: Icon(
              FluentIcons.chevron_up_24_regular,
              size: metrics.iconSize,
            ),
            dropdownMenuEntries: widget.entries
                .map(
                  (entry) => DropdownMenuEntry<T>(
                    value: entry.value,
                    label: entry.label,
                    enabled: entry.enabled,
                    leadingIcon: entry.icon != null
                        ? Icon(entry.icon, size: metrics.iconSize)
                        : null,
                    trailingIcon: entry.trailing,
                  ),
                )
                .toList(),
            onSelected: (value) {
              widget.onSelected?.call(value);
            },
          ),
        );
      },
    );
  }
}
