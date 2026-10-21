import 'dart:math';

import 'package:flutter/material.dart';

import 'menu_metrics.dart';
import 'menu_models.dart';
import 'menu_presentation.dart';

const double _kCheckmarkGap = 4;

const FontWeight _kSelectedItemFontWeight = FontWeight.w600;

Widget buildAppMenuRowContent(
  BuildContext context,
  AppMenuMetrics metrics, {
  required String label,
  required MenuPresentation presentation,
  double? maxWidth,
  Widget? labelWidget,
  IconData? icon,
  Color? iconColor,
  Widget? trailing,
  bool isSelected = false,
  bool isDestructive = false,
  bool enabled = true,
  bool reserveTrailingGap = false,
  double trailingReservedWidth = 0,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final foregroundColor = !enabled
      ? colorScheme.onSurface.withValues(alpha: 0.38)
      : isDestructive
      ? colorScheme.error
      : isSelected
      ? colorScheme.primary
      : colorScheme.onSurface;

  final hasTrailingWidget = isSelected || trailing != null;
  // selected+trailing מציג גם trailing וגם checkmark → slot נוסף.
  // non-selected+trailing+reserve מציג trailing + SizedBox ריק → slot נוסף.
  final hasExtraSlot =
      (isSelected && trailing != null) ||
      (!isSelected && reserveTrailingGap && trailing != null);
  final labelMaxWidth = calculateAppMenuLabelMaxWidth(
    metrics,
    maxWidth: maxWidth,
    hasLeadingIcon: icon != null,
    hasTrailingWidget: hasTrailingWidget,
    trailingWidth: trailingReservedWidth,
    hasExtraSlot: hasExtraSlot,
  );
  final labelTextStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: metrics.fontSize,
    fontWeight: isSelected ? _kSelectedItemFontWeight : metrics.itemFontWeight,
    color: foregroundColor,
  );
  final labelChild =
      labelWidget ??
      Text(
        label,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );

  final row = Row(
    mainAxisSize: (isSelected || trailing != null)
        ? MainAxisSize.max
        : MainAxisSize.min,
    children: [
      if (icon != null) ...[
        presentation.iconBuilder(
          context,
          icon,
          metrics.iconSize,
          enabled ? iconColor ?? foregroundColor : foregroundColor,
          true,
        ),
        const SizedBox(width: 8),
      ],
      DefaultTextStyle.merge(
        style: labelTextStyle,
        child: labelMaxWidth == null
            ? labelChild
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: labelChild,
              ),
      ),
      if (isSelected && trailing != null) ...[
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
        const SizedBox(width: _kCheckmarkGap),
        presentation.selectedMarkBuilder(
          context,
          metrics.iconSize,
          foregroundColor,
        ),
      ] else if (isSelected) ...[
        const Spacer(),
        const SizedBox(width: _kCheckmarkGap),
        presentation.selectedMarkBuilder(
          context,
          metrics.iconSize,
          foregroundColor,
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
        if (reserveTrailingGap) SizedBox(width: metrics.iconSize + 8),
      ],
    ],
  );

  return Container(
    constraints: BoxConstraints(
      minWidth: metrics.menuMinWidth,
      minHeight: metrics.itemHeight,
    ),
    padding: metrics.itemPadding,
    alignment: AlignmentDirectional.centerStart,
    child: row,
  );
}

double? calculateAppMenuLabelMaxWidth(
  AppMenuMetrics metrics, {
  required double? maxWidth,
  required bool hasLeadingIcon,
  required bool hasTrailingWidget,
  double trailingWidth = 0,
  bool hasExtraSlot = false,
}) {
  if (maxWidth == null) return null;

  final trailingSlot = hasTrailingWidget
      ? (trailingWidth > 0 ? trailingWidth : metrics.iconSize + 8)
      : 0.0;
  final occupiedWidth =
      metrics.itemPadding.horizontal +
      (hasLeadingIcon ? metrics.iconSize + 8 : 0) +
      trailingSlot +
      (hasExtraSlot ? metrics.iconSize + 8 : 0);
  final availableWidth = maxWidth - occupiedWidth;
  if (availableWidth <= 0) return null;

  return availableWidth;
}

/// מחשב את הרוחב הדרוש להצגת הפריט הארוך ביותר ב-[entries] בלי קיצוץ —
/// משמש גם לקביעת רוחב התפריט וגם לרוחב הכפתור הפותח אותו (AppDropdownField).
double calculateAppMenuPreferredWidth<T>(
  AppMenuMetrics metrics,
  List<AppMenuEntry<T>> entries,
) {
  if (entries.isEmpty) return metrics.menuMinWidth;

  // נמדד במשקל של פריט נבחר (מודגש) — כל פריט עשוי להיות זה שנבחר,
  // והגופן המודגש רחב יותר מהרגיל.
  final textStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: metrics.fontSize,
    fontWeight: _kSelectedItemFontWeight,
  );

  var maxLabelWidth = 0.0;
  for (final entry in entries) {
    final painter = TextPainter(
      text: TextSpan(text: entry.label, style: textStyle),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    if (painter.width > maxLabelWidth) maxLabelWidth = painter.width;
  }

  final hasIcon = entries.any((entry) => entry.icon != null);

  var maxTrailingWidth = 0.0;
  var hasExtraSlot = false;
  for (final entry in entries) {
    if (entry.trailing != null) {
      final tWidth = entry.trailingReservedWidth > 0
          ? entry.trailingReservedWidth
          : metrics.iconSize + 8;
      if (tWidth > maxTrailingWidth) maxTrailingWidth = tWidth;
      if (entry.reserveTrailingGap) hasExtraSlot = true;
    }
  }

  // תמיד משוריין מקום לסימן ה-✓ שמוצג ליד הפריט הנבחר, יהיה אשר יהיה.
  final occupiedWidth =
      metrics.itemPadding.horizontal +
      (hasIcon ? metrics.iconSize + 8 : 0) +
      metrics.iconSize +
      _kCheckmarkGap +
      maxTrailingWidth +
      (hasExtraSlot ? metrics.iconSize + 8 : 0);

  return max(metrics.menuMinWidth, maxLabelWidth + occupiedWidth);
}

ButtonStyle buildAppSubmenuItemStyle(
  BuildContext context,
  AppMenuMetrics metrics, {
  required MenuPresentation presentation,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return ButtonStyle(
    padding: WidgetStatePropertyAll(metrics.itemPadding),
    minimumSize: WidgetStatePropertyAll(
      Size(metrics.menuMinWidth, metrics.itemHeight),
    ),
    visualDensity: metrics.visualDensity,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: presentation.borderRadius,
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
