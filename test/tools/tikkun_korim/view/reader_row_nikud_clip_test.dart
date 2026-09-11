/// הניקוד והטעמים חורגים מתיבת השורה של הגופן — השורה אסור שתחתוך אותם.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/nikud_word.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';

/// מילה ניטרלית עם קמץ ושווא מתחת לאותיות וטעמים מעליהן.
const String _word = 'שָׁלְוָ֣ה';

final GlobalKey _rowKey = GlobalKey();
final GlobalKey _plainKey = GlobalKey();

/// הגופן של הטור המנוקד — חייב להיות זה שיש בו מִתאר לניקוד ולטעמים; בגופן
/// סת"ם הבדיקה מודדת אותיות בלבד ואינה בודקת דבר.
Future<void> _loadNikudFont() async {
  final bytes = await File('fonts/KeterYG-Medium.ttf').readAsBytes();
  await (FontLoader(
    kTikkunNikudFallbackFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

/// גובה הדיו בפיקסלים — משורת הפיקסלים הכהה הראשונה עד האחרונה.
Future<int> _inkHeight(GlobalKey key, WidgetTester tester) async {
  late int result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    var top = -1;
    var bottom = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        if (bytes[i + 3] > 128 && bytes[i] < 120) {
          if (top < 0) top = y;
          bottom = y;
          break;
        }
      }
    }
    image.dispose();
    result = top < 0 ? 0 : bottom - top + 1;
  });
  return result;
}

void main() {
  setUpAll(_loadNikudFont);

  testWidgets('שורה במרווח השורות המינימלי אינה חותכת את הניקוד', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1250, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const settings = TikkunSettings(
      hideStam: true,
      hideRowBorders: true,
      lineSpacing: 0.5,
    );
    final metrics = TikkunRenderMetrics.forWidth(
      kTikkunReferenceWidth,
      settings,
    );
    final line = TikkunLine(
      words: [const LayoutWord(stam: 'x', nikud: _word)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),
              RepaintBoundary(
                key: _rowKey,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: buildTikkunLineWidget(
                    line: line,
                    markers: const TikkunLineMarkers(),
                    metrics: metrics,
                    settings: settings,
                    hideStam: true,
                    hideNikud: false,
                  ),
                ),
              ),
              RepaintBoundary(
                key: _plainKey,
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: NikudWord(text: _word, style: metrics.nikudStyle()),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final inRow = await _inkHeight(_rowKey, tester);
    final plain = await _inkHeight(_plainKey, tester);
    expect(plain, greaterThan(0));
    expect(inRow, greaterThanOrEqualTo(plain));
  });
}
