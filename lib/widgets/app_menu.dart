import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

class AppPopupMenuButton<T> extends StatelessWidget {
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
    this.position = PopupMenuPosition.over,
    this.offset = const Offset(0, 8),
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    assert(entries != null || itemBuilder != null);

    return PopupMenuButton<T>(
      tooltip: tooltip,
      padding: padding ?? EdgeInsets.zero,
      constraints: constraints,
      position: position,
      offset: offset,
      enabled: enabled,
      onSelected: onSelected,
      icon: icon,
      child: child,
      itemBuilder: (context) =>
          itemBuilder?.call(context) ??
          entries!
              .map((entry) => buildAppPopupMenuItem(context, entry, metrics))
              .toList(),
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
          ),
        ),
        if (entry.trailing != null) ...[
          const SizedBox(width: 8),
          entry.trailing!,
        ],
      ],
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

class AppDropdownField<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final metrics = Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    AppMenuEntry<T>? selectedEntry;
    if (value != null) {
      for (final entry in entries) {
        if (entry.value == value) {
          selectedEntry = entry;
          break;
        }
      }
    }
    final effectiveEnabled =
        enabled && onSelected != null && entries.isNotEmpty;
    final textStyle = TextStyle(
      fontFamily: 'Roboto',
      fontSize: metrics.fontSize,
      fontWeight: FontWeight.w400,
      color: Theme.of(context).colorScheme.onSurface,
    );

    final nonNullValue = value;
    final selectedLabel = selectedEntry?.label ??
        (nonNullValue != null && labelBuilder != null
            ? labelBuilder!(nonNullValue)
            : '');

    final selectedChild = selectedBuilder?.call(context, value) ??
        Text(
          selectedLabel,
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.rtl,
        );

    final field = InputDecorator(
      isEmpty: value == null,
      isFocused: false,
      expands: false,
      decoration: (decoration ?? const InputDecoration()).copyWith(
        enabled: effectiveEnabled,
        suffixIcon: Icon(
          FluentIcons.chevron_down_24_regular,
          size: metrics.iconSize,
        ),
        contentPadding: decoration?.contentPadding ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: selectedChild,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.itemHeight + 16),
      child: AppPopupMenuButton<T>(
        entries: entries,
        enabled: effectiveEnabled,
        position: PopupMenuPosition.under,
        onSelected: onSelected == null ? null : (value) => onSelected!(value),
        child:
            isExpanded ? SizedBox(width: double.infinity, child: field) : field,
      ),
    );
  }
}
