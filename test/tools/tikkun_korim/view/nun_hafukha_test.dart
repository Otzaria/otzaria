/// נו"ן מנוזרת: שני הטורים מרנדרים אותה דרך אותו מסלול היפוך, והרוחב הנמדד
/// שווה לרוחב המרונדר. עם TIKKUN_VISUAL=1 גם נשמר PNG לבדיקת עין.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_width_measurer.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/nikud_word.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

const Map<String, String> _fontFiles = {
  'AshkenaziStam': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'SefardiStam': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
};

const String _outDir =
    r'C:\Users\User\AppData\Local\Temp\claude'
    r'\C--otzaria\98aaa966-38ac-4a2b-b78d-9c44d5c4ee51\scratchpad\qa_nun';

final bool _capturePng = Platform.environment['TIKKUN_VISUAL'] == '1';
final GlobalKey _captureKey = GlobalKey();

Future<void> _loadFonts() async {
  for (final entry in _fontFiles.entries) {
    final bytes = await File(entry.value).readAsBytes();
    await (FontLoader(
      entry.key,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

/// הטקסט הגלוי של כל ווידג'טי הטקסט תחת [of].
List<String> _textsUnder(WidgetTester tester, Finder of) => tester
    .widgetList<Text>(find.descendant(of: of, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

Future<void> _pumpWords(WidgetTester tester, String text) async {
  const settings = TikkunSettings();
  final metrics = TikkunRenderMetrics.forWidth(1200, settings);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _captureKey,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StamWord(text: text, style: metrics.stamStyle()),
                  const SizedBox(width: 40),
                  NikudWord(text: text, style: metrics.nikudStyle()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) => tester.runAsync(
  () async {
    final boundary =
        _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir\\$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  },
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('שני הטורים מרנדרים נו"ן רגילה הפוכה, לא את U+05C6', (
    tester,
  ) async {
    await _pumpWords(tester, kNunHafukha);

    for (final column in [find.byType(StamWord), find.byType(NikudWord)]) {
      final mirrored = find.descendant(
        of: column,
        matching: find.byType(Transform),
      );
      // שתי שכבות לכל טור — משיחה ומילוי.
      expect(tester.widgetList(mirrored), hasLength(2));
      final texts = _textsUnder(tester, column);
      expect(texts, everyElement(isNot(contains(kNunHafukha))));
      expect(texts, everyElement(equals(kNunHafukhaGlyph)));
    }

    if (_capturePng) await _capture(tester, 'nun_hafukha_columns');
  });

  testWidgets('הרוחב הנמדד שווה לרוחב המרונדר בשני הטורים', (tester) async {
    const text = 'וּ׆יְהִי';
    await _pumpWords(tester, text);

    const settings = TikkunSettings();
    final metrics = TikkunRenderMetrics.forWidth(1200, settings);
    expect(
      tester.getSize(find.byType(StamWord)).width,
      moreOrLessEquals(
        tikkunWordWidth(text, metrics.stamStyle()),
        epsilon: 0.5,
      ),
    );
    expect(
      tester.getSize(find.byType(NikudWord)).width,
      moreOrLessEquals(
        tikkunWordWidth(text, metrics.nikudStyle()),
        epsilon: 0.5,
      ),
    );

    if (_capturePng) await _capture(tester, 'nun_hafukha_in_word');
  });

  test('מודל רוחב הסת"ם נותן לנו"ן המנוזרת את רוחב הנו"ן הרגילה', () {
    final model = measureStamWidthModel(const TikkunSettings().stamFontFamily);
    final nun = model.advanceOf(kNunHafukhaGlyphCode);
    expect(nun, greaterThan(0));
    expect(model.advanceOf(kNunHafukhaCode), nun);
  });
}
