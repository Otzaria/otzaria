/// מדידת הגג של דהלת"ם ברסטור — על גופני הסת"ם המוטמעים.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart';

const _fonts = {
  'AshkenaziStam': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'SefardiStam': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
};

/// טווח העמודות שבהן רק הגג — נמדד ידנית מפיקסלי הגליף, לאימות המדידה.
const Map<String, Map<int, (double, double)>> _roofRanges = {
  'AshkenaziStam': {
    0x05D3: (0.24, 0.70),
    0x05D4: (0.34, 0.83),
    0x05DC: (0.12, 0.33),
    0x05EA: (0.45, 0.84),
    0x05DD: (0.26, 0.83),
  },
  'SefardiStam': {
    0x05D3: (0.30, 0.70),
    0x05D4: (0.27, 0.74),
    0x05DC: (0.22, 0.41),
    0x05EA: (0.45, 0.79),
    0x05DD: (0.30, 0.78),
  },
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final e in _fonts.entries) {
      final bytes = await File(e.value).readAsBytes();
      await (FontLoader(
        e.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  tearDown(debugResetStamRoofMetrics);

  for (final font in _fonts.keys) {
    testWidgets('$font — רצועת השכפול בתוך הגג', (
      tester,
    ) async {
      await tester.runAsync(() => measureStamRoofMetrics(font));
      for (final entry in _roofRanges[font]!.entries) {
        final metrics = stamRoofMetricsFor(font, entry.key);
        final name = String.fromCharCode(entry.key);
        expect(metrics, isNotNull, reason: name);
        expect(metrics!.sliceX, greaterThan(entry.value.$1), reason: name);
        expect(metrics.sliceX, lessThan(entry.value.$2), reason: name);
        expect(metrics.sliceWidth, greaterThan(0.05), reason: name);
        expect(
          metrics.sliceX + metrics.sliceWidth,
          lessThan(entry.value.$2 + 0.01),
          reason: name,
        );
      }
    });
  }

  for (final font in _fonts.keys) {
    testWidgets('$font — גג הרי"ש נמדד, כחלופה אחרונה', (tester) async {
      await tester.runAsync(() => measureStamRoofMetrics(font));
      final resh = stamRoofMetricsFor(font, 0x05E8);
      expect(resh, isNotNull);
      expect(resh!.sliceWidth, greaterThan(0.05));
      expect(resh.sliceX + resh.sliceWidth, lessThan(1));
      expect(kTikkunLastResortStretchLetters, contains(0x05E8));
    });
  }

  test('גופן שלא נמדד — אין מדדים, והאות אינה נמתחת', () {
    expect(stamRoofMetricsFor('Nope', 0x05D3), isNull);
  });
}
