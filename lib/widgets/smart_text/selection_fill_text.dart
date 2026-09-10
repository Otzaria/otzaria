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
/// כשיש בחירה `Text` עוטף את ה-`RichText` שלו במיכל פנימי שמסדר בחירה של
/// `WidgetSpan`, ואין דרך להחליף דרכו את ה-render object. הספאנים כאן הם טקסט
/// טהור, ולכן המיכל אינו נדרש ואפשר לבנות את ה-`RichText` ישירות.
class SelectionFillText extends StatelessWidget {
  const SelectionFillText.rich(
    this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
  });

  final InlineSpan textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) {
      return Text.rich(
        textSpan,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
      );
    }

    final defaultTextStyle = DefaultTextStyle.of(context);
    final selectionStyle = DefaultSelectionStyle.of(context);
    return MouseRegion(
      cursor: selectionStyle.mouseCursor ?? SystemMouseCursors.text,
      child: SelectionFillRichText(
        text: TextSpan(
          style: style == null || style!.inherit
              ? defaultTextStyle.style.merge(style)
              : style,
          children: [textSpan],
        ),
        textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
        softWrap: defaultTextStyle.softWrap,
        overflow: defaultTextStyle.overflow,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: defaultTextStyle.maxLines,
        strutStyle: strutStyle,
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
}
