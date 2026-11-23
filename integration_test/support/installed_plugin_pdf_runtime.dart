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
import '../../tool/perf_probe/src/installed_pdf_desktop_contract.dart';
import 'installed_plugin_memory_pressure.dart';
import 'installed_plugin_pdf_android.dart';
import 'installed_plugin_pdf_desktop_window.dart';
import 'installed_plugin_pdf_fixture.dart';
import 'installed_plugin_pdf_macos.dart';
import 'installed_plugin_pdf_ios.dart';
import 'installed_plugin_pdf_readiness.dart';
import 'installed_plugin_pdf_output_assertions.dart';

const _deadline = Duration(seconds: 45);

/// רץ מתוך האפליקציה המותקנת, בלי להחליף loader או ערוץ native.
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
        'Installed app: actual reader, indexing, vector export and raster; '
        'not physical printer or device-matrix acceptance.',
    'steps': {
      for (final name in installedPdfRuntimeSteps)
        name: <String, Object?>{'status': 'notRun'},
      if (installedPdfDesktopPlatforms.contains(Platform.operatingSystem)) ...{
        'desktopLifecycle': <String, Object?>{'status': 'notRun'},
        'repeatedLifecycle': <String, Object?>{'status': 'notRun'},
      },
    },
  });
  report.remove('reason');
  await checkpoint();
  try {
    expect(
      installedPdfRuntimePlatforms.contains(Platform.operatingSystem),
      true,
    );
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
  final _viewers = <PdfBookTab, _OwnedPdfViewer>{};
  PdfBookTab? _tab;
  PdfDocument? get _viewerDocument => _viewers[_tab]?.document;
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
      // בדיקות הנתונים משתמשות ב-expectSync בזמן שהקורא מצייר במקביל.
      await Future.wait([
        observed('indexing', () async {
          final result = await index(book);
          expectSync(result.isClean, true, reason: '${result.failures}');
          expectSync(result.indexedBooks, 1);
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
    if (installedPdfDesktopPlatforms.contains(Platform.operatingSystem)) {
      await phase('desktopLifecycle', () => desktopLifecycle(book, bytes));
    }
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
    if (installedPdfDesktopPlatforms.contains(Platform.operatingSystem)) {
      await phase('repeatedLifecycle', () => repeatedLifecycle(book));
    }
    await phase('loadedModules', loadedModules);
    await phase('teardown', () async {
      await cleanup();
      expect(_ownedTabs, isEmpty);
      expect(_ownedDocuments, isEmpty);
      expect(_viewers, isEmpty);
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
    final reader = find.byWidgetPredicate(
      (widget) => widget is PdfBookScreen && identical(widget.tab, tab),
    );
    expect(reader, findsOneWidget);
    _viewers[tab] = _OwnedPdfViewer(tab.pdfViewerController.document);
    await navigateInstalledPdfTarget(
      tab.pdfViewerController,
      page,
      nextFrame: tester.pump,
      wait: wait,
    );
  }

  Future<void> closeViewer([PdfBookTab? target]) async {
    final tab = target ?? _tab;
    if (tab == null) return;
    final controller = tab.pdfViewerController;
    if (!_viewers.containsKey(tab) && controller.isReady) {
      _viewers[tab] = _OwnedPdfViewer(controller.document);
    }
    tabs.add(RemoveTabs([tab]));
    await wait(
      () => !tabs.state.tabs.contains(tab) && !controller.isReady,
      'PDF tab host detached',
    );
    final viewer = _viewers[tab];
    if (viewer != null) {
      // הסגירה מתחילה בבעלות ה־viewer; ה־probe רק ממתין לסיום ה־native.
      await viewer.closed.future.timeout(_deadline);
      await viewer.document.dispose().timeout(_deadline);
      await viewer.events.cancel();
    }
    _viewers.remove(tab);
    _ownedTabs.remove(tab);
    if (identical(_tab, tab)) _tab = null;
  }

  Future<Map<String, Object?>> visibleReader(PdfBookTab tab, int page) async {
    final controller = tab.pdfViewerController;
    await tester.pump().timeout(_deadline);
    await wait(
      () =>
          identical(tabs.state.currentTab, tab) &&
          installedPdfTargetReady(controller, page),
      'PDF content returns after desktop transition',
    );
    expectSync(controller.document, same(_viewers[tab]!.document));
    return {
      'path': tab.book.path,
      'targetPage': page,
      'reportedPage': controller.pageNumber,
      'targetCenterVisible': true,
      'visibleRenderState': controller.visibleRenderState.value.name,
      'documentUnchanged': true,
      'navigationIssued': false,
      'viewWidth': controller.viewSize.width,
      'viewHeight': controller.viewSize.height,
    };
  }

  Future<void> selectPdfTab(PdfBookTab tab) async {
    _tab = tab;
    final index = tabs.state.tabs.indexOf(tab);
    expectSync(index, greaterThanOrEqualTo(0));
    tabs.add(SetCurrentTab(index));
    await wait(
      () => identical(tabs.state.currentTab, tab),
      'Select real PDF tab',
    );
  }

  Future<void> desktopLifecycle(PdfBook book, Uint8List bytes) async {
    final record = step('desktopLifecycle');
    final primary = _tab!;
    final secondaryFile = File(
      p.join(output.path, 'bundle-runtime-secondary.pdf'),
    );
    await secondaryFile.writeAsBytes(bytes, flush: true);
    final secondaryBook = PdfBook(
      title: 'בדיקת חבילת PDF — טאב שני',
      path: secondaryFile.path,
      source: BookSource.user,
    );
    final window = await InstalledPdfDesktopWindow.capture();
    record.addAll({
      'originalWindow': window.original,
      'primaryPath': book.path,
      'secondaryPath': secondaryBook.path,
      'activityMeaning':
          'Overlapping submitted raster and transition futures; native threads are not instrumented.',
      'physicalSleep': 'notRun',
      'multipleNativeWindows': 'notRun',
      'actions': <Map<String, Object?>>[],
      'tabCohorts': <Map<String, Object?>>[],
    });
    PdfBookTab? secondary;
    try {
      expect(window.original['ready'], true);
      await window.normalize();
      record['normalWindow'] = window.normal;
      await navigateInstalledPdfTarget(
        primary.pdfViewerController,
        2,
        nextFrame: tester.pump,
        wait: wait,
      );
      Future<void> cohort(int count) async {
        await selectPdfTab(primary);
        final reader = await visibleReader(primary, 2);
        final documents = <PdfDocument>{};
        final paths = <String>{};
        for (final tab in _ownedTabs) {
          expectSync(tabs.state.tabs, contains(tab));
          expectSync(tab.pdfViewerController.isReady, true);
          expectSync(
            tab.pdfViewerController.document,
            same(_viewers[tab]!.document),
          );
          documents.add(tab.pdfViewerController.document);
          paths.add(tab.book.path);
        }
        expectSync(documents, hasLength(count));
        expectSync(paths, hasLength(count));
        (record['tabCohorts']! as List).add({
          'tabCount': count,
          'nativeDocumentCount': documents.length,
          'paths': paths.toList(),
          'primaryReader': reader,
        });
      }

      await cohort(1);
      for (var index = 2; index <= 10; index++) {
        final nextBook = index == 2
            ? secondaryBook
            : PdfBook(
                title: 'בדיקת חבילת PDF — טאב $index',
                path: p.join(output.path, 'bundle-runtime-tab-$index.pdf'),
                source: BookSource.user,
              );
        if (index != 2) {
          await File(nextBook.path).writeAsBytes(bytes, flush: true);
        }
        await open(nextBook, index == 2 ? 3 : index % 4 + 1);
        if (index == 2) secondary = _tab!;
        if (index == 5 || index == 10) await cohort(index);
      }
      record['distinctDocuments'] = true;
      final clock = Stopwatch()..start();
      Future<void> transition(
        String name,
        Future<Map<String, Object?>> Function() change,
        PdfBookTab target,
        int page, {
        Map<String, Object?>? requestedBounds,
      }) async {
        final action = <String, Object?>{
          'name': name,
          'status': 'running',
          'beforeWindow': await InstalledPdfDesktopWindow.read(),
          'requestedBounds': ?requestedBounds,
        };
        (record['actions']! as List<Map<String, Object?>>).add(action);
        final activity = <String, Object?>{};
        final operation = <String, Object?>{};
        action.addAll({'activity': activity, 'transition': operation});
        Future<void> rasterize() async {
          activity['startUs'] = clock.elapsedMicroseconds;
          try {
            final raster = await Printing.raster(
              bytes,
              pages: [0],
              dpi: 72,
            ).timeout(_deadline).single;
            activity['raster'] = installedPdfRasterProof(
              raster.width,
              raster.height,
              raster.pixels,
              1,
            );
          } finally {
            activity['endUs'] = clock.elapsedMicroseconds;
          }
        }

        Future<void> changeWindowOrTab() async {
          operation['startUs'] = clock.elapsedMicroseconds;
          try {
            action['nativeAcknowledgement'] = await change();
            action['afterWindow'] = await window.reveal();
            action['reader'] = await visibleReader(target, page);
          } finally {
            operation['endUs'] = clock.elapsedMicroseconds;
          }
        }

        // הציור אינו מצפה לפריימים בזמן שהחלון מוסתר; שני המסלולים נסגרים גם בכשל.
        await Future.wait([rasterize(), changeWindowOrTab()]);
        action['status'] = 'passed';
        await checkpoint();
      }

      await transition('hide', window.hide, primary, 2);
      await transition('minimize', window.minimize, primary, 2);
      final requested = window.resizedBounds();
      await transition(
        'resize',
        () => window.resize(requested),
        primary,
        2,
        requestedBounds: requested,
      );
      final secondaryTab = secondary!;
      await transition(
        'switchSecondary',
        () async {
          await selectPdfTab(secondaryTab);
          return InstalledPdfDesktopWindow.read();
        },
        secondaryTab,
        3,
      );
      await transition(
        'switchPrimary',
        () async {
          await selectPdfTab(primary);
          return InstalledPdfDesktopWindow.read();
        },
        primary,
        2,
      );
      await transition(
        'memoryPressure',
        () async {
          await notifyInstalledPluginMemoryPressure();
          record['memoryPressureSource'] =
              'flutter/system memoryPressure (synthetic)';
          record['memoryPressureAcknowledged'] = true;
          for (final tab in _ownedTabs) {
            expectSync(tab.pdfViewerController.isReady, true);
            expectSync(
              tab.pdfViewerController.document,
              same(_viewers[tab]!.document),
            );
          }
          record['documentsRetainedAfterPressure'] = _ownedTabs.length;
          return InstalledPdfDesktopWindow.read();
        },
        primary,
        2,
      );
    } finally {
      try {
        record['restoredWindow'] = await window.restore();
        record['windowRestored'] = true;
      } finally {
        var closed = 0;
        Object? closeError;
        StackTrace? closeStack;
        for (final tab in _ownedTabs.toList().reversed) {
          if (identical(tab, primary)) continue;
          try {
            await closeViewer(tab);
            closed++;
          } catch (error, stack) {
            closeError ??= error;
            closeStack ??= stack;
          }
        }
        record['additionalNativeCloses'] = closed;
        record['secondaryNativeCloseCompleted'] =
            secondary != null && !_ownedTabs.contains(secondary);
        if (closeError != null) {
          Error.throwWithStackTrace(closeError, closeStack!);
        }
      }
    }
    await selectPdfTab(primary);
    record['restoredReader'] = await visibleReader(primary, 2);
  }

  Future<void> repeatedLifecycle(PdfBook book) async {
    final record = step('repeatedLifecycle');
    final cycles = <Map<String, Object?>>[];
    record.addAll({
      'requiredCycles': installedPdfRepeatedLifecycleCycles,
      'cycles': cycles,
      'deadlineSeconds': installedPdfRepeatedLifecycleTimeout.inSeconds,
    });
    var previous = _viewerDocument;
    await closeViewer();
    final clock = Stopwatch()..start();
    for (var cycle = 1; cycle <= installedPdfRepeatedLifecycleCycles; cycle++) {
      if (clock.elapsed >= installedPdfRepeatedLifecycleTimeout) {
        throw TimeoutException(
          'Fifty native PDF open/render/close cycles',
          clock.elapsed,
        );
      }
      final page = (cycle - 1) % installedPdfPageSizes.length + 1;
      final stageDurationMs = <String, double>{};
      final receipt = <String, Object?>{
        'cycle': cycle,
        'targetPage': page,
        'stageDurationMs': stageDurationMs,
      };
      cycles.add(receipt);
      final started = clock.elapsedMicroseconds;
      Future<T> timed<T>(String name, Future<T> Function() action) async {
        final stageStarted = clock.elapsedMicroseconds;
        try {
          return await action();
        } finally {
          stageDurationMs[name] =
              (clock.elapsedMicroseconds - stageStarted) / 1000;
        }
      }

      try {
        await timed('openAndReady', () => open(book, page));
        final document = _viewerDocument!;
        expect(identical(document, previous), false);
        receipt.addAll({
          'differentDocument': true,
          'visibleRenderState':
              _tab!.pdfViewerController.visibleRenderState.value.name,
          'targetCenterVisible': true,
          'raster': await timed(
            'nativeProof',
            () => checkNativePage(document.pages[page - 1], page),
          ),
        });
        previous = document;
      } finally {
        await timed('close', closeViewer);
        receipt['nativeCloseCompleted'] = true;
        receipt['ownedTabsRemaining'] = _ownedTabs.length;
        receipt['durationMs'] = (clock.elapsedMicroseconds - started) / 1000;
      }
      record['cyclesElapsedMs'] = clock.elapsedMicroseconds / 1000;
      if (clock.elapsed >= installedPdfRepeatedLifecycleTimeout) {
        throw TimeoutException(
          'Native PDF cycles exceeded the deadline after close',
          clock.elapsed,
        );
      }
      if (cycle % 10 == 0) await checkpoint();
    }
    record['completedCycles'] = cycles.length;
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
    expectSync(own, hasLength(installedPdfPageSizes.length));
    expectSync(own.every((hit) => hit.isPdf), true);
    final pages = own.map((hit) => hit.segment.toInt()).toList()..sort();
    expectSync(pages, [0, 1, 2, 3]);
    return pages;
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
      return installedPdfRasterProof(
        image!.width,
        image.height,
        image.pixels,
        number,
      );
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
    expectInstalledPdfRasterSupport(capabilities.canRaster);
    final rasters = <Map<String, Object?>>[];
    await for (final raster in Printing.raster(bytes, dpi: 72)) {
      rasters.add(
        installedPdfRasterProof(
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
    expectSync(rasters, hasLength(installedPdfPageSizes.length));
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
        expectSync(export.pages, hasLength(1));
        final page = export.pages.single;
        expectSync((page.width, page.height), (480.0, 320.0));
        final text = await page.loadStructuredText();
        for (final number in [2, 3]) {
          expectSync(text.fullText, contains(installedPdfPageToken(number)));
        }
        for (final number in [1, 4]) {
          expectSync(
            text.fullText,
            isNot(contains(installedPdfPageToken(number))),
          );
        }
        final right = text.fullText.indexOf(installedPdfPageToken(2));
        final left = text.fullText.indexOf(installedPdfPageToken(3));
        expectSync(
          text.charRects[right].left,
          greaterThan(text.charRects[left].left),
        );
        final raster = await Printing.raster(bytes, dpi: 72).single;
        expectSync((raster.width, raster.height), (480, 320));
        expectSync(raster.pixels, hasLength(480 * 320 * 4));
        var inkPixels = 0;
        for (var i = 0; i < raster.pixels.length; i += 4) {
          if (raster.pixels[i] < 128 &&
              raster.pixels[i + 1] < 128 &&
              raster.pixels[i + 2] < 128 &&
              raster.pixels[i + 3] == 255) {
            inkPixels++;
          }
        }
        expectSync(inkPixels, greaterThan(100));
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
      installedPdfRasterProof(raster.width, raster.height, raster.pixels, 1);
    }
    expect(received, 1);
    final recovered = await Printing.raster(bytes, pages: [3], dpi: 72).single;
    installedPdfRasterProof(
      recovered.width,
      recovered.height,
      recovered.pixels,
      4,
    );

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
          'The subscription was cancelled. The native job may keep running '
          'while recovery is requested.',
      'indexCancellationObserved': true,
      'indexRecoveryPages': installedPdfPageSizes.length,
      'originalIndexPreserved': true,
      'pdfrxRecovery': await checkNativePage(page, 1),
    });
  }

  Future<void> loadedModules() async {
    if (Platform.isAndroid) {
      step('loadedModules').addAll(await installedAndroidPdfModules(output));
      report['bundlePathsVerified'] = true;
      return;
    }
    if (Platform.isIOS) {
      step('loadedModules').addAll(await collectInstalledPdfIosImages(output));
      report['bundlePathsVerified'] = true;
      return;
    }
    if (Platform.isMacOS) {
      final images = await collectInstalledPdfMacosImages(output);
      step('loadedModules').addAll(images);
      report['bundlePathsVerified'] = true;
      return;
    }
    final directory = await Directory(
      p.dirname(Platform.resolvedExecutable),
    ).resolveSymbolicLinks();
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
        bundleDirectory: directory,
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
    Object? closeError;
    StackTrace? closeStack;
    for (final tab in _ownedTabs.toList().reversed) {
      try {
        await closeViewer(tab);
      } catch (error, stack) {
        closeError ??= error;
        closeStack ??= stack;
      }
    }
    report.addAll({
      'ownedDocumentsRemaining': _ownedDocuments.length + _viewers.length,
      'ownedTabsRemaining': _ownedTabs.length,
      'indexingActiveAfter': provider.isIndexing.value,
    });
    if (closeError != null) Error.throwWithStackTrace(closeError, closeStack!);
  }
}

class _OwnedPdfViewer {
  _OwnedPdfViewer(this.document) {
    events = document.events.listen((_) {}, onDone: closed.complete);
  }

  final PdfDocument document;
  final closed = Completer<void>();
  late final StreamSubscription<PdfDocumentEvent> events;
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
