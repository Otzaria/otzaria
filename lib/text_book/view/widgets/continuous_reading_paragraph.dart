import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ContinuousReadingParagraphLine {
  final int lineIndex;
  final String text;
  final TextStyle style;

  const ContinuousReadingParagraphLine({
    required this.lineIndex,
    required this.text,
    required this.style,
  });
}

class ContinuousReadingParagraph extends StatefulWidget {
  final List<ContinuousReadingParagraphLine> lines;
  final TextStyle baseStyle;
  final ValueChanged<int> onLineTap;
  final TextDirection textDirection;
  final TextAlign textAlign;

  const ContinuousReadingParagraph({
    super.key,
    required this.lines,
    required this.baseStyle,
    required this.onLineTap,
    this.textDirection = TextDirection.rtl,
    this.textAlign = TextAlign.justify,
  });

  @override
  State<ContinuousReadingParagraph> createState() =>
      _ContinuousReadingParagraphState();
}

class _ContinuousReadingParagraphState
    extends State<ContinuousReadingParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(covariant ContinuousReadingParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameLineOrder(oldWidget.lines, widget.lines)) {
      _rebuildRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final hasNext = i < widget.lines.length - 1;
      spans.add(
        TextSpan(
          text: hasNext ? '${line.text} ' : line.text,
          style: line.style,
          recognizer: _recognizers[i],
        ),
      );
    }

    return Text.rich(
      TextSpan(style: widget.baseStyle, children: spans),
      textDirection: widget.textDirection,
      textAlign: widget.textAlign,
    );
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();
    for (var i = 0; i < widget.lines.length; i++) {
      _recognizers.add(
        TapGestureRecognizer()
          ..onTap = () => widget.onLineTap(widget.lines[i].lineIndex),
      );
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  bool _sameLineOrder(
    List<ContinuousReadingParagraphLine> oldLines,
    List<ContinuousReadingParagraphLine> newLines,
  ) {
    if (oldLines.length != newLines.length) {
      return false;
    }
    for (var i = 0; i < oldLines.length; i++) {
      if (oldLines[i].lineIndex != newLines[i].lineIndex) {
        return false;
      }
    }
    return true;
  }
}
