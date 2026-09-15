/// מדידת מודל הרוחב של גופן הסת"ם — הצד היחיד שנוגע ב-TextPainter; המנוע
/// מקבל את התוצאה כערך ניתן להעברה ל-isolate.
library;

import 'package:flutter/widgets.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';

/// גודל המדידה ומספר העותקים — TextPainter מעגל את הרוחב כלפי מעלה, ומדידת
/// מחרוזת ארוכה מחלקת את השארית.
const double _measureFontSize = 100;
const int _measureRepeat = 16;

/// נקודות הקוד שנמדדות: אותיות עברית וסימניה וספרות. השאר נופל לרוחב הממוצע.
/// רווח אינו נמדד — TextPainter מקצץ רווח בסוף השורה, ומילת סת"ם אינה מכילה
/// רווחים ממילא.
Iterable<int> _measuredCodePoints() sync* {
  for (var c = 0x0030; c <= 0x0039; c++) {
    yield c;
  }
  for (var c = 0x05D0; c <= 0x05F4; c++) {
    yield c;
  }
  yield kNunHafukhaCode;
}

final Map<String, StamWidthModel> _cache = {};

/// מודל הרוחב של [fontFamily] — נמדד פעם אחת לכל משפחת גופן.
StamWidthModel measureStamWidthModel(String fontFamily) {
  final cached = _cache[fontFamily];
  if (cached != null) return cached;

  final style = TextStyle(fontFamily: fontFamily, fontSize: _measureFontSize);
  final advances = <int, double>{};
  for (final code in _measuredCodePoints()) {
    // הנו"ן המנוזרת מרונדרת כנו"ן רגילה הפוכה, ולכן נמדדת כמותה.
    final measured = code == kNunHafukhaCode ? kNunHafukhaGlyphCode : code;
    advances[code] = _advanceOf(String.fromCharCode(measured), style);
  }

  var letterSum = 0.0;
  var letterCount = 0;
  for (var c = 0x05D0; c <= 0x05EA; c++) {
    final advance = advances[c];
    if (advance == null || advance <= 0) continue;
    letterSum += advance;
    letterCount++;
  }

  final model = StamWidthModel(
    id: fontFamily,
    advances: advances,
    fallbackAdvance: letterCount == 0 ? 0.55 : letterSum / letterCount,
  );
  _cache[fontFamily] = model;
  return model;
}

double _advanceOf(String char, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: char * _measureRepeat, style: style),
    textDirection: TextDirection.rtl,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width / (_measureRepeat * _measureFontSize);
}
