/// מילה בטור הסת"ם — כולל זעירא/רבתי ונו"ן הפוכה.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// עובי המשיחה של גופן הסת"ם (בפיקסלים לוגיים). Flutter מרנדר בהחלקה אפורה,
/// ובלי משיחה הקווים דקים מהתצוגה ב-WebView; לסת"ם די בעיבוי עדין.
const double kTikkunStamStrokeWidth = 0.10;

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

/// מצייר את הטקסט של [builder] פעמיים: משיחה מתחת ומילוי מעל, כך שכל קו
/// מתעבה בחצי [strokeWidth] לכל צד. הצבע נלקח מהסגנון או מהקשר הטקסט.
Widget tikkunStrokedText({
  required BuildContext context,
  required TextStyle style,
  required double strokeWidth,
  required Widget Function(TextStyle style) builder,
}) {
  final color =
      style.color ??
      DefaultTextStyle.of(context).style.color ??
      Theme.of(context).colorScheme.onSurface;
  return Stack(
    children: [
      builder(tikkunStrokeStyle(style, color, strokeWidth)),
      builder(style),
    ],
  );
}

/// אותו סגנון בדיוק (גופן, גודל, גובה) אך כמשיחה — כדי שהמדידות יהיו זהות למילוי.
TextStyle tikkunStrokeStyle(TextStyle style, Color color, double strokeWidth) =>
    TextStyle(
      inherit: style.inherit,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      height: style.height,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

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
/// גליף בתוך span.
Widget tikkunWordText(String text, TextStyle style) {
  Widget chunk(String value) => Text.rich(
    TextSpan(children: tikkunRunSpans(splitTikkunRuns(value), style)),
    style: style,
    textAlign: TextAlign.start,
  );
  if (!text.contains(kNunHafukha)) return chunk(text);
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      for (final part in splitTikkunNun(text))
        part == kNunHafukhaGlyph
            ? Transform.flip(flipX: true, child: chunk(part))
            : chunk(part),
    ],
  );
}

class StamWord extends StatelessWidget {
  final String text;
  final TextStyle style;

  const StamWord({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) => tikkunStrokedText(
    context: context,
    style: style,
    strokeWidth: kTikkunStamStrokeWidth,
    builder: (style) => tikkunWordText(text, style),
  );
}
