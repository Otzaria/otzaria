/// מרווח השורות: הריווח בין שורה לשורה נגזר מגובה האות בגופן.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';

import '../support/tikkun_fixtures.dart';

const String _family = 'AshkenaziStam';

final List<GlobalKey> _rowKeys = [for (var i = 0; i < 3; i++) GlobalKey()];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await File(
      'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
    ).readAsBytes();
    await (FontLoader(
      _family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    await measureStamRoofMetrics(_family);
  });

  tearDownAll(debugResetStamRoofMetrics);

  test('גובה האות נמדד מן הגופן', () {
    expect(stamLetterHeightFor(_family), inInclusiveRange(0.4, 0.8));
  });

  for (final spacing in [1.0, 0.5, 2.0]) {
    testWidgets('מרווח $spacing — הריווח בין השורות יחסי לגובה האות', (
      tester,
    ) async {
      final settings = TikkunSettings(
        stamFont: 'Ashkenazi',
        lineSpacing: spacing,
        hideRowBorders: true,
      );
      final metrics = TikkunRenderMetrics.forWidth(
        kTikkunReferenceWidth,
        settings,
        lineWidthEm: kTestLineWidthEm,
      );
      final letter = stamLetterHeightFor(_family)! * metrics.stamFontSize;
      expect(
        metrics.rowPitch - letter,
        closeTo(letter * kTikkunLineGapLetters * spacing, 0.01),
      );

      await tester.binding.setSurfaceSize(const Size(1600, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in _rowKeys)
                  KeyedSubtree(
                    key: key,
                    child: buildTikkunLineWidget(
                      line: TikkunLine(
                        words: [
                          for (final w in ['בכל', 'מקום', 'שם'])
                            LayoutWord(stam: w, nikud: w),
                        ],
                      ),
                      markers: const TikkunLineMarkers(),
                      metrics: metrics,
                      settings: settings,
                      hideStam: false,
                      hideNikud: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      for (final key in _rowKeys) {
        final box = key.currentContext!.findRenderObject()! as RenderBox;
        // פריסת הטקסט מעגלת את גובה השורה לפיקסל שלם כלפי מעלה.
        expect(box.size.height, closeTo(metrics.rowPitch, 1));
      }
    });
  }
}
