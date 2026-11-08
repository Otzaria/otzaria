import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'menu_metrics.dart';
import 'menu_models.dart';
import 'menu_presentation.dart';

const double _kCheckmarkGap = 4;

const FontWeight _kSelectedItemFontWeight = FontWeight.w600;

const int _kLabelsPerMeasurement = 64;
const int _kMaxBatchedLabelLength = 2048;
const int _kMaxBatchedTextLength = 8192;
const int _kSortLabelsThreshold = 1024;
const int _kPreprocessingEntriesPerYield = 1024;
// תווי בקרה דורשים פסקה עצמאית כדי שלא ישפיעו על מדידת תוויות אחרות.
final _independentParagraphLabel = RegExp(
  r'[\p{C}\p{Zl}\p{Zp}\u{10000}-\u{10ffff}]',
  unicode: true,
);

// גופן ברירת המחדל של הפלטפורמה, כמו ב־ThemeData בלי fontFamily (Segoe UI
// ב־Windows). המדידה והציור חייבים להשתמש באותה משפחה.
String? get _platformFontFamily => Typography.material2021(
  platform: defaultTargetPlatform,
).black.bodyMedium?.fontFamily;

Widget buildAppMenuRowContent(
  BuildContext context,
  AppMenuMetrics metrics, {
  required String label,
  required MenuPresentation presentation,
  double? maxWidth,
  Widget? labelWidget,
  IconData? icon,
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
    fontFamily: _platformFontFamily,
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

  final styledLabel = DefaultTextStyle.merge(
    style: labelTextStyle,
    child: labelMaxWidth == null
        ? labelChild
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: labelMaxWidth),
            child: labelChild,
          ),
  );
  final hasTrailing = isSelected || trailing != null;

  // התווית מתכווצת כשהשורה רחבה מהתפריט, למשל בחלון צר או בהגדלת טקסט
  // של המערכת: קיצור ב־"…" ולא גלישה. כשיש סימון או trailing היא תופסת את
  // המקום שבין האייקון לסוף השורה (כמו Spacer), ונצמדת להתחלה.
  final row = Row(
    mainAxisSize: hasTrailing ? MainAxisSize.max : MainAxisSize.min,
    children: [
      if (icon != null) ...[
        presentation.iconBuilder(
          context,
          icon,
          metrics.iconSize,
          foregroundColor,
          true,
        ),
        const SizedBox(width: 8),
      ],
      if (hasTrailing)
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            heightFactor: 1,
            child: styledLabel,
          ),
        )
      else
        Flexible(child: styledLabel),
      if (isSelected && trailing != null) ...[
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
        const SizedBox(width: _kCheckmarkGap),
        presentation.selectedMarkBuilder(
          context,
          metrics.iconSize,
          foregroundColor,
        ),
      ] else if (trailing != null) ...[
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

/// רוחב התפריט או הכפתור הנדרש להצגת כל [entries], עד לתקרה [maxWidth].
double calculateAppMenuPreferredWidth<T>(
  AppMenuMetrics metrics,
  List<AppMenuEntry<T>> entries, {
  double maxWidth = double.infinity,
}) => _appMenuPreferredWidths(metrics, entries, maxWidth).last;

/// מדידה מדויקת במנות, כדי שפתיחת תפריט גדול לא תחסום אירועי ממשק.
Future<double> calculateAppMenuPreferredWidthAsync<T>(
  AppMenuMetrics metrics,
  List<AppMenuEntry<T>> entries, {
  double maxWidth = double.infinity,
}) async {
  final budget = Stopwatch()..start();
  var width = min(metrics.menuMinWidth, maxWidth);
  for (final measured in _appMenuPreferredWidths(metrics, entries, maxWidth)) {
    width = measured;
    if (budget.elapsedMilliseconds >= 8) {
      await Future<void>.delayed(Duration.zero);
      budget.reset();
    }
  }
  return width;
}

Iterable<double> _appMenuPreferredWidths<T>(
  AppMenuMetrics metrics,
  List<AppMenuEntry<T>> entries,
  double maxWidth,
) sync* {
  assert(maxWidth >= 0);
  if (entries.isEmpty) {
    yield min(metrics.menuMinWidth, maxWidth);
    return;
  }
  // The menu cannot be narrower than its floor unless the caller imposes a
  // smaller maximum. In either case no label measurements are needed.
  if (maxWidth <= metrics.menuMinWidth) {
    yield maxWidth;
    return;
  }

  var hasIcon = false;
  var maxTrailingWidth = 0.0;
  var hasExtraSlot = false;
  var inspectedEntries = 0;
  for (final entry in entries) {
    if (entry.icon != null) hasIcon = true;
    if (entry.trailing != null) {
      final tWidth = entry.trailingReservedWidth > 0
          ? entry.trailingReservedWidth
          : metrics.iconSize + 8;
      if (tWidth > maxTrailingWidth) maxTrailingWidth = tWidth;
      if (entry.reserveTrailingGap) hasExtraSlot = true;
    }
    // Let the async caller yield during metadata scanning, not only after
    // all entries have been deduplicated and text layout has begun.
    if (++inspectedEntries % _kPreprocessingEntriesPerYield == 0) {
      yield min(metrics.menuMinWidth, maxWidth);
    }
  }

  // תמיד משוריין מקום לסימן הבחירה, גם אם הפריט הנבחר ישתנה.
  final occupiedWidth =
      metrics.itemPadding.horizontal +
      (hasIcon ? metrics.iconSize + 8 : 0) +
      metrics.iconSize +
      _kCheckmarkGap +
      maxTrailingWidth +
      (hasExtraSlot ? metrics.iconSize + 8 : 0);
  if (max(metrics.menuMinWidth, occupiedWidth) >= maxWidth) {
    yield maxWidth;
    return;
  }

  // נמדד במשקל של פריט נבחר (מודגש) — כל פריט עשוי להיות זה שנבחר,
  // והגופן המודגש רחב יותר מהרגיל.
  final textStyle = TextStyle(
    fontFamily: _platformFontFamily,
    fontSize: metrics.fontSize,
    fontWeight: _kSelectedItemFontWeight,
  );

  final uniqueLabels = <String>{};
  inspectedEntries = 0;
  for (final entry in entries) {
    uniqueLabels.add(entry.label);
    if (++inspectedEntries % _kPreprocessingEntriesPerYield == 0) {
      yield min(metrics.menuMinWidth, maxWidth);
    }
  }
  final labels = uniqueLabels.toList();
  // ארוכות תחילה כדי להגיע מהר לתקרת רוחב התפריט; אורך לבדו אינו חסם רוחב.
  if (maxWidth.isFinite && labels.length > _kSortLabelsThreshold) {
    labels.sort((a, b) => b.length.compareTo(a.length));
  }
  var maxLabelWidth = 0.0;
  for (var start = 0; start < labels.length;) {
    var end = start;
    var textLength = 0;
    do {
      textLength += labels[end++].length;
    } while (end < labels.length &&
        end - start < _kLabelsPerMeasurement &&
        textLength < _kMaxBatchedTextLength);
    final batch = labels.sublist(start, end);
    start = end;
    final paragraphs = <String>[];
    final ordinaryLabels = <String>[];
    for (final label in batch) {
      if (label.length > _kMaxBatchedLabelLength ||
          _independentParagraphLabel.hasMatch(label)) {
        paragraphs.add(label);
      } else {
        ordinaryLabels.add(label);
      }
    }
    if (ordinaryLabels.isNotEmpty) paragraphs.add(ordinaryLabels.join('\n'));
    for (final paragraph in paragraphs) {
      final painter = TextPainter(
        text: TextSpan(text: paragraph, style: textStyle),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      maxLabelWidth = max(maxLabelWidth, painter.width);
      painter.dispose();
      // חיבור פסקאות עלול לצבור שגיאת עיגול תת־פיקסלית במדידה של המנוע.
      final width = max(
        metrics.menuMinWidth,
        maxLabelWidth.ceilToDouble() + 1 + occupiedWidth,
      );
      yield min(width, maxWidth);
      if (width >= maxWidth) return;
    }
  }
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
    alignment: AlignmentDirectional.centerStart,
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: _platformFontFamily,
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
