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

  bool Function() _selectedTextGuard(
    int generation,
    PdfDocument document,
    PdfTextSelectionRange range,
  ) {
    final originalPages = document.pages;
    var checkedPages = originalPages;
    final start = range.start.text.pageNumber - 1;
    final end = range.end.text.pageNumber - 1;
    return () {
      if (!_isCurrent(generation, document, range) ||
          !controller.textSelectionDelegate.isCopyAllowed) {
        return false;
      }
      final currentPages = document.pages;
      if (start < 0 ||
          end >= currentPages.length ||
          end >= originalPages.length) {
        return false;
      }
      if (!identical(currentPages, checkedPages)) {
        for (var i = start; i <= end; i++) {
          if (!identical(currentPages[i], originalPages[i])) return false;
        }
        checkedPages = currentPages;
      }
      return true;
    };
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
    final isCurrent = _selectedTextGuard(generation, document, range);
    try {
      if (!isCurrent()) return PdfTextActionResult.none;
      if (document.pages
          .skip(range.start.text.pageNumber - 1)
          .take(range.end.text.pageNumber - range.start.text.pageNumber + 1)
          .any((page) => !page.isLoaded)) {
        return PdfTextActionResult.loading;
      }
      final text = await _readText(document, range, isCurrent);
      if (!isCurrent() || text == null || text.isEmpty) {
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

  /// קורא את הבחירה בלי להכניס גאומטריה של עמודי ביניים למטמון המשותף.
  Future<String> readSelectedText() async {
    final generation = ++_generation;
    if (!isActive() || !controller.isReady) return '';
    final document = controller.document;
    final selection = controller.textSelectionDelegate;
    final range = selection.textSelectionPointRange;
    if (range == null || !selection.isCopyAllowed) return '';
    final isCurrent = _selectedTextGuard(generation, document, range);
    try {
      final text = await _readText(document, range, isCurrent);
      return isCurrent() ? text ?? '' : '';
    } catch (_) {
      if (!isCurrent()) return '';
      rethrow;
    }
  }

  Future<String?> _readText(
    PdfDocument document,
    PdfTextSelectionRange range,
    bool Function() isCurrent,
  ) async {
    final first = range.start;
    final last = range.end;
    final pages = document.pages;
    if (first.text.pageNumber < 1 || last.text.pageNumber > pages.length) {
      return null;
    }
    final result = StringBuffer();
    for (
      var number = first.text.pageNumber;
      number <= last.text.pageNumber;
      number++
    ) {
      if (!isCurrent()) return null;
      final page = pages[number - 1];
      if (!page.isLoaded) return null;
      // cache.get אינו מאמת זהות עמוד לפני שאירוע החלפת התוכן מופץ.
      final text = number == first.text.pageNumber
          ? first.text
          : number == last.text.pageNumber
          ? last.text
          : await page.loadStructuredText(ensureLoaded: false);
      if (!isCurrent() || !identical(document.pages[number - 1], page)) {
        return null;
      }
      if (text.fullText.isEmpty) continue;
      result.write(
        text
            .getRangeFromAB(
              number == first.text.pageNumber ? first.index : 0,
              number == last.text.pageNumber
                  ? last.index
                  : text.charRects.length - 1,
            )
            .text,
      );
    }
    return result.toString();
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
      // ה-setter סינכרוני; selectAllText של החבילה ממתין בלי לבדוק
      // אם הצפיין או הבחירה הוחלפו בזמן ההמתנה.
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
