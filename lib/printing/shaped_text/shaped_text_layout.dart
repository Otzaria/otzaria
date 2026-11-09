/// Line layout over shaped runs.
///
/// `package:pdf`'s own text widgets measure with a font's `cmap` and reorder a
/// right-to-left string before drawing it, which is what misplaces nikud. This
/// lays out the same text from shaped runs instead: a word is measured by the
/// advance its glyphs actually carry, and the words of a line are ordered by
/// the Unicode bidi algorithm before they are positioned.
library;

import 'package:bidi/bidi.dart' as bidi;
import 'package:opentype_shaper/opentype_shaper.dart';

enum ShapedTextAlign { start, end, center, justify }

/// A word of the source text, shaped in its own direction.
class ShapedWord {
  const ShapedWord({
    required this.run,
    required this.fontIndex,
    required this.logicalStart,
    required this.logicalEnd,
    required this.rtl,
    required this.width,
  });

  final ShapedRun run;

  /// Which of the layout's fonts shaped this word.
  final int fontIndex;

  /// UTF-16 range of the paragraph this word came from.
  final int logicalStart;
  final int logicalEnd;

  final bool rtl;

  /// Advance in points at the size it was measured for.
  final double width;
}

/// A shaped run placed on a line.
class ShapedTextSegment {
  const ShapedTextSegment({
    required this.run,
    required this.fontIndex,
    required this.x,
  });

  final ShapedRun run;

  /// Index into the layout's font list, so the painter picks the same face.
  final int fontIndex;

  /// Left edge of the run, relative to the line box.
  final double x;
}

class ShapedTextLine {
  const ShapedTextLine({required this.segments, required this.width});

  final List<ShapedTextSegment> segments;

  /// Ink width of the line, before alignment.
  final double width;
}

class ShapedTextBlock {
  const ShapedTextBlock({
    required this.lines,
    required this.lineHeight,
    required this.width,
    required this.baselineOffset,
  });

  final List<ShapedTextLine> lines;

  /// Distance between baselines.
  final double lineHeight;

  /// Width the block was laid out against.
  final double width;

  /// Distance from the top of a line box down to its baseline.
  final double baselineOffset;

  bool get isEmpty => lines.isEmpty;
}

/// Breaks text into lines of shaped runs.
class ShapedTextLayout {
  ShapedTextLayout({
    required this.fonts,
    required this.fontSize,
    this.align = ShapedTextAlign.start,
    this.rtl = true,
    this.script = 'hebr',
    this.language,
    this.features,
    this.heightFactor,
  });

  /// Fonts to try for each word, in order. A word is shaped with the first
  /// font that has a glyph for every one of its characters, which mirrors the
  /// font fallback a text engine applies per glyph.
  final List<ShaperFont> fonts;

  final double fontSize;
  final ShapedTextAlign align;

  /// Base direction of the paragraph. It decides which edge `start` means and
  /// how the bidi algorithm resolves neutral characters.
  final bool rtl;

  final String script;
  final String? language;
  final String? features;

  /// Line height as a multiple of the font size, as in a Flutter `TextStyle`.
  ///
  /// The result is never allowed below the font's own line height: te'amim
  /// reach further from the baseline than a typographic 1.3 leaves room for,
  /// and a line box too short for them lets ink from one line print inside the
  /// next.
  final double? heightFactor;

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Characters that give a word its direction. Everything else is neutral and
  /// inherits the paragraph's direction.
  static bool _isRtlCharacter(int rune) =>
      (rune >= 0x0590 && rune <= 0x08FF) ||
      (rune >= 0xFB1D && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);

  static bool _isLtrCharacter(int rune) =>
      (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A) ||
      (rune >= 0x00C0 && rune <= 0x024F) ||
      (rune >= 0x0370 && rune <= 0x058F);

  ShaperFont get primaryFont => fonts.first;

  /// The tallest line the fonts need, so a fallback face cannot overflow a box
  /// measured for the primary one.
  double get naturalLineHeight => fonts
      .map(
        (font) => font.metrics.lineHeight * fontSize / font.metrics.unitsPerEm,
      )
      .reduce((a, b) => a > b ? a : b);

  double get lineHeight {
    final requested = heightFactor == null
        ? naturalLineHeight
        : fontSize * heightFactor!;
    return requested < naturalLineHeight ? naturalLineHeight : requested;
  }

  double get baselineOffset {
    final ascent = fonts
        .map(
          (font) => font.metrics.ascender * fontSize / font.metrics.unitsPerEm,
        )
        .reduce((a, b) => a > b ? a : b);
    final leading = lineHeight - naturalLineHeight;
    return ascent + leading / 2;
  }

  double get spaceWidth =>
      primaryFont.shape(' ', rtl: rtl, script: script).advanceAt(fontSize);

  /// Lays `text` out into lines no wider than `maxWidth`.
  ///
  /// A single word wider than `maxWidth` is placed on a line of its own and
  /// allowed to overflow rather than being cut mid-word.
  ShapedTextBlock layout(String text, {required double maxWidth}) {
    final lines = <ShapedTextLine>[];
    final gap = spaceWidth;

    for (final paragraph in text.split('\n')) {
      final words = _splitWords(paragraph);
      if (words.isEmpty) {
        lines.add(const ShapedTextLine(segments: [], width: 0));
        continue;
      }

      var pending = <ShapedWord>[];
      var pendingWidth = 0.0;

      for (final word in words) {
        final extra = pending.isEmpty ? 0.0 : gap;
        if (pending.isNotEmpty &&
            pendingWidth + extra + word.width > maxWidth + 0.001) {
          lines.add(
            _placeLine(paragraph, pending, pendingWidth, maxWidth, gap, false),
          );
          pending = [];
          pendingWidth = 0;
        }
        pendingWidth += (pending.isEmpty ? 0.0 : gap) + word.width;
        pending.add(word);
      }

      if (pending.isNotEmpty) {
        lines.add(
          _placeLine(paragraph, pending, pendingWidth, maxWidth, gap, true),
        );
      }
    }

    return ShapedTextBlock(
      lines: lines,
      lineHeight: lineHeight,
      width: maxWidth,
      baselineOffset: baselineOffset,
    );
  }

  List<ShapedWord> _splitWords(String paragraph) {
    final words = <ShapedWord>[];
    var offset = 0;
    for (final match in _whitespace.allMatches(paragraph)) {
      if (match.start > offset) {
        words.add(_shapeWord(paragraph, offset, match.start));
      }
      offset = match.end;
    }
    if (offset < paragraph.length) {
      words.add(_shapeWord(paragraph, offset, paragraph.length));
    }
    return words;
  }

  ShapedWord _shapeWord(String paragraph, int start, int end) {
    final text = paragraph.substring(start, end);
    final wordRtl = _directionOf(text);
    // The shaper does no bidi: a number shaped right-to-left prints reversed.
    final shapeRtl = wordRtl && !_isNumber(text);

    ShapedRun? primary;
    for (var index = 0; index < fonts.length; index++) {
      final run = fonts[index].shape(
        text,
        rtl: shapeRtl,
        script: shapeRtl ? script : '',
        language: language,
        features: features,
      );
      primary ??= run;
      if (_covers(run)) {
        return _word(run, index, start, end, wordRtl);
      }
    }

    // No font covered the word. The primary font's result keeps the text in
    // place, with a missing-glyph box wherever it has no glyph.
    return _word(primary!, 0, start, end, wordRtl);
  }

  ShapedWord _word(
    ShapedRun run,
    int fontIndex,
    int start,
    int end,
    bool wordRtl,
  ) => ShapedWord(
    run: run,
    fontIndex: fontIndex,
    logicalStart: start,
    logicalEnd: end,
    rtl: wordRtl,
    width: run.advanceAt(fontSize),
  );

  /// Glyph id zero is `.notdef`: the font has no glyph for that character.
  static bool _covers(ShapedRun run) {
    for (var index = 0; index < run.glyphCount; index++) {
      if (run.glyphId(index) == 0) {
        return false;
      }
    }
    return true;
  }

  /// A word's direction comes from its first strong character; a word of only
  /// digits and punctuation follows the paragraph.
  bool _directionOf(String text) {
    for (final rune in text.runes) {
      if (_isRtlCharacter(rune)) {
        return true;
      }
      if (_isLtrCharacter(rune)) {
        return false;
      }
    }
    return rtl;
  }

  /// A word with a digit and no strong character, such as `2026` or `06:32`.
  bool _isNumber(String text) {
    var hasDigit = false;
    for (final rune in text.runes) {
      if (_isRtlCharacter(rune) || _isLtrCharacter(rune)) return false;
      if (rune >= 0x30 && rune <= 0x39) hasDigit = true;
    }
    return hasDigit;
  }

  ShapedTextLine _placeLine(
    String paragraph,
    List<ShapedWord> words,
    double inkWidth,
    double maxWidth,
    double gap,
    bool isLastLine,
  ) {
    final ordered = _visualOrder(paragraph, words);

    var effectiveGap = gap;
    var start = 0.0;
    final slack = maxWidth - inkWidth;

    switch (align) {
      case ShapedTextAlign.justify:
        if (!isLastLine && words.length > 1 && slack > 0) {
          effectiveGap = gap + slack / (words.length - 1);
        } else {
          start = rtl ? slack : 0;
        }
      case ShapedTextAlign.start:
        start = rtl ? slack : 0;
      case ShapedTextAlign.end:
        start = rtl ? 0 : slack;
      case ShapedTextAlign.center:
        start = slack / 2;
    }

    final segments = <ShapedTextSegment>[];
    var cursor = start;
    for (var index = 0; index < ordered.length; index++) {
      if (index > 0) {
        cursor += effectiveGap;
      }
      segments.add(
        ShapedTextSegment(
          run: ordered[index].run,
          fontIndex: ordered[index].fontIndex,
          x: cursor,
        ),
      );
      cursor += ordered[index].width;
    }

    return ShapedTextLine(segments: segments, width: cursor - start);
  }

  /// Orders a line's words left to right.
  ///
  /// The bidi algorithm returns, for each visual position, the logical index
  /// that belongs there. Walking those positions and taking each word the first
  /// time one of its characters appears puts the words in visual order, which
  /// is what mixed Hebrew and Latin on one line needs.
  List<ShapedWord> _visualOrder(String paragraph, List<ShapedWord> words) {
    if (words.length < 2) {
      return words;
    }
    // All one direction: the order is the logical order, or its reverse.
    if (words.every((word) => word.rtl == words.first.rtl)) {
      return words.first.rtl ? words.reversed.toList() : words;
    }

    final lineStart = words.first.logicalStart;
    final lineEnd = words.last.logicalEnd;
    final lineText = paragraph.substring(lineStart, lineEnd);

    // The package chooses its paragraph direction from the first strong
    // character. Printed line fragments can start in English even when the
    // paragraph is RTL (or vice versa), so explicitly seed the requested base
    // direction. The mark is removed from visual output by the package.
    const rtlMark = '\u200F';
    const ltrMark = '\u200E';
    final directionMark = rtl ? rtlMark : ltrMark;
    final paragraphs =
        bidi.BidiString.fromLogical('$directionMark$lineText').paragraphs;
    if (paragraphs.isEmpty) {
      return words;
    }

    final owner = List<int>.filled(lineText.length, -1);
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      for (
        var position = word.logicalStart - lineStart;
        position < word.logicalEnd - lineStart;
        position++
      ) {
        owner[position] = index;
      }
    }

    final ordered = <ShapedWord>[];
    // Word indices are dense; a bitset-sized bool list avoids a hash set for
    // every printed line. Account for the single directional prefix code unit.
    final seen = List<bool>.filled(words.length, false);
    for (final paragraphPart in paragraphs) {
      for (final logical in paragraphPart.indices) {
        final position = logical - 1;
        if (position < 0 || position >= owner.length) {
          continue;
        }
        final index = owner[position];
        if (index >= 0 && !seen[index]) {
          seen[index] = true;
          ordered.add(words[index]);
        }
      }
    }

    // Anything the algorithm did not report keeps its logical place.
    for (var index = 0; index < words.length; index++) {
      if (!seen[index]) {
        ordered.add(words[index]);
      }
    }
    return ordered;
  }
}
