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
}) {
  final entries = cache ?? _overflowCache;
  final direction = textDirection ?? Directionality.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  final key = (
    text,
    style,
    maxLines,
    maxWidth,
    textAlign,
    direction,
    textScaler,
  );
  final cached = entries.remove(key);
  if (cached != null) return entries[key] = cached;
  debugTextOverflowLayouts++;
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: direction,
    maxLines: maxLines,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
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
/// כשהטקסט נכנס במלואו במגבלות הרוחב, מרונדר [Text] רגיל ללא תקורה או טולטיפ מיותר.
class OverflowTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  final String? tooltipMessage;
  final Duration waitDuration;

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
    // Text merges [style] into the ambient DefaultTextStyle; measure the same
    // style it renders with.
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);

    return _TextIntrinsics(
      text: text,
      style: resolvedStyle,
      maxLines: maxLines,
      textAlign: textAlign,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      child: _buildLayout(resolvedStyle),
    );
  }

  Widget _buildLayout(TextStyle resolvedStyle) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            textOverflows(
              context: context,
              text: text,
              style: resolvedStyle,
              maxLines: maxLines,
              maxWidth: constraints.maxWidth,
              textAlign: textAlign,
              cache: cache,
            );

        final child = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: resolvedStyle,
        );

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
    );
  }
}

/// Answers intrinsic and dry-layout queries for [OverflowTooltipText] by
/// measuring the text directly. [LayoutBuilder] cannot answer them, and parents
/// such as menus and dialogs (IntrinsicWidth, AlertDialog) ask for them. The
/// real layout still goes through the LayoutBuilder child; the tooltip never
/// changes the size of the text.
class _TextIntrinsics extends SingleChildRenderObjectWidget {
  const _TextIntrinsics({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required super.child,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  _RenderTextIntrinsics createRenderObject(BuildContext context) =>
      _RenderTextIntrinsics(_painter());

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTextIntrinsics renderObject,
  ) {
    renderObject.painter = _painter();
  }

  TextPainter _painter() => TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: textDirection,
    maxLines: maxLines,
    ellipsis: '…',
    textScaler: textScaler,
  );
}

class _RenderTextIntrinsics extends RenderProxyBox {
  _RenderTextIntrinsics(this._painter);

  TextPainter _painter;

  set painter(TextPainter value) {
    final old = _painter;
    _painter = value;
    final changed =
        old.text != value.text ||
        old.textAlign != value.textAlign ||
        old.textDirection != value.textDirection ||
        old.maxLines != value.maxLines ||
        old.textScaler != value.textScaler;
    old.dispose();
    if (changed) markNeedsLayout();
  }

  TextPainter _layoutFor(double maxWidth) =>
      _painter
        ..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);

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
    final painter = _layoutFor(constraints.maxWidth);
    return constraints.constrain(painter.size);
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _layoutFor(
    constraints.maxWidth,
  ).computeDistanceToActualBaseline(baseline);

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
