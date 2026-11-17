/// סדר תוצאות המנוע בתוך עמוד ובין תוצאות בעלות אותו רצף, לפי זהות האובייקט.
final class PdfEngineResultOrdinals<T extends Object> {
  PdfEngineResultOrdinals(
    this._results, {
    required this._pageOf,
    required this._spanOf,
  });

  // התוצאות ממוינות לפי עמוד ונשארות קבועות במשך חיי האינדקס.
  final List<T> _results;
  final int Function(T) _pageOf;
  final String? Function(T) _spanOf;
  final _pages = <int, _PageOrdinals<T>>{};
  final _spans = Map<T, String?>.identity();

  ({int offset, String? span, int spanOffset}) positionOf(T result, int page) {
    final positions = _pages.putIfAbsent(page, () {
      final start = _firstResultAtOrAfter(page);
      final end = _firstResultAtOrAfter(page + 1);
      final offsets = Map<T, int>.identity();
      for (var i = start; i < end; i++) {
        offsets.putIfAbsent(_results[i], () => i - start);
      }
      return _PageOrdinals(start, end - start, offsets);
    });
    final offset = positions.offsets[result] ?? positions.count;
    final span = _span(result);
    if (span == null) return (offset: offset, span: null, spanOffset: 0);

    final spanOffsets = positions.spanOffsets;
    final counts = positions.spanCounts;
    // מפענחים רק את הקידומת הנדרשת. לחיצה חוזרת משתמשת במונים שכבר חושבו.
    while (spanOffsets.length < offset) {
      final previous = _span(_results[positions.start + spanOffsets.length]);
      final previousCount = counts[previous] ?? 0;
      spanOffsets.add(previousCount);
      if (previous != null) counts[previous] = previousCount + 1;
    }
    final spanOffset = offset < spanOffsets.length
        ? spanOffsets[offset]
        : counts[span] ?? 0;
    return (offset: offset, span: span, spanOffset: spanOffset);
  }

  String? _span(T result) => _spans.putIfAbsent(result, () => _spanOf(result));

  int _firstResultAtOrAfter(int page) {
    var low = 0;
    var high = _results.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_pageOf(_results[middle]) < page) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

final class _PageOrdinals<T extends Object> {
  _PageOrdinals(this.start, this.count, this.offsets);

  final int start;
  final int count;
  final Map<T, int> offsets;
  final spanOffsets = <int>[];
  final spanCounts = <String, int>{};
}
