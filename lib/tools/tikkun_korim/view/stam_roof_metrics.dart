/// הגג של אותיות דהלת"ם — היכן לרוחב האות הוא עובר לבדו, לכל גופן סת"ם.
/// נמדד ברסטור של הגליף פעם אחת לכל גופן; ההארכה משכפלת את הרצועה הזאת.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// האותיות שנמתחות ליישור השורה: דהלת"ם, ור' כחלופה אחרונה.
const Set<int> kTikkunStretchLetters = {
  0x05D3,
  0x05D4,
  0x05DC,
  0x05EA,
  0x05DD,
  0x05E8,
};

/// אותיות שנמתחות רק כשדהלת"ם שבשורה אינן מספיקות.
const Set<int> kTikkunLastResortStretchLetters = {0x05E8};

/// גודל הרסטור. גדול דיו שקצה מוחלק הוא שבריר מעובי הקו.
const double _measureFontSize = 200;

/// קו אופקי — רצף דיו שגובהו עד שבר זה מגובה הגליף. הגג של ת' האשכנזית
/// והבסיס של ם' מגיעים לשליש; רגל או צוואר הם יותר ממחצית.
const double _thinRunFraction = 0.45;

/// אורך מזערי לרצף גג, כשבר מרוחב האות — מסנן רגליים דקות וקצוות מוחלקים.
const double _minRoofRunFraction = 0.1;

/// סטייה מותרת בגבולות הגג בין עמודה לעמודה, ב-em — גג אינו ישר לגמרי.
const double _bandTolerance = 0.02;

/// חלק הרצף שנגזר בכל קצה לפני השכפול.
const double _sliceTrimFraction = 0.15;

/// רצועת הגג של אות: תחילתה ורוחבה כשבר מרוחב ה-advance, מהשמאל. בכל
/// עמודה שם יש רק את הגג (בם' גם הבסיס), ולכן אפשר לשכפל אותה לרוחב.
@immutable
class StamRoofMetrics {
  final double sliceX;
  final double sliceWidth;

  const StamRoofMetrics({required this.sliceX, required this.sliceWidth});
}

final Map<String, Map<int, StamRoofMetrics>> _cache = {};

/// מדדי הגג של [letter] בגופן [family]; null כשהגופן טרם נמדד או כשהאות
/// לא זוהתה בו — אז היא אינה נמתחת.
StamRoofMetrics? stamRoofMetricsFor(String family, int letter) =>
    _cache[family]?[letter];

/// מודד את גגות האותיות הנמתחות ואת גובה האות בגופן [family] — פעם אחת.
/// הגופן חייב להיות טעון לפני הקריאה.
Future<void> measureStamRoofMetrics(String family) async {
  if (_cache.containsKey(family)) return;
  final result = <int, StamRoofMetrics>{};
  for (final letter in kTikkunStretchLetters) {
    try {
      final metrics = await _measureLetter(family, letter);
      if (metrics != null) result[letter] = metrics;
    } catch (_) {
      // אות שהמדידה שלה נכשלה פשוט אינה נמתחת.
    }
  }
  _cache[family] = result;
  final heights = <double>[];
  for (final letter in _kBodyLetters) {
    try {
      final h = await _inkHeight(family, letter);
      if (h != null) heights.add(h);
    } catch (_) {
      // גופן שהמדידה בו נכשלה נופל לגובה ברירת המחדל.
    }
  }
  if (heights.isNotEmpty) {
    _letterHeights[family] = heights.reduce((a, b) => a + b) / heights.length;
  }
}

/// אותיות בלי תגין, רגל או צוואר: גובהן הוא שיעור השיטה.
const List<int> _kBodyLetters = [0x05D1, 0x05DB, 0x05DE];

final Map<String, double> _letterHeights = {};

/// גובה האות בגופן [family] כשבר מגודל הגופן — גובה השיטה, שכמותו הריווח
/// שבין שיטה לשיטה; null כשהגופן טרם נמדד.
double? stamLetterHeightFor(String family) => _letterHeights[family];

@visibleForTesting
void debugSetStamRoofMetrics(String family, Map<int, StamRoofMetrics> value) {
  _cache[family] = value;
}

@visibleForTesting
void debugResetStamRoofMetrics() {
  _cache.clear();
  _letterHeights.clear();
}

typedef _Raster = ({ByteData data, int width, int height, double advance});

/// הגליף של [letter] ברסטור, עם ריפוד של [_rasterPad] מכל צד.
Future<_Raster?> _rasterize(String family, int letter) async {
  const padOffset = Offset(_rasterPad * 1.0, 0);
  final style = TextStyle(
    fontFamily: family,
    fontSize: _measureFontSize,
    color: const Color(0xFF000000),
  );
  final painter = TextPainter(
    text: TextSpan(text: String.fromCharCode(letter), style: style),
    textDirection: TextDirection.rtl,
  )..layout();
  final advance = painter.width;
  final width = (advance + _rasterPad * 2).ceil();
  final height = (painter.height * 2).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  painter.paint(canvas, padOffset);
  painter.dispose();
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return null;
  return (data: data, width: width, height: height, advance: advance);
}

const int _rasterPad = 20;

/// גובה הדיו של [letter] כשבר מגודל הגופן.
Future<double?> _inkHeight(String family, int letter) async {
  final raster = await _rasterize(family, letter);
  if (raster == null) return null;
  final (:data, :width, :height, advance: _) = raster;
  var top = -1, bottom = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (data.getUint8((y * width + x) * 4) < 128) {
        if (top < 0) top = y;
        bottom = y;
        break;
      }
    }
  }
  return top < 0 ? null : (bottom - top + 1) / _measureFontSize;
}

Future<StamRoofMetrics?> _measureLetter(String family, int letter) async {
  final raster = await _rasterize(family, letter);
  if (raster == null) return null;
  final (:data, :width, :height, :advance) = raster;
  const pad = _rasterPad;

  bool ink(int x, int y) => data.getUint8((y * width + x) * 4) < 128;
  var top = height, bottom = -1;
  final columns = <int, List<(int, int)>>{};
  for (var x = 0; x < width; x++) {
    List<(int, int)>? runs;
    var runStart = -1;
    for (var y = 0; y <= height; y++) {
      final on = y < height && ink(x, y);
      if (on && runStart < 0) runStart = y;
      if (!on && runStart >= 0) {
        (runs ??= []).add((runStart, y - 1));
        runStart = -1;
      }
      if (on) {
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (runs != null) columns[x] = runs;
  }
  if (bottom < 0) return null;

  final glyphHeight = bottom - top;
  final maxRun = glyphHeight * _thinRunFraction;
  final tolerance = _measureFontSize * _bandTolerance;
  final begin = pad;
  final end = pad + advance.floor();

  // עמודה נקייה: כל הדיו בה קווים אופקיים דקים, לכל היותר שניים (גג ובסיס).
  List<(int, int)>? cleanRuns(int x) {
    final runs = columns[x];
    if (runs == null || runs.length > 2) return null;
    if (runs.any((r) => r.$2 - r.$1 + 1 > maxRun)) return null;
    return runs;
  }

  // הגג הוא הקו הדק השכיח ביותר לרוחב האות; רגל, צוואר וכתר נדירים ממנו.
  final votes = <(int, int), int>{};
  for (var x = begin; x < end; x++) {
    for (final run in cleanRuns(x) ?? const <(int, int)>[]) {
      final key = ((run.$1 / tolerance).round(), (run.$2 / tolerance).round());
      votes[key] = (votes[key] ?? 0) + 1;
    }
  }
  if (votes.isEmpty) return null;
  final roofKey = votes.entries
      .reduce(
        (a, b) =>
            b.value > a.value || (b.value == a.value && b.key.$1 < a.key.$1)
            ? b
            : a,
      )
      .key;
  bool isRoof((int, int) run) =>
      (run.$1 - roofKey.$1 * tolerance).abs() <= tolerance &&
      (run.$2 - roofKey.$2 * tolerance).abs() <= tolerance;

  // רצפי עמודות שנושאות את הגג. עדיפות לרצף של גג בלבד (שם רק הוא מוארך);
  // כשאין רצף כזה — עמודות נקיות, וכל הקווים בהן מוארכים יחד (ם').
  (int, int)? longestRun(bool Function(List<(int, int)> runs) accept) {
    final minLen = advance * _minRoofRunFraction;
    var best = (-1, 0);
    var start = -1;
    for (var x = begin; x <= end; x++) {
      final runs = x < end ? cleanRuns(x) : null;
      if (runs != null && runs.any(isRoof) && accept(runs)) {
        if (start < 0) start = x;
        continue;
      }
      if (start >= 0 && x - start >= minLen && x - start > best.$2) {
        best = (start, x - start);
      }
      start = -1;
    }
    return best.$1 < 0 ? null : best;
  }

  // ם' מוארכת בגג ובבסיס יחד; באות אחרת עדיף מקום שיש בו רק הגג.
  final run = letter == 0x05DD
      ? longestRun((runs) => runs.length == 2)
      : longestRun((runs) => runs.length == 1) ?? longestRun((_) => true);
  if (run == null) return null;
  // קצוות הרצף נגזרים מעט: שם הגג מתחיל להתעקל.
  final trim = run.$2 * _sliceTrimFraction;
  return StamRoofMetrics(
    sliceX: (run.$1 + trim - pad) / advance,
    sliceWidth: (run.$2 - 2 * trim) / advance,
  );
}
