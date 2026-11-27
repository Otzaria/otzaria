import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// מיפוי UTF-16 קנוני לצמתי טקסט, בלי לשנות את תגיות המקור.
class PluginCorrectionText {
  final String source;
  late final String plain;
  final List<CorrectionTextNode> nodes = [];
  final List<int> _droppedEntities = [];
  late final List<String> _markup = [];
  late final List<CorrectionHtmlOrigin> htmlOrigins = [];
  late final List<({int start, int end})> tags = List.unmodifiable(
    _scanTags(source),
  );

  PluginCorrectionText(this.source, {bool trackHtml = false}) {
    final trackMarkup = trackHtml && hasMarkup;
    final output = StringBuffer();
    var offset = 0;
    for (final tag in tags) {
      _addNode(offset, tag.start, output, trackHtml: trackMarkup);
      final markup = source.substring(tag.start, tag.end);
      final separator = TextRendererService.stripHtml(markup);
      if (trackMarkup) {
        final slot = _markup.length;
        _markup.add(markup);
        htmlOrigins.addAll(
          List.filled(separator.length, (slot: slot, spelling: const ('', 1))),
        );
      }
      output.write(separator);
      offset = tag.end;
    }
    _addNode(offset, source.length, output, trackHtml: trackMarkup);
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

  void _addNode(
    int start,
    int end,
    StringBuffer output, {
    required bool trackHtml,
  }) {
    if (start == end) return;
    final raw = source.substring(start, end);
    final boundaries = <int, int>{0: start};
    final text = StringBuffer();
    var offset = 0;
    void literal(int end) {
      if (end == offset) return;
      final slot = trackHtml ? _markup.length : -1;
      final CorrectionHtmlOrigin? origin = trackHtml
          ? (slot: slot, spelling: null)
          : null;
      if (trackHtml) _markup.add('');
      while (offset < end) {
        final char = raw[offset++];
        text.write(char);
        boundaries[text.length] = start + offset;
        if (trackHtml) {
          htmlOrigins.add(
            char == '&' || char == '>'
                ? (slot: slot, spelling: (char, 1))
                : origin!,
          );
        }
      }
    }

    for (final entity in _entities.allMatches(raw)) {
      literal(entity.start);
      final decoded = TextRendererService.stripHtml(entity[0]!);
      // ישות שהפענוח מוחק (כמו &copy;) מוצגת בקורא, אך אין לה היסט קנוני:
      // טווח שנוגע בה אינו מכריע אם היא נבחרה.
      if (decoded.isEmpty) {
        _droppedEntities.add(output.length + text.length);
        if (trackHtml) _markup.add(entity[0]!);
      } else if (trackHtml) {
        final origin = (
          slot: _markup.length,
          spelling: (entity[0]!, decoded.length),
        );
        _markup.add('');
        htmlOrigins.addAll(List.filled(decoded.length, origin));
      }
      text.write(decoded);
      offset = entity.end;
      boundaries[text.length] = start + offset;
    }
    literal(raw.length);
    nodes.add(CorrectionTextNode(output.length, text.toString(), boundaries));
    output.write(text);
  }

  /// משחזר את תגיות המקור לאיתור התאמות, וממפה אותן להיסטים הקנוניים.
  ({String html, List<int> offsets}) searchHtml(
    String text,
    List<CorrectionHtmlOrigin?> origins,
  ) {
    final html = StringBuffer();
    final offsets = <int>[];
    void write(String value, int offset, [int units = 1]) {
      html.write(value);
      for (var i = 0; i < value.length; i++) {
        offsets.add(offset + i * units ~/ value.length);
      }
    }

    var slot = 0;
    for (var i = 0; i < text.length;) {
      final origin = origins[i];
      if (origin == ambiguousCorrectionOrigin) {
        // תו חסר שיוך משאיר גבול בלי לייחס התאמה למופע הלא נכון.
        write('\uFFFC', -1);
        i++;
        continue;
      }
      final target = origin?.slot ?? (slot == 0 ? 0 : slot - 1);
      while (slot <= target && slot < _markup.length) {
        write(_markup[slot++], -1);
      }
      final spelling = origin?.spelling;
      if (spelling != null &&
          i + spelling.$2 <= text.length &&
          (spelling.$2 == 1 || origins[i + 1] == origin)) {
        write(spelling.$1, i, spelling.$2);
        i += spelling.$2;
      } else {
        final char = text[i];
        write(switch (char) {
          '&' => '&amp;',
          '<' => '&lt;',
          '>' => '&gt;',
          _ => char,
        }, i);
        i++;
      }
    }
    while (slot < _markup.length) {
      write(_markup[slot++], -1);
    }
    return (html: html.toString(), offsets: offsets);
  }

  late final bool hasMarkup =
      tags.isNotEmpty || source.contains('&') || source.contains('>');

  late final Set<CorrectionHtmlOrigin> _sourceOrigins = htmlOrigins.toSet();
  late final Set<int> _sourceSlots = _sourceOrigins
      .map((origin) => origin.slot)
      .toSet();
  late final Map<int, (String, int)> _encodedSlots = {
    for (final origin in _sourceOrigins)
      if (origin.spelling case final spelling?)
        if (spelling.$1 != '&' && spelling.$1 != '>') origin.slot: spelling,
  };

  /// מקודד רצפי צמתים ביחס למקור הזה, לשימוש בטיוטה המקומית.
  List<int>? encodeOrigins(
    Iterable<({int end, CorrectionHtmlOrigin? origin})> runs,
  ) {
    if (!hasMarkup) return null;
    return [
      for (final run in runs) ...[
        run.end,
        run.origin?.slot ?? -2,
        switch (run.origin?.spelling?.$1) {
          null => 0,
          '&' => 1,
          '>' => 2,
          _ => 3,
        },
      ],
    ];
  }

  /// מחזיר את שיוך התווים שנשמר בטיוטה, לאחר בדיקה מול צמתי המקור.
  List<CorrectionHtmlOrigin?>? restoreOrigins(String text, List<int>? runs) {
    if (runs == null || runs.length % 3 != 0) return null;
    final result = <CorrectionHtmlOrigin?>[];
    var previousSlot = 0;
    for (var i = 0; i < runs.length; i += 3) {
      final end = runs[i];
      final slot = runs[i + 1];
      final spellingCode = runs[i + 2];
      final start = result.length;
      if (end <= start ||
          end > text.length ||
          slot >= _markup.length ||
          slot < -2 ||
          (slot >= 0 && slot < previousSlot)) {
        return null;
      }
      if (slot < 0) {
        if (spellingCode != 0) return null;
        result.addAll(
          List.filled(
            end - start,
            slot == -1 ? ambiguousCorrectionOrigin : null,
          ),
        );
        continue;
      }
      if (!_sourceSlots.contains(slot)) return null;
      previousSlot = slot;
      final spelling = switch (spellingCode) {
        0 => null,
        1 => const ('&', 1),
        2 => const ('>', 1),
        3 => _encodedSlots[slot],
        _ => null,
      };
      final origin = (slot: slot, spelling: spelling);
      if (spellingCode != 0) {
        if (spelling == null || !_sourceOrigins.contains(origin)) return null;
        final decoded = spelling.$1.isEmpty
            ? ' '
            : TextRendererService.stripHtml(spelling.$1);
        if (decoded.isEmpty || (end - start) % decoded.length != 0) return null;
        for (var offset = start; offset < end; offset += decoded.length) {
          if (!text.startsWith(decoded, offset)) return null;
        }
      }
      result.addAll(List.filled(end - start, origin));
    }
    return result.length == text.length ? result : null;
  }

  int get visibleStart => nodes.isEmpty ? 0 : nodes.first.start;
  int get visibleEnd => nodes.isEmpty ? plain.length : nodes.last.end;

  /// מחזיר שינוי בצומת יחיד; טווח עמום או חוצה תגיות אינו ניתן למיפוי.
  ({int start, int end, String replacement})? replacement(
    int start,
    int end,
    String proposed,
  ) {
    if (plain != TextRendererService.stripHtml(source) ||
        _droppedEntities.any((offset) => offset >= start && offset <= end)) {
      return null;
    }
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
    final insertedEnd = delta.start + delta.replacement.length;
    if (TextRendererService.stripHtml(updated) !=
            plain.replaceRange(start, end, proposed) ||
        !_keepsDisplay(source, [
          mapped.start,
          delta.start,
          delta.end,
          mapped.end,
        ]) ||
        !_keepsDisplay(updated, [
          mapped.start,
          delta.start,
          insertedEnd,
          mapped.start + mapped.replacement.length,
        ])) {
      return null;
    }
    return mapped;
  }

  // פרסר HTML5 של הקורא מפענח גם ישויות בלי `;` (`&copy`), שהפענוח הקנוני
  // אינו מכיר: חיתוך במקור או בתוצאה אסור שישנה את מה שמוצג.
  static bool _keepsDisplay(String html, List<int> cuts) {
    final pieces = StringBuffer();
    var previous = 0;
    for (final cut in cuts) {
      pieces.write(_displayed(html.substring(previous, cut)));
      previous = cut;
    }
    pieces.write(_displayed(html.substring(previous)));
    return pieces.toString() == _displayed(html);
  }

  static String _displayed(String html) =>
      html_parser.parseFragment(html).text ?? '';

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

/// צומת ה-HTML והאיות הגולמי של ישות שנשמרו לאחר עריכה.
typedef CorrectionHtmlOrigin = ({int slot, (String, int)? spelling});

const CorrectionHtmlOrigin ambiguousCorrectionOrigin = (
  slot: -1,
  spelling: null,
);
