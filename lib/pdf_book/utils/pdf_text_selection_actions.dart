import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

enum PdfTextActionResult { none, copied, loading, failed }

class PdfTextSelectionActions {
  PdfTextSelectionActions(this.controller, {required this.isActive});

  final PdfViewerController controller;
  final bool Function() isActive;
  int _generation = 0;

  void cancel() => _generation++;

  bool _isCurrent(
    int generation,
    PdfDocument document,
    PdfTextSelectionRange? range,
  ) {
    if (generation != _generation ||
        !isActive() ||
        !controller.isReady ||
        !identical(controller.document, document)) {
      return false;
    }
    final selection = controller.textSelectionDelegate;
    final current = selection.textSelectionPointRange;
    return selection.isTextSelectionEnabled &&
        current?.start == range?.start &&
        current?.end == range?.end;
  }

  Future<PdfTextActionResult> copy({bool keepSelection = false}) async {
    final generation = ++_generation;
    if (!isActive() || !controller.isReady) return PdfTextActionResult.none;
    final document = controller.document;
    final selection = controller.textSelectionDelegate;
    final range = selection.textSelectionPointRange;
    if (range == null || !selection.isCopyAllowed) {
      return PdfTextActionResult.none;
    }
    bool isCurrent() => _isCurrent(generation, document, range);
    try {
      if (!isCurrent()) return PdfTextActionResult.none;
      if (document.pages
          .skip(range.start.text.pageNumber - 1)
          .take(range.end.text.pageNumber - range.start.text.pageNumber + 1)
          .any((page) => !page.isLoaded)) {
        return PdfTextActionResult.loading;
      }
      final text = await selection.getSelectedText();
      if (!isCurrent() || !selection.isCopyAllowed || text.isEmpty) {
        return PdfTextActionResult.none;
      }
      // pdfrx's copy helper does not await the platform clipboard response.
      await Clipboard.setData(ClipboardData(text: text));
      if (!isCurrent()) return PdfTextActionResult.none;
      if (!keepSelection) {
        await selection.clearTextSelection();
        if (!_isCurrent(generation, document, null)) {
          return PdfTextActionResult.none;
        }
      }
      return PdfTextActionResult.copied;
    } catch (_) {
      return isCurrent()
          ? PdfTextActionResult.failed
          : PdfTextActionResult.none;
    }
  }

  Future<PdfTextActionResult> selectAll() async {
    final generation = ++_generation;
    if (!isActive() || !controller.isReady) return PdfTextActionResult.none;
    final document = controller.document;
    final selection = controller.textSelectionDelegate;
    final range = selection.textSelectionPointRange;
    bool isCurrent() => _isCurrent(generation, document, range);
    try {
      if (!isCurrent()) return PdfTextActionResult.none;
      // An incomplete progressive load must not masquerade as a full selection.
      if (document.pages.any((page) => !page.isLoaded)) {
        return PdfTextActionResult.loading;
      }
      final cache = PdfPageTextCache.forDocument(document);
      Future<PdfPageText?> boundary(Iterable<PdfPage> pages) async {
        for (final page in pages) {
          if (!isCurrent()) return null;
          final text = await cache.load(page);
          if (!isCurrent() ||
              !identical(document.pages[page.pageNumber - 1], page)) {
            return null;
          }
          if (text.fullText.isNotEmpty && text.charRects.isNotEmpty) {
            return text;
          }
        }
        return null;
      }

      final first = await boundary(document.pages);
      if (first == null || !isCurrent()) return PdfTextActionResult.none;
      final last = await boundary(document.pages.reversed);
      if (last == null || !isCurrent()) return PdfTextActionResult.none;
      if (document.pages.any((page) => !page.isLoaded)) {
        return PdfTextActionResult.loading;
      }
      // This setter applies synchronously; native selectAllText awaits without
      // checking whether the viewer or its selection has changed in the meantime.
      await selection.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(first, 0),
          PdfTextSelectionPoint(last, last.charRects.length - 1),
        ),
      );
      return PdfTextActionResult.none;
    } catch (_) {
      return isCurrent()
          ? PdfTextActionResult.failed
          : PdfTextActionResult.none;
    }
  }
}
