import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/pdf_sheet_composer.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/installed_plugin_pdf_fixture.dart';
import '../../../integration_test/support/installed_plugin_pdf_readiness.dart';
import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldModule = Pdfrx.pdfiumModulePath;
  late Directory temporary;
  setUpAll(() async {
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    temporary = await Directory.systemTemp.createTemp('bundle-pdf-fixture-');
    await pdfrxInitialize(tmpPath: temporary.path);
  });
  tearDownAll(() async {
    Pdfrx.pdfiumModulePath = oldModule;
    await temporary.delete(recursive: true);
  });

  test('fixture bytes are reproducible', () {
    final first = createInstalledPdfFixture();
    expect(first, createInstalledPdfFixture());
  });

  testWidgets('target readiness waits for the navigated viewport to paint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final document = (await tester.runAsync(
      () => PdfDocument.openData(createInstalledPdfFixture()),
    ))!;
    final controller = PdfViewerController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(document.dispose);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
        ),
      ),
    );
    Future<void> paintPage(int page) async {
      final clock = Stopwatch()..start();
      while (!installedPdfTargetReady(controller, page)) {
        expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await paintPage(1);
    expect(installedPdfTargetReady(controller, 4), false);
    await tester.runAsync(
      () => controller.goToPage(pageNumber: 4, duration: Duration.zero),
    );
    expect(
      controller.visibleRect.contains(controller.layout.pageLayouts[3].center),
      true,
    );
    expect(installedPdfTargetReady(controller, 4), false);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    await paintPage(4);
    controller.setCurrentPageNumber(3);
    expect(controller.pageNumber, 3);
    expect(installedPdfTargetReady(controller, 4), true);

    // Drain the viewer's trailing-load timer before Flutter checks test invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(
      const PdfViewerBehaviorControlParams().trailingPageLoadingDelay,
    );
  });

  testWidgets('a top-aligned ready reader navigates before target readiness', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final document = (await tester.runAsync(
      () => PdfDocument.openData(createInstalledPdfFixture()),
    ))!;
    final controller = PdfViewerController();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            params: const PdfViewerParams(
              sizeDelegateProvider: PdfViewerSizeDelegateProviderSmart(
                maxScale: 20,
                smartMaxScale: 20,
                maxPagesVisible: 1,
              ),
            ),
          ),
        ),
      );
      Future<void> wait(
        bool Function() ready,
        String description, {
        Duration timeout = const Duration(seconds: 10),
      }) async {
        final clock = Stopwatch()..start();
        while (!ready()) {
          expect(
            clock.elapsed,
            lessThan(timeout),
            reason: description,
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      await wait(
        () =>
            controller.isReady &&
            controller.visibleRenderState.value == PdfVisibleRenderState.ready,
        'initial top-aligned image',
      );
      expect(installedPdfTargetReady(controller, 1), false);
      final initialZoom = controller.currentZoom;
      var frames = 0;
      await navigateInstalledPdfTarget(
        controller,
        1,
        nextFrame: () async {
          frames++;
          await tester.pump();
        },
        wait: wait,
        timeout: const Duration(seconds: 10),
      );
      expect(frames, 1);
      expect(controller.currentZoom, closeTo(initialZoom, 0.000001));
      expect(installedPdfTargetReady(controller, 1), true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(
        const PdfViewerBehaviorControlParams().trailingPageLoadingDelay,
      );
      await tester.runAsync(document.dispose);
    }
  });

  test(
    'real PDFium extracts every page and renders the expected content pixels',
    () async {
      final document = await PdfDocument.openData(createInstalledPdfFixture());
      addTearDown(document.dispose);
      expect(document.pages, hasLength(installedPdfPageSizes.length));
      for (var i = 0; i < document.pages.length; i++) {
        final page = document.pages[i];
        final size = installedPdfPageSizes[i];
        expect(
          (page.width, page.height),
          (size.width.toDouble(), size.height.toDouble()),
        );
        final text = await page.loadText();
        expect(text!.fullText, contains(installedPdfQuery));
        expect(text.fullText, contains(installedPdfPageToken(i + 1)));
        final image = await page.render(
          fullWidth: page.width,
          fullHeight: page.height,
          backgroundColor: 0x00000000,
        );
        expect(image, isNotNull);
        try {
          expect((image!.width, image.height), (size.width, size.height));
          final dark = ((image.height - 40) * image.width + 40) * 4;
          expect(image.pixels.sublist(dark, dark + 4), [0, 0, 0, 255]);
          final light = (4 * image.width + 4) * 4;
          expect(image.pixels.sublist(light, light + 4), [255, 255, 255, 255]);
        } finally {
          image?.dispose();
        }
      }
    },
  );

  test(
    'range export retains only the selected vector text in RTL order',
    () async {
      final source = await PdfDocument.openData(createInstalledPdfFixture());
      addTearDown(source.dispose);
      final bytes = await composePdfSheets(
        source,
        firstIndex: 1,
        lastIndex: 2,
        rows: 1,
        cols: 2,
        sheetWidth: 480,
        sheetHeight: 320,
      );
      final exported = await PrintPdfSource.data(bytes).open();
      addTearDown(exported.dispose);
      expect(exported.pages, hasLength(1));
      final text = await exported.pages.single.loadStructuredText();
      for (final number in [2, 3]) {
        expect(text.fullText, contains(installedPdfPageToken(number)));
      }
      for (final number in [1, 4]) {
        expect(text.fullText, isNot(contains(installedPdfPageToken(number))));
      }
      final right = text.fullText.indexOf(installedPdfPageToken(2));
      final left = text.fullText.indexOf(installedPdfPageToken(3));
      expect(
        text.charRects[right].left,
        greaterThan(text.charRects[left].left),
      );
    },
  );

  test(
    'canceling native render leaves the document usable before explicit close',
    () async {
      final document = await PdfDocument.openData(createInstalledPdfFixture());
      addTearDown(document.dispose);
      final page = document.pages.first;
      final token = page.createCancellationToken()..cancel();
      final canceled = await page.render(cancellationToken: token);
      try {
        expect(canceled, isNull);
      } finally {
        canceled?.dispose();
      }
      final image = await page.render();
      expect(image, isNotNull);
      image!.dispose();
      await document.dispose();
      final reopened = await PdfDocument.openData(createInstalledPdfFixture());
      addTearDown(reopened.dispose);
      expect(
        (await reopened.pages.last.loadText())!.fullText,
        contains(installedPdfPageToken(4)),
      );
    },
  );

  test(
    'real indexing cancellation and recovery preserve searchable PDF pages',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      expect(await tryInitSearchEngine(), true, reason: searchEngineSkipReason);
      AppPaths.debugOverrideDataRootPath(temporary.path);
      addTearDown(() => AppPaths.debugOverrideDataRootPath(null));
      final indexPath = await Directory('${temporary.path}/index').create();
      final engine = await SearchEngine.newInstance(path: indexPath.path);
      addTearDown(() async {
        await engine.closeIndexWriter();
        engine.dispose();
      });
      final provider = TantivyDataProvider.forTesting(Future.value(engine))
        ..activeIndexPath = indexPath.path
        ..isInitialized.value = true;
      TantivyDataProvider.instance = provider;
      final repository = IndexingRepository(
        provider,
        indexPdfBooks: () => true,
        indexUpdateMode: () => IndexUpdateMode.all,
      );
      final file = await File(
        '${temporary.path}/indexed.pdf',
      ).writeAsBytes(createInstalledPdfFixture());
      final book = PdfBook(
        title: 'מסמך בדיקה',
        path: file.path,
        source: BookSource.user,
      );
      final library = Library(categories: [])..books.add(book);
      var cancellationRequested = false;
      final canceled = await repository.runIndexing(
        library,
        books: [book],
        onProgress: (_, _) {},
        onActualIndexingStarted: () {
          cancellationRequested = true;
          repository.cancelIndexing();
        },
      );
      expect(cancellationRequested, true);
      expect(canceled.cancelled, true);
      expect(canceled.failures, isEmpty);
      expect(canceled.indexedBooks, 0);
      expect(provider.isIndexing.value, false);
      final complete = await repository.runIndexing(
        library,
        books: [book],
        onProgress: (_, _) {},
      );
      expect(complete.isClean, true, reason: '${complete.failures}');
      expect(complete.indexedBooks, 1);
      final hits = await const SearchRepository().searchLiteralPhrase(
        installedPdfQuery,
        [],
        100,
      );
      expect(hits, hasLength(installedPdfPageSizes.length));
      expect(
        hits.every(
          (hit) =>
              hit.isPdf && hit.filePath == BookIdentity.indexedFilePath(book),
        ),
        true,
      );
      expect(hits.map((hit) => hit.segment.toInt()).toList()..sort(), [
        0,
        1,
        2,
        3,
      ]);
      expect(provider.isIndexing.value, false);
    },
  );
}
