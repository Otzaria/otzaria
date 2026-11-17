import 'package:otzaria/models/links.dart';

/// חיפוש לפי טווח שורות כולל, ברשימה ממוינת לפי שורת המקור.
final class PdfLinkRangeIndex {
  PdfLinkRangeIndex(this._links);

  static const _maxCachedSpans = 64;

  final List<Link> _links;
  List<Link>? _spans = [];
  int _scannedLength = 0;
  ({int first, int last})? _previousRange;
  List<Link> _previousMatches = const [];

  List<Link> overlapping(int first, int last) {
    final range = (first: first, last: last);
    if (_previousRange == range) return _previousMatches;

    final matches = <Link>[];
    final spans = _spans;
    if (spans == null) {
      _scan(0, first, last, matches);
    } else {
      _collect(spans, first, last, matches);
    }
    _previousRange = range;
    return _previousMatches = matches;
  }

  void _collect(List<Link> spans, int first, int last, List<Link> matches) {
    var low = 0;
    var high = _scannedLength;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_links[middle].index1 < first) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    // רק עוגנים משתרעים יכולים לחפוף לטווח מתוך הקידומת שעליה דילגנו.
    for (final link in spans) {
      if (link.index1 >= first || link.index1 > last) break;
      if (link.index1End! >= first) matches.add(link);
    }

    final length = _links.length;
    var i = low;
    for (; i < length; i++) {
      final link = _links[i];
      final start = link.index1;
      if (start > last) break;
      final end = link.index1End;
      if ((end ?? start) >= first) matches.add(link);
      if (end != null && end > start && i >= _scannedLength) {
        // עם עוגנים רבים, סריקה ישירה חוסכת רשימת קישורים נוספת.
        if (spans.length == _maxCachedSpans) {
          _spans = null;
          _scan(i + 1, first, last, matches);
          return;
        }
        spans.add(link);
      }
    }
    if (i > _scannedLength) _scannedLength = i;
  }

  void _scan(int start, int first, int last, List<Link> matches) {
    final length = _links.length;
    for (var i = start; i < length; i++) {
      final link = _links[i];
      if (link.index1 > last) break;
      if (link.overlapsSourceLines(first, last)) matches.add(link);
    }
  }
}
