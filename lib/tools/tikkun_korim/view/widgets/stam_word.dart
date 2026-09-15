/// מילה בטור הסת"ם — כולל זעירא/רבתי ונו"ן הפוכה.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart';

export 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart'
    show kTikkunStretchLetters, kTikkunLastResortStretchLetters;

/// מספר האותיות הנמתחות במילה; מילה שיש בה שם הוי"ה אינה נמתחת.
int tikkunStretchableCount(String text) {
  if (text.contains('יהוה') || text.contains('יקוק')) return 0;
  var count = 0;
  for (final code in text.codeUnits) {
    if (kTikkunStretchLetters.contains(code)) count++;
  }
  return count;
}

/// אות נמתחת לכל היותר בעוד מלוא רוחבה; מה שנותר מעבר לזה נשאר ברווחים.
const double kTikkunMaxLetterStretch = 1;

/// רוחבי האותיות הנמתחות שבמילה, בסדר הכתיבה — המדידה שמתכנן השורה מקצה לפיה.
/// אות שגגה לא נמדד בגופן הזה מקבלת 0, ולכן אינה נמתחת.
List<double> tikkunStretchLetterWidths(String text, TextStyle style) {
  if (tikkunStretchableCount(text) == 0) return const [];
  return [
    for (final part in splitTikkunNun(text))
      if (part != kNunHafukhaGlyph)
        for (final piece in _splitStretchLetters(part))
          if (piece.stretch)
            _roofOf(piece.text, style) == null
                ? 0
                : tikkunWordWidth(piece.text, style),
  ];
}

/// לכל אות נמתחת ב-[text], באותו סדר: האם היא חלופה אחרונה (ר').
List<bool> tikkunStretchLetterLastResort(String text) => [
  for (final part in splitTikkunNun(text))
    if (part != kNunHafukhaGlyph)
      for (final piece in _splitStretchLetters(part))
        if (piece.stretch)
          kTikkunLastResortStretchLetters.contains(
            piece.text.codeUnits.firstWhere(kTikkunStretchLetters.contains),
          ),
];

StamRoofMetrics? _roofOf(String piece, TextStyle style) => stamRoofMetricsFor(
  style.fontFamily ?? '',
  piece.codeUnits.firstWhere(kTikkunStretchLetters.contains),
);

/// מפרק מילה כך שכל אות נמתחת היא קטע לעצמה; סימן זעירא/רבתי פתוח נפתח
/// מחדש בכל קטע, כדי שהגודל יישמר.
List<({String text, bool stretch})> _splitStretchLetters(String text) {
  final pieces = <({String text, bool stretch})>[];
  var current = StringBuffer();
  var hasLetters = false;
  var open = '';
  for (final code in text.codeUnits) {
    if (code == kZeiraStart || code == kRabatiStart) {
      open = String.fromCharCode(code);
      current.writeCharCode(code);
    } else if (code == kZeiraEnd || code == kRabatiEnd) {
      open = '';
      current.writeCharCode(code);
    } else if (kTikkunStretchLetters.contains(code)) {
      if (hasLetters) pieces.add((text: current.toString(), stretch: false));
      pieces.add((text: '$open${String.fromCharCode(code)}', stretch: true));
      current = StringBuffer(open);
      hasLetters = false;
    } else {
      current.writeCharCode(code);
      hasLetters = true;
    }
  }
  if (hasLetters) pieces.add((text: current.toString(), stretch: false));
  return pieces;
}

/// קטע רצוף באותו סימון גודל.
class TikkunTextRun {
  final String text;
  final bool zeira;
  final bool rabati;

  const TikkunTextRun(this.text, {this.zeira = false, this.rabati = false});

  double get factor =>
      zeira ? kTikkunZeiraFactor : (rabati ? kTikkunRabatiFactor : 1.0);

  bool get isBold => rabati;
}

/// מפרק טקסט לקטעים לפי תווי ה-PUA של זעירא/רבתי. התווים עצמם נשמטים.
List<TikkunTextRun> splitTikkunRuns(String text) {
  final runs = <TikkunTextRun>[];
  final buffer = StringBuffer();
  var zeira = false;
  var rabati = false;

  void flush() {
    if (buffer.isEmpty) return;
    runs.add(TikkunTextRun(buffer.toString(), zeira: zeira, rabati: rabati));
    buffer.clear();
  }

  for (final code in text.codeUnits) {
    switch (code) {
      case kZeiraStart:
        flush();
        zeira = true;
      case kZeiraEnd:
        flush();
        zeira = false;
      case kRabatiStart:
        flush();
        rabati = true;
      case kRabatiEnd:
        flush();
        rabati = false;
      default:
        buffer.writeCharCode(code);
    }
  }
  flush();
  return runs;
}

/// בונה spans לקטעים, כאשר [baseStyle] הוא סגנון הטור.
List<InlineSpan> tikkunRunSpans(List<TikkunTextRun> runs, TextStyle baseStyle) {
  final baseSize = baseStyle.fontSize ?? 16;
  return [
    for (final run in runs)
      TextSpan(
        text: run.text,
        style: run.factor == 1 && !run.isBold
            ? null
            : baseStyle.copyWith(
                fontSize: baseSize * run.factor,
                fontWeight: run.isBold ? FontWeight.bold : null,
              ),
      ),
  ];
}

/// מפרק מילה לקטעי רינדור: כל נו"ן מנוזרת חוזרת כקטע נפרד של [kNunHafukhaGlyph].
/// מקור יחיד למרנדר ולמדידת הרוחב, כדי ששניהם ימדדו את אותם קטעים.
List<String> splitTikkunNun(String text) {
  if (!text.contains(kNunHafukha)) return [text];
  final parts = <String>[];
  final buffer = StringBuffer();
  for (final code in text.codeUnits) {
    if (code == kNunHafukhaCode) {
      if (buffer.isNotEmpty) {
        parts.add(buffer.toString());
        buffer.clear();
      }
      parts.add(kNunHafukhaGlyph);
      continue;
    }
    buffer.writeCharCode(code);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts;
}

/// טקסט מילה בשני הטורים. נו"ן מנוזרת היא ווידג'ט נפרד כי אין דרך להפוך
/// גליף בתוך span; כך גם אות שגגה נמתח לפי [letterExtras] (תוספת לכל אות
/// נמתחת, בסדר הכתיבה). [condense] מכווץ את המילה אופקית בעמוד צפוף.
Widget tikkunWordText(
  String text,
  TextStyle style, {
  List<double> letterExtras = const [],
  double condense = 1,
}) {
  // אות רבתי אינה מגביהה את המילה: גובה השורה וקו הבסיס לפי הכתב הרגיל,
  // ובאותו חלוקת ריווח שהטקסט יורש מההקשר — אחרת כל המילים זזות.
  Widget chunk(String value) => Builder(
    builder: (context) => Text.rich(
      TextSpan(children: tikkunRunSpans(splitTikkunRuns(value), style)),
      style: style,
      textAlign: TextAlign.start,
      strutStyle: StrutStyle.fromTextStyle(
        DefaultTextStyle.of(context).style.merge(style),
        forceStrutHeight: true,
      ),
    ),
  );
  // האות נחתכת בגג; הפער מתמלא בעותקים של רצועת הגג עצמה, מוזזים אופקית
  // בלבד. כך ההארכה יורשת בדיוק את ההנחה האנכית של המנוע — מלבן או גליף
  // מתוח נשארים בשבריר פיקסל מהגג, וזה ניכר בכתב קטן.
  Widget stretched(String value, double extra) {
    final width = tikkunWordWidth(value, style);
    final roof = _roofOf(value, style);
    if (extra <= 0 || width <= 0 || roof == null) return chunk(value);
    final from = width * roof.sliceX;
    final slice = math.min(width * roof.sliceWidth, extra);
    final copies = (extra / slice).ceil();
    Widget part(double left, double right, double shift) {
      final clipped = ClipRect(
        clipper: TikkunLetterSliceClipper(left, right),
        child: chunk(value),
      );
      return shift == 0
          ? clipped
          : Transform.translate(offset: Offset(shift, 0), child: clipped);
    }

    return SizedBox(
      width: width + extra,
      child: Stack(
        alignment: Alignment.topLeft,
        clipBehavior: Clip.none,
        children: [
          part(double.negativeInfinity, from, 0),
          for (var k = 0; k < copies; k++)
            part(from, from + slice, math.min(k * slice, extra - slice)),
          part(from, double.infinity, extra),
        ],
      ),
    );
  }

  Widget condensed(Widget child) =>
      condense >= 1 ? child : _Condensed(scale: condense, child: child);

  final stretch =
      letterExtras.any((e) => e > 0) && tikkunStretchableCount(text) > 0;
  if (!stretch && !text.contains(kNunHafukha)) return condensed(chunk(text));
  var letterIdx = 0;
  double nextExtra() =>
      letterIdx < letterExtras.length ? letterExtras[letterIdx++] : 0;
  return condensed(
    Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final part in splitTikkunNun(text))
          if (part == kNunHafukhaGlyph)
            Transform.flip(flipX: true, child: chunk(part))
          else if (!stretch)
            chunk(part)
          else
            for (final piece in _splitStretchLetters(part))
              piece.stretch
                  ? stretched(piece.text, nextExtra())
                  : chunk(piece.text),
      ],
    ),
  );
}

/// מניח את הילד ברוחבו הטבעי ומצייר אותו מכווץ אופקית פי [scale]; תופס
/// את הרוחב המכווץ בלבד. ייצוא ה-PDF קורא את הכיווץ מטרנספורם הציור.
class _Condensed extends SingleChildRenderObjectWidget {
  final double scale;

  const _Condensed({required this.scale, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCondensed(scale);

  @override
  void updateRenderObject(BuildContext context, _RenderCondensed renderObject) {
    renderObject.scale = scale;
  }
}

class _RenderCondensed extends RenderProxyBox {
  _RenderCondensed(this._scale);

  double _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsLayout();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, 1, 1);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      constraints.copyWith(minWidth: 0, maxWidth: double.infinity),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(child.size.width * _scale, child.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.pushTransform(needsCompositing, offset, _transform, super.paint);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}

/// חותך את גליף האות לרצועה אופקית [left]..[right]; לגובה אינו חותך דבר.
/// ייצוא ה-PDF מזהה את הסוג הזה ומשחזר ממנו את החיתוך.
class TikkunLetterSliceClipper extends CustomClipper<Rect> {
  final double left;
  final double right;

  const TikkunLetterSliceClipper(this.left, this.right);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    math.max(left, -size.width),
    -size.height,
    math.min(right, size.width * 2),
    size.height * 2,
  );

  @override
  bool shouldReclip(TikkunLetterSliceClipper oldClipper) =>
      oldClipper.left != left || oldClipper.right != right;
}

class StamWord extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// התוספת לרוחב כל אות דהלת"ם שבמילה, בסדר הכתיבה, בפיקסלים.
  final List<double> letterExtras;

  /// כיווץ אופקי (עד 1) — עמוד צפוף שאינו נכנס לרוחב הטור.
  final double condense;

  const StamWord({
    super.key,
    required this.text,
    required this.style,
    this.letterExtras = const [],
    this.condense = 1,
  });

  @override
  Widget build(BuildContext context) => tikkunWordText(
    text,
    style,
    letterExtras: letterExtras,
    condense: condense,
  );
}

/// רוחב מילה מרונדרת — נמדד פעם אחת לכל (טקסט, גופן, גודל).
double tikkunWordWidth(String text, TextStyle style) {
  final key = '${style.fontFamily}|${style.fontSize}|$text';
  final cached = _wordWidthCache[key];
  if (cached != null) return cached;
  // אותם קטעים שהמרנדר מצייר — אחרת רוחב הנו"ן המנוזרת אינו נמדד כלל.
  var width = 0.0;
  for (final part in splitTikkunNun(text)) {
    final painter = TextPainter(
      text: TextSpan(
        style: style,
        children: tikkunRunSpans(splitTikkunRuns(part), style),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    width += painter.width;
    painter.dispose();
  }
  // גבול עליון פשוט — עמוד חדש מודד מחדש במקום להחזיק את כל התנ"ך בזיכרון.
  if (_wordWidthCache.length > 20000) _wordWidthCache.clear();
  _wordWidthCache[key] = width;
  return width;
}

final Map<String, double> _wordWidthCache = {};
