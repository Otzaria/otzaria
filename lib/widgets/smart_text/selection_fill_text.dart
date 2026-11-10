/// הדגשת בחירה שממלאת את גובה השורה, בלי פס לא-צבוע בין שורה לשורה.
///
/// הפריימוורק מצייר את הבחירה ב-`BoxHeightStyle.tight` — תיבה בגובה הגליף
/// בלבד — ואין פרמטר לשנות זאת מחוץ ל-`TextField`. `max` נותן תיבה בגובה שורת
/// התצוגה, שנוגעת בשורה שאחריה, כמו בדפדפן ובוורד.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// `RichText` שתיבות הבחירה בו נמדדות בגובה שורת התצוגה המלאה.
class SelectionFillRichText extends RichText {
  SelectionFillRichText({
    super.key,
    required super.text,
    super.textAlign,
    super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionRegistrar,
    super.selectionColor,
  });

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    return _RenderSelectionFillParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
      devicePixelRatio:
          MediaQuery.maybeDevicePixelRatioOf(context) ??
          View.maybeOf(context)?.devicePixelRatio ??
          1.0,
    );
  }
}

/// `Text.rich` שהדגשת הבחירה בו ממלאת את גובה השורה.
///
/// יורש מ-`Text` כדי שהעץ יכיל `Text` (אחרת `find.text` בטסטים לא מוצא כלום),
/// ודורס את `build` בלבד: הספאנים כאן טקסט טהור, ולכן המיכל של `Text` מיותר.
class SelectionFillText extends Text {
  const SelectionFillText.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
  }) : super.rich();

  @override
  Widget build(BuildContext context) {
    final registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) {
      return super.build(context);
    }

    final defaultTextStyle = DefaultTextStyle.of(context);
    final selectionStyle = DefaultSelectionStyle.of(context);
    TextStyle? effectiveStyle = style;
    if (style == null || style!.inherit) {
      effectiveStyle = defaultTextStyle.style.merge(style);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle!.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final lineHeightScaleFactor =
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final text = _withTextSpacingOverrides(
      TextSpan(style: effectiveStyle, children: [textSpan!]),
      lineHeightScaleFactor: lineHeightScaleFactor,
      letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
      wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
    );
    return MouseRegion(
      cursor: selectionStyle.mouseCursor ?? SystemMouseCursors.text,
      child: SelectionFillRichText(
        text: text,
        textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
        softWrap: defaultTextStyle.softWrap,
        overflow: effectiveStyle?.overflow ?? defaultTextStyle.overflow,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: defaultTextStyle.maxLines,
        strutStyle: strutStyle?.merge(
          StrutStyle(height: lineHeightScaleFactor),
        ),
        textWidthBasis: defaultTextStyle.textWidthBasis,
        textHeightBehavior:
            defaultTextStyle.textHeightBehavior ??
            DefaultTextHeightBehavior.maybeOf(context),
        selectionRegistrar: registrar,
        selectionColor:
            selectionStyle.selectionColor ?? DefaultSelectionStyle.defaultColor,
      ),
    );
  }
}

TextSpan _withTextSpacingOverrides(
  TextSpan span, {
  required double? lineHeightScaleFactor,
  required double? letterSpacing,
  required double? wordSpacing,
}) {
  if (lineHeightScaleFactor == null &&
      letterSpacing == null &&
      wordSpacing == null) {
    return span;
  }
  final override = TextStyle(
    height: lineHeightScaleFactor,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
  );
  TextSpan apply(TextSpan current) => TextSpan(
    text: current.text,
    children: current.children?.map((child) {
      return child is TextSpan && child.runtimeType == TextSpan
          ? apply(child)
          : child;
    }).toList(),
    style: current.style?.merge(override) ?? override,
    recognizer: current.recognizer,
    mouseCursor: current.mouseCursor,
    onEnter: current.onEnter,
    onExit: current.onExit,
    semanticsLabel: current.semanticsLabel,
    semanticsIdentifier: current.semanticsIdentifier,
    locale: current.locale,
    spellOut: current.spellOut,
  );
  return apply(span);
}

/// מחזיר את [built] כשה-`RichText` שבשורשו נבנה מחדש עם [strutStyle] ועם מילוי
/// גובה השורה לבחירה. מבנה לא מוכר חוזר כפי שהוא.
Widget withSelectionFillRichText(Widget built, {StrutStyle? strutStyle}) {
  if (built is RichText) {
    return _rebuild(built, strutStyle);
  }
  if (built is MouseRegion && built.child is RichText) {
    return MouseRegion(
      onEnter: built.onEnter,
      onExit: built.onExit,
      onHover: built.onHover,
      cursor: built.cursor,
      opaque: built.opaque,
      hitTestBehavior: built.hitTestBehavior,
      child: _rebuild(built.child! as RichText, strutStyle),
    );
  }
  return built;
}

/// בלי `selectionRegistrar` הטקסט אינו בר-בחירה ואין מה למלא — נשאר
/// `RichText` רגיל, ולא נבנה מחדש אלא אם ה-strut באמת משתנה.
RichText _rebuild(RichText source, StrutStyle? strutStyle) {
  final selectable = source.selectionRegistrar != null;
  if (!selectable && (strutStyle == null || strutStyle == source.strutStyle)) {
    return source;
  }
  final construct = selectable ? SelectionFillRichText.new : RichText.new;
  return construct(
    key: source.key,
    text: source.text,
    textAlign: source.textAlign,
    textDirection: source.textDirection,
    softWrap: source.softWrap,
    overflow: source.overflow,
    textScaler: source.textScaler,
    maxLines: source.maxLines,
    locale: source.locale,
    strutStyle: strutStyle ?? source.strutStyle,
    textWidthBasis: source.textWidthBasis,
    textHeightBehavior: source.textHeightBehavior,
    selectionRegistrar: source.selectionRegistrar,
    selectionColor: source.selectionColor,
  );
}

class _RenderSelectionFillParagraph extends RenderParagraph {
  _RenderSelectionFillParagraph(
    super.text, {
    super.textAlign,
    required super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    super.registrar,
    super.devicePixelRatio,
  });

  /// הבחירה ממיינת את הנרשמים לפי מיקומם, ופסקה שלא נפרסה (פריט רשימה שמור
  /// מחוץ לתצוגה) מפילה את המיון — לכן נרשמים לבחירה רק אחרי הפריסה הראשונה.
  SelectionRegistrar? _pendingRegistrar;

  @override
  SelectionRegistrar? get registrar =>
      hasSize ? super.registrar : _pendingRegistrar;

  @override
  set registrar(SelectionRegistrar? value) {
    if (hasSize) {
      super.registrar = value;
    } else {
      _pendingRegistrar = value;
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    _hardBreakShifts = null;
    final pending = _pendingRegistrar;
    if (pending != null) {
      _pendingRegistrar = null;
      super.registrar = pending;
    }
  }

  /// ציור הבחירה בפריימוורק קורא לכאן בלי `boxHeightStyle`, כלומר `tight`.
  /// סגנון שהמתקשר ביקש במפורש נשאר שלו.
  @override
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    return _unshiftBoxes(
      super.getBoxesForSelection(
        selection,
        boxHeightStyle: boxHeightStyle == ui.BoxHeightStyle.tight
            ? ui.BoxHeightStyle.max
            : boxHeightStyle,
        boxWidthStyle: boxWidthStyle,
      ),
    );
  }

  /// הבחירה מבקשת מיקום מחוץ לפסקה בפינה הוויזואלית (`adjustDragOffset`), ובשורה
  /// שמתחילה או מסתיימת ברצף בכיוון ההפוך הפינה אינה תחילת הטקסט או סופו (flutter#196327).
  @override
  TextPosition getPositionForOffset(Offset offset) {
    if (textDirection != TextDirection.rtl) {
      return super.getPositionForOffset(offset);
    }
    if (offset.dy <= 0) return const TextPosition(offset: 0);
    if (offset.dy >= size.height) {
      return TextPosition(
        offset: text.toPlainText(includeSemanticsLabels: false).length,
        affinity: TextAffinity.upstream,
      );
    }
    final dx = _shiftAt(offset.dy)?.dx ?? 0;
    return super.getPositionForOffset(offset.translate(dx, 0));
  }

  List<ui.TextBox> _glyphBoxesForSelection(TextSelection selection) =>
      _unshiftBoxes(super.getBoxesForSelection(selection));

  /// skparagraph מודד שורת RTL שמסתיימת ב-`\n` כאילו ל-`\n` רוחב בקצה השמאלי,
  /// ולכן התיבות והמיקומים בה זזים ימינה ממה שצויר (flutter#196326).
  List<_LineShift>? _hardBreakShifts;

  List<_LineShift> get _shifts =>
      _hardBreakShifts ??= _measureHardBreakShifts();

  List<_LineShift> _measureHardBreakShifts() {
    if (textDirection != TextDirection.rtl) return const [];
    final plain = text.toPlainText(includeSemanticsLabels: false);
    final shifts = <_LineShift>[];
    var start = 0;
    for (var i = plain.indexOf('\n'); i >= 0; i = plain.indexOf('\n', i + 1)) {
      final lineStart = start;
      start = i + 1;
      final breakBoxes = super.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      if (i == lineStart || breakBoxes.isEmpty) continue;
      final line = breakBoxes.first;
      var left = double.infinity;
      for (final box in super.getBoxesForSelection(
        TextSelection(baseOffset: lineStart, extentOffset: i),
      )) {
        if (box.bottom > line.top && box.top < line.bottom) {
          left = math.min(left, box.left);
        }
      }
      final dx = left - line.left;
      if (dx.isFinite && dx > 0.5) {
        shifts.add((
          top: line.top,
          bottom: line.bottom,
          left: line.left,
          dx: dx,
        ));
      }
    }
    return shifts;
  }

  _LineShift? _shiftAt(double dy) {
    for (final shift in _shifts) {
      if (dy >= shift.top && dy < shift.bottom) return shift;
    }
    return null;
  }

  List<ui.TextBox> _unshiftBoxes(List<ui.TextBox> boxes) {
    if (_shifts.isEmpty) return boxes;
    return [
      for (final box in boxes)
        if (_shiftAt((box.top + box.bottom) / 2) case final shift?)
          ui.TextBox.fromLTRBD(
            math.max(box.left - shift.dx, shift.left),
            box.top,
            math.max(box.right - shift.dx, shift.left),
            box.bottom,
            box.direction,
          )
        else
          box,
    ];
  }
}

/// תיבות בגובה הגליף (`tight`) גם בפסקה שמילוי הבחירה ממפה בה `tight` ל-`max` —
/// למי שממקם ציור ביחס לאותיות עצמן ולא ביחס לשורה.
List<ui.TextBox> glyphBoxesForSelection(
  RenderParagraph paragraph,
  TextSelection selection,
) => paragraph is _RenderSelectionFillParagraph
    ? paragraph._glyphBoxesForSelection(selection)
    : paragraph.getBoxesForSelection(selection);

typedef _LineShift = ({double top, double bottom, double left, double dx});
