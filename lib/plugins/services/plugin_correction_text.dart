import 'dart:convert';

import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// מיפוי UTF-16 קנוני לצמתי טקסט, בלי לשנות את תגיות המקור.
class PluginCorrectionText {
  final String source;
  late final String plain;
  final List<CorrectionTextNode> nodes = [];
  late final List<({int start, int end})> tags = List.unmodifiable(
    _scanTags(source),
  );

  PluginCorrectionText(this.source) {
    final output = StringBuffer();
    var offset = 0;
    for (final tag in tags) {
      _addNode(offset, tag.start, output);
      output.write(
        TextRendererService.stripHtml(source.substring(tag.start, tag.end)),
      );
      offset = tag.end;
    }
    _addNode(offset, source.length, output);
    plain = output.toString();
  }

  static Iterable<({int start, int end})> _scanTags(String text) sync* {
    var offset = 0;
    scan:
    while (offset < text.length) {
      if (text.codeUnitAt(offset) != 60) {
        offset++;
        continue;
      }
      final start = offset;
      if (text.startsWith('<!--', offset)) {
        final end = text.indexOf('-->', offset + 4);
        if (end < 0) {
          yield (start: start, end: text.length);
          return;
        }
        offset = end + 3;
        yield (start: start, end: offset);
        continue;
      }
      var quote = 0;
      offset++;
      while (offset < text.length) {
        final unit = text.codeUnitAt(offset++);
        if (quote != 0) {
          if (unit == quote) quote = 0;
        } else if (unit == 34 || unit == 39) {
          quote = unit;
        } else if (unit == 62) {
          yield (start: start, end: offset);
          continue scan;
        }
      }
      yield (start: start, end: offset);
    }
  }

  static final _entities = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

  void _addNode(int start, int end, StringBuffer output) {
    if (start == end) return;
    final raw = source.substring(start, end);
    final boundaries = <int, int>{0: start};
    final text = StringBuffer();
    var offset = 0;
    void literal(int end) {
      while (offset < end) {
        text.write(raw[offset++]);
        boundaries[text.length] = start + offset;
      }
    }

    for (final entity in _entities.allMatches(raw)) {
      literal(entity.start);
      text.write(TextRendererService.stripHtml(entity[0]!));
      offset = entity.end;
      boundaries[text.length] = start + offset;
    }
    literal(raw.length);
    nodes.add(CorrectionTextNode(output.length, text.toString(), boundaries));
    output.write(text);
  }

  int get visibleStart => nodes.isEmpty ? 0 : nodes.first.start;
  int get visibleEnd => nodes.isEmpty ? plain.length : nodes.last.end;

  /// מחזיר שינוי בצומת יחיד; טווח עמום או חוצה תגיות אינו ניתן למיפוי.
  ({int start, int end, String replacement})? replacement(
    int start,
    int end,
    String proposed,
  ) {
    if (plain != TextRendererService.stripHtml(source)) return null;
    final full = _map(start, end, proposed);
    final original = plain.substring(start, end);
    var prefix = 0;
    while (prefix < original.length &&
        prefix < proposed.length &&
        original.codeUnitAt(prefix) == proposed.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < original.length - prefix &&
        suffix < proposed.length - prefix &&
        original.codeUnitAt(original.length - suffix - 1) ==
            proposed.codeUnitAt(proposed.length - suffix - 1)) {
      suffix++;
    }
    while (prefix > 0 && !_boundary(plain, start + prefix)) {
      prefix--;
    }
    while (suffix > 0 && !_boundary(plain, end - suffix)) {
      suffix--;
    }
    final delta = _map(
      start + prefix,
      end - suffix,
      proposed.substring(prefix, proposed.length - suffix),
      within: full == null ? null : (start: start, end: end),
    );
    if (delta == null) return null;
    // הקשר שלא השתנה נשמר בגולמי כדי לא לאבד ישויות ורווחים.
    final mapped = full == null
        ? delta
        : (
            start: full.start,
            end: full.end,
            replacement:
                source.substring(full.start, delta.start) +
                delta.replacement +
                source.substring(delta.end, full.end),
          );
    final updated = source.replaceRange(
      mapped.start,
      mapped.end,
      mapped.replacement,
    );
    if (TextRendererService.stripHtml(updated) !=
        plain.replaceRange(start, end, proposed)) {
      return null;
    }
    return mapped;
  }

  ({int start, int end, String replacement})? _map(
    int start,
    int end,
    String proposed, {
    ({int start, int end})? within,
  }) {
    final candidates = nodes.where(
      (node) =>
          node.start <= start &&
          node.end >= end &&
          (within == null ||
              node.start <= within.start && node.end >= within.end),
    );
    if (candidates.length != 1) return null;
    final node = candidates.single;
    final rawStart = node.boundaries[start - node.start];
    final rawEnd = node.boundaries[end - node.start];
    if (rawStart == null ||
        rawEnd == null ||
        !_boundary(plain, start) ||
        !_boundary(plain, end)) {
      return null;
    }
    return (
      start: rawStart,
      end: rawEnd,
      replacement: const HtmlEscape(HtmlEscapeMode.element).convert(proposed),
    );
  }

  static bool _boundary(String text, int offset) =>
      offset == 0 ||
      offset == text.length ||
      text.codeUnitAt(offset) < 0xDC00 ||
      text.codeUnitAt(offset) > 0xDFFF;
}

class CorrectionTextNode {
  final int start;
  final String text;
  final Map<int, int> boundaries;
  CorrectionTextNode(this.start, this.text, this.boundaries);
  int get end => start + text.length;
}
