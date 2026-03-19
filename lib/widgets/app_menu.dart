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
            .map<PopupMenuEntry<T>>(
              (entry) => buildAppPopupMenuItem<T>(
                context,
                entry,
                metrics,
                null,
              ),
            )
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

PopupMenuEntry<T> buildAppPopupMenuItem<T>(
  BuildContext context,
  AppMenuEntry<T> entry,
  AppMenuMetrics metrics,
  T? selectedValue,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final isSelected = selectedValue != null && entry.value == selectedValue;
  final foregroundColor = entry.isDestructive
      ? colorScheme.error
      : isSelected
          ? colorScheme.onSecondaryContainer
          : colorScheme.onSurface;

  return PopupMenuItem<T>(
    value: entry.value,
    enabled: entry.enabled,
    height: metrics.itemHeight,
    padding: metrics.itemPadding,
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: metrics.menuMinWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.secondaryContainer.withValues(alpha: 0.95)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(metrics.itemBorderRadius),
        ),
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
                  fontWeight:
                      isSelected ? FontWeight.w700 : metrics.itemFontWeight,
                  color: foregroundColor,
                ),
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(
                FluentIcons.checkmark_24_regular,
                size: metrics.iconSize,
                color: foregroundColor,
              ),
            ] else if (entry.trailing != null) ...[
              const SizedBox(width: 8),
              entry.trailing!,
            ],
          ],
        ),
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
        .map<PopupMenuEntry<T>>(
          (entry) => buildAppPopupMenuItem<T>(context, entry, metrics, null),
        )
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
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedLabel);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
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
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) return;
    if (widget.enableSearch && _controller.text != _selectedLabel) {
      _restoreSelectedText();
    }
  }

  void _restoreSelectedText() {
    final selectedLabel = _selectedLabel;
    _controller.value = TextEditingValue(
      text: selectedLabel,
      selection: TextSelection.collapsed(offset: selectedLabel.length),
    );
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

  AppMenuEntry<T>? get _selectedEntry {
    if (widget.value == null) return null;
    for (final entry in widget.entries) {
      if (entry.value == widget.value) {
        return entry;
      }
    }
    return null;
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

        if (!widget.enableSearch) {
          final selectedEntry = _selectedEntry;
          final displayText = widget.selectedBuilder?.call(context, widget.value) ??
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

          final field = InputDecorator(
            isEmpty: widget.value == null,
            isFocused: false,
            expands: false,
            decoration: (widget.decoration ?? const InputDecoration()).copyWith(
              enabled: effectiveEnabled,
              suffixIcon: Icon(
                FluentIcons.chevron_down_24_regular,
                size: metrics.iconSize,
              ),
            ),
            child: selectedEntry?.icon == null
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
                  ),
          );

          return SizedBox(
            width: resolvedWidth,
            child: AppPopupMenuButton<T>(
              entries: widget.entries,
              enabled: effectiveEnabled,
              onSelected: widget.onSelected == null
                  ? null
                  : (value) => widget.onSelected!(value),
              child: SizedBox(
                width: double.infinity,
                child: field,
              ),
            ),
          );
        }

        return SizedBox(
          width: resolvedWidth,
          child: DropdownMenu<T>(
            controller: _controller,
            focusNode: _focusNode,
            enabled: effectiveEnabled,
            enableFilter: widget.enableSearch,
            enableSearch: widget.enableSearch,
            requestFocusOnTap: widget.enableSearch,
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
                    trailingIcon: entry.value == widget.value
                        ? Icon(
                            FluentIcons.checkmark_24_regular,
                            size: metrics.iconSize,
                            color: cs.onSecondaryContainer,
                          )
                        : entry.trailing,
                    style: entry.value == widget.value
                        ? ButtonStyle(
                            foregroundColor: WidgetStatePropertyAll(
                              cs.onSecondaryContainer,
                            ),
                            textStyle: const WidgetStatePropertyAll(
                              TextStyle(fontWeight: FontWeight.w700),
                            ),
                            iconColor: WidgetStatePropertyAll(
                              cs.onSecondaryContainer,
                            ),
                            backgroundColor: WidgetStatePropertyAll(
                              cs.secondaryContainer.withValues(alpha: 0.95),
                            ),
                          )
                        : null,
                  ),
                )
                .toList(),
            onSelected: (value) {
              if (value == null) {
                if (widget.enableSearch) {
                  _restoreSelectedText();
                }
                return;
              }
              widget.onSelected?.call(value);
            },
          ),
        );
      },
    );
  }
}
