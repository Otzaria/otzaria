import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:otzaria/printing/print_preview_controller.dart';
import 'package:pdfrx/pdfrx.dart';

/// Releases the queue on failure, like PrintingScreen's raster lock.
class _Serial {
  Future<void> idle = Future.value();

  Future<void> run(Future<void> Function() action) async {
    final previous = idle;
    final done = Completer<void>();
    idle = done.future;
    try {
      await previous;
      await action();
    } finally {
      done.complete();
    }
  }
}

class _Cancel extends PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _Bitmap extends PdfImage {
  _Bitmap(this.width, this.height);
  @override
  final int width;
  @override
  final int height;
  int reads = 0;
  int disposals = 0;

  @override
  Uint8List get pixels {
    reads++;
    return Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);
  }

  @override
  void dispose() => disposals++;
}

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber, this.rendered);
  @override
  final int pageNumber;
  final List<int> rendered;
  Completer<void>? entered;
  Completer<void>? resume;
  final outputs = <_Bitmap>[];
  double actualWidth = 600;
  double actualHeight = 300;
  @override
  bool isLoaded = true;

  // Large enough for both normal and thumbnail renders to reach the small
  // injected budget. This models a large physical page at the normal budget.
  @override
  double get width => isLoaded ? actualWidth : 600;
  @override
  double get height => isLoaded ? actualHeight : 300;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Cancel();

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
    expect(
      isLoaded,
      isTrue,
      reason: 'Page geometry must load before rendering.',
    );
    rendered.add(pageNumber);
    if (entered?.isCompleted == false) entered!.complete();
    await resume?.future;
    final bitmap = _Bitmap(width!, height!);
    outputs.add(bitmap);
    return bitmap;
  }
}

class _Document extends Fake implements PdfDocument {
  _Document(this.pages, {required this.failClose});
  @override
  final List<_Page> pages;
  final bool failClose;
  int disposals = 0;
  final reloadedPages = <List<int>>[];

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    final numbers =
        pageNumbersToReload ??
        List.generate(pages.length, (index) => index + 1);
    reloadedPages.add(List.of(numbers));
    for (final number in numbers) {
      pages[number - 1].isLoaded = true;
    }
  }

  @override
  Future<void> dispose() async {
    disposals++;
    if (failClose) throw StateError('test: native close failed');
  }
}

class _Source extends PrintPdfSource {
  _Source(int count) : super.data(Uint8List(0)) {
    pages = List.generate(count, (i) => _Page(i + 1, rendered));
  }
  late final List<_Page> pages;
  final rendered = <int>[];
  final documents = <_Document>[];
  final progressiveOpens = <bool>[];
  Completer<void>? enteredOpen;
  Completer<void>? resumeOpen;
  bool failNextClose = false;

  @override
  Future<PdfDocument> open({bool useProgressiveLoading = false}) async {
    expect(
      documents.every((d) => d.disposals == 1),
      isTrue,
      reason: 'Each document must close before the next open.',
    );
    progressiveOpens.add(useProgressiveLoading);
    for (var index = 0; index < pages.length; index++) {
      pages[index].isLoaded = !useProgressiveLoading || index == 0;
    }
    final document = _Document(pages, failClose: failNextClose);
    failNextClose = false;
    documents.add(document);
    if (enteredOpen?.isCompleted == false) enteredOpen!.complete();
    await resumeOpen?.future;
    return document;
  }
}

Future<void> _load(PrintPreviewController preview, _Source source) =>
    preview.load(
      source,
      startPage: 1,
      endPage: null,
      isStale: () => false,
      onPageCount: (_) {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eight small thumbnails preserve full main-page resolution', () async {
    final queue = _Serial();
    final source = _Source(40);
    final preview = PrintPreviewController(serialize: queue.run);
    addTearDown(preview.dispose);
    preview.reset(pagesPerSheet: 1);
    await _load(preview, source);
    final initial = preview.image(0)!;
    expect((initial.width, initial.height), (900, 450));

    preview.showSheets({0, 1, 2, 3, 4, 5, 6, 7}, thumbnails: true);
    await queue.idle;

    final main = preview.image(0)!;
    expect((main.width, main.height), (900, 450));
    expect(
      identical(main, initial),
      isTrue,
      reason: 'Adding small thumbnails should reuse an adequate main image.',
    );
    for (var page = 0; page < 8; page++) {
      final thumbnail = preview.image(page, thumbnail: true)!;
      expect((thumbnail.width, thumbnail.height), (150, 75));
    }
    expect(preview.estimatedBytes, lessThanOrEqualTo(32 * 1024 * 1024));
  });

  test('main resolution recovers when viewport pressure is removed', () async {
    const budget = 10000000;
    final queue = _Serial();
    final source = _Source(40);
    final preview = PrintPreviewController(
      serialize: queue.run,
      maximumBytes: budget,
    );
    addTearDown(preview.dispose);
    preview.reset(pagesPerSheet: 1);
    await _load(preview, source);
    expect(preview.image(0)!.width, 900);

    preview.showSheets({0, 1, 2, 3, 4, 5});
    await queue.idle;
    expect(preview.image(0)!.width, lessThan(900));
    for (var page = 0; page < 7; page++) {
      expect(preview.image(page), isNotNull);
    }
    expect(preview.estimatedBytes, lessThanOrEqualTo(budget));

    preview.showSheets({0});
    await queue.idle;
    for (var page = 0; page < 2; page++) {
      final image = preview.image(page)!;
      expect((image.width, image.height), (900, 450));
    }
    expect(preview.estimatedBytes, lessThanOrEqualTo(budget));
  });

  test(
    'narrow pages fit the byte budget after minimum-pixel rounding',
    () async {
      final queue = _Serial();
      final source = _Source(2);
      for (final page in source.pages) {
        page
          ..actualWidth = 1
          ..actualHeight = 3000;
      }
      final preview = PrintPreviewController(
        serialize: queue.run,
        maximumBytes: 4096,
      );
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 1);
      await _load(preview, source);

      for (var page = 0; page < 2; page++) {
        final image = preview.image(page);
        expect(
          image,
          isNotNull,
          reason: 'Rounding a narrow side must not leave a permanent spinner.',
        );
        expect(image!.width, 1);
        expect(image.height, greaterThan(0));
      }
      expect(preview.estimatedBytes, lessThanOrEqualTo(4096));
    },
  );

  test('the minimum valid budget prioritizes the visible page', () async {
    final queue = _Serial();
    final source = _Source(3);
    final preview = PrintPreviewController(
      serialize: queue.run,
      maximumBytes: 12,
    );
    addTearDown(preview.dispose);
    preview.reset(pagesPerSheet: 1);
    await _load(preview, source);
    expect(preview.image(0), isNotNull);
    expect(preview.cachedImageCount, 1);
    expect(preview.estimatedBytes, lessThanOrEqualTo(12));

    preview.showSheets({1});
    await queue.idle;
    expect(preview.image(1), isNotNull);
    expect(preview.cachedImageCount, 1);
    expect(preview.estimatedBytes, lessThanOrEqualTo(12));
  });

  test(
    'a short progressive range loads actual selected-page geometry',
    () async {
      final queue = _Serial();
      final source = _Source(300);
      source.pages[249]
        ..actualWidth = 100
        ..actualHeight = 200;
      source.pages[250]
        ..actualWidth = 640
        ..actualHeight = 480;
      source.pages[251]
        ..actualWidth = 210
        ..actualHeight = 350;
      final preview = PrintPreviewController(serialize: queue.run);
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 1);

      await preview.load(
        source,
        startPage: 250,
        endPage: 252,
        isStale: () => false,
        onPageCount: (_) {},
      );

      expect(source.progressiveOpens, [true]);
      expect(source.documents.single.reloadedPages, [
        [250, 251, 252],
      ]);
      expect(preview.pageCount, 3);
      expect(
        (preview.pageSize(0).width, preview.pageSize(0).height),
        (100, 200),
      );
      expect(
        (preview.pageSize(1).width, preview.pageSize(1).height),
        (640, 480),
      );
      expect(
        (preview.pageSize(2).width, preview.pageSize(2).height),
        (210, 350),
      );
      expect(source.rendered, [250, 251]);

      preview.showSheets({2});
      await queue.idle;
      expect(source.progressiveOpens, [true, true]);
      expect(
        source.documents.last.reloadedPages.single,
        unorderedEquals([251, 252]),
      );
      final image = preview.image(2)!;
      expect((image.width, image.height), (315, 525));
    },
  );

  test(
    'thumbnail pressure keeps every requested main image available',
    () async {
      final queue = _Serial();
      final source = _Source(40);
      final preview = PrintPreviewController(
        serialize: queue.run,
        maximumBytes: 600000,
      );
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 1);
      await _load(preview, source);
      preview.showSheets({0, 1, 2, 3, 4, 5, 6, 7}, thumbnails: true);
      await queue.idle;

      expect(
        preview.image(0),
        isNotNull,
        reason: 'A visible main page must not become a permanent spinner.',
      );
      for (var page = 0; page < 8; page++) {
        expect(preview.image(page, thumbnail: true), isNotNull);
      }
      expect(preview.estimatedBytes, lessThanOrEqualTo(600000));
    },
  );

  test('rapid viewport requests skip intermediate destinations', () async {
    final queue = _Serial();
    final source = _Source(100);
    final preview = PrintPreviewController(serialize: queue.run);
    addTearDown(preview.dispose);
    preview.reset(pagesPerSheet: 1);
    await _load(preview, source);
    final blocked = source.pages[20]
      ..entered = Completer<void>()
      ..resume = Completer<void>();
    preview.showSheets({20});
    await blocked.entered!.future;
    preview.showSheets({40});
    preview.showSheets({60});
    preview.showSheets({80});
    blocked.resume!.complete();
    await queue.idle;

    expect(source.rendered, isNot(contains(41)));
    expect(source.rendered, isNot(contains(61)));
    expect(
      blocked.outputs.single.reads,
      0,
      reason: 'A canceled raster must not be converted into ui.Image.',
    );
    expect(blocked.outputs.single.disposals, 1);
    expect(preview.image(20), isNull);
    expect(preview.image(80), isNotNull);
    expect(source.documents.every((d) => d.disposals == 1), isTrue);
  });

  test(
    'close during open disposes the resulting native document exactly once',
    () async {
      final queue = _Serial();
      final source = _Source(20)
        ..enteredOpen = Completer<void>()
        ..resumeOpen = Completer<void>();
      final preview = PrintPreviewController(serialize: queue.run);
      preview.reset(pagesPerSheet: 1);
      final pending = _load(preview, source);
      await source.enteredOpen!.future;
      preview.dispose();
      source.resumeOpen!.complete();
      await pending;
      expect(source.rendered, isEmpty);
      expect(source.documents.single.disposals, 1);
      expect(preview.estimatedBytes, 0);
    },
  );

  test(
    'route stop cancels native work and keeps handles for the closing frame',
    () async {
      final queue = _Serial();
      final source = _Source(40);
      final preview = PrintPreviewController(serialize: queue.run);
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 1);
      await _load(preview, source);
      final image = preview.image(0)!;
      final blocked = source.pages[20]
        ..entered = Completer<void>()
        ..resume = Completer<void>();
      preview.showSheets({20});
      await blocked.entered!.future;

      preview.stop();
      preview.reset(pagesPerSheet: 4);
      final lateLoad = _load(preview, source);
      expect(image.debugDisposed, isFalse);
      expect(identical(preview.image(0), image), isTrue);
      preview.showSheets({30});
      blocked.resume!.complete();
      await queue.idle;
      await lateLoad;

      expect(
        source.documents.length,
        2,
        reason: 'A late continuation must not restart a stopped preview.',
      );
      expect(source.rendered, isNot(contains(31)));
      expect(blocked.outputs.single.reads, 0);
      expect(blocked.outputs.single.disposals, 1);
      expect(preview.image(20), isNull);
      expect(image.debugDisposed, isFalse);
      expect(
        source.documents.every((document) => document.disposals == 1),
        isTrue,
      );
    },
  );

  test(
    'viewport teardown failures are reported without unhandled futures',
    () async {
      final queue = _Serial();
      final source = _Source(40);
      final preview = PrintPreviewController(serialize: queue.run);
      addTearDown(preview.dispose);
      preview.reset(pagesPerSheet: 1);
      await _load(preview, source);
      source.failNextClose = true;
      final errors = <Object>[];
      final done = Completer<void>();
      runZonedGuarded(() {
        preview.showSheets({25});
        unawaited(queue.idle.then((_) => done.complete()));
      }, (error, stack) => errors.add(error));
      await done.future;
      await Future<void>.delayed(Duration.zero);

      expect(
        errors,
        isEmpty,
        reason: 'The internally scheduled render must collect close errors.',
      );
      expect(preview.failed, isTrue);
    },
  );
}
