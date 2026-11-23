import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/pdf_book/models/pdf_page_highlight_anchor.dart';
import 'package:otzaria/pdf_book/utils/pdf_page_highlights.dart';
import 'package:pdfrx/pdfrx.dart';

/// ממרכז התאמה באנימציה אחת, תוך שימור הבחירה וניהול הדור של pdfrx.
class CenteredTextSearchSession extends PdfTextSearchSession {
  CenteredTextSearchSession(
    super.controller, {
    super.contextLength,
    PdfPageHighlightAnchor? initialPageHighlight,
  }) : _pendingHighlightRestore = initialPageHighlight,
       _highlightQuery = initialPageHighlight?.query ?? '',
       super(onNavigateToMatch: _centerMatch);

  late final _pageHighlights = PdfPageHighlights(
    loadText: _loadHighlightText,
    onChanged: notifyListeners,
    contextLength: contextLength,
  );
  PdfPageHighlightAnchor? _highlightSelection;
  PdfPageHighlightAnchor? _pendingHighlightRestore;
  String _highlightQuery;
  PdfDocument? _highlightDocument;
  int? _highlightPageCount;
  int? _loadingReadyPage;
  int? _loadingGeneration;
  StreamSubscription<PdfDocumentEvent>? _highlightEvents;
  final _paintedPages = <int>{};
  bool _paintPending = false;
  bool _disposed = false;
  int _highlightNavigation = 0;

  /// ההדגשות הן לעמודים שנדרשו בלבד, ואינן מניין תוצאות של הספר כולו.
  bool get isPageHighlighting => _pageHighlights.pattern != null;

  PdfPageHighlightAnchor? get pageHighlightAnchor =>
      _highlightSelection ?? _pendingHighlightRestore;

  void startPageHighlights(Pattern? pattern, {String query = ''}) {
    if (_disposed) return;
    _observeHighlightDocument();
    if (_pendingHighlightRestore?.query != query) {
      _pendingHighlightRestore = null;
    }
    final generation = _pageHighlights.generation;
    if (_highlightQuery != query) _pageHighlights.clear();
    _highlightQuery = query;
    final wasHighlighting = isPageHighlighting;
    _pageHighlights.setPattern(pattern);
    if (generation == _pageHighlights.generation &&
        (pattern != null || super.pattern == null)) {
      return;
    }
    _highlightSelection = null;
    if (wasHighlighting) _pendingHighlightRestore = null;
    _highlightNavigation++;
    super.resetTextSearch();
    if (pattern != null) {
      _observeHighlightDocument();
      if (_pendingHighlightRestore != null) {
        unawaited(_restorePageHighlight());
      } else {
        final page = controller?.pageNumber;
        if (page != null) unawaited(ensurePageHighlights(page));
      }
    }
  }

  Future<void> _restorePageHighlight() async {
    final anchor = _pendingHighlightRestore;
    if (anchor == null || !isActive || !isPageHighlighting) return;
    final generation = _pageHighlights.generation;
    final matches = await ensurePageHighlights(
      anchor.pageNumber,
      forNavigation: true,
    );
    if (_disposed ||
        !isActive ||
        generation != _pageHighlights.generation ||
        !identical(anchor, _pendingHighlightRestore)) {
      return;
    }
    _pendingHighlightRestore = null;
    _highlightSelection =
        matches?.any(
              (match) => match.start == anchor.start && match.end == anchor.end,
            ) ==
            true
        ? anchor
        : null;
    notifyListeners();
  }

  void discardPageHighlightSelection() {
    _highlightSelection = null;
    _pendingHighlightRestore = null;
    _highlightNavigation++;
  }

  List<PdfTextSearchResult>? pageHighlights(int pageNumber) {
    if (_disposed) return null;

    _observeHighlightDocument();
    return _pageHighlights.matchesForPage(pageNumber);
  }

  void cancelPageHighlightNavigation() => _highlightNavigation++;

  Future<PdfPageText?> _loadHighlightText(int page) {
    final document = controller?.document;
    _loadingReadyPage =
        document != null &&
            page <= document.pages.length &&
            document.pages[page - 1].isLoaded
        ? page
        : null;
    _loadingGeneration = _pageHighlights.generation;
    return loadText(pageNumber: page);
  }

  Future<List<PdfTextSearchResult>?> ensurePageHighlights(
    int pageNumber, {
    bool forNavigation = false,
  }) {
    final document = controller?.document;
    if (document == null ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return Future.value(null);
    }
    _observeHighlightDocument();
    return _pageHighlights.ensurePage(pageNumber, forNavigation: forNavigation);
  }

  void _observeHighlightDocument() {
    final document = controller?.document;
    if (identical(document, _highlightDocument)) return;
    _highlightEvents?.cancel();
    if (_highlightDocument != null) {
      _pageHighlights.clear();
      discardPageHighlightSelection();
    }
    _highlightDocument = document;
    _highlightPageCount = document?.pages.length;
    if (document == null) return;
    final restorePage = _pendingHighlightRestore?.pageNumber;
    var restorePageLoaded =
        restorePage != null &&
        restorePage >= 1 &&
        restorePage <= document.pages.length &&
        document.pages[restorePage - 1].isLoaded;
    _highlightEvents = document.events.listen((event) {
      if (_disposed) return;
      bool affects(int page) =>
          _pageHighlights.hasCachedPage(page) ||
          _highlightSelection?.pageNumber == page ||
          (_pendingHighlightRestore?.pageNumber == page && restorePageLoaded) ||
          (_pageHighlights.loadingPage == page &&
              _loadingReadyPage == page &&
              _loadingGeneration == _pageHighlights.generation);
      if (isPageHighlighting &&
          event is PdfDocumentPageStatusChangedEvent &&
          (document.pages.length != _highlightPageCount ||
              event.changes.keys.any(affects) ||
              event.changes.values.whereType<PdfPageStatusMoved>().any(
                (change) => affects(change.oldPageNumber),
              ))) {
        _highlightPageCount = document.pages.length;
        _pageHighlights.clear();
        discardPageHighlightSelection();
        notifyListeners();
      }
      // metadata ראשונית אינה שינוי בתוכן שנבחר; שינוי נוסף כבר פוסל את העוגן.
      if (restorePage != null &&
          restorePage >= 1 &&
          restorePage <= document.pages.length &&
          document.pages[restorePage - 1].isLoaded) {
        restorePageLoaded = true;
      }
    });
  }

  Future<void> goToPageHighlight(PdfTextSearchResult match) async {
    final viewer = controller;
    if (viewer == null || !isActive || !isPageHighlighting) return;
    final navigation = ++_highlightNavigation;
    final generation = _pageHighlights.generation;
    _pendingHighlightRestore = null;
    _highlightSelection = PdfPageHighlightAnchor(
      pageNumber: match.pageNumber,
      start: match.start,
      end: match.end,
      query: _highlightQuery,
    );
    await _centerMatch(viewer, match);
    if (_disposed ||
        !isActive ||
        navigation != _highlightNavigation ||
        generation != _pageHighlights.generation) {
      return;
    }
    viewer.setCurrentPageNumber(match.pageNumber);
    notifyListeners();
  }

  /// קיצור הבא/הקודם מחפש מעבר לעמוד הנוכחי רק כשהמשתמש מבקש לעבור.
  Future<void> navigatePageHighlight({
    required bool forward,
    ValueChanged<int>? beforeNavigate,
  }) async {
    final viewer = controller;
    if (viewer == null || !isPageHighlighting || !isActive) return;
    final navigation = ++_highlightNavigation;
    final generation = _pageHighlights.generation;
    await _restorePageHighlight();
    if (_disposed ||
        !isActive ||
        navigation != _highlightNavigation ||
        generation != _pageHighlights.generation) {
      return;
    }
    final selected = _highlightSelection;
    var page =
        selected?.pageNumber ?? (forward ? 1 : viewer.document.pages.length);
    while (page >= 1 && page <= viewer.document.pages.length) {
      final matches = await ensurePageHighlights(page, forNavigation: true);
      if (_disposed ||
          !isActive ||
          navigation != _highlightNavigation ||
          generation != _pageHighlights.generation) {
        return;
      }
      if (matches == null) return;
      final candidates = forward ? matches : matches.reversed;
      for (final match in candidates) {
        if (selected != null &&
            page == selected.pageNumber &&
            (forward
                ? match.start <= selected.start
                : match.start >= selected.start)) {
          continue;
        }
        beforeNavigate?.call(page);
        await goToPageHighlight(match);
        return;
      }
      page += forward ? 1 : -1;
    }
  }

  @override
  void pageTextMatchPaintCallback(Canvas canvas, Rect pageRect, PdfPage page) {
    if (!isPageHighlighting) {
      super.pageTextMatchPaintCallback(canvas, pageRect, page);
      return;
    }
    if (!isActive || _disposed) return;
    _paintedPages.add(page.pageNumber);
    if (!_paintPending) {
      _paintPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _paintPending = false;
        if (_disposed) return;
        _pageHighlights.setVisiblePages(Set.of(_paintedPages));
        _paintedPages.clear();
      });
    }
    final matches = pageHighlights(page.pageNumber);
    if (matches == null) {
      unawaited(ensurePageHighlights(page.pageNumber));
      return;
    }
    final params = controller?.params;
    final selection = _highlightSelection;
    for (final match in matches) {
      final isSelected =
          selection != null &&
          match.pageNumber == selection.pageNumber &&
          match.start == selection.start &&
          match.end == selection.end;
      final color = isSelected
          ? params?.activeMatchTextColor
          : params?.matchTextColor;
      if (color == null) continue;
      final paint = Paint()..color = color;
      for (final bounds in match.rects) {
        canvas.drawRect(
          bounds
              .toRect(page: page, scaledPageSize: pageRect.size)
              .translate(pageRect.left, pageRect.top),
          paint,
        );
      }
    }
  }

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
    int? startPageNumber,
  }) {
    _pageHighlights.setPattern(null);
    discardPageHighlightSelection();
    super.startTextSearch(
      pattern,
      caseInsensitive: caseInsensitive,
      goToFirstMatch: goToFirstMatch,
      searchImmediately: searchImmediately,
      startPageNumber: startPageNumber,
    );
  }

  @override
  void resetTextSearch() {
    _pageHighlights.setPattern(null);
    discardPageHighlightSelection();
    super.resetTextSearch();
  }

  @override
  set isActive(bool value) {
    _pageHighlights.setActive(value);
    if (!value) _highlightNavigation++;
    super.isActive = value;
    if (value) unawaited(_restorePageHighlight());
  }

  @override
  void releaseCachedText() {
    _pageHighlights.clear();
    _highlightNavigation++;
    super.releaseCachedText();
  }

  @override
  void dispose() {
    _disposed = true;
    _highlightEvents?.cancel();
    _pageHighlights.dispose();
    super.dispose();
  }

  static Future<void> _centerMatch(
    PdfViewerController controller,
    PdfTextSearchResult match,
  ) {
    final rect = controller.calcRectForRectInsidePage(
      pageNumber: match.pageNumber,
      rect: match.bounds,
    );
    return controller.goTo(controller.calcMatrixFor(rect.center));
  }
}
