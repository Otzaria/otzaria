import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'print_pdf_source.dart';

typedef _ImageKey = ({int page, bool thumbnail});
typedef _ImageSize = ({int width, int height});
typedef _CachedImage = ({ui.Image image, PdfImageCacheEntry entry});

/// תצוגה מדורגת עם מטמון LRU מוגבל, בלי להחזיק מסמך פתוח בין פעולות.
class PrintPreviewController extends ChangeNotifier {
  PrintPreviewController({
    required this.serialize,
    int maximumBytes = 32 * 1024 * 1024,
  }) : _budget = PdfImageCacheBudget(maximumBytes: maximumBytes) {
    if (maximumBytes < 12) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
  }

  final Future<void> Function(Future<void> Function()) serialize;
  final PdfImageCacheBudget _budget;
  final _images = <_ImageKey, _CachedImage>{};
  List<ui.Size> _pageSizes = const [];
  PrintPdfSource? _source;
  int _firstPage = 0;
  int _generation = 0;
  int _window = 0;
  int _cells = 1;
  Set<int> _visibleSheets = {0};
  Set<int> _thumbnailSheets = {};
  PdfPageRenderCancellationToken? _cancellation;
  bool _queued = false;
  bool _stopped = false;
  bool _disposed = false;
  bool _busy = true;
  bool _failed = false;

  int get pageCount => _pageSizes.length;
  bool get busy => _busy;
  bool get failed => _failed;
  bool get isStopped => _stopped || _disposed;
  ui.Size pageSize(int index) => _pageSizes[index];

  void reportError(Object error, StackTrace stack) {
    if (!isStopped) _fail(error, stack);
  }

  /// מפסיק עבודה מיד עם סגירת הנתיב; התמונות נשארות עד סוף אנימציית הסגירה.
  void stop() {
    _stopped = true;
    _generation++;
    _cancelRender();
    _source = null;
  }

  @visibleForTesting
  int get estimatedBytes => _budget.estimatedBytes;
  @visibleForTesting
  int get cachedImageCount => _images.length;

  ui.Image? image(int index, {bool thumbnail = false}) {
    final cached = _images[(page: index, thumbnail: thumbnail)];
    cached?.entry.touch();
    return cached?.image;
  }

  void reset({required int pagesPerSheet}) {
    if (isStopped) return;
    _generation++;
    _window++;
    _cancelRender();
    _source = null;
    _pageSizes = const [];
    _cells = pagesPerSheet;
    _visibleSheets = {0};
    _thumbnailSheets = {};
    _busy = true;
    _failed = false;
    _clearImages();
    notifyListeners();
  }

  Future<void> load(
    PrintPdfSource source, {
    required int startPage,
    required int? endPage,
    required bool Function() isStale,
    required void Function(int) onPageCount,
  }) async {
    final generation = _generation;
    bool stale() => isStopped || generation != _generation || isStale();
    await serialize(() async {
      if (stale()) return;
      PdfDocument? document;
      try {
        document = await source.open(useProgressiveLoading: endPage != null);
        if (stale()) return;
        onPageCount(document.pages.length);
        if (stale()) return;
        if (document.pages.isEmpty) {
          _busy = false;
          notifyListeners();
          return;
        }
        _firstPage = (startPage - 1).clamp(0, document.pages.length - 1);
        final last = ((endPage ?? document.pages.length) - 1).clamp(
          _firstPage,
          document.pages.length - 1,
        );
        await _loadPageSizes(document, [
          for (var i = _firstPage; i <= last; i++) i,
        ]);
        if (stale()) return;
        _pageSizes = [
          for (var i = _firstPage; i <= last; i++) document.pages[i].size,
        ];
        _source = source;
        notifyListeners();
        await _renderWindow(document, generation);
      } catch (error, stack) {
        if (!stale()) _fail(error, stack);
      } finally {
        // Closing is part of the serialized operation, including cancellation.
        await document?.dispose();
        if (!stale()) {
          _busy = false;
          notifyListeners();
        }
      }
    });
  }

  void showSheets(Set<int> sheets, {bool thumbnails = false}) {
    if (isStopped || pageCount == 0) return;
    final previous = thumbnails ? _thumbnailSheets : _visibleSheets;
    if (setEquals(previous, sheets)) return;
    if (thumbnails) {
      _thumbnailSheets = Set.of(sheets);
    } else {
      _visibleSheets = Set.of(sheets);
    }
    _window++;
    _cancelRender();
    _queueWindow();
  }

  void setPagesPerSheet(int value) {
    if (isStopped || value == _cells) return;
    _cells = value;
    _window++;
    _cancelRender();
    final lastSheet = max(0, (pageCount + _cells - 1) ~/ _cells - 1);
    _visibleSheets = _visibleSheets.map((i) => i.clamp(0, lastSheet)).toSet();
    _thumbnailSheets = _thumbnailSheets.where((i) => i <= lastSheet).toSet();
    _queueWindow();
    notifyListeners();
  }

  List<_ImageKey> _wantedImages() {
    final sheetCount = (pageCount + _cells - 1) ~/ _cells;
    final wanted = <_ImageKey>{};
    void addSheet(int sheet, {bool thumbnail = false}) {
      if (sheet < 0 || sheet >= sheetCount) return;
      for (
        var page = sheet * _cells;
        page < min((sheet + 1) * _cells, pageCount);
        page++
      ) {
        wanted.add((page: page, thumbnail: thumbnail));
      }
    }

    final visible = _visibleSheets.toList()..sort();
    for (final sheet in visible) {
      addSheet(sheet);
    }
    for (final sheet in _thumbnailSheets.toList()..sort()) {
      addSheet(sheet, thumbnail: true);
    }
    if (visible.isNotEmpty) {
      addSheet(visible.first - 1);
      addSheet(visible.last + 1);
    }
    // Even a one-pixel image needs eight retained bytes and four extra bytes
    // while rendering. An exceptionally small budget still serves the first
    // visible page; neighbors follow only when their minimum cost can fit.
    final maximumImages = (_budget.maximumBytes - 4) ~/ 8;
    return wanted.take(maximumImages).toList();
  }

  void _queueWindow() {
    if (_queued || _source == null || isStopped) return;
    final wanted = _wantedImages();
    final targets = _targetSizes(wanted);
    if (wanted.every((key) {
      final image = _images[key]?.image;
      final target = targets[key]!;
      return image != null &&
          image.width >= target.width &&
          image.height >= target.height;
    })) {
      return;
    }
    _queued = true;
    final generation = _generation;
    final source = _source!;
    unawaited(
      serialize(() async {
        _queued = false;
        if (isStopped || generation != _generation) return;
        PdfDocument? document;
        try {
          document = await source.open(useProgressiveLoading: true);
          if (isStopped || generation != _generation) return;
          await _renderWindow(document, generation);
        } catch (error, stack) {
          if (!isStopped && generation == _generation) _fail(error, stack);
        } finally {
          await document?.dispose();
        }
      }).catchError((Object error, StackTrace stack) {
        if (!isStopped && generation == _generation) _fail(error, stack);
      }),
    );
  }

  Future<void> _renderWindow(PdfDocument document, int generation) async {
    final window = _window;
    bool stale() => isStopped || generation != _generation || window != _window;
    final wanted = _wantedImages();
    await _loadPageSizes(document, [
      for (final key in wanted) _firstPage + key.page,
    ]);
    if (stale()) return;
    final targets = _targetSizes(wanted);
    for (final item in _images.entries.toList()) {
      final cached = item.value;
      final target = targets[item.key];
      if (target != null &&
          (cached.image.width != target.width ||
              cached.image.height != target.height)) {
        _images.remove(item.key);
        cached.entry.dispose();
        cached.image.dispose();
      } else {
        cached.entry.touch(isPinned: target != null);
      }
    }
    for (final key in wanted) {
      if (stale()) return;
      if (_images.containsKey(key)) continue;
      final page = document.pages[_firstPage + key.page];
      final (:width, :height) = targets[key]!;
      final reservation = _budget.tryReserve(width * height * 12);
      if (reservation == null) continue;
      final token = page.createCancellationToken();
      _cancellation = token;
      ui.Image? rendered;
      try {
        rendered = await page.renderForDisplay(
          width: width,
          height: height,
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xffffffff,
          cancellationToken: token,
        );
        if (stale() || token.isCanceled) return;
        if (rendered == null) {
          throw StateError('PDF page could not be rendered');
        }
        final image = rendered;
        final entry = reservation.commit(
          retainedBytes: image.width * image.height * 8,
          isPinned: true,
          onEvict: () {
            _images.remove(key);
            image.dispose();
          },
        );
        if (entry == null) continue;
        _images[key] = (image: image, entry: entry);
        rendered = null;
        notifyListeners();
      } finally {
        rendered?.dispose();
        reservation.dispose();
        if (identical(_cancellation, token)) _cancellation = null;
      }
    }
  }

  Map<_ImageKey, _ImageSize> _targetSizes(List<_ImageKey> wanted) {
    final sizes = <_ImageKey, _ImageSize>{};
    var pixels = 0;
    var largest = 0;
    for (final key in wanted) {
      final size = _pageSizes[key.page];
      final scale = min(
        key.thumbnail ? 0.25 : 1.5,
        4096 / max(size.width, size.height),
      );
      final width = max(1, (size.width * scale).floor());
      final height = max(1, (size.height * scale).floor());
      sizes[key] = (width: width, height: height);
      pixels += width * height;
      largest = max(largest, width * height);
    }
    // Retained CPU/GPU estimates plus the extra buffer for one active render.
    final requiredBytes = pixels * 8 + largest * 4;
    if (requiredBytes <= _budget.maximumBytes) return sizes;
    final minimumBytes = sizes.length * 8 + 4;
    final availableExtraBytes = _budget.maximumBytes - minimumBytes;
    final requiredExtraBytes = requiredBytes - minimumBytes;
    return sizes.map((key, size) {
      final pixels = size.width * size.height;
      // Reserve one pixel per image before scaling the remainder. Scaling
      // dimensions alone can exceed the budget when a narrow side rounds up
      // to one pixel. Integer division keeps the aggregate bound exact.
      final maximumPixels =
          1 + (pixels - 1) * availableExtraBytes ~/ requiredExtraBytes;
      final scale = sqrt(maximumPixels / pixels);
      var width = max(1, (size.width * scale).floor());
      var height = max(1, (size.height * scale).floor());
      if (width * height > maximumPixels) {
        if (width >= height) {
          width = maximumPixels ~/ height;
        } else {
          height = maximumPixels ~/ width;
        }
      }
      return MapEntry(key, (width: width, height: height));
    });
  }

  Future<void> _loadPageSizes(
    PdfDocument document,
    Iterable<int> indices,
  ) async {
    final missing = {
      for (final index in indices)
        if (!document.pages[index].isLoaded) index + 1,
    };
    if (missing.isNotEmpty) {
      await document.reloadPages(pageNumbersToReload: missing.toList());
    }
  }

  void _cancelRender() {
    _cancellation?.cancel();
  }

  void _fail(Object error, StackTrace stack) {
    debugPrint('[PRINT] preview render failed: $error\n$stack');
    _failed = true;
    _busy = false;
    notifyListeners();
  }

  void _clearImages() {
    for (final cached in _images.values) {
      cached.entry.dispose();
      cached.image.dispose();
    }
    _images.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelRender();
    _source = null;
    _clearImages();
    _budget.dispose();
    super.dispose();
  }
}
