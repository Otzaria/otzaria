import 'dart:collection';

import 'package:pdfrx/pdfrx.dart';

/// תוצאות והקשרים נוצרים רק כשהחלונית מבקשת אותם, ונשמרים לאורך אותו חיפוש.
class PdfSearchResultList<T extends Object> extends ListBase<T> {
  PdfSearchResultList(this._createResult);

  final T Function(PdfTextSearchResult match, int id) _createResult;
  List<PdfTextSearchResult> _matches = const [];
  Expando<T> _results = Expando<T>();
  Expando<PdfTextSearchResult> _resultMatches = Expando<PdfTextSearchResult>();
  int _nextId = 0;
  int? _generation;
  List<_PageBatch> _pages = const [];
  List<int> _pageEnds = const [];
  List<int> _groupEnds = const [];
  late final List<Object> groupedItems = _GroupedResults(this);

  void update(List<PdfTextSearchResult> matches, {required int generation}) {
    if (_generation != generation) {
      reset();
      _generation = generation;
    }
    if (identical(_matches, matches)) return;
    final previous = {for (final page in _pages) page.number: page};
    final pages = <_PageBatch>[];
    final pageEnds = <int>[];
    final groupEnds = <int>[];
    for (var start = 0; start < matches.length;) {
      final first = matches[start];
      final cached = previous[first.pageNumber];
      var end = start + (cached?.count ?? 0);
      final reuse =
          cached != null &&
          identical(cached.first, first) &&
          end <= matches.length &&
          identical(cached.last, matches[end - 1]) &&
          (end == matches.length ||
              matches[end].pageNumber != first.pageNumber);
      if (!reuse) {
        end = _pageEnd(matches, start);
      }
      pages.add(
        reuse ? cached : _PageBatch(first, matches[end - 1], end - start),
      );
      pageEnds.add(end);
      groupEnds.add(end + pages.length);
      start = end;
    }
    _matches = matches;
    _pages = pages;
    _pageEnds = pageEnds;
    _groupEnds = groupEnds;
  }

  void reset() {
    _matches = const [];
    _pages = const [];
    _pageEnds = const [];
    _groupEnds = const [];
    _results = Expando<T>();
    _resultMatches = Expando<PdfTextSearchResult>();
    _nextId = 0;
    _generation = null;
  }

  /// אינדקס ההתאמה הנוכחי עשוי להשתנות כשעמודים קודמים מתווספים אחרי wrap.
  int? matchIndexOf(T result, List<PdfTextSearchResult> currentMatches) {
    final match = _resultMatches[result];
    if (match == null) return null;
    var low = 0;
    var high = currentMatches.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final candidate = currentMatches[mid];
      if (candidate.pageNumber < match.pageNumber ||
          (candidate.pageNumber == match.pageNumber &&
              candidate.start < match.start)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < currentMatches.length; i++) {
      final candidate = currentMatches[i];
      if (candidate.pageNumber != match.pageNumber ||
          candidate.start != match.start) {
        break;
      }
      if (identical(candidate, match)) return i;
    }
    return null;
  }

  int visualIndexForPage(int pageNumber) {
    if (_pages.isEmpty) return 0;
    var low = 0;
    var high = _pages.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_pages[mid].number < pageNumber) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final page = low.clamp(0, _pages.length - 1);
    return page == 0 ? 0 : _groupEnds[page - 1];
  }

  @override
  int get length => _matches.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Search results are read-only.');

  @override
  T operator [](int index) {
    final match = _matches[index];
    final cached = _results[match];
    if (cached != null) return cached;
    final result = _createResult(match, _nextId++);
    _results[match] = result;
    _resultMatches[result] = match;
    return result;
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Search results are read-only.');

  static int _pageEnd(List<PdfTextSearchResult> matches, int start) {
    final page = matches[start].pageNumber;
    var low = start + 1;
    var high = matches.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (matches[mid].pageNumber == page) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

class _PageBatch {
  const _PageBatch(this.first, this.last, this.count);

  final PdfTextSearchResult first;
  final PdfTextSearchResult last;
  final int count;
  int get number => first.pageNumber;
}

class _GroupedResults<T extends Object> extends ListBase<Object> {
  _GroupedResults(this._results);

  final PdfSearchResultList<T> _results;

  @override
  int get length => _results.length + _results._pages.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Search groups are read-only.');

  @override
  Object operator [](int index) {
    RangeError.checkValidIndex(index, this);
    var low = 0;
    var high = _results._pages.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_results._groupEnds[mid] <= index) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final offset = index - (low == 0 ? 0 : _results._groupEnds[low - 1]);
    if (offset == 0) return _results._pages[low].number;
    final matchStart = low == 0 ? 0 : _results._pageEnds[low - 1];
    return _results[matchStart + offset - 1];
  }

  @override
  void operator []=(int index, Object value) =>
      throw UnsupportedError('Search groups are read-only.');
}
