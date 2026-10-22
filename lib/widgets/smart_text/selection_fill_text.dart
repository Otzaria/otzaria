/// הדגשת בחירה שממלאת את גובה השורה, בלי פס לא-צבוע בין שורה לשורה.
///
/// הפריימוורק מצייר את הבחירה ב-`BoxHeightStyle.tight` — תיבה בגובה הגליף
/// בלבד — ואין פרמטר לשנות זאת מחוץ ל-`TextField`. `max` נותן תיבה בגובה שורת
/// התצוגה, שנוגעת בשורה שאחריה, כמו בדפדפן ובוורד.
library;

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
    return super.getBoxesForSelection(
      selection,
      boxHeightStyle: boxHeightStyle == ui.BoxHeightStyle.tight
          ? ui.BoxHeightStyle.max
          : boxHeightStyle,
      boxWidthStyle: boxWidthStyle,
    );
  }

  List<ui.TextBox> _glyphBoxesForSelection(TextSelection selection) =>
      super.getBoxesForSelection(selection);
}

/// תיבות בגובה הגליף (`tight`) גם בפסקה שמילוי הבחירה ממפה בה `tight` ל-`max` —
/// למי שממקם ציור ביחס לאותיות עצמן ולא ביחס לשורה.
List<ui.TextBox> glyphBoxesForSelection(
  RenderParagraph paragraph,
  TextSelection selection,
) => paragraph is _RenderSelectionFillParagraph
    ? paragraph._glyphBoxesForSelection(selection)
    : paragraph.getBoxesForSelection(selection);
