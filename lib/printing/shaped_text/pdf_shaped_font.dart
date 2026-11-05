/// A PDF font that emits pre-shaped glyphs.
///
/// `package:pdf` runs no OpenType layout: it maps characters through `cmap`
/// and draws them at the pen, so a mark ends up beside its letter instead of
/// under it, and a glyph that only a GSUB rule can produce cannot be reached at
/// all. This font takes the output of [ShapedRun] instead — a glyph id with an
/// offset and an advance — and writes it as vector text.
///
/// This is the one file that imports `package:pdf`'s internals. The format and
/// object layers are not exported, and a Type0 font cannot be assembled without
/// them. Keeping the seam here means a breaking change upstream surfaces as a
/// compile error in a single place.
library;

// ignore_for_file: implementation_imports

import 'dart:typed_data';

import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/format/array.dart';
import 'package:pdf/src/pdf/format/dict.dart';
import 'package:pdf/src/pdf/format/num.dart';
import 'package:pdf/src/pdf/format/string.dart';
import 'package:pdf/src/pdf/obj/object.dart';
import 'package:pdf/src/pdf/obj/object_stream.dart';

/// PDF glyph space: widths and `TJ` adjustments are thousandths of an em.
const double _pdfGlyphSpace = 1000.0;

/// An OpenType file whose outlines are CFF starts with this tag; one with
/// TrueType outlines starts with a version number. The two embed differently.
const List<int> _cffSignature = [0x4F, 0x54, 0x54, 0x4F];

class PdfShapedFont extends PdfFont {
  PdfShapedFont(
    PdfDocument document, {
    required this.shaper,
    required this.fontBytes,
    this.defaultScript = 'hebr',
    this.defaultRtl = true,
    this.faceIndex = 0,
    this.textForExtraction,
  }) : super.create(document, subtype: '/Type0') {
    _file = PdfObjectStream(document, isBinary: true);
    _toUnicode = PdfObjectStream(document);
    _widths = PdfObject<PdfArray>(document, params: PdfArray());
    _descriptor = PdfObject<PdfDict>(
      document,
      params: PdfDict.values({'/Type': const PdfName('/FontDescriptor')}),
    );
  }

  /// השייפר מושאל: יוצרו משאיר אותו חי עד ש-save מסתיים ומשחרר אותו בעצמו.
  final ShaperFont shaper;

  /// Used when text arrives without an explicit direction or script, which is
  /// what happens if this font is handed to a plain `Text` widget.
  final String defaultScript;
  final bool defaultRtl;

  /// The font file. Only drawn glyphs are embedded, subset by glyph id: a glyph
  /// a GSUB rule produced has no character to subset it by.
  final Uint8List fontBytes;

  /// The face of a collection that [shaper] was registered from.
  final int faceIndex;

  /// מאפשר לגליף פרטי לייצג אות רגילה בשכבת הטקסט הניתנת להעתקה ולחיפוש.
  final String Function(String)? textForExtraction;

  late final PdfObjectStream _file;
  late final PdfObjectStream _toUnicode;
  late final PdfObject<PdfArray> _widths;
  late final PdfObject<PdfDict> _descriptor;

  /// Glyph id to the characters it stands for, collected as glyphs are drawn.
  /// Only what a document actually used goes into the text layer.
  final Map<int, String> _glyphText = {};

  /// Set immediately before a `drawString` call and read back by [putText].
  /// `drawString` calls `putText` synchronously on the same isolate, so no
  /// other emission can interleave.
  _PendingLine? _pending;

  /// Runs already attributed in [_glyphText]. The shaper caches runs, so the
  /// same word arrives as the same object every time it is drawn.
  final Set<ShapedRun> _recordedRuns = Set.identity();

  @override
  String get fontName {
    final name = shaper.postScriptName;
    if (name.isEmpty) {
      return 'OtzariaShaped$objser';
    }
    // PDF names cannot carry whitespace or delimiters.
    return name.replaceAll(RegExp(r'[^\w.-]'), '');
  }

  @override
  int get unitsPerEm => shaper.metrics.unitsPerEm;

  @override
  double get ascent => shaper.metrics.ascender / unitsPerEm;

  @override
  double get descent => shaper.metrics.descender / unitsPerEm;

  @override
  bool isRuneSupported(int charCode) {
    final run = _shapeForMetrics(String.fromCharCode(charCode));
    if (run.isEmpty) {
      return false;
    }
    for (var index = 0; index < run.glyphCount; index++) {
      if (run.glyphId(index) == 0) {
        return false;
      }
    }
    return true;
  }

  @override
  PdfFontMetrics glyphMetrics(int charCode) =>
      _metricsOf(_shapeForMetrics(String.fromCharCode(charCode)));

  @override
  PdfFontMetrics stringMetrics(String s, {double letterSpacing = 0}) {
    if (s.isEmpty) {
      return PdfFontMetrics.zero;
    }
    final metrics = _metricsOf(_shapeForMetrics(s));
    if (letterSpacing == 0) {
      return metrics;
    }
    return metrics.copyWith(
      advanceWidth: metrics.advanceWidth + letterSpacing * s.length,
    );
  }

  ShapedRun _shapeForMetrics(String text) =>
      shaper.shape(text, rtl: defaultRtl, script: defaultScript);

  PdfFontMetrics _metricsOf(ShapedRun run) {
    if (run.isEmpty) {
      return PdfFontMetrics.zero;
    }
    final scale = 1 / run.unitsPerEm;
    var pen = 0;
    var left = 0.0;
    var right = 0.0;
    for (var index = 0; index < run.glyphCount; index++) {
      final origin = pen + run.xOffset(index);
      final width = _advanceOf(run.glyphId(index));
      left = index == 0 ? origin * scale : left;
      right = right < (origin + width) * scale
          ? (origin + width) * scale
          : right;
      pen += run.xAdvance(index);
    }
    return PdfFontMetrics(
      left: left,
      top: shaper.metrics.yMin * scale,
      right: right,
      bottom: shaper.metrics.yMax * scale,
      ascent: shaper.metrics.ascender * scale,
      descent: shaper.metrics.descender * scale,
      advanceWidth: pen * scale,
    );
  }

  int _advanceOf(int glyphId) =>
      glyphId < shaper.glyphAdvances.length ? shaper.glyphAdvances[glyphId] : 0;

  /// Draws a shaped run with `x`, `y` as the origin of its first pen position.
  void drawShapedRun(
    PdfGraphics canvas,
    ShapedRun run, {
    required double x,
    required double y,
    required double fontSize,
    PdfTextRenderingMode mode = PdfTextRenderingMode.fill,
  }) => drawShapedRuns(
    canvas,
    [PlacedShapedRun(run, x)],
    y: y,
    fontSize: fontSize,
    mode: mode,
  );

  /// Draws runs sharing a baseline (a line's words) as one text object: gaps
  /// become `TJ` adjustments and a mark's vertical offset a `Ts` change.
  void drawShapedRuns(
    PdfGraphics canvas,
    List<PlacedShapedRun> runs, {
    required double y,
    required double fontSize,
    PdfTextRenderingMode mode = PdfTextRenderingMode.fill,
  }) {
    final first = runs.indexWhere((placed) => placed.run.isNotEmpty);
    if (first < 0) {
      return;
    }
    for (final placed in runs) {
      _recordGlyphText(placed.run);
    }

    final originX = runs[first].x;
    final glyphScale = _pdfGlyphSpace / fontSize;
    final line = _PendingLine(
      [
        for (final placed in runs.skip(first))
          (placed.run, (placed.x - originX) * glyphScale),
      ],
      fontSize: fontSize,
    );
    _pending = line;
    try {
      canvas.drawString(
        this,
        fontSize,
        '',
        originX,
        y,
        mode: mode,
        rise: line.initialRise,
      );
    } finally {
      _pending = null;
    }
  }

  /// Writes the body of a `TJ` array. Without a pending line (a widget drawing
  /// strings itself) the text is shaped here, correct only if not reordered.
  @override
  void putText(PdfStream stream, String text) {
    final pending = _pending;
    if (pending != null) {
      _writeLine(stream, pending);
      return;
    }
    final run = _shapeForMetrics(text);
    if (run.isEmpty) {
      return;
    }
    _recordGlyphText(run);
    _writeLine(stream, _PendingLine([(run, 0)]));
  }

  void _writeLine(PdfStream stream, _PendingLine line) {
    final unitsToGlyphSpace = _pdfGlyphSpace / unitsPerEm;
    final fontSize = line.fontSize;
    // The viewer advances by the rounded width declared in `/W`. Tracking the
    // pen in the same integers keeps rounding from accumulating along a line.
    var cursor = 0;
    var rise = line.initialRise;
    var hexOpen = false;

    void closeHex() {
      if (hexOpen) {
        stream.putByte(0x3e); // '>'
        hexOpen = false;
      }
    }

    for (final (run, start) in line.runs) {
      var penUnits = 0;
      for (var index = 0; index < run.glyphCount; index++) {
        if (fontSize != null) {
          final glyphRise = run.yOffset(index) * fontSize / unitsPerEm;
          if (glyphRise != rise) {
            // Ts is text state: it can change between TJ arrays inside one
            // text object, and it stays in force until written again.
            closeHex();
            stream.putString(']TJ ${_formatRise(glyphRise)} Ts [');
            rise = glyphRise;
          }
        }
        final origin =
            (start + (penUnits + run.xOffset(index)) * unitsToGlyphSpace)
                .round();
        final adjustment = origin - cursor;
        if (adjustment != 0) {
          closeHex();
          // A `TJ` number displaces the pen by its negation.
          stream.putString('${-adjustment}');
        }
        if (!hexOpen) {
          stream.putByte(0x3c); // '<'
          hexOpen = true;
        }
        final glyph = run.glyphId(index);
        stream.putString(glyph.toRadixString(16).padLeft(4, '0'));
        cursor = origin + _declaredWidth(glyph);
        penUnits += run.xAdvance(index);
      }
    }
    closeHex();
    // Whatever is drawn next may not set its own rise.
    if (rise != 0) {
      stream.putString(']TJ 0 Ts [');
    }
  }

  int _declaredWidth(int glyphId) =>
      (_advanceOf(glyphId) * _pdfGlyphSpace / unitsPerEm).round();

  static String _formatRise(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0005) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(3);
  }

  /// Maps cluster characters to glyphs in RTL storage order; a merged cluster
  /// is attributed once, to its advancing glyph, for text extraction.
  void _recordGlyphText(ShapedRun run) {
    if (!_recordedRuns.add(run) || _allGlyphsRecorded(run)) {
      return;
    }
    for (final cluster in run.clusters()) {
      final raw = run.text.substring(cluster.textStart, cluster.textEnd);
      final source = textForExtraction?.call(raw) ?? raw;
      final characters = source.runes.toList();

      if (characters.length == cluster.glyphCount) {
        for (var offset = 0; offset < cluster.glyphCount; offset++) {
          final glyph = run.glyphId(cluster.firstGlyph + offset);
          final rune = characters[characters.length - 1 - offset];
          _glyphText.putIfAbsent(glyph, () => String.fromCharCode(rune));
        }
        continue;
      }

      var carrier = cluster.lastGlyph;
      for (
        var index = cluster.firstGlyph;
        index <= cluster.lastGlyph;
        index++
      ) {
        if (run.xAdvance(index) != 0) {
          carrier = index;
          break;
        }
      }
      for (
        var index = cluster.firstGlyph;
        index <= cluster.lastGlyph;
        index++
      ) {
        final glyph = run.glyphId(index);
        _glyphText.putIfAbsent(glyph, () => index == carrier ? source : '');
      }
    }
  }

  /// Attribution only fills glyphs not yet in [_glyphText], so a word made of
  /// known glyphs would change nothing and need not be split into clusters.
  bool _allGlyphsRecorded(ShapedRun run) {
    for (var index = 0; index < run.glyphCount; index++) {
      if (!_glyphText.containsKey(run.glyphId(index))) return false;
    }
    return true;
  }

  /// CFF outlines cannot be embedded as a TrueType file: the descendant font
  /// is a CIDFontType0 and the file goes in `/FontFile3`, not `/FontFile2`.
  bool get _isCff =>
      fontBytes.length >= 4 &&
      _cffSignature.indexed.every((e) => fontBytes[e.$1] == e.$2);

  @override
  void prepare() {
    super.prepare();

    final embedded = _embeddedFont();
    _file.buf.putBytes(embedded);
    if (_isCff) {
      _file.params['/Subtype'] = const PdfName('/OpenType');
    } else {
      _file.params['/Length1'] = PdfNum(embedded.length);
    }

    final base = PdfName('/$_subsetTag+$fontName');
    _buildDescriptor(base);
    _buildWidths();
    _buildToUnicode();

    params['/BaseFont'] = base;
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/ToUnicode'] = _toUnicode.ref();
    params['/DescendantFonts'] = PdfArray([
      PdfDict.values({
        '/Type': const PdfName('/Font'),
        '/Subtype': PdfName(_isCff ? '/CIDFontType0' : '/CIDFontType2'),
        '/BaseFont': base,
        '/FontDescriptor': _descriptor.ref(),
        // CIDFontType0 has no CIDToGIDMap: the CFF maps CIDs to glyphs itself.
        if (!_isCff) '/CIDToGIDMap': const PdfName('/Identity'),
        '/DW': const PdfNum(0),
        '/W': _widths.ref(),
        '/CIDSystemInfo': PdfDict.values({
          '/Registry': PdfString.fromString('Adobe'),
          '/Ordering': PdfString.fromString('Identity'),
          '/Supplement': const PdfNum(0),
        }),
      }),
    ]);
  }

  Uint8List _embeddedFont() {
    try {
      return subsetFontForPdf(fontBytes, _glyphText.keys, faceIndex: faceIndex);
    } on FormatException {
      // A user font the shaper reads can still break a table rule the subsetter
      // checks; the whole file is what it would render from anyway.
      return fontBytes;
    }
  }

  /// Six capitals derived from the glyph set, the PDF convention that marks an
  /// embedded font as a subset and keeps two different subsets apart.
  String get _subsetTag {
    var hash = 0x811C9DC5;
    for (final glyph in _glyphText.keys.toList()..sort()) {
      hash = ((hash ^ glyph) * 0x01000193) & 0xFFFFFFFF;
    }
    final letters = StringBuffer();
    for (var index = 0; index < 6; index++) {
      letters.writeCharCode(0x41 + hash % 26);
      hash ~/= 26;
    }
    return letters.toString();
  }

  void _buildDescriptor(PdfName fontName) {
    final metrics = shaper.metrics;
    final scale = _pdfGlyphSpace / unitsPerEm;

    // Bit 3 marks a symbolic font, which is what a Type0 font with an Identity
    // encoding is; bit 2 adds serif and bit 7 italic.
    var flags = 4;
    if (metrics.isSerif) {
      flags |= 2;
    }
    if (metrics.isItalic) {
      flags |= 64;
    }
    if (metrics.isFixedPitch) {
      flags |= 1;
    }

    _descriptor.params
      ..['/FontName'] = fontName
      ..[_isCff ? '/FontFile3' : '/FontFile2'] = _file.ref()
      ..['/Flags'] = PdfNum(flags)
      ..['/FontBBox'] = PdfArray.fromNum(<int>[
        (metrics.xMin * scale).round(),
        (metrics.yMin * scale).round(),
        (metrics.xMax * scale).round(),
        (metrics.yMax * scale).round(),
      ])
      ..['/Ascent'] = PdfNum((metrics.ascender * scale).round())
      ..['/Descent'] = PdfNum((metrics.descender * scale).round())
      ..['/ItalicAngle'] = PdfNum(metrics.italicAngle)
      ..['/CapHeight'] = PdfNum(
        ((metrics.capHeight == 0 ? metrics.ascender : metrics.capHeight) *
                scale)
            .round(),
      )
      // No table carries stem width; the weight class is the closest signal a
      // font gives, and viewers only use this to synthesise a substitute.
      ..['/StemV'] = PdfNum((metrics.weightClass / 5).round().clamp(1, 500));
  }

  /// Declares widths for the drawn glyphs only, as runs of consecutive ids:
  /// `first [w1 w2 ...]`. Everything else falls back to `/DW` 0.
  void _buildWidths() {
    final glyphs = _glyphText.keys.toList()..sort();
    var index = 0;
    while (index < glyphs.length) {
      final first = glyphs[index];
      final widths = <PdfNum>[];
      while (index < glyphs.length && glyphs[index] == first + widths.length) {
        widths.add(PdfNum(_declaredWidth(glyphs[index])));
        index++;
      }
      _widths.params
        ..add(PdfNum(first))
        ..add(PdfArray(widths));
    }
  }

  void _buildToUnicode() {
    final entries =
        _glyphText.entries.where((entry) => entry.value.isNotEmpty).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    final buffer = StringBuffer()
      ..write(
        '/CIDInit /ProcSet findresource begin\n'
        '12 dict begin\n'
        'begincmap\n'
        '/CIDSystemInfo <<\n'
        '/Registry (Adobe)\n'
        '/Ordering (UCS)\n'
        '/Supplement 0\n'
        '>> def\n'
        '/CMapName /Adobe-Identity-UCS def\n'
        '/CMapType 2 def\n'
        '1 begincodespacerange\n'
        '<0000> <FFFF>\n'
        'endcodespacerange\n',
      );

    // `beginbfchar` takes at most 100 entries per block.
    for (var offset = 0; offset < entries.length; offset += 100) {
      final chunk = entries.skip(offset).take(100).toList();
      buffer.writeln('${chunk.length} beginbfchar');
      for (final entry in chunk) {
        buffer.writeln(
          '<${_hex4(entry.key)}> <${_utf16Hex(entry.value)}>',
        );
      }
      buffer.writeln('endbfchar');
    }

    buffer.write(
      'endcmap\n'
      'CMapName currentdict /CMap defineresource pop\n'
      'end\n'
      'end',
    );
    _toUnicode.buf.putString(buffer.toString());
  }

  static String _hex4(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(4, '0');

  static String _utf16Hex(String text) => text.codeUnits.map(_hex4).join();
}

/// A shaped run and the x of its first pen position, in points.
class PlacedShapedRun {
  const PlacedShapedRun(this.run, this.x);

  final ShapedRun run;
  final double x;
}

class _PendingLine {
  _PendingLine(this.runs, {this.fontSize})
    : initialRise = fontSize == null ? 0 : _firstRise(runs, fontSize);

  /// Each run with its start in glyph space, relative to the line's origin.
  final List<(ShapedRun, double)> runs;

  /// Null when the size is unknown, which drops vertical offsets.
  final double? fontSize;

  final double initialRise;

  static double _firstRise(List<(ShapedRun, double)> runs, double fontSize) {
    for (final (run, _) in runs) {
      if (run.isNotEmpty) {
        return run.yOffset(0) * fontSize / run.unitsPerEm;
      }
    }
    return 0;
  }
}
