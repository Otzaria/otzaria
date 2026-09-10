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
import 'package:pdf/src/pdf/format/stream.dart';
import 'package:pdf/src/pdf/format/string.dart';
import 'package:pdf/src/pdf/obj/object.dart';
import 'package:pdf/src/pdf/obj/object_stream.dart';

/// PDF glyph space: widths and `TJ` adjustments are thousandths of an em.
const double _pdfGlyphSpace = 1000.0;

class PdfShapedFont extends PdfFont {
  PdfShapedFont(
    PdfDocument document, {
    required this.shaper,
    required this.fontBytes,
    this.defaultScript = 'hebr',
    this.defaultRtl = true,
  }) : super.create(document, subtype: '/Type0') {
    _file = PdfObjectStream(document, isBinary: true);
    _toUnicode = PdfObjectStream(document);
    _widths = PdfObject<PdfArray>(document, params: PdfArray());
    _descriptor = PdfObject<PdfDict>(
      document,
      params: PdfDict.values({'/Type': const PdfName('/FontDescriptor')}),
    );
  }

  /// The shaping font this PDF font mirrors.
  final ShaperFont shaper;

  /// Used when text arrives without an explicit direction or script, which is
  /// what happens if this font is handed to a plain `Text` widget.
  final String defaultScript;
  final bool defaultRtl;

  /// The complete font file, embedded as-is.
  ///
  /// Embedding the whole font rather than a subset keeps glyph ids valid: a
  /// glyph a GSUB rule produced has no character to subset it by.
  final Uint8List fontBytes;

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
  _PendingSegment? _pending;

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

  /// Distance between baselines, as a fraction of the font size.
  double get lineSpacing => shaper.metrics.lineHeight / unitsPerEm;

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
  ///
  /// The run is split wherever the vertical offset changes, because a `TJ`
  /// array can only move the pen horizontally; each part is drawn with its own
  /// text rise. Marks usually sit on the baseline offset zero, so a word is
  /// normally one part.
  void drawShapedRun(
    PdfGraphics canvas,
    ShapedRun run, {
    required double x,
    required double y,
    required double fontSize,
    PdfTextRenderingMode mode = PdfTextRenderingMode.fill,
  }) {
    if (run.isEmpty) {
      return;
    }
    _recordGlyphText(run);

    final unitScale = fontSize / run.unitsPerEm;
    var segmentStart = 0;
    var penUnits = 0;
    var segmentPenUnits = 0;

    void flush(int end) {
      if (end <= segmentStart) {
        return;
      }
      final rise = run.yOffset(segmentStart) * unitScale;
      _pending = _PendingSegment(run, segmentStart, end);
      try {
        canvas.drawString(
          this,
          fontSize,
          '',
          x + segmentPenUnits * unitScale,
          y,
          mode: mode,
          rise: rise == 0 ? null : rise,
        );
      } finally {
        _pending = null;
      }
    }

    for (var index = 0; index < run.glyphCount; index++) {
      if (run.yOffset(index) != run.yOffset(segmentStart)) {
        flush(index);
        segmentStart = index;
        segmentPenUnits = penUnits;
      }
      penUnits += run.xAdvance(index);
    }
    flush(run.glyphCount);
  }

  /// Writes the body of a `TJ` array.
  ///
  /// With a segment pending, the glyphs come from the shaped run. Without one,
  /// the text is shaped here, which is what happens when this font is used with
  /// a widget that draws strings itself. That path is only correct for text the
  /// widget layer has not reordered, so prefer [drawShapedRun].
  @override
  void putText(PdfStream stream, String text) {
    final pending = _pending;
    if (pending != null) {
      _writeSegment(stream, pending);
      return;
    }
    final run = _shapeForMetrics(text);
    if (run.isEmpty) {
      return;
    }
    _recordGlyphText(run);
    _writeSegment(stream, _PendingSegment(run, 0, run.glyphCount));
  }

  void _writeSegment(PdfStream stream, _PendingSegment segment) {
    final run = segment.run;
    final scale = _pdfGlyphSpace / run.unitsPerEm;

    // Positions are relative to the segment's pen start, which the caller
    // already applied through `Td`.
    var penUnits = 0;
    for (var index = segment.start; index < segment.end; index++) {
      final origin = (penUnits + run.xOffset(index)) * scale;
      // A `TJ` number displaces the pen by its negation, so the adjustment
      // needed to reach this glyph's origin is the negated gap.
      final adjustment = origin - segment.cursor;
      if (adjustment.abs() > 0.0005) {
        stream.putString(_formatNumber(-adjustment));
        stream.putByte(0x20);
      }
      stream.putByte(0x3c); // '<'
      stream.putString(
        run.glyphId(index).toRadixString(16).padLeft(4, '0'),
      );
      stream.putByte(0x3e); // '>'

      // The viewer advances by the width declared in `/W`, not by the shaped
      // advance, so the cursor must follow the declared width.
      segment.cursor = origin + _advanceOf(run.glyphId(index)) * scale;
      penUnits += run.xAdvance(index);
    }
  }

  static String _formatNumber(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0005) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(3);
  }

  /// Remembers which characters a glyph stands for, for the text layer.
  ///
  /// When a cluster produced as many glyphs as it had characters, the glyphs
  /// pair up with the characters in reverse of the storage order, because a
  /// right-to-left run stores a cluster's marks before its base. Otherwise a
  /// rule combined or split characters, and the whole cluster is attributed to
  /// the glyph that carries the advance so extraction yields the text once.
  void _recordGlyphText(ShapedRun run) {
    for (final cluster in run.clusters()) {
      final source = run.text.substring(cluster.textStart, cluster.textEnd);
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

  @override
  void prepare() {
    super.prepare();

    _file.buf.putBytes(fontBytes);
    _file.params['/Length1'] = PdfNum(fontBytes.length);

    _buildDescriptor();
    _buildWidths();
    _buildToUnicode();

    final base = PdfName('/$fontName');
    params['/BaseFont'] = base;
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/ToUnicode'] = _toUnicode.ref();
    params['/DescendantFonts'] = PdfArray([
      PdfDict.values({
        '/Type': const PdfName('/Font'),
        '/Subtype': const PdfName('/CIDFontType2'),
        '/BaseFont': base,
        '/FontDescriptor': _descriptor.ref(),
        '/CIDToGIDMap': const PdfName('/Identity'),
        '/DW': const PdfNum(0),
        '/W': PdfArray([const PdfNum(0), _widths.ref()]),
        '/CIDSystemInfo': PdfDict.values({
          '/Registry': PdfString.fromString('Adobe'),
          '/Ordering': PdfString.fromString('Identity'),
          '/Supplement': const PdfNum(0),
        }),
      }),
    ]);
  }

  void _buildDescriptor() {
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
      ..['/FontName'] = PdfName('/$fontName')
      ..['/FontFile2'] = _file.ref()
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

  void _buildWidths() {
    final scale = _pdfGlyphSpace / unitsPerEm;
    for (final advance in shaper.glyphAdvances) {
      _widths.params.add(PdfNum((advance * scale).round()));
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

class _PendingSegment {
  _PendingSegment(this.run, this.start, this.end);

  final ShapedRun run;
  final int start;
  final int end;

  /// Where the PDF pen sits, in glyph space relative to the segment start.
  double cursor = 0;
}
