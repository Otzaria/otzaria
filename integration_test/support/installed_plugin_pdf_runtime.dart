import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/pdf_book/utils/pdf_viewer_activity.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/printing/pdf_sheet_composer.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:win32/win32.dart' as win;

import '../../tool/perf_probe/src/installed_pdf_runtime_contract.dart';
import 'installed_plugin_pdf_fixture.dart';
import 'installed_plugin_pdf_readiness.dart';

const _deadline = Duration(seconds: 45);

/// רץ בתוך חבילת שולחן העבודה, בלי להחליף loader או ערוץ native.
Future<void> runInstalledPdfRuntime({
  required WidgetTester tester,
  required BuildContext context,
  required Directory output,
  required Map<String, Object?> report,
  required Future<void> Function() checkpoint,
}) async {
  final probe = _PdfRuntime(tester, context, output, report, checkpoint);
  report.addAll({
    'status': 'running',
    'platform': Platform.operatingSystem,
    'executable': Platform.resolvedExecutable,
    'physicalPrinter': 'notRun',
    'scope':
        'Desktop bundle: actual reader, indexing, vector export and raster; '
        'not physical printer or device-matrix acceptance.',
    'steps': {
      for (final name in installedPdfRuntimeSteps)
        name: <String, Object?>{'status': 'notRun'},
    },
  });
  report.remove('reason');
  await checkpoint();
  try {
    expect(Platform.isLinux || Platform.isWindows, true);
    await probe.run();
    report['status'] = 'passed';
    expect(
      installedPdfRuntimeErrors(report, platform: Platform.operatingSystem),
      isEmpty,
    );
  } catch (error, stack) {
    report.addAll({'status': 'failed', 'error': '$error\n$stack'});
    rethrow;
  } finally {
    try {
      await probe.cleanup();
    } catch (error, stack) {
      report.addAll({'status': 'failed', 'cleanupError': '$error\n$stack'});
      rethrow;
    } finally {
      await checkpoint();
    }
  }
}

class _PdfRuntime {
  _PdfRuntime(
    this.tester,
    this.context,
    this.output,
    this.report,
    this.checkpoint,
  );

  final WidgetTester tester;
  final BuildContext context;
  final Directory output;
  final Map<String, Object?> report;
  final Future<void> Function() checkpoint;
  late final TabsBloc tabs = context.read<TabsBloc>();
  late final provider = TantivyDataProvider.instance;
  late final repository = IndexingRepository(
    provider,
    indexPdfBooks: () => true,
    indexUpdateMode: () => IndexUpdateMode.all,
  );
  final library = Library(categories: []);
  final _ownedDocuments = <PdfDocument>{};
  final _ownedTabs = <PdfBookTab>{};
  PdfBookTab? _tab;
  PdfDocument? _viewerDocument;
  StreamSubscription<PdfDocumentEvent>? _viewerEvents;
  Completer<void>? _viewerClosed;
  Future<IndexingRunResult>? _indexing;

  Map<String, Object?> step(String name) =>
      (report['steps'] as Map)[name] as Map<String, Object?>;

  Future<void> phase(String name, Future<void> Function() action) async {
    final record = step(name)..['status'] = 'running';
    final clock = Stopwatch()..start();
    await checkpoint();
    try {
      await action();
      record['status'] = 'passed';
    } catch (error) {
      record.addAll({'status': 'failed', 'error': error.toString()});
      rethrow;
    } finally {
      record['durationMs'] = clock.elapsedMicroseconds / 1000;
      await checkpoint();
    }
  }

  Future<void> wait(
    bool Function() ready,
    String description, {
    Duration timeout = _deadline,
  }) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      if (clock.elapsed >= timeout) {
        final controller = _tab?.pdfViewerController;
        throw TimeoutException(
          '$description; '
          'selected=${_tab != null && identical(tabs.state.currentTab, _tab)}; '
          'readerWidgets=${find.byType(PdfBookScreen).evaluate().length}; '
          'lifecycle=${WidgetsBinding.instance.lifecycleState?.name}; '
          'controllerReady=${controller?.isReady}; '
          'render=${controller?.visibleRenderState.value.name}'
          '${controller != null && installedPdfLayoutReady(controller, 1) ? '; page=${controller.pageNumber}; '
                    'zoom=${controller.currentZoom}; view=${controller.viewSize}; '
                    'visible=${controller.visibleRect}; '
                    'pages=${controller.layout.pageLayouts.take(installedPdfPageSizes.length).toList()}' : ''}',
          timeout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> run() async {
    expect(provider.isIndexing.value, false);
    final bytes = createInstalledPdfFixture();
    final file = File(p.join(output.path, 'bundle-runtime.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    final book = PdfBook(
      title: 'בדיקת חבילת PDF',
      path: file.path,
      source: BookSource.user,
    );
    library.books.add(book);
    report['fixture'] = {
      'path': file.path,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
      'pages': installedPdfPageSizes.length,
      'content':
          'Deterministic vector text and black rectangle; mixed page sizes.',
    };
    await phase('view', () async {
      await open(book, 1);
      step('view').addAll({
        'screen': 'PdfBookScreen',
        'visibleRenderState':
            _tab!.pdfViewerController.visibleRenderState.value.name,
        'meaning':
            'Final page images painted into the layer tree, not a GPU-present measurement.',
        'targetPage': 1,
        'reportedPage': _tab!.pdfViewerController.pageNumber,
        'targetCenterVisible': true,
        'raster': await checkNativePage(_viewerDocument!.pages.first, 1),
      });
    });
    await phase('concurrentWork', () async {
      final intervals = <String, Object?>{};
      final clock = Stopwatch()..start();
      Future<void> observed(String name, Future<void> Function() action) async {
        final interval = <String, Object?>{
          'startUs': clock.elapsedMicroseconds,
        };
        intervals[name] = interval;
        try {
          await action();
        } finally {
          interval['endUs'] = clock.elapsedMicroseconds;
        }
      }

      step('concurrentWork')['submittedOperations'] = intervals;
      await Future.wait([
        observed('indexing', () async {
          final result = await index(book);
          expect(result.isClean, true, reason: '${result.failures}');
          expect(result.indexedBooks, 1);
          step('concurrentWork')['indexedPages'] = await verifyIndex(book);
        }),
        observed('printing', () => printAndExport(file.path, bytes)),
        observed('viewing', () async {
          await navigateInstalledPdfTarget(
            _tab!.pdfViewerController,
            4,
            nextFrame: tester.pump,
            wait: wait,
          );
          step('concurrentWork').addAll({
            'viewerTargetPage': 4,
            'viewerReportedPage': _tab!.pdfViewerController.pageNumber,
            'targetCenterVisible': true,
          });
          step('concurrentWork')['viewerRaster'] = await checkNativePage(
            _viewerDocument!.pages.last,
            4,
          );
        }),
      ]);
    });
    await phase('cancelAndRecover', () => cancelAndRecover(book, bytes));
    await phase('reopen', () async {
      final old = _viewerDocument;
      await closeViewer();
      await open(book, 2);
      expect(identical(old, _viewerDocument), false);
      step('reopen').addAll({
        'differentDocument': true,
        'previousNativeCloseCompleted': true,
        'targetPage': 2,
        'reportedPage': _tab!.pdfViewerController.pageNumber,
        'targetCenterVisible': true,
        'visibleRenderState':
            _tab!.pdfViewerController.visibleRenderState.value.name,
        'raster': await checkNativePage(_viewerDocument!.pages[1], 2),
      });
    });
    await phase('loadedModules', loadedModules);
    await phase('teardown', () async {
      await cleanup();
      expect(_ownedTabs, isEmpty);
      expect(_ownedDocuments, isEmpty);
      expect(provider.isIndexing.value, false);
      expect(PdfViewerActivity.instance.loadingCount.value, 0);
      step('teardown').addAll({
        'viewerDetached': true,
        'viewerNativeCloseCompleted': true,
        'viewerLoadingCount': PdfViewerActivity.instance.loadingCount.value,
      });
    });
  }

  Future<void> open(PdfBook book, int page) async {
    final tab = _tab = PdfBookTab(book: book, pageNumber: page);
    _ownedTabs.add(tab);
    tabs.add(AddTab(tab));
    context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
    await wait(
      () => tabs.state.currentTab == tab && tab.pdfViewerController.isReady,
      'Actual PDF reader opens',
    );
    expect(find.byType(PdfBookScreen), findsOneWidget);
    expect(
      tester.widget<PdfBookScreen>(find.byType(PdfBookScreen)).tab,
      same(tab),
    );
    _viewerDocument = tab.pdfViewerController.document;
    final closed = _viewerClosed = Completer<void>();
    _viewerEvents = _viewerDocument!.events.listen(
      (_) {},
      onDone: closed.complete,
    );
    await navigateInstalledPdfTarget(
      tab.pdfViewerController,
      page,
      nextFrame: tester.pump,
      wait: wait,
    );
  }

  Future<void> closeViewer() async {
    final tab = _tab;
    if (tab == null) return;
    final controller = tab.pdfViewerController;
    tabs.add(RemoveTabs([tab]));
    await wait(
      () => !tabs.state.tabs.contains(tab) && !controller.isReady,
      'PDF tab host detached',
    );
    final document = _viewerDocument;
    if (document != null) {
      // Wait for the app to request disposal before joining its native close.
      await _viewerClosed!.future.timeout(_deadline);
      await document.dispose();
    }
    await _viewerEvents?.cancel();
    _viewerEvents = null;
    _viewerClosed = null;
    _viewerDocument = null;
    _ownedTabs.remove(tab);
    _tab = null;
  }

  Future<IndexingRunResult> index(
    PdfBook book, {
    void Function()? onStarted,
  }) async {
    final pending = _indexing = repository.runIndexing(
      library,
      books: [book],
      onProgress: (_, _) {},
      onActualIndexingStarted: onStarted,
    );
    try {
      return await pending;
    } finally {
      _indexing = null;
    }
  }

  Future<List<int>> verifyIndex(PdfBook book) async {
    final hits = await const SearchRepository().searchLiteralPhrase(
      installedPdfQuery,
      [],
      100,
    );
    final own = hits
        .where((hit) => hit.filePath == BookIdentity.indexedFilePath(book))
        .toList();
    expect(own, hasLength(installedPdfPageSizes.length));
    expect(own.every((hit) => hit.isPdf), true);
    final pages = own.map((hit) => hit.segment.toInt()).toList()..sort();
    expect(pages, [0, 1, 2, 3]);
    return pages;
  }

  Map<String, Object?> rasterProof(
    int width,
    int height,
    Uint8List pixels,
    int page,
  ) {
    final size = installedPdfPageSizes[page - 1];
    expect((width, height), (size.width, size.height));
    expect(pixels, hasLength(width * height * 4));
    final dark = ((height - 40) * width + 40) * 4;
    final light = (4 * width + 4) * 4;
    expect(pixels.sublist(dark, dark + 4), [0, 0, 0, 255]);
    expect(pixels.sublist(light, light + 4), [255, 255, 255, 255]);
    return {
      'page': page,
      'width': width,
      'height': height,
      'pixelSha256': sha256.convert(pixels).toString(),
      'contentPixelsVerified': true,
    };
  }

  Future<Map<String, Object?>> checkNativePage(PdfPage page, int number) async {
    final text = await page.loadText();
    expect(text?.fullText, contains(installedPdfPageToken(number)));
    final image = await page.render(
      fullWidth: page.width,
      fullHeight: page.height,
    );
    expect(image, isNotNull);
    try {
      return rasterProof(image!.width, image.height, image.pixels, number);
    } finally {
      image?.dispose();
    }
  }

  Future<void> withDocument(
    PrintPdfSource source,
    Future<void> Function(PdfDocument) use,
  ) async {
    final document = await source.open(useProgressiveLoading: false);
    _ownedDocuments.add(document);
    try {
      await use(document);
    } finally {
      await document.dispose();
      _ownedDocuments.remove(document);
    }
  }

  Future<void> printAndExport(String path, Uint8List bytes) async {
    final capabilities = await Printing.info();
    expect(capabilities.canRaster, true);
    final rasters = <Map<String, Object?>>[];
    await for (final raster in Printing.raster(bytes, dpi: 72)) {
      rasters.add(
        rasterProof(
          raster.width,
          raster.height,
          raster.pixels,
          rasters.length + 1,
        ),
      );
      if (rasters.length == 1) {
        await File(
          p.join(output.path, 'bundle-runtime-print.png'),
        ).writeAsBytes(await raster.toPng());
      }
    }
    expect(rasters, hasLength(installedPdfPageSizes.length));
    step('concurrentWork')['printingRasters'] = rasters;
    await withDocument(PrintPdfSource.file(path), (source) async {
      final bytes = await composePdfSheets(
        source,
        firstIndex: 1,
        lastIndex: 2,
        rows: 1,
        cols: 2,
        sheetWidth: 480,
        sheetHeight: 320,
      );
      await File(
        p.join(output.path, 'bundle-runtime-export.pdf'),
      ).writeAsBytes(bytes, flush: true);
      await withDocument(PrintPdfSource.data(bytes), (export) async {
        expect(export.pages, hasLength(1));
        final page = export.pages.single;
        expect((page.width, page.height), (480.0, 320.0));
        final text = await page.loadStructuredText();
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
        final raster = await Printing.raster(bytes, dpi: 72).single;
        expect((raster.width, raster.height), (480, 320));
        expect(raster.pixels, hasLength(480 * 320 * 4));
        var inkPixels = 0;
        for (var i = 0; i < raster.pixels.length; i += 4) {
          if (raster.pixels[i] < 128 &&
              raster.pixels[i + 1] < 128 &&
              raster.pixels[i + 2] < 128 &&
              raster.pixels[i + 3] == 255) {
            inkPixels++;
          }
        }
        expect(inkPixels, greaterThan(100));
        await File(
          p.join(output.path, 'bundle-runtime-export.png'),
        ).writeAsBytes(await raster.toPng());
        step('concurrentWork')['vectorExport'] = {
          'sourcePages': [2, 3],
          'sheets': 1,
          'textPreserved': true,
          'rightToLeft': true,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'printingRasterVerified': true,
          'printingInkPixels': inkPixels,
        };
      });
    });
  }

  Future<void> cancelAndRecover(PdfBook book, Uint8List bytes) async {
    final page = _viewerDocument!.pages.first;
    final token = page.createCancellationToken()..cancel();
    final canceledImage = await page.render(cancellationToken: token);
    try {
      expect(canceledImage, isNull);
    } finally {
      canceledImage?.dispose();
    }
    var received = 0;
    await for (final raster in Printing.raster(bytes, dpi: 72).take(1)) {
      received++;
      rasterProof(raster.width, raster.height, raster.pixels, 1);
    }
    expect(received, 1);
    final recovered = await Printing.raster(bytes, pages: [3], dpi: 72).single;
    rasterProof(recovered.width, recovered.height, recovered.pixels, 4);

    final cancelFile = File(p.join(output.path, 'bundle-runtime-cancel.pdf'));
    await cancelFile.writeAsBytes(bytes);
    final canceledBook = PdfBook(
      title: 'בדיקת ביטול PDF',
      path: cancelFile.path,
      source: BookSource.user,
    );
    library.books.add(canceledBook);
    var requested = false;
    final canceled = await index(
      canceledBook,
      onStarted: () {
        requested = true;
        repository.cancelIndexing();
      },
    );
    expect(requested, true);
    expect(canceled.cancelled, true);
    expect(canceled.failures, isEmpty);
    expect(canceled.indexedBooks, 0);
    expect(provider.isIndexing.value, false);
    final resumed = await index(canceledBook);
    expect(resumed.isClean, true, reason: '${resumed.failures}');
    expect(resumed.indexedBooks, 1);
    await verifyIndex(canceledBook);
    await verifyIndex(book);
    step('cancelAndRecover').addAll({
      'preCanceledPdfrxRenderReturnedNull': true,
      'printingSubscriptionCanceledAfterPages': received,
      'printingRecoveryPage': 4,
      'printingCancellationScope':
          'Subscription cancellation; native job may finish. Recovery raster waits behind it.',
      'indexCancellationObserved': true,
      'indexRecoveryPages': installedPdfPageSizes.length,
      'originalIndexPreserved': true,
      'pdfrxRecovery': await checkNativePage(page, 1),
    });
  }

  Future<void> loadedModules() async {
    final directory = p.dirname(Platform.resolvedExecutable);
    final names = installedPdfRuntimeModules[Platform.operatingSystem]!;
    final Set<String> observed;
    if (Platform.isWindows) {
      final unresolved = <Map<String, Object?>>[];
      observed = _windowsModulePaths(unresolved);
      step('loadedModules')['unresolvedModuleHandles'] = unresolved;
      await File(
        p.join(output.path, 'bundle-runtime-modules.json'),
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'pid': pid,
          'source': 'EnumProcessModules / GetModuleFileNameW',
          'paths': observed.toList()..sort(),
          'unresolvedModuleHandles': unresolved,
        }),
        flush: true,
      );
    } else {
      final maps = await File('/proc/self/maps').readAsString();
      await File(
        p.join(output.path, 'bundle-runtime-maps.txt'),
      ).writeAsString(maps, flush: true);
      observed = installedPdfMappedPaths(maps);
    }
    final expected = <String, String>{};
    final modules = <Map<String, Object?>>[];
    for (final name in names) {
      final file = File(
        Platform.isWindows
            ? p.join(directory, name)
            : p.join(directory, 'lib', name),
      );
      expected[name] = await file.resolveSymbolicLinks();
      modules.add({
        'name': name,
        'path': expected[name],
        'bytes': await file.length(),
        'sha256': (await sha256.bind(file.openRead()).first).toString(),
      });
    }
    final mapped = <String>{};
    for (final path in observed) {
      if (Platform.isWindows) {
        if (names.contains(p.basename(path).toLowerCase())) {
          mapped.add(await File(path).resolveSymbolicLinks());
        }
      } else {
        mapped.add(path);
      }
    }
    step('loadedModules').addAll({
      'modules': modules,
      'observedModulePaths': mapped.toList()..sort(),
      'configuredPdfrxModule': Pdfrx.pdfiumModulePath,
    });
    expect(
      installedPdfModuleErrors(
        platform: Platform.operatingSystem,
        mappedPaths: mapped,
        expectedPaths: expected,
      ),
      isEmpty,
    );
    expect(modules[0]['sha256'], isNot(modules[1]['sha256']));
    report['bundlePathsVerified'] = true;
  }

  Future<void> cleanup() async {
    if (_indexing case final pending?) {
      repository.cancelIndexing();
      await pending;
    }
    await closeViewer();
    report.addAll({
      'ownedDocumentsRemaining': _ownedDocuments.length,
      'ownedTabsRemaining': _ownedTabs.length,
      'indexingActiveAfter': provider.isIndexing.value,
    });
  }
}

/// הידיות בתצלום שייכות ל־loader; אין לסגור אותן או לשנות את נתיב הטעינה.
Set<String> _windowsModulePaths(
  List<Map<String, Object?>> unresolved,
) => using((arena) {
  final needed = arena<Uint32>();
  final pointerBytes = sizeOf<Pointer<Void>>();
  final buffer = arena<Uint16>(32768).cast<Utf16>();
  for (var capacity = 256; capacity <= 16384; capacity *= 2) {
    final modules = arena<Pointer<Void>>(capacity);
    final result = win.EnumProcessModules(
      win.GetCurrentProcess(),
      modules,
      capacity * pointerBytes,
      needed,
    );
    if (!result.value) {
      throw StateError('EnumProcessModules failed: ${result.error}');
    }
    if (needed.value > capacity * pointerBytes) {
      continue;
    }
    final paths = <String>{};
    for (var i = 0; i < needed.value ~/ pointerBytes; i++) {
      final name = win.GetModuleFileName(
        win.HMODULE(modules[i]),
        win.PWSTR(buffer),
        32768,
      );
      if (name.value == 0) {
        // DLL אחר יכול להיפרק אחרי התצלום; שלושת מודולי ה־PDF עדיין נדרשים בשמם.
        unresolved.add({
          'handle': '0x${modules[i].address.toRadixString(16)}',
          'error': '${name.error}',
        });
        continue;
      }
      if (name.value >= 32768) {
        throw StateError(
          'GetModuleFileNameW failed or truncated: ${name.error}',
        );
      }
      paths.add(buffer.toDartString(length: name.value));
    }
    return paths;
  }
  throw StateError('Loaded module list exceeds the bounded snapshot capacity');
});
