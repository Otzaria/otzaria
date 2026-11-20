import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// בודק האם הטקסט גולש מעבר למספר השורות המרבי ברוחב הנתון.
///
/// רשימה ארוכה מעבירה [cache] משלה ([newTextOverflowCache]), כדי שלא תדחק
/// מהמטמון המשותף את המדידות של עצי הניווט.
bool textOverflows({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
  TextAlign textAlign = TextAlign.start,
  TextDirection? textDirection,
  Map<Object, bool>? cache,
}) => _hasOverflow(
  _textLayoutOf(
    context,
    text: text,
    style: style,
    maxLines: maxLines,
    textAlign: textAlign,
    textDirection: textDirection,
  ),
  maxWidth,
  cache,
);

bool _hasOverflow(
  _TextLayout layout,
  double maxWidth,
  Map<Object, bool>? cache,
) {
  final entries = cache ?? _overflowCache;
  final key = (layout, maxWidth);
  final cached = entries.remove(key);
  if (cached != null) return entries[key] = cached;
  debugTextOverflowLayouts++;
  final textPainter = layout.createPainter()..layout(maxWidth: maxWidth);
  final overflows = textPainter.didExceedMaxLines;
  textPainter.dispose();
  if (entries.length >= 2000) {
    entries.remove(entries.keys.first);
  }
  return entries[key] = overflows;
}

/// מטמון ל-[textOverflows]. שורות נבנות מחדש בגלילה ומודדות שוב אותו טקסט;
/// גופן שנטען משנה מדידה, ולכן המטמון מתרוקן.
Map<Object, bool> newTextOverflowCache() {
  final cache = <Object, bool>{};
  PaintingBinding.instance.systemFonts.addListener(cache.clear);
  return cache;
}

final Map<Object, bool> _overflowCache = newTextOverflowCache();

@visibleForTesting
int debugTextOverflowLayouts = 0;

/// ווידג'ט טקסט שעוטף את עצמו ב-[Tooltip] אך ורק כאשר הטקסט נקטע ([TextOverflow.ellipsis]).
///
/// כשהטקסט נכנס במלואו במגבלות הרוחב, מרונדר [Text] בלי טולטיפ.
class OverflowTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  final String? tooltipMessage;

  /// null משתמש בזמן ההמתנה של ערכת הנושא.
  final Duration? waitDuration;

  /// סגנון הרמז, כשהוא שונה מ-`tooltipTheme` של ערכת הנושא.
  final TooltipThemeData? tooltipTheme;

  /// מטמון מדידה משלו לרשימה ארוכה ([newTextOverflowCache]).
  final Map<Object, bool>? cache;

  const OverflowTooltipText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.tooltipMessage,
    this.waitDuration = const Duration(milliseconds: 300),
    this.tooltipTheme,
    this.cache,
  });

  @override
  Widget build(BuildContext context) {
    final layout = _textLayoutOf(
      context,
      text: text,
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
    );
    final child = Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: style,
    );
    return _TextIntrinsics(
      layout: layout,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final hasOverflow =
              width > 0 &&
              (width.isFinite || text.contains('\n')) &&
              _hasOverflow(layout, width, cache);
          if (!hasOverflow) {
            return child;
          }

          final tooltip = Tooltip(
            message: tooltipMessage ?? text,
            waitDuration: waitDuration,
            child: child,
          );
          final theme = tooltipTheme;
          return theme == null
              ? tooltip
              : TooltipTheme(data: theme, child: tooltip);
        },
      ),
    );
  }
}

/// מודד מידות פנימיות עבור הורים כמו [IntrinsicWidth], כי [LayoutBuilder]
/// מספק פריסה בפועל בלבד.
class _TextIntrinsics extends SingleChildRenderObjectWidget {
  const _TextIntrinsics({required this.layout, required super.child});

  final _TextLayout layout;

  @override
  _RenderTextIntrinsics createRenderObject(BuildContext context) =>
      _RenderTextIntrinsics(layout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTextIntrinsics renderObject,
  ) {
    renderObject.textLayout = layout;
  }
}

class _RenderTextIntrinsics extends RenderProxyBox
    with RelayoutWhenSystemFontsChangeMixin {
  _RenderTextIntrinsics(this._textLayout);

  _TextLayout _textLayout;
  TextPainter? _painter;

  set textLayout(_TextLayout value) {
    if (_textLayout == value) return;
    _textLayout = value;
    _painter?.dispose();
    _painter = null;
    markNeedsLayout();
  }

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    _painter?.markNeedsLayout();
  }

  TextPainter _layoutFor(double maxWidth, {double minWidth = 0}) =>
      (_painter ??= _textLayout.createPainter())
        ..layout(minWidth: minWidth, maxWidth: maxWidth);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _layoutFor(double.infinity).minIntrinsicWidth;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _layoutFor(double.infinity).maxIntrinsicWidth;

  @override
  double computeMinIntrinsicHeight(double width) => _layoutFor(width).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _layoutFor(width).height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final painter = _layoutFor(
      constraints.maxWidth,
      minWidth: constraints.minWidth,
    );
    return constraints.constrain(painter.size);
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _layoutFor(
    constraints.maxWidth,
    minWidth: constraints.minWidth,
  ).computeDistanceToActualBaseline(TextBaseline.alphabetic);

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}

typedef _TextLayout = ({
  String text,
  TextStyle style,
  TextAlign textAlign,
  TextDirection textDirection,
  TextScaler textScaler,
  Locale? locale,
  TextWidthBasis textWidthBasis,
  TextHeightBehavior? textHeightBehavior,
  int maxLines,
});

_TextLayout _textLayoutOf(
  BuildContext context, {
  required String text,
  required TextStyle? style,
  required int maxLines,
  required TextAlign textAlign,
  TextDirection? textDirection,
}) {
  final defaults = DefaultTextStyle.of(context);
  // אלה אותם מאפייני טיפוגרפיה ונגישות ש־Text מעביר לפסקה.
  final bold = MediaQuery.boldTextOf(context);
  final height = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  final resolvedStyle = defaults.style.merge(style);
  final effectiveStyle =
      bold || height != null || letterSpacing != null || wordSpacing != null
      ? resolvedStyle.copyWith(
          fontWeight: bold ? FontWeight.bold : null,
          height: height,
          letterSpacing: letterSpacing,
          wordSpacing: wordSpacing,
        )
      : resolvedStyle;
  return (
    text: text,
    style: effectiveStyle,
    textAlign: textAlign,
    textDirection: textDirection ?? Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textWidthBasis: defaults.textWidthBasis,
    textHeightBehavior:
        defaults.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
    maxLines: maxLines,
  );
}

extension on _TextLayout {
  TextPainter createPainter() => TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: textDirection,
    maxLines: maxLines,
    ellipsis: '…',
    textScaler: textScaler,
    locale: locale,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
  );
}
