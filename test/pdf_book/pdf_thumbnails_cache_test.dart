import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:pdfrx/pdfrx.dart';
import '../test_helpers/pdf_document_dispose.dart';

List<int> _blankPdf(int pageCount) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(pageCount, (i) => '${i + 3} 0 R').join(' ')}] /Count $pageCount >>',
    for (var i = 0; i < pageCount; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return latin1.encode(out.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria-pdf-thumbs-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => tempDir.path,
            _ => null,
          },
        );
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  RawImage firstThumbnail(WidgetTester tester) =>
      tester.widget<RawImage>(find.byType(RawImage).first);

  testWidgets('תמונה ממוזערת שחוזרת למסך מוצגת מהמטמון בלי רינדור חוזר', (
    tester,
  ) async {
    final document = (await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      return PdfDocument.openData(
        Uint8List.fromList(_blankPdf(40)),
        sourceName: 'thumbs.pdf',
      );
    }))!;
    final ref = PdfDocumentRefDirect(document);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 600,
            child: ThumbnailsView(documentRef: ref, controller: null),
          ),
        ),
      ),
    );
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(RawImage).evaluate().isNotEmpty &&
          firstThumbnail(tester).image != null) {
        break;
      }
    }
    expect(firstThumbnail(tester).image, isNotNull);

    final list = find.byType(Scrollable);
    tester.state<ScrollableState>(list).position.jumpTo(266.0 * 30);
    await tester.pump();
    expect(find.text('1'), findsNothing);
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump();

    expect(firstThumbnail(tester).image, isNotNull);

    await tester.pumpWidget(const SizedBox());
    await disposePdfDocument(tester, document);
  });

  testWidgets('ניקוי מטמון שומר חשבונאות לתמונה מוצגת, והסתרה מפנה אותה', (
    tester,
  ) async {
    final budget = PdfImageCacheBudget(maximumBytes: 8 * 1024 * 1024);
    final cache = PdfThumbnailCache(maxBytes: 4 * 1024 * 1024, budget: budget);
    final document = (await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      return PdfDocument.openData(
        Uint8List.fromList(_blankPdf(1)),
        sourceName: 'thumbnail-accounting.pdf',
      );
    }))!;
    final ref = PdfDocumentRefDirect(document);
    Widget harness({required bool shown}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 300,
          child: ThumbnailsView(
            documentRef: ref,
            controller: null,
            thumbnailCache: cache,
            isPaneOpen: shown,
          ),
        ),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    Future<void> waitForImage() async {
      for (
        var i = 0;
        i < 100 && find.byType(RawImage).evaluate().isEmpty;
        i++
      ) {
        await settle();
      }
      expect(find.byType(RawImage), findsOneWidget);
      expect(firstThumbnail(tester).image, isNotNull);
    }

    try {
      await tester.pumpWidget(harness(shown: true));
      await waitForImage();
      final image = firstThumbnail(tester).image!;
      final bytes = image.width * image.height * 8;
      expect(cache.length, 1);
      expect(budget.pendingBytes, 0);
      expect(budget.retainedBytes, bytes * 2);
      cache.clear();
      expect(cache.length, 0);
      expect(budget.retainedBytes, bytes);
      expect(firstThumbnail(tester).image, same(image));
      await tester.pumpWidget(harness(shown: false));
      for (var i = 0; i < 10; i++) {
        await settle();
      }
      expect(budget.pendingBytes, 0);
      expect(budget.retainedBytes, 0);
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(harness(shown: true));
      await waitForImage();
      expect(cache.length, 1);
      expect(budget.retainedBytes, greaterThan(0));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      cache.dispose();
      await disposePdfDocument(tester, document);
    }
    expect(budget.estimatedBytes, 0);
    budget.dispose();
  });

  testWidgets(
    'ניקוי מטמון בזמן רינדור מנסה שוב ואינו משאיר תמונה ממוזערת ריקה',
    (tester) async {
      final document = _ControlledDocument();
      final page = document.page;
      final budget = PdfImageCacheBudget(maximumBytes: 8 * 1024 * 1024);
      final cache = PdfThumbnailCache(
        maxBytes: 4 * 1024 * 1024,
        budget: budget,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 300,
                child: ThumbnailsView(
                  documentRef: PdfDocumentRefDirect(document),
                  controller: null,
                  thumbnailCache: cache,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 10 && page.renderCount == 0; i++) {
          await tester.pump();
        }
        expect(page.renderCount, 1);
        expect(budget.pendingBytes, greaterThan(0));
        cache.clear();
        page.finishFirstRender();
        await tester.pump();
        await tester.pump();
        expect(
          page.renderCount,
          2,
          reason: 'תוצר מדור ישן צריך לפנות את הבקשה כדי שניתן יהיה לנסות שוב',
        );
        expect(page.images.first.disposeCount, 1);
        for (
          var i = 0;
          i < 100 && find.byType(RawImage).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byType(RawImage), findsOneWidget);
        expect(firstThumbnail(tester).image, isNotNull);
        expect(page.priorities, everyElement(PdfPageRenderPriority.low));
        expect(cache.length, 1);
        expect(budget.pendingBytes, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        cache.dispose();
        await disposePdfDocument(tester, document);
      }
      expect(page.images.map((image) => image.disposeCount), everyElement(1));
      expect(budget.estimatedBytes, 0);
      budget.dispose();
    },
  );

  testWidgets('שינוי DPR משחרר תמונה ישנה כשבלעדיו אין מקום לרינדור החדש', (
    tester,
  ) async {
    final document = _ControlledDocument();
    final page = document.page;
    final budget = PdfImageCacheBudget(maximumBytes: 8 * 1024 * 1024);
    final cache = PdfThumbnailCache(maxBytes: 4 * 1024 * 1024, budget: budget);
    final ref = PdfDocumentRefDirect(document);
    Widget harness(double pixelRatio) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(devicePixelRatio: pixelRatio),
          child: SizedBox(
            width: 160,
            height: 300,
            child: ThumbnailsView(
              documentRef: ref,
              controller: null,
              thumbnailCache: cache,
            ),
          ),
        ),
      ),
    );
    Future<void> waitForWidth(int width) async {
      for (var i = 0; i < 100; i++) {
        final images = find.byType(RawImage).evaluate();
        if (images.isNotEmpty && firstThumbnail(tester).image?.width == width) {
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    try {
      await tester.pumpWidget(harness(1));
      for (var i = 0; i < 10 && page.renderCount == 0; i++) {
        await tester.pump();
      }
      expect(page.renderCount, 1);
      page.finishFirstRender();
      await waitForWidth(page.images.first.width);
      final oldImage = firstThumbnail(tester).image!;
      final oldWidth = oldImage.width;
      final pixels = oldImage.width * oldImage.height;
      expect(budget.pendingBytes, 0);
      expect(budget.retainedBytes, pixels * 16);
      budget.maximumBytes = pixels * 52;
      await tester.pumpWidget(harness(2));
      await tester.pump();
      expect(
        page.renderCount,
        2,
        reason:
            'רינדור חדש דורש 48A ונכנס בתקציב 52A לאחר שחרור התמונה הישנה 8A',
      );
      await waitForWidth(oldWidth * 2);
      expect(firstThumbnail(tester).image!.width, oldWidth * 2);
      expect(budget.pendingBytes, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      cache.dispose();
      await disposePdfDocument(tester, document);
    }
    expect(budget.estimatedBytes, 0);
    budget.dispose();
  });
}

class _ControlledDocument extends Fake implements PdfDocument {
  late final page = _ControlledPage(this);
  @override
  String get sourceName => 'controlled-thumbnail.pdf';
  @override
  List<PdfPage> get pages => [page];
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {}
  @override
  Future<void> dispose() async {}
}

class _ControlledPage extends Fake implements PdfPage {
  _ControlledPage(this.document);
  @override
  final PdfDocument document;
  final _firstRender = Completer<PdfImage?>();
  final images = <_CountingPdfImage>[];
  final priorities = <PdfPageRenderPriority?>[];
  int renderCount = 0;
  @override
  int get pageNumber => 1;
  @override
  double get width => 200;
  @override
  double get height => 300;
  @override
  bool get isLoaded => true;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Token();
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
  }) {
    renderCount++;
    priorities.add(priority);
    final image = _CountingPdfImage(fullWidth!.round(), fullHeight!.round());
    images.add(image);
    return renderCount == 1 ? _firstRender.future : Future.value(image);
  }

  void finishFirstRender() => _firstRender.complete(images.first);
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _CountingPdfImage implements PdfImage {
  _CountingPdfImage(this.width, this.height)
    : pixels = Uint8List(width * height * 4);
  @override
  final int width;
  @override
  final int height;
  @override
  final Uint8List pixels;
  int disposeCount = 0;
  @override
  void dispose() => disposeCount++;
}
