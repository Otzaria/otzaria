import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';

typedef MarkerWord = ({int start, int end});

/// עריכת גבולות של סימון במילים שלמות: התחלת המקטע הראשון וסוף המקטע
/// האחרון זזים, ומה שביניהם נשאר. המיקומים ביחידות grapheme של המקור.
class MarkerRangeEdit {
  MarkerRangeEdit({
    required this.mark,
    required String firstSource,
    required String lastSource,
  }) : first = firstSource.characters.toList(growable: false),
       last = lastSource.characters.toList(growable: false),
       _firstSource = firstSource,
       _lastSource = lastSource,
       start = mark.segments.first.start,
       end = mark.segments.last.end {
    firstWords = _words(first);
    lastWords = single ? firstWords : _words(last);
  }

  final MarkerHighlight mark;
  final List<String> first;
  final List<String> last;
  final String _firstSource;
  final String _lastSource;
  late final List<MarkerWord> firstWords;
  late final List<MarkerWord> lastWords;

  /// התחלת הסימון במקטע הראשון.
  int start;

  /// סוף הסימון (לא כולל) במקטע האחרון.
  int end;

  bool get single => mark.segments.length == 1;

  /// הגבול הפנימי שהתחלה אינה עוברת: סוף הסימון, או סוף המקטע הראשון.
  int get _startLimit => single ? end : mark.segments.first.end;
  int get _endLimit => single ? start : mark.segments.last.start;

  bool get isValid =>
      start >= 0 &&
      end <= last.length &&
      mark.segments.first.end <= first.length &&
      mark.segments.last.start <= last.length &&
      start < _startLimit &&
      _endLimit < end &&
      _hasText(first, start, _startLimit) &&
      _hasText(last, _endLimit, end);

  bool get changed =>
      start != mark.segments.first.start || end != mark.segments.last.end;

  int? get _growStart => _lastWhere(firstWords, (w) => w.start < start)?.start;
  int? get _shrinkStart {
    final next = _firstWhere(firstWords, (w) => w.start > start)?.start;
    return next != null && _hasText(first, next, _startLimit) ? next : null;
  }

  int? get _growEnd => _firstWhere(lastWords, (w) => w.end > end)?.end;
  int? get _shrinkEnd {
    final previous = _lastWhere(lastWords, (w) => w.end < end)?.end;
    return previous != null && _hasText(last, _endLimit, previous)
        ? previous
        : null;
  }

  bool get canGrowStart => _growStart != null;
  bool get canShrinkStart => _shrinkStart != null;
  bool get canGrowEnd => _growEnd != null;
  bool get canShrinkEnd => _shrinkEnd != null;

  void growStart() => start = _growStart ?? start;
  void shrinkStart() => start = _shrinkStart ?? start;
  void growEnd() => end = _growEnd ?? end;
  void shrinkEnd() => end = _shrinkEnd ?? end;

  /// חזרה לגבולות שהסימון נשמר בהם.
  void reset() {
    start = mark.segments.first.start;
    end = mark.segments.last.end;
  }

  /// המילה שהסימון מתחיל בה ([start]) או מסתיים בה (אחרת).
  MarkerWord? edgeWord({required bool start}) => start
      ? _firstWhere(firstWords, (w) => w.end > this.start)
      : _lastWhere(lastWords, (w) => w.start < end);

  /// המילים שהסימון מכסה, לסרגל הגרירה. רק לסימון בפסקה אחת.
  ({int first, int last}) get wordSpan {
    final from = firstWords.indexWhere((w) => w.end > start);
    final to = firstWords.lastIndexWhere((w) => w.start < end);
    return (
      first: from < 0 ? 0 : from,
      last: to < 0 ? firstWords.length - 1 : to,
    );
  }

  void setWordSpan(int from, int to) {
    if (!single || firstWords.isEmpty) return;
    final a = from.clamp(0, firstWords.length - 1);
    final b = to.clamp(a, firstWords.length - 1);
    start = firstWords[a].start;
    end = firstWords[b].end;
  }

  /// המקטעים החדשים, או null כשאי אפשר לעגן אותם.
  List<MarkerSegment>? buildSegments() {
    if (!isValid) return null;
    const service = ReaderSelectionService();
    final segments = [...mark.segments];
    MarkerSegment? rebuilt(MarkerSegment segment, String source, int s, int e) {
      final range = service.buildRangeAnchor(
        text: source,
        startGrapheme: s,
        endGrapheme: e,
        layer: 'source',
        sourceTextHash: sha256.convert(utf8.encode(source)).toString(),
      );
      return range == null
          ? null
          : segment.copyWith(range: range, status: MarkerAnchorStatus.active);
    }

    final head = rebuilt(
      segments.first,
      _firstSource,
      start,
      single ? end : segments.first.end,
    );
    if (head == null) return null;
    segments[0] = head;
    if (!single) {
      final tail = rebuilt(
        segments.last,
        _lastSource,
        segments.last.start,
        end,
      );
      if (tail == null) return null;
      segments[segments.length - 1] = tail;
    }
    return segments;
  }

  /// הטקסט המוצג ברשימה, כמו בסימון חדש.
  static String textOf(List<MarkerSegment> segments) => segments
      .map((segment) => segment.range.exactText)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<MarkerWord> _words(List<String> chars) {
    final words = <MarkerWord>[];
    int? from;
    for (var i = 0; i <= chars.length; i++) {
      final space = i == chars.length || chars[i].trim().isEmpty;
      if (!space) {
        from ??= i;
      } else if (from != null) {
        words.add((start: from, end: i));
        from = null;
      }
    }
    return words;
  }

  static bool _hasText(List<String> chars, int from, int to) {
    for (var i = from; i < to && i < chars.length; i++) {
      if (i >= 0 && chars[i].trim().isNotEmpty) return true;
    }
    return false;
  }

  static MarkerWord? _firstWhere(
    List<MarkerWord> words,
    bool Function(MarkerWord) test,
  ) {
    for (final word in words) {
      if (test(word)) return word;
    }
    return null;
  }

  static MarkerWord? _lastWhere(
    List<MarkerWord> words,
    bool Function(MarkerWord) test,
  ) {
    for (final word in words.reversed) {
      if (test(word)) return word;
    }
    return null;
  }
}
