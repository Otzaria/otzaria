import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

/// הדגשות לפי דרישה; רשימת עמודי האינדקס אינה הוכחה ששאר העמודים ריקים.
class PdfPageHighlights {
  PdfPageHighlights({
    required this.loadText,
    required this.onChanged,
    this.contextLength = 80,
    this.maxCachedPages = 8,
  }) : assert(maxCachedPages > 0);

  final Future<PdfPageText?> Function(int pageNumber) loadText;
  final void Function() onChanged;
  final int contextLength;
  final int maxCachedPages;
  final _pages = <int, List<PdfTextSearchResult>>{};
  final _pending = <int, Completer<List<PdfTextSearchResult>?>>{};
  final _failed = <int>{};
  Set<int> _visiblePages = {};
  int? _navigationPage;
  Completer<List<PdfTextSearchResult>?>? _running;
  int? _runningPage;
  int _generation = 0;
  bool _draining = false;
  bool _active = true;
  bool _disposed = false;
  Pattern? _pattern;

  Pattern? get pattern => _pattern;
  int get generation => _generation;
  int get cachedPageCount => _pages.length;
  int? get loadingPage => _runningPage;
  Object? error;

  List<PdfTextSearchResult>? matchesForPage(int pageNumber) {
    final matches = _pages.remove(pageNumber);
    if (matches != null) _pages[pageNumber] = matches;
    return matches;
  }

  void setPattern(Pattern? pattern) {
    if (_disposed || (_samePattern(_pattern, pattern) && error == null)) return;
    clear();
    _pattern = pattern;
  }

  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    if (!value) _cancelPending();
  }

  void setVisiblePages(Set<int> pages) {
    if (_disposed) return;
    _visiblePages = pages;
    for (final page in _pending.keys.toList()) {
      if (!pages.contains(page) && page != _navigationPage) {
        _pending.remove(page)!.complete(null);
      }
    }
    _trim();
  }

  Future<List<PdfTextSearchResult>?> ensurePage(
    int pageNumber, {
    bool forNavigation = false,
  }) {
    if (_disposed || !_active || _pattern == null || pageNumber < 1) {
      return Future.value(null);
    }
    if (forNavigation) {
      _navigationPage = pageNumber;
      _failed.remove(pageNumber);
    }
    final cached = matchesForPage(pageNumber);
    if (cached != null) return Future.value(cached);
    if (_failed.contains(pageNumber)) return Future.value(null);
    if (_runningPage == pageNumber && _running?.isCompleted == false) {
      return _running!.future;
    }
    final pending = _pending[pageNumber];
    if (pending != null) return pending.future;
    final request = _pending[pageNumber] = Completer();
    if (!_draining) unawaited(_drain());
    return request.future;
  }

  Future<void> _drain() async {
    _draining = true;
    // בקשת ציור לא מחלצת טקסט ולא מודיעה למאזינים באמצע paint.
    await Future<void>.delayed(Duration.zero);
    try {
      while (!_disposed && _active && _pending.isNotEmpty) {
        final page = _pending.containsKey(_navigationPage)
            ? _navigationPage!
            : _pending.keys.first;
        final request = _running = _pending.remove(page)!;
        _runningPage = page;
        final generation = _generation;
        final pattern = _pattern!;
        bool current() => !_disposed && _active && generation == _generation;
        try {
          final text = await loadText(page);
          if (!current()) continue;
          if (text == null) {
            _failed.add(page);
            continue;
          }
          final ranges = pattern is String || pattern is RegExp
              ? text.allMatches(pattern, caseInsensitive: true)
              : Stream.fromIterable(
                  pattern
                      .allMatches(text.fullText)
                      .where((m) => m.end > m.start)
                      .map(
                        (m) => PdfPageTextRange(
                          pageText: text,
                          start: m.start,
                          end: m.end,
                        ),
                      ),
                );
          final matches = <PdfTextSearchResult>[];
          await for (final range in ranges) {
            if (!current()) break;
            matches.add(
              PdfTextSearchResult.fromRange(
                range,
                contextLength: contextLength,
              ),
            );
            if (matches.length % 128 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
          }
          if (!current()) continue;
          final snapshot = List<PdfTextSearchResult>.unmodifiable(matches);
          _pages[page] = snapshot;
          _trim();
          request.complete(snapshot);
          onChanged();
        } catch (e) {
          if (current()) {
            error = e;
            _failed.add(page);
            onChanged();
          }
        } finally {
          if (!request.isCompleted) request.complete(null);
          _running = null;
          _runningPage = null;
        }
      }
    } finally {
      _draining = false;
    }
  }

  void _trim() {
    for (final page in _pages.keys.toList()) {
      if (_pages.length <= maxCachedPages) break;
      // כל העמודים המצוירים נשארים: תקרת LRU אינה גורמת ללולאת פינוי בזום רחוק.
      if (!_visiblePages.contains(page) && page != _navigationPage) {
        _pages.remove(page);
      }
    }
    _failed.removeWhere(
      (page) => !_visiblePages.contains(page) && page != _navigationPage,
    );
  }

  bool hasCachedPage(int pageNumber) => _pages.containsKey(pageNumber);

  void clear() {
    _cancelPending();
    _pages.clear();
    _failed.clear();
    _visiblePages = {};
    _navigationPage = null;
    error = null;
  }

  void _cancelPending() {
    _generation++;
    for (final request in _pending.values) {
      request.complete(null);
    }
    _pending.clear();
    final running = _running;
    if (running != null && !running.isCompleted) running.complete(null);
  }

  void dispose() {
    _disposed = true;
    clear();
    _pattern = null;
  }

  static bool _samePattern(Pattern? a, Pattern? b) {
    if (a is RegExp && b is RegExp) {
      return a.pattern == b.pattern &&
          a.isCaseSensitive == b.isCaseSensitive &&
          a.isMultiLine == b.isMultiLine &&
          a.isUnicode == b.isUnicode &&
          a.isDotAll == b.isDotAll;
    }
    return a == b;
  }
}
