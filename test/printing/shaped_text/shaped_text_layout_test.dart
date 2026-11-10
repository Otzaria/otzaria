import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_layout.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Ordinary pointed Hebrew words, repeated to fill several lines.
const List<String> _words = [
  'שָׁלוֹם',
  'בָּרוּךְ',
  'גָּדוֹל',
  'חָכְמָה',
  'מְלָאכָה',
  'תִּפְאֶרֶת',
  'אֱמוּנָה',
  'יְשׁוּעָה',
];

String buildParagraph(int wordCount) => [
  for (var index = 0; index < wordCount; index++) _words[index % _words.length],
].join(' ');

Uint8List? _readFont() {
  for (final path in const [
    'fonts/TaameyDavidCLM-Medium.ttf',
    'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsBytesSync();
    }
  }
  return null;
}

void main() {
  final fontBytes = _readFont();
  final skipReason = fontBytes == null ? 'no test font found' : null;

  group('ShapedTextLayout', () {
    late ShaperFont shaper;

    setUp(() {
      shaper = ShaperFont.register(fontBytes!);
    });

    tearDown(() => shaper.dispose());

    ShapedTextLayout layoutWith({
      ShapedTextAlign align = ShapedTextAlign.start,
      double? heightFactor,
      double fontSize = 14,
      bool rtl = true,
    }) => ShapedTextLayout(
      fonts: [shaper],
      fontSize: fontSize,
      align: align,
      rtl: rtl,
      heightFactor: heightFactor,
    );

    test('breaks a paragraph into lines that fit the width', () {
      final block = layoutWith().layout(
        buildParagraph(40),
        maxWidth: 200,
      );

      expect(block.lines.length, greaterThan(1));
      for (final line in block.lines) {
        expect(line.width, lessThanOrEqualTo(200.001));
      }
    });

    test('never lets a line box be shorter than the font needs', () {
      // 1.0 is below the font's own line height for a face with te'amim; a
      // shorter box would let one line's marks print inside the next.
      final tight = layoutWith(heightFactor: 1.0);
      expect(tight.lineHeight, tight.naturalLineHeight);

      final roomy = layoutWith(heightFactor: 3.0);
      expect(roomy.lineHeight, greaterThan(roomy.naturalLineHeight));
    });

    test('starts a right-to-left line at the right edge', () {
      final block = layoutWith().layout('שָׁלוֹם', maxWidth: 300);
      final segment = block.lines.single.segments.single;
      // One word, aligned to the start, which is the right in Hebrew.
      expect(segment.x, greaterThan(150));
    });

    test('orders a right-to-left line from the last word leftwards', () {
      final block = layoutWith().layout('שָׁלוֹם בָּרוּךְ', maxWidth: 300);
      final segments = block.lines.single.segments;
      expect(segments.length, 2);

      // The leftmost segment must be the second word of the source.
      final second = shaper.shape('בָּרוּךְ', rtl: true, script: 'hebr');
      expect(segments.first.run.text, second.text);
      expect(segments.first.x, lessThan(segments.last.x));
    });

    test('justify fills the width except on the last line', () {
      final justified = layoutWith(
        align: ShapedTextAlign.justify,
      ).layout(buildParagraph(40), maxWidth: 220);

      expect(justified.lines.length, greaterThan(2));
      // Every line but the last reaches the full width.
      for (final line in justified.lines.take(justified.lines.length - 1)) {
        expect(line.width, closeTo(220, 0.5));
      }
    });

    test('keeps a Latin word to the left of a Hebrew one', () {
      final block = layoutWith().layout('שָׁלוֹם Otzaria', maxWidth: 300);
      final segments = block.lines.single.segments;
      expect(segments.length, 2);
      // Base direction is right-to-left, so the Latin run sits on the left.
      expect(segments.first.run.text, 'Otzaria');
    });

    test('mixed print line uses RTL base even when Latin comes first', () {
      final block = layoutWith(rtl: true).layout(
        'Otzaria שָׁלוֹם',
        maxWidth: 300,
      );
      final segments = block.lines.single.segments;
      expect(segments, hasLength(2));
      // In an RTL paragraph the Hebrew word appears visually leftmost.
      expect(segments.first.run.text, 'שָׁלוֹם');
      expect(segments.last.run.text, 'Otzaria');
      expect(segments.first.x, lessThan(segments.last.x));
    });

    test('mixed print line uses LTR base even when Hebrew comes first', () {
      final block = layoutWith(rtl: false).layout(
        'שָׁלוֹם Otzaria',
        maxWidth: 300,
      );
      final segments = block.lines.single.segments;
      expect(segments, hasLength(2));
      // In an LTR paragraph the Hebrew run occupies the left edge.
      expect(segments.first.run.text, 'שָׁלוֹם');
      expect(segments.last.run.text, 'Otzaria');
      expect(segments.first.x, lessThan(segments.last.x));
    });

    test('keeps the digits of a number in reading order', () {
      final block = layoutWith().layout('זְרִיחָה 06:32', maxWidth: 300);
      final segments = block.lines.single.segments;
      // The number sits left of the Hebrew word, its first digit leftmost.
      final number = segments.first.run;
      expect(number.text, '06:32');
      expect(
        [for (var i = 0; i < number.glyphCount; i++) number.cluster(i)],
        [0, 1, 2, 3, 4],
      );
    });

    test('places an over-wide word on its own line', () {
      final block = layoutWith(fontSize: 40).layout(
        'תִּפְאֶרֶת שָׁלוֹם',
        maxWidth: 30,
      );
      expect(block.lines.length, 2);
      for (final line in block.lines) {
        expect(line.segments.length, 1);
      }
    });
  }, skip: skipReason);

  group('ShapedText widget', () {
    test('spans a long paragraph across pages', () async {
      final shaper = ShaperFont.register(fontBytes!);
      addTearDown(shaper.dispose);

      final document = pw.Document();
      late PdfShapedFont pdfFont;
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            pdfFont = PdfShapedFont(
              context.document,
              shaper: shaper,
              fontBytes: fontBytes,
            );
            return [
              ShapedText(
                buildParagraph(500),
                fonts: [pdfFont],
                fontSize: 16,
                heightFactor: 1.35,
              ),
            ];
          },
        ),
      );

      final bytes = await document.save();
      expect(document.document.pdfPageList.pages.length, greaterThan(1));
      expect(bytes.length, greaterThan(1000));
    });

    // Regression: with less room than the padding, a line was forced onto the
    // page anyway and printed over the line above it.
    test('moves a line that has no room left to the next page', () async {
      final shaper = ShaperFont.register(fontBytes!);
      addTearDown(shaper.dispose);

      const format = PdfPageFormat.a5;
      const margin = 24.0;
      final painted = <(int, double)>[];
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(margin),
          build: (context) {
            final pdfFont = PdfShapedFont(
              context.document,
              shaper: shaper,
              fontBytes: fontBytes,
            );
            return [
              // Leaves 10pt, less than the 16pt of padding below.
              pw.SizedBox(height: format.height - 2 * margin - 10),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: _PaintRecorder(
                  painted,
                  buildParagraph(2),
                  fonts: [pdfFont],
                  fontSize: 16,
                ),
              ),
            ];
          },
        ),
      );
      await document.save();

      expect(document.document.pdfPageList.pages, hasLength(2));
      final onFirstPage = painted.where((entry) => entry.$1 == 1);
      expect(onFirstPage.every((entry) => entry.$2 == 0), isTrue);
      expect(
        painted.where((entry) => entry.$1 == 2 && entry.$2 > 0),
        hasLength(1),
      );
    });

    test('renders a multi-line document for inspection', () async {
      final shaper = ShaperFont.register(fontBytes!);
      addTearDown(shaper.dispose);

      final document = pw.Document();
      late PdfShapedFont pdfFont;

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (context) {
            pdfFont = PdfShapedFont(
              context.document,
              shaper: shaper,
              fontBytes: fontBytes,
            );
            return pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: ShapedText(
                buildParagraph(48),
                fonts: [pdfFont],
                fontSize: 16,
                align: ShapedTextAlign.justify,
                heightFactor: 1.35,
              ),
            );
          },
        ),
      );

      final bytes = await document.save();
      final out = File(
        '${Directory.systemTemp.createTempSync('shaped_layout').path}'
        '${Platform.pathSeparator}shaped_paragraph.pdf',
      );
      out.writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('wrote ${out.path}');

      expect(bytes.length, greaterThan(1000));
      final text = String.fromCharCodes(bytes);
      expect(text, contains('/Identity-H'));
    });
  }, skip: skipReason);
}

/// Records, for every paint, the page and the height of the lines drawn.
class _PaintRecorder extends ShapedText {
  _PaintRecorder(
    this.painted,
    super.text, {
    required super.fonts,
    required super.fontSize,
  });

  final List<(int, double)> painted;

  @override
  void paint(pw.Context context) {
    painted.add((context.pageNumber, box!.height));
    super.paint(context);
  }
}
