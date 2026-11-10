import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:pdf/pdf.dart';

/// A pointed Hebrew word: three letters carrying nikud, one of them a ta'am.
const String pointedWord = 'שָׁ֖לֹם';

/// Free fonts already shipped with the app. The Guttman faces are proprietary
/// and deliberately not used here.
const List<String> _fontCandidates = [
  'fonts/TaameyDavidCLM-Medium.ttf',
  'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
];

(String, Uint8List)? _readFont() {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (file.existsSync()) {
      return (path, file.readAsBytesSync());
    }
  }
  return null;
}

void main() {
  final font = _readFont();

  final skipReason = font == null ? 'no test font found' : null;

  group('PdfShapedFont', () {
    late ShaperFont shaper;
    late PdfDocument document;
    late PdfShapedFont pdfFont;

    setUp(() {
      shaper = ShaperFont.register(font!.$2);
      document = PdfDocument(compress: false);
      pdfFont = PdfShapedFont(
        document,
        shaper: shaper,
        fontBytes: font.$2,
      );
    });

    tearDown(() => shaper.dispose());

    Future<Uint8List> renderPage() async {
      final page = PdfPage(document, pageFormat: PdfPageFormat.a5);
      final canvas = page.getGraphics()..setFillColor(PdfColors.black);
      pdfFont.drawShapedRun(
        canvas,
        shaper.shape(pointedWord, rtl: true, script: 'hebr'),
        x: 60,
        y: 300,
        fontSize: 48,
      );
      return Uint8List.fromList(await document.save());
    }

    test('declares an Identity-H Type0 font with the file embedded', () async {
      final bytes = await renderPage();
      final text = String.fromCharCodes(bytes);

      expect(text, contains('/Type0'));
      expect(text, contains('/Identity-H'));
      expect(text, contains('/CIDFontType2'));
      // The dict serialiser writes no space between key and value.
      expect(text, contains('/CIDToGIDMap/Identity'));
      expect(text, contains('/FontFile2'));
      expect(text, contains('/ToUnicode'));
      // Only the drawn glyphs are embedded, under a subset-tagged name.
      expect(RegExp(r'/BaseFont/[A-Z]{6}\+').hasMatch(text), isTrue);
      final length1 = int.parse(
        RegExp(r'/Length1 (\d+)').firstMatch(text)!.group(1)!,
      );
      expect(length1, lessThan(font!.$2.length ~/ 2));
    });

    test('emits glyph ids, not characters', () async {
      final bytes = await renderPage();
      final text = String.fromCharCodes(bytes);

      // Content streams carry hex glyph ids inside a TJ array.
      expect(text, contains('TJ'));
      expect(RegExp(r'<[0-9a-f]{4}>').hasMatch(text), isTrue);
      // No literal Hebrew may reach the content stream.
      expect(text.contains(pointedWord), isFalse);
    });

    test('maps every drawn glyph back to its characters', () async {
      final bytes = await renderPage();
      final text = String.fromCharCodes(bytes);

      final cmapStart = text.indexOf('beginbfchar');
      expect(cmapStart, greaterThan(-1));
      final cmap = text.substring(cmapStart, text.indexOf('endbfchar'));

      // Every character of the word must be recoverable from the text layer.
      for (final rune in pointedWord.runes) {
        final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
        expect(
          cmap,
          contains(hex),
          reason: 'U+$hex is missing from the ToUnicode map',
        );
      }
    });

    test('positions marks away from the pen', () async {
      final run = shaper.shape(pointedWord, rtl: true, script: 'hebr');
      // Guards the premise of the whole file: without GPOS offsets the PDF
      // would be no better than the unshaped path it replaces.
      final marks = [
        for (var index = 0; index < run.glyphCount; index++)
          if (run.xAdvance(index) == 0) index,
      ];
      expect(marks, isNotEmpty);
      expect(
        marks.any(
          (index) => run.xOffset(index) != 0 || run.yOffset(index) != 0,
        ),
        isTrue,
      );
    });
  }, skip: skipReason);

  /// Ts נשאר בתוקף עד שנכתב שוב: כל שינוי הזזה נכתב, ובסוף השורה חוזרים לאפס.
  test(
    'הזזה אנכית משנה Ts בתוך אותו בלוק טקסט ומתאפסת בסופו',
    () async {
      const word = 'וַיֹּ֕אמֶר';
      final file = File(_riseFontPath);
      final shaper = ShaperFont.register(file.readAsBytesSync());
      addTearDown(shaper.dispose);
      final document = PdfDocument(compress: false);
      final pdfFont = PdfShapedFont(
        document,
        shaper: shaper,
        fontBytes: file.readAsBytesSync(),
      );
      final run = shaper.shape(word, rtl: true, script: 'hebr');
      final rises = {for (var i = 0; i < run.glyphCount; i++) run.yOffset(i)};
      expect(rises, contains(isNot(0)), reason: 'אין במילה סימן מוזז אנכית');

      final page = PdfPage(document, pageFormat: PdfPageFormat.a5);
      pdfFont.drawShapedRun(
        page.getGraphics()..setFillColor(PdfColors.black),
        run,
        x: 60,
        y: 300,
        fontSize: 48,
      );
      final text = String.fromCharCodes(await document.save());
      final body = text.substring(text.indexOf('BT '), text.indexOf(' ET'));

      expect('BT '.allMatches(text).length, 1);
      expect(' Ts '.allMatches(body).length, greaterThan(1));
      final lastRise = RegExp(r'(-?[\d.]+) Ts').allMatches(body).last;
      expect(lastRise.group(1), '0');
    },
    skip: File(_riseFontPath).existsSync()
        ? null
        : 'the rise test font is missing',
  );

  test(
    'שורה של כמה מילים נכתבת כבלוק אחד וכל גליף נוחת במקומו המדויק',
    () async {
      final file = File(_riseFontPath);
      final bytes = file.readAsBytesSync();
      final shaper = ShaperFont.register(bytes);
      addTearDown(shaper.dispose);
      final document = PdfDocument(compress: false);
      final pdfFont = PdfShapedFont(
        document,
        shaper: shaper,
        fontBytes: bytes,
      );
      const fontSize = 17.3;
      // Many glyphs on one line: rounding that accumulated would show here.
      final words = [
        for (var i = 0; i < 12; i++) ...[pointedWord, 'בראשית', 'וַיֹּ֕אמֶר'],
      ];
      final placed = <PlacedShapedRun>[];
      var x = 20.0;
      for (final word in words) {
        final run = shaper.shape(word, rtl: true, script: 'hebr');
        placed.add(PlacedShapedRun(run, x));
        x += run.advanceAt(fontSize) + 3.7;
      }

      final page = PdfPage(document, pageFormat: PdfPageFormat.a3.landscape);
      pdfFont.drawShapedRuns(
        page.getGraphics()..setFillColor(PdfColors.black),
        placed,
        y: 300,
        fontSize: fontSize,
      );
      final text = String.fromCharCodes(await document.save());
      expect('BT '.allMatches(text).length, 1);

      final expected = <(int, double, double)>[
        for (final p in placed)
          for (
            var i = 0, pen = 0;
            i < p.run.glyphCount;
            pen += p.run.xAdvance(i), i++
          )
            (
              p.run.glyphId(i),
              p.x + (pen + p.run.xOffset(i)) * fontSize / p.run.unitsPerEm,
              p.run.yOffset(i) * fontSize / p.run.unitsPerEm,
            ),
      ];
      final drawn = _simulateTextObject(
        text.substring(text.indexOf('BT '), text.indexOf(' ET')),
        fontSize: fontSize,
        widthOf: (glyph) =>
            (shaper.glyphAdvances[glyph] * 1000 / shaper.metrics.unitsPerEm)
                .round(),
      );

      expect(drawn, hasLength(expected.length));
      // Half a glyph-space unit is the rounding bound; it must not grow.
      final tolerance = 0.5 * fontSize / 1000 + 1e-6;
      for (var i = 0; i < expected.length; i++) {
        expect(drawn[i].$1, expected[i].$1);
        expect(drawn[i].$2, closeTo(expected[i].$2, tolerance));
        expect(drawn[i].$3, closeTo(expected[i].$3, 0.001));
      }
    },
    skip: File(_riseFontPath).existsSync()
        ? null
        : 'the rise test font is missing',
  );
}

/// Replays one text object the way a viewer does: `Td` sets the pen, a `TJ`
/// number moves it back by n/1000 em, a glyph draws and advances by its `/W`
/// width, and `Ts` raises what follows. Returns (glyph, x, rise) per glyph.
List<(int, double, double)> _simulateTextObject(
  String body, {
  required double fontSize,
  required int Function(int glyph) widthOf,
}) {
  final tokens = RegExp(
    r'/\S+|<([0-9a-f]+)>|(-?\d+(?:\.\d+)?)|([A-Za-z]+)|(\[)|(\])',
  ).allMatches(body);
  final drawn = <(int, double, double)>[];
  final operands = <double>[];
  var inArray = false;
  var pen = 0.0;
  var rise = 0.0;
  for (final token in tokens) {
    if (token.group(1) case final hex?) {
      for (var i = 0; i < hex.length; i += 4) {
        final glyph = int.parse(hex.substring(i, i + 4), radix: 16);
        drawn.add((glyph, pen, rise));
        pen += widthOf(glyph) * fontSize / 1000;
      }
    } else if (token.group(2) case final number?) {
      final value = double.parse(number);
      // Inside a TJ array a number moves the pen back by value/1000 em.
      inArray ? pen -= value * fontSize / 1000 : operands.add(value);
    } else if (token.group(4) != null) {
      inArray = true;
    } else if (token.group(5) != null) {
      inArray = false;
    } else if (token.group(3) case final op?) {
      if (op == 'Td') pen = operands[operands.length - 2];
      if (op == 'Ts') rise = operands.last;
      operands.clear();
    }
  }
  return drawn;
}

/// גופן מוטמע שיש בו הזזה אנכית אמיתית לסימן.
const String _riseFontPath = 'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf';
