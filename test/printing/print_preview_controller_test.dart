import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:otzaria/printing/print_preview_controller.dart';
import 'package:pdfrx/pdfrx.dart';

class _Queue {
  Future<void> idle = Future.value();

  Future<void> run(Future<void> Function() action) {
    final result = idle.then((_) => action());
    idle = result;
    return result;
  }
}

class _Token extends PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;

  @override
  Future<void> cancel() async => isCanceled = true;
}

class _Image extends PdfImage {
  _Image(this.width, this.height);
  @override
  final int width;
  @override
  final int height;
  int pixelReads = 0;
  int disposals = 0;

  @override
  Uint8List get pixels {
    pixelReads++;
    return Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);
  }

  @override
  void dispose() => disposals++;
}

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber, this.log);
  @override
  final int pageNumber;
  final List<int> log;
  Completer<void>? entered;
  Completer<void>? release;
  _Token? token;
  _Image? output;
  @override
  double get width => pageNumber.isEven ? 140 : 100;
  @override
  double get height => pageNumber.isEven ? 100 : 140;
  @override
  bool get isLoaded => true;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => token = _Token();

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) async {
    log.add(pageNumber);
    entered?.complete();
    await release?.future;
    return output = _Image(width!, height!);
  }
}

class _Document extends Fake implements PdfDocument {
  _Document(this.pages);
  @override
  final List<_Page> pages;
  bool closed = false;
  @override
  Future<void> dispose() async => closed = true;
}

class _Source extends PrintPdfSource {
  _Source(int count) : super.data(Uint8List(0)) {
    pages = List.generate(count, (i) => _Page(i + 1, rendered));
  }
  final rendered = <int>[];
  late final List<_Page> pages;
  final documents = <_Document>[];

  @override
  Future<PdfDocument> open({bool useProgressiveLoading = false}) async {
    expect(documents.every((doc) => doc.closed), isTrue);
    final doc = _Document(pages);
    documents.add(doc);
    return doc;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load(
    PrintPreviewController preview,
    _Source source, {
    int start = 1,
    int? end,
  }) => preview.load(
    source,
    startPage: start,
    endPage: end,
    isStale: () => false,
    onPageCount: (count) => expect(count, source.pages.length),
  );

  test(
    'a large document renders the visible sheet and its neighbor only',
    () async {
      final queue = _Queue();
      final source = _Source(600);
      final preview = PrintPreviewController(serialize: queue.run);
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 1);
      await load(preview, source);

      expect(preview.pageCount, 600);
      expect(source.rendered, [1, 2]);
      expect(preview.pageSize(0).aspectRatio, 100 / 140);
      expect(preview.pageSize(1).aspectRatio, 140 / 100);
      expect(source.documents.single.closed, isTrue);
      preview.showSheets({499});
      await queue.idle;
      expect(source.rendered.skip(2), [500, 499, 501]);
      expect(preview.image(499), isNotNull);
    },
  );

  test(
    'a short range uses the correct source pages and N-up stays bounded',
    () async {
      final queue = _Queue();
      final source = _Source(600);
      final preview = PrintPreviewController(serialize: queue.run);
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 4);
      await load(preview, source, start: 500, end: 510);

      expect(preview.pageCount, 11);
      expect(source.rendered, List.generate(8, (i) => 500 + i));
      preview.showSheets({2});
      await queue.idle;
      expect(source.rendered.skip(8), [508, 509, 510]);
      expect(preview.pageSize(0).aspectRatio, 140 / 100);
    },
  );

  test('LRU charges render allocations and disposes evicted handles', () async {
    final queue = _Queue();
    final source = _Source(100);
    const budget = 600000;
    final preview = PrintPreviewController(
      serialize: queue.run,
      maximumBytes: budget,
    );
    addTearDown(preview.dispose);
    preview.addListener(
      () => expect(preview.estimatedBytes, lessThanOrEqualTo(budget)),
    );
    preview.reset(pagesPerSheet: 1);
    await load(preview, source);
    final first = preview.image(0)!;
    for (final sheet in [20, 40, 60]) {
      preview.showSheets({sheet});
      await queue.idle;
    }
    expect(first.debugDisposed, isTrue);
    expect(preview.cachedImageCount, lessThan(10));
    expect(preview.image(60), isNotNull);
    expect(
      source.pages
          .where((page) => page.output != null)
          .every(
            (page) => page.output!.disposals == 1,
          ),
      isTrue,
    );
  });

  test('stale native results are freed before image conversion', () async {
    final queue = _Queue();
    final source = _Source(20);
    final page = source.pages.first;
    page.entered = Completer<void>();
    page.release = Completer<void>();
    final preview = PrintPreviewController(serialize: queue.run);
    addTearDown(preview.dispose);
    preview.reset(pagesPerSheet: 1);
    final pending = load(preview, source);
    await page.entered!.future;
    preview.reset(pagesPerSheet: 1);
    expect(page.token!.isCanceled, isTrue);
    page.release!.complete();
    await pending;

    expect(page.output!.disposals, 1);
    expect(page.output!.pixelReads, 0);
    expect(preview.cachedImageCount, 0);
    expect(preview.estimatedBytes, 0);
    expect(source.documents.single.closed, isTrue);
  });

  test('close cancels queued opening without entering native code', () async {
    final queue = _Queue();
    final blocker = Completer<void>();
    unawaited(queue.run(() => blocker.future));
    final source = _Source(10);
    final preview = PrintPreviewController(serialize: queue.run);
    final pending = load(preview, source);
    preview.dispose();
    blocker.complete();
    await pending;
    expect(source.documents, isEmpty);
    expect(source.rendered, isEmpty);
  });
}
