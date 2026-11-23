import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
// קידוד ה־PNG משתמש בחבילת image שכבר נעולה דרך pdf.
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as raster_image;
import 'package:pdf/pdf.dart' as pdf;
// Same engine pinned transitively by the application's pdfrx dependency.
// ignore: depend_on_referenced_packages
import 'package:pdfrx_engine/pdfrx_engine.dart' as engine;

const pdfTextFixtureVersion = 'otzaria-pdf-text-v2';
const pdfTextFixtureFontSha256 =
    '054f3f97a338070c3558a9ce7e302565be85c7436b10bb0a01cf6a41f0782e61';
const pdfTextPointedExtractedLine = 'שָׁ לוֹם עוֹלָ ם';
const pdfTextFixturePageCount = 32;
const pdfTextFixtureLines = 12;
const pdfTextFixtureKinds = [
  'hebrew',
  'niqqud',
  'columns',
  'mixed_direction',
  'rotate_90',
  'rotate_270',
  'visual_order',
  'legacy_map',
];

const pdfTextNiqqudPattern =
    r'ש[\u0591-\u05C7]*ל[\u0591-\u05C7]*ו[\u0591-\u05C7]*ם';

Map<String, int> pdfTextExpectedMatches(int pageNumber) {
  final kind = pdfTextFixtureKinds[(pageNumber - 1) % 8];
  return {
    'literal_hebrew': kind == 'niqqud' ? 0 : pdfTextFixtureLines,
    'niqqud_tolerant': kind == 'niqqud' ? 0 : pdfTextFixtureLines,
    'niqqud_marks': kind == 'niqqud' ? pdfTextFixtureLines * 5 : 0,
    'latin_case_insensitive': kind == 'mixed_direction'
        ? pdfTextFixtureLines
        : 0,
    'latin_case_sensitive': 0,
    'two_columns': kind == 'columns' ? pdfTextFixtureLines * 2 : 0,
    'no_match': 0,
    'zero_length': 0,
  };
}

/// קלט קבוע עם פונטים מוטמעים; יצירתו קודמת לחלון המדידה.
Future<Map<String, Object?>> writePdfTextFixture(
  File output, {
  required File fontFile,
}) async {
  final fontBytes = await fontFile.readAsBytes();
  if (sha256.convert(fontBytes).toString() != pdfTextFixtureFontSha256) {
    throw StateError('The positioned niqqud corpus requires the pinned Tinos');
  }
  final document = _FixedPdfDocument();
  final font = _PointedTinosFont(document, ByteData.sublistView(fontBytes));
  final legacy = pdf.PdfTtfFont(document, ByteData.sublistView(fontBytes));
  final pages = <Map<String, Object?>>[];
  for (var index = 0; index < pdfTextFixturePageCount; index++) {
    final kind = pdfTextFixtureKinds[index % pdfTextFixtureKinds.length];
    final rotation = switch (kind) {
      'rotate_90' => pdf.PdfPageRotation.rotate90,
      'rotate_270' => pdf.PdfPageRotation.rotate270,
      _ => pdf.PdfPageRotation.none,
    };
    final page = pdf.PdfPage(
      document,
      pageFormat: pdf.PdfPageFormat.a4,
      rotate: rotation,
    );
    final canvas = page.getGraphics();
    canvas.setColor(const pdf.PdfColor(0.7, 0.7, 0.7));
    canvas.drawString(font, 12, 'PAGE ${index + 1}', 36, 805);
    canvas.setColor(pdf.PdfColors.black);
    for (var line = 0; line < pdfTextFixtureLines; line++) {
      final y = 750.0 - line * 36;
      switch (kind) {
        case 'niqqud':
          _drawRtl(canvas, font, 'שָׁלוֹם עוֹלָם', 540, y);
        case 'columns':
          _drawRtl(canvas, font, 'טור ימין שלום', 540, y);
          _drawRtl(canvas, font, 'טור שמאל עולם', 265, y);
        case 'mixed_direction':
          _drawRtl(canvas, font, 'שלום', 540, y);
          canvas.drawString(font, 20, 'PDF 123', 285, y);
          _drawRtl(canvas, font, 'עולם', 180, y);
        case 'visual_order':
          canvas.drawString(
            font,
            20,
            'שלום עולם'.characters.toList().reversed.join(),
            360,
            y,
          );
        case 'legacy_map':
          _drawRtl(canvas, legacy, 'שלום עולם', 540, y);
        default:
          _drawRtl(canvas, font, 'שלום עולם', 540, y);
      }
    }
    pages.add({
      'pageNumber': index + 1,
      'kind': kind,
      'rotationDegrees': rotation.index * 90,
      'lines': pdfTextFixtureLines,
    });
  }
  final original = await document.save();
  final bytes = _legacyTextMap(original, legacy.unicodeCMap.objser);
  await output.writeAsBytes(bytes, flush: true);
  return {
    'version': pdfTextFixtureVersion,
    'pageCount': pdfTextFixturePageCount,
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'fontSha256': sha256.convert(fontBytes).toString(),
    'fontBytes': fontBytes.length,
    'pages': pages,
  };
}

void _drawRtl(
  pdf.PdfGraphics canvas,
  pdf.PdfFont font,
  String text,
  double right,
  double y,
) {
  final visual = text.characters.toList().reversed.join();
  final left = right - font.stringMetrics(visual).advanceWidth * 20;
  canvas.drawString(font, 20, visual, left, y);
}

/// מפת legacy מכוונת משמרת glyphs עבריים; רק מיפוי הטקסט משתנה באורך זהה.
Uint8List _legacyTextMap(Uint8List bytes, int objectNumber) {
  final text = latin1.decode(bytes);
  final marker = RegExp('^$objectNumber 0 obj\\b', multiLine: true);
  final matches = marker.allMatches(text).toList();
  if (matches.length != 1) throw StateError('Missing unique legacy CMap');
  final start = matches.single.start;
  final end = text.indexOf('\nendobj', start);
  if (end < 0) throw StateError('Unterminated legacy CMap');
  var replacements = 0;
  final patched = text.substring(start, end).replaceAllMapped(
    RegExp(r'(<[0-9A-F]{4}> )<([0-9A-F]{4})>'),
    (match) {
      final unicode = int.parse(match[2]!, radix: 16);
      if (unicode < 0x05d0 || unicode > 0x05ea) return match[0]!;
      replacements++;
      final legacy = (unicode - 0x05d0 + 0xe0)
          .toRadixString(16)
          .toUpperCase()
          .padLeft(4, '0');
      return '${match[1]}<$legacy>';
    },
  );
  if (replacements < 5 || patched.length != end - start) {
    throw StateError('Legacy CMap did not preserve PDF offsets');
  }
  return Uint8List.fromList(
    latin1.encode(text.replaceRange(start, end, patched)),
  );
}

class _FixedPdfDocument extends pdf.PdfDocument {
  _FixedPdfDocument() : super(compress: false);

  @override
  Uint8List get documentID => Uint8List.fromList(
    sha256.convert(utf8.encode(pdfTextFixtureVersion)).bytes,
  );
}

/// מאמת את הקלט מחוץ למדידה, לרבות גוף כהה שאינו כותרת העמוד האפורה.
Future<Map<String, Object?>> validatePdfTextFixture(
  engine.PdfDocument document, {
  Directory? rasterDirectory,
}) async {
  if (document.pages.length != pdfTextFixturePageCount ||
      !engine.Pdfrx.normalizeHebrewText ||
      !engine.Pdfrx.decodeLegacyHebrewText) {
    throw StateError('Unexpected PDF corpus or Hebrew normalization policy');
  }
  await rasterDirectory?.create(recursive: true);
  final pages = <Map<String, Object?>>[];
  for (var index = 0; index < document.pages.length; index++) {
    final page = await document.pages[index].ensureLoaded();
    final kind = pdfTextFixtureKinds[index % 8];
    final text = await page.loadStructuredText();
    final expectedRotation = switch (kind) {
      'rotate_90' => 90,
      'rotate_270' => 270,
      _ => 0,
    };
    final plain = text.fullText.replaceAll(RegExp(r'[\u0591-\u05C7]'), '');
    final words = kind == 'niqqud' ? plain.replaceAll(' ', '') : plain;
    if (kind == 'niqqud') {
      final lines = List.filled(
        pdfTextFixtureLines,
        pdfTextPointedExtractedLine,
      ).join('\n');
      if (text.fullText != 'PAGE ${index + 1}\n$lines') {
        throw StateError('Pinned pointed-text extraction changed');
      }
    }
    final marks = RegExp(r'[\u0591-\u05C7]').allMatches(text.fullText).length;
    if (page.rotation.index * 90 != expectedRotation ||
        !text.fullText.contains('PAGE ${index + 1}') ||
        'שלום'.allMatches(words).length != pdfTextFixtureLines ||
        'עולם'.allMatches(words).length != pdfTextFixtureLines ||
        marks != (kind == 'niqqud' ? pdfTextFixtureLines * 5 : 0) ||
        text.fullText.length != text.charRects.length ||
        text.charRects.any(
          (r) => [r.left, r.top, r.right, r.bottom].any((n) => !n.isFinite),
        )) {
      throw StateError(
        'Text/marks/rotation parity failed on page ${index + 1}',
      );
    }
    if (kind == 'columns') {
      for (final (pattern, rightColumn) in [
        ('טור ימין', true),
        ('טור שמאל', false),
      ]) {
        final matches = await text.allMatches(pattern).toList();
        if (matches.length != pdfTextFixtureLines ||
            matches.any(
              (m) =>
                  m.bounds.isEmpty ||
                  (rightColumn ? m.bounds.left <= 300 : m.bounds.right >= 300),
            )) {
          throw StateError('Column geometry failed on page ${index + 1}');
        }
      }
    }
    Map<String, Object?>? raster;
    if (index < pdfTextFixtureKinds.length) {
      final image = await page.render(backgroundColor: 0xffffffff);
      if (image == null) throw StateError('Missing native corpus raster');
      try {
        var darkBodyPixels = 0;
        final pixels = image.pixels;
        for (var pixel = 0; pixel < pixels.length; pixel += 4) {
          if ((765 - pixels[pixel] - pixels[pixel + 1] - pixels[pixel + 2]) *
                  pixels[pixel + 3] >
              3 * 150 * 255) {
            darkBodyPixels++;
          }
        }
        if (darkBodyPixels <= 100 ||
            pixels.length != image.width * image.height * 4) {
          throw StateError('Blank or invalid body raster on page ${index + 1}');
        }
        raster = {
          'width': image.width,
          'height': image.height,
          'bytes': pixels.length,
          'darkBodyPixels': darkBodyPixels,
          'sha256': sha256.convert(pixels).toString(),
        };
        if (rasterDirectory != null) {
          final png = raster_image.encodePng(
            raster_image.Image.fromBytes(
              width: image.width,
              height: image.height,
              bytes: pixels.buffer,
              bytesOffset: pixels.offsetInBytes,
              order: raster_image.ChannelOrder.bgra,
            ),
          );
          final name = '${(index + 1).toString().padLeft(2, '0')}-$kind.png';
          await File(
            '${rasterDirectory.path}/$name',
          ).writeAsBytes(png, flush: true);
          raster['file'] = name;
          raster['pngSha256'] = sha256.convert(png).toString();
        }
      } finally {
        image.dispose();
      }
    }
    pages.add({
      'pageNumber': index + 1,
      'kind': kind,
      'rotationDegrees': expectedRotation,
      'characters': text.fullText.length,
      'niqqudMarks': marks,
      'textSha256': sha256.convert(utf8.encode(text.fullText)).toString(),
      'raster': ?raster,
    });
  }
  return {
    'status': 'passed',
    'pages': pages,
    'pointedTextObservation': {
      'kind': 'pdfium-inserted-spaces',
      'pages': [2, 10, 18, 26],
      'extractedLine': pdfTextPointedExtractedLine,
      'niqqudMarksPerPage': pdfTextFixtureLines * 5,
      'queryId': 'niqqud_tolerant',
      'matchesPerPage': 0,
    },
  };
}

/// עוגני Tinos הקבוע משמרים מיקום ניקוד ב־TJ יחיד, בלי להניח shaping ב־drawString.
/// זהו קלט סינתטי לארבעת צמדי האות/סימן של התרחיש, ולא מנוע GPOS כללי.
class _PointedTinosFont extends pdf.PdfTtfFont {
  _PointedTinosFont(super.pdfDocument, super.bytes);

  @override
  void putText(pdf.PdfStream stream, String text) {
    if (!RegExp(r'[\u0591-\u05C7]').hasMatch(text)) {
      return super.putText(stream, text);
    }
    for (final cluster in text.characters) {
      final runes = cluster.runes.toList();
      final base = runes.first;
      var position = 0;
      for (final mark in runes.skip(1).toList().reversed) {
        final offset = switch ((base, mark)) {
          (0x05e9, 0x05b8) => 600,
          (0x05e9, 0x05c1) => 1341,
          (0x05d5, 0x05b9) => 213,
          (0x05dc, 0x05b8) => 340,
          _ => throw StateError('Unexpected corpus mark'),
        };
        stream.putString(' ${(position - offset) * 1000 / unitsPerEm} ');
        super.putText(stream, String.fromCharCode(mark));
        position = offset;
      }
      if (position != 0) stream.putString(' ${position * 1000 / unitsPerEm} ');
      super.putText(stream, String.fromCharCode(base));
    }
  }
}
