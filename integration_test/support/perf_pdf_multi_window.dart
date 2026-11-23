import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
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
import 'package:window_manager/window_manager.dart';

import '../../tool/perf_probe/src/pdf_multi_window.dart';
import '../../tool/perf_probe/src/pdf_reader_case.dart';
import 'installed_plugin_pdf_readiness.dart';
import 'perf_fixture.dart';
import 'perf_probe_wait.dart';

typedef PerfPdfMultiWindowPhase =
    Future<void> Function(
      String name,
      Future<void> Function() action, {
      Map<String, Object?>? details,
      Duration? observationWindow,
    });

/// מפעיל חלונות וקוראים דרך מסלולי האפליקציה ובודק רק משאבים שבבעלות התרחיש.
Future<Map<String, Object?>> runPerfPdfMultiWindow({
  required WidgetController controller,
  required BuildContext context,
  required PerfFixture fixture,
  required Directory output,
  required PerfPdfMultiWindowPhase phase,
}) async {
  final directory = await output.createTemp('pdf-multi-window-');
  final probe = _MultiWindowProbe(controller, context, fixture, directory);
  await phase('pdf_multi_window', probe.run, details: probe.report);
  return probe.report;
}

const _deadline = Duration(seconds: 45);

void _require(bool condition, String description) {
  if (!condition) throw StateError(description);
}

class _Reader {
  _Reader({
    required this.tab,
    required this.tabs,
    required this.window,
    required this.viewId,
    required this.nativeHandle,
    this.entry,
  }) : document = tab.pdfViewerController.document {
    events = document.events.listen(
      (_) {},
      onError: (Object error, StackTrace stack) => eventError = error,
      onDone: () => closed.complete(),
    );
  }

  final PdfBookTab tab;
  final TabsBloc tabs;
  final AppWindowController window;
  final int viewId;
  final int nativeHandle;
  final ViewWindowEntry? entry;
  final PdfDocument document;
  final closed = Completer<void>();
  late final StreamSubscription<PdfDocumentEvent> events;
  Object? eventError;
  bool nativeClosed = false;
}

class _MultiWindowProbe {
  _MultiWindowProbe(this.driver, this.context, this.fixture, this.output);

  final WidgetController driver;
  final BuildContext context;
  final PerfFixture fixture;
  final Directory output;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'status': 'running',
    'platform': Platform.operatingSystem,
    'bindingMode': 'framework',
    'scope': 'Actual app readers in native windows, indexing and PDF output.',
    'overlapMeaning':
        'Intervals of submitted and awaited work; not proof of native parallelism.',
    'readiness': 'Final visible image in the layer tree; no GPU presentation claim.',
    'physicalSleep': 'notRun',
    'physicalPrinter': 'notRun',
    'steps': <String, Object?>{},
  };

  final registry = ViewWindowRegistry.instance;
  late final primaryTabs = context.read<TabsBloc>();
  late final provider = TantivyDataProvider.instance;
  late final repository = IndexingRepository(
    provider,
    indexPdfBooks: () => true,
    indexUpdateMode: () => IndexUpdateMode.all,
  );
  final _readers = <_Reader>{};
  final _windows = <ViewWindowEntry, int>{};
  final _documents = <PdfDocument>{};
  final _unreadyTabs = <PdfBookTab, TabsBloc>{};
  final _pendingOperations = <Future<void>>{};
  final _initialWindows = <ViewWindowEntry>{};
  List<int> _initialViews = const [];
  Future<IndexingRunResult>? _indexing;
  bool _cleaningUp = false;
  _Reader? _primary;
  late PdfBook _primaryBook;
  late PdfBook _secondaryBook;
  late PdfDocument _rasterDocument;

  List<int> get _viewIds =>
      ui.PlatformDispatcher.instance.views.map((view) => view.viewId).toList()
        ..sort();

  Map<String, Object?> _record(String name) =>
      (report['steps'] as Map<String, Object?>)[name] as Map<String, Object?>;

  Future<void> _checkpoint() async {
    final temporary = File(p.join(output.path, 'report.pending'));
    await temporary.writeAsString(jsonEncode(report), flush: true);
    await temporary.rename(p.join(output.path, 'report.json'));
  }

  Future<void> _step(String name, Future<void> Function() action) async {
    final record = <String, Object?>{'status': 'running'};
    (report['steps'] as Map<String, Object?>)[name] = record;
    await _checkpoint();
    final clock = Stopwatch()..start();
    try {
      await action();
      record['status'] = 'passed';
    } catch (error) {
      record.addAll({'status': 'failed', 'error': error.toString()});
      rethrow;
    } finally {
      record['durationUs'] = clock.elapsedMicroseconds;
      await _checkpoint();
    }
  }

  Future<void> _wait(
    bool Function() ready,
    String description, {
    Duration timeout = _deadline,
  }) => waitForPdfProbeCondition(
    ready,
    description,
    timeout: timeout,
    advance: driver.pump,
  );

  Future<void> _nativeWait(
    Future<bool> Function() ready,
    String description,
  ) async {
    final clock = Stopwatch()..start();
    while (true) {
      final remaining = _deadline - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(description, _deadline);
      }
      if (await ready().timeout(remaining)) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<T> _tracked<T>(Future<T> operation, String description) {
    // A timeout does not cancel native work. Keep it joinable before disposal.
    late final Future<void> settled;
    settled = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _pendingOperations.add(settled);
    unawaited(settled.then((_) {
      _pendingOperations.remove(settled);
    }));
    return operation.timeout(
      _deadline,
      onTimeout: () => throw TimeoutException(description, _deadline),
    );
  }

  Future<PdfDocument> _openDocument(PrintPdfSource source) => _tracked(
    source.open(useProgressiveLoading: false).then((document) async {
      _documents.add(document);
      if (_cleaningUp) {
        await document.dispose();
        _documents.remove(document);
        throw StateError('PDF document opened after cleanup started.');
      }
      return document;
    }),
    'Opening an owned PDF document',
  );

  Future<int> _mainHandle() async {
    final value = Platform.isMacOS
        ? implicitViewWindowHandle()
        : Platform.isLinux
        ? await const MethodChannel(
            'otzaria/multiwindow',
          ).invokeMethod<int>('mainWindowHandle')
        : await windowManager.getId();
    _require(value != null && value > 0, 'Missing primary native window handle.');
    return value!;
  }

  Future<void> run() async {
    Object? failure;
    StackTrace? failureStack;
    _initialViews = _viewIds;
    _initialWindows.addAll(registry.windows);
    report.addAll({
      'initialViewIds': _initialViews,
      'realPlatformDispatcher': hasRealPlatformDispatcher(),
      'windowingOwnerInstalled': MultiViewMode.ownerInstalled,
      'engineId': ui.PlatformDispatcher.instance.engineId,
    });
    try {
      _require(
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
            hasRealPlatformDispatcher() &&
            MultiViewMode.enabled &&
            MultiViewMode.ownerInstalled,
        'This scenario requires the real desktop dispatcher and windowing owner.',
      );
      _require(_initialWindows.isEmpty, 'Unrelated secondary windows are open.');
      _require(primaryTabs.state.tabs.isEmpty, 'Unrelated primary tabs are open.');
      _require(
        fixture.pdfReaderCase.sourceKind == PerfPdfSourceKind.generated &&
            fixture.pdfReaderCase.pageCount >= 4,
        'Multi-window QA requires a generated PDF case with at least four pages.',
      );
      _require(!provider.isIndexing.value, 'Unrelated indexing is already active.');
      await _prepare();
      late _Reader secondary;
      await _step('open', () async {
        final tab = PdfBookTab(book: _primaryBook, pageNumber: 1);
        _unreadyTabs[tab] = primaryTabs;
        primaryTabs.add(AddTab(tab));
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.reading),
        );
        await _wait(
          () => primaryTabs.state.tabs.contains(tab) &&
              tab.pdfViewerController.isReady,
          'Primary PDF controller',
        );
        final handle = await _mainHandle().timeout(_deadline);
        final primary = _Reader(
          tab: tab,
          tabs: primaryTabs,
          window: AppWindowScope.controllerOf(context),
          viewId: View.of(context).viewId,
          nativeHandle: handle,
        );
        _readers.add(primary);
        _unreadyTabs.remove(tab);
        _primary = primary;
        fixture.pdfReaderCase.verifyPageCount(primary.document.pages.length);
        await _navigate(primary, 1);
        secondary = await _openSecondary(2);
        _require(
          !identical(primary.document, secondary.document) &&
              !identical(
                primary.tab.pdfViewerController,
                secondary.tab.pdfViewerController,
              ),
          'Native windows did not receive independent PDF readers.',
        );
        _record('open').addAll({
          'primary': await _snapshot(primary, 1),
          'secondary': await _snapshot(secondary, 2),
          'separateDocuments': true,
          'separateControllers': true,
        });
      });
      _rasterDocument = await _openDocument(
        PrintPdfSource.file(fixture.pdfPath),
      );
      await _step('concurrentWork', () => _concurrentWork(secondary));
      await _duringRaster('minimizeRestore', () async {
        await secondary.window.minimize().timeout(_deadline);
        await _nativeWait(
          secondary.window.isMinimized,
          'Secondary native window minimized',
        );
        _record('minimizeRestore')['nativeMinimized'] = true;
        await secondary.window.show().timeout(_deadline);
        await secondary.window.focus().timeout(_deadline);
        await _nativeWait(
          () async => !await secondary.window.isMinimized(),
          'Secondary native window restored',
        );
        _record('minimizeRestore')['secondaryAfter'] =
            await _snapshot(secondary, 4);
      });
      await _duringRaster('closeSecondary', () async {
        _record('closeSecondary')['closed'] = await _close(secondary);
      });
      final previousDocument = secondary.document;
      await _step('reopen', () async {
        secondary = await _openSecondary(2);
        _require(
          !identical(previousDocument, secondary.document),
          'Reopened window reused the closed native PDF document.',
        );
        _record('reopen').addAll({
          'secondary': await _snapshot(secondary, 2),
          'differentDocument': true,
        });
      });
      await _duringRaster('closeReopened', () async {
        _record('closeReopened')['closed'] = await _close(secondary);
      });
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
      report['error'] = error.toString();
    } finally {
      try {
        await _step('teardown', _cleanup);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
        report['cleanupError'] = error.toString();
      }
    }
    report['status'] = failure == null ? 'passed' : 'failed';
    if (failure == null) {
      final errors = perfPdfMultiWindowErrors(report);
      if (errors.isNotEmpty) {
        failure = StateError(errors.join('\n'));
        failureStack = StackTrace.current;
        report.addAll({'status': 'failed', 'error': failure.toString()});
      }
    }
    await _checkpoint();
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> _prepare() async {
    final source = File(fixture.pdfPath);
    final before = (await sha256.bind(source.openRead()).first).toString();
    _require(before == fixture.pdfSha256, 'Fixture PDF hash changed.');
    final copy = await source.copy(p.join(output.path, 'secondary.pdf'));
    final after = (await sha256.bind(source.openRead()).first).toString();
    final copied = (await sha256.bind(copy.openRead()).first).toString();
    _require(before == after && copied == before, 'PDF copy identity mismatch.');
    _primaryBook = PdfBook(
      title: 'בדיקת PDF בחלון ראשי',
      path: source.path,
      source: BookSource.user,
    );
    _secondaryBook = PdfBook(
      title: 'בדיקת PDF בחלון נוסף',
      path: copy.path,
      source: BookSource.user,
    );
    report['fixture'] = {
      'sourceKind': 'generated',
      'pageCount': fixture.pdfReaderCase.pageCount,
      'sourcePath': source.path,
      'copyPath': copy.path,
      'sha256': before,
      'copySha256': copied,
    };
  }

  Future<_Reader> _openSecondary(int page) => _tracked(
    _openSecondaryOwned(page),
    'Opening the owned secondary PDF window',
  );

  Future<_Reader> _openSecondaryOwned(int page) async {
    final seed = PdfBookTab(book: _secondaryBook, pageNumber: page);
    final before = registry.windows.toSet();
    try {
      final opened = await WindowOpener.current.openWindow(
        tab: seed,
        inheritPlacement: false,
      );
      _require(opened, 'WindowOpener could not open the PDF window.');
      final added = registry.windows.where((entry) => !before.contains(entry));
      _require(added.length == 1, 'Native window ownership is ambiguous.');
      final entry = added.single;
      _windows[entry] = entry.handle.view.viewId;
      final secondaryContext = entry.keys.navigator.currentContext;
      _require(
        secondaryContext != null && secondaryContext.mounted,
        'Secondary window has no mounted application context.',
      );
      final tabs = secondaryContext!.read<TabsBloc>();
      await _wait(
        () => tabs.state.currentTab is PdfBookTab &&
            (tabs.state.currentTab as PdfBookTab).book.path == _secondaryBook.path,
        'Transferred PDF tab in the secondary window',
      );
      final tab = tabs.state.currentTab! as PdfBookTab;
      _require(!identical(tab, seed), 'Window transfer did not clone the tab.');
      _unreadyTabs[tab] = tabs;
      _require(!_cleaningUp, 'Secondary window opened after cleanup started.');
      await _wait(() => tab.pdfViewerController.isReady, 'Secondary PDF controller');
      final handle = entry.handle.nativeHandle;
      _require(handle != null && handle > 0, 'Secondary native handle is missing.');
      final reader = _Reader(
        tab: tab,
        tabs: tabs,
        window: entry.controller,
        viewId: entry.handle.view.viewId,
        nativeHandle: handle!,
        entry: entry,
      );
      _readers.add(reader);
      _unreadyTabs.remove(tab);
      fixture.pdfReaderCase.verifyPageCount(reader.document.pages.length);
      await _navigate(reader, page);
      return reader;
    } finally {
      // WindowOpener transfers a clone; the seed never belongs to a reader.
      seed.dispose();
    }
  }

  Future<void> _navigate(_Reader reader, int page) =>
      navigateInstalledPdfTarget(
        reader.tab.pdfViewerController,
        page,
        nextFrame: driver.pump,
        wait: _wait,
      );

  Future<Map<String, Object?>> _snapshot(_Reader reader, int page) async {
    await driver.pump().timeout(_deadline);
    await _wait(
      () => installedPdfTargetReady(reader.tab.pdfViewerController, page),
      'Visible final image for target page $page',
    );
    _require(
      identical(reader.document, reader.tab.pdfViewerController.document),
      'Reader document identity changed.',
    );
    final screens = find.byWidgetPredicate(
      (widget) => widget is PdfBookScreen && identical(widget.tab, reader.tab),
      skipOffstage: false,
    ).evaluate().toList();
    _require(screens.length == 1, 'Reader screen ownership is ambiguous.');
    final screenView = View.of(screens.single).viewId;
    _require(screenView == reader.viewId, 'Reader is attached to another view.');
    await _nativeWait(reader.window.isVisible, 'Reader native window visible');
    _require(
      !await reader.window.isMinimized() && _viewIds.contains(reader.viewId),
      'Reader native view is minimized or absent.',
    );
    return {
      'path': reader.tab.book.path,
      'targetPage': page,
      'visibleRenderState': 'ready',
      'targetCenterVisible': true,
      'documentUnchanged': true,
      'windowVisible': true,
      'windowMinimized': false,
      'viewId': reader.viewId,
      'screenViewId': screenView,
      'nativeHandle': reader.nativeHandle,
      'liveViewIds': _viewIds,
    };
  }

  Future<void> _concurrentWork(_Reader secondary) async {
    final primary = _primary!;
    final record = _record('concurrentWork');
    final operations = <String, Object?>{};
    record['submittedOperations'] = operations;
    final clock = Stopwatch()..start();
    Future<void> observed(String name, Future<void> Function() action) async {
      final interval = <String, Object?>{
        'startUs': clock.elapsedMicroseconds,
      };
      operations[name] = interval;
      try {
        await action();
      } finally {
        interval['endUs'] = clock.elapsedMicroseconds;
      }
    }

    await Future.wait([
      observed('indexing', () async {
        final library = Library(categories: [])..books.add(_primaryBook);
        final pending = repository.runIndexing(
          library,
          books: [],
          changedBooks: [_primaryBook],
          onProgress: (_, _) {},
        );
        _indexing = pending;
        final result = await pending.timeout(_deadline);
        _indexing = null;
        _require(
          result.isClean && result.indexedBooks == 1,
          'Actual PDF indexing did not complete cleanly: $result',
        );
        final verifiedPages = <int>[];
        final searchResults = <Map<String, Object?>>[];
        record['indexing'] = {
          'clean': true,
          'indexedBooks': result.indexedBooks,
          'indexedPath': _primaryBook.path,
          'verifiedPages': verifiedPages,
          'searchResults': searchResults,
        };
        for (final page in [2, 4]) {
          final query = 'PDF preview fixture - page $page';
          // Exercise the UI's search path, including the engine's query
          // normalization, with the original PDF text unchanged.
          final hits = await const SearchRepository()
              .searchTexts(
                SearchEngineRequest(query: query, facets: const [], limit: 100),
              )
              .timeout(_deadline);
          final own = hits.where(
            (hit) =>
                hit.filePath == BookIdentity.indexedFilePath(_primaryBook) &&
                hit.isPdf &&
                hit.segment == BigInt.from(page - 1),
          );
          final matchingHits = own.length;
          searchResults.add({
            'query': query,
            'page': page,
            'totalHits': hits.length,
            'matchingHits': matchingHits,
            'hits': [
              for (final hit in hits)
                {
                  'filePath': hit.filePath,
                  'isPdf': hit.isPdf,
                  'segment': hit.segment.toString(),
                },
            ],
          });
          _require(
            matchingHits == 1,
            'Index returned $matchingHits matches for PDF page $page '
            'among ${hits.length} hits.',
          );
          verifiedPages.add(page);
        }
      }),
      observed('printing', () async {
        record['printing'] = await _tracked(
          _printAndExport(),
          'Actual PDF vector output and printing raster',
        );
      }),
      observed('viewing', () async {
        await _navigate(secondary, 4);
        await _snapshot(primary, 1);
        record['primaryUnchangedBySecondaryNavigation'] = true;
        await _navigate(primary, 3);
        record['primary'] = await _snapshot(primary, 3);
        record['secondary'] = await _snapshot(secondary, 4);
        record['secondaryUnchangedByPrimaryNavigation'] = true;
      }),
    ]);
  }

  Future<Map<String, Object?>> _printAndExport() async {
    _require((await Printing.info()).canRaster, 'Printing raster is unavailable.');
    final bytes = await composePdfSheets(
      _rasterDocument,
      firstIndex: 1,
      lastIndex: 2,
      rows: 1,
      cols: 2,
      sheetWidth: 480,
      sheetHeight: 320,
    );
    await File(p.join(output.path, 'two-up.pdf')).writeAsBytes(bytes, flush: true);
    final export = await _openDocument(PrintPdfSource.data(bytes));
    try {
      _require(export.pages.length == 1, 'Expected one vector output sheet.');
      final page = export.pages.single;
      _require(page.width == 480 && page.height == 320, 'Wrong output sheet size.');
      final text = await page.loadStructuredText();
      final right = text.fullText.indexOf('PDF preview fixture - page 2');
      final left = text.fullText.indexOf('PDF preview fixture - page 3');
      _require(right >= 0 && left >= 0, 'Selected text was lost during export.');
      _require(
        !text.fullText.contains('PDF preview fixture - page 1') &&
            !text.fullText.contains('PDF preview fixture - page 4'),
        'Unselected source pages entered the vector output.',
      );
      _require(
        text.charRects[right].left > text.charRects[left].left,
        'Two-up output did not preserve RTL slot order.',
      );
      final raster = await Printing.raster(bytes, dpi: 72).single;
      _require(
        raster.width == 480 && raster.height == 320,
        'Printing raster dimensions differ from the vector sheet.',
      );
      final proof = _rasterProof(
        raster.width,
        raster.height,
        raster.pixels,
        'rgba8888',
        // The pinned printing plugin uses premultipliedLast on macOS;
        // Windows/Linux return PDFium's straight-alpha bitmap bytes.
        premultipliedAlpha: Platform.isMacOS,
      );
      final png = await raster.toPng();
      await File(p.join(output.path, 'two-up.png')).writeAsBytes(
        png,
        flush: true,
      );
      return {
        'sourcePages': [2, 3],
        'textPreserved': true,
        'rightToLeft': true,
        'width': 480,
        'height': 320,
        'sha256': sha256.convert(bytes).toString(),
        'pngSha256': sha256.convert(png).toString(),
        'pngBytes': png.length,
        'raster': proof,
      };
    } finally {
      await export.dispose();
      _documents.remove(export);
    }
  }

  Map<String, Object?> _rasterProof(
    int width,
    int height,
    Uint8List pixels,
    String pixelFormat, {
    bool premultipliedAlpha = false,
  }) {
    _require(
      width > 0 && height > 0 && pixels.length == width * height * 4,
      'Invalid native raster dimensions or byte count.',
    );
    final ink = perfPdfInkPixelsOnWhite(
      pixels,
      premultipliedAlpha: premultipliedAlpha,
    );
    _require(ink > 10, 'Native raster has no visible text or vector content.');
    return {
      'width': width,
      'height': height,
      'pixelFormat': pixelFormat,
      'alphaPremultiplied': premultipliedAlpha,
      'pixelBytes': pixels.length,
      'inkPixels': ink,
      'sha256': sha256.convert(pixels).toString(),
    };
  }

  Future<Map<String, Object?>> _renderNativePage() async {
    final page = _rasterDocument.pages[1];
    final image = await page.render(
      fullWidth: page.width,
      fullHeight: page.height,
    );
    _require(image != null, 'Native PDF render was cancelled or failed.');
    try {
      return _rasterProof(image!.width, image.height, image.pixels, 'bgra8888');
    } finally {
      image?.dispose();
    }
  }

  Future<void> _duringRaster(
    String name,
    Future<void> Function() transition,
  ) => _step(name, () async {
    final record = _record(name);
    final clock = Stopwatch()..start();
    Future<void> observed(String key, Future<void> Function() action) async {
      final interval = <String, Object?>{
        'startUs': clock.elapsedMicroseconds,
      };
      record[key] = interval;
      try {
        await action();
      } finally {
        interval['endUs'] = clock.elapsedMicroseconds;
      }
    }

    await Future.wait([
      observed('rasterInterval', () async {
        record['raster'] = await _tracked(
          _renderNativePage(),
          'Native PDF raster during $name',
        );
      }),
      observed('transitionInterval', transition),
    ]);
    record['primaryAfter'] = await _snapshot(_primary!, 3);
    record['primaryUnchanged'] = true;
  });

  Future<Map<String, Object?>> _close(_Reader reader) async {
    final entry = reader.entry;
    if (entry == null) {
      if (reader.tabs.state.tabs.contains(reader.tab)) {
        reader.tabs.add(RemoveTabs([reader.tab]));
      }
      await _wait(
        () => !reader.tabs.state.tabs.contains(reader.tab) &&
            !reader.tab.pdfViewerController.isReady,
        'Primary PDF tab detached',
      );
    } else {
      _require(_windows.containsKey(entry), 'Refusing to close an unowned window.');
      if (registry.windows.contains(entry)) {
        await entry.controller.close().timeout(_deadline);
      }
      await _wait(
        () => !registry.windows.contains(entry),
        'Owned secondary window removed from the registry',
      );
    }
    await reader.closed.future.timeout(_deadline);
    _require(reader.eventError == null, 'PDF event stream reported an error.');
    await reader.document.dispose().timeout(_deadline);
    reader.nativeClosed = true;
    if (entry != null) {
      // Linux removes the registry entry before its deferred native destroy.
      await _wait(
        () => !_viewIds.contains(reader.viewId),
        'Owned native view removed from PlatformDispatcher',
      );
      _windows.remove(entry);
    }
    await reader.events.cancel();
    _readers.remove(reader);
    return {
      'viewId': reader.viewId,
      'nativeHandle': reader.nativeHandle,
      'documentEventsClosed': reader.closed.isCompleted,
      'nativeDisposeAwaited': reader.nativeClosed,
      'registryEntryRemoved': entry == null || !registry.windows.contains(entry),
      'liveViewIdsAfter': _viewIds,
    };
  }

  Future<void> _cleanup() async {
    _cleaningUp = true;
    Object? firstError;
    StackTrace? firstStack;
    final errors = <String>[];
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        errors.add(error.toString());
      }
    }

    try {
      final indexing = _indexing;
      if (indexing != null) {
        await attempt(() async {
          repository.cancelIndexing();
          await indexing.timeout(_deadline);
          _indexing = null;
        });
      }
      if (_pendingOperations.isNotEmpty) {
        await attempt(() async {
          await Future.wait(_pendingOperations.toList()).timeout(_deadline);
        });
      }
      for (final reader in _readers.toList().reversed) {
        await attempt(() async {
          await _close(reader);
        });
      }
      for (final entry in _unreadyTabs.entries.toList()) {
        await attempt(() async {
          final tab = entry.key;
          final tabs = entry.value;
          if (!tabs.isClosed && tabs.state.tabs.contains(tab)) {
            tabs.add(RemoveTabs([tab]));
            await _wait(
              () => !tabs.state.tabs.contains(tab),
              'Unready owned PDF tab removed',
            );
          }
          _unreadyTabs.remove(tab);
        });
      }
      for (final owned in _windows.entries.toList()) {
        await attempt(() async {
          final entry = owned.key;
          final viewId = owned.value;
          if (registry.windows.contains(entry)) {
            await entry.controller.close().timeout(_deadline);
          }
          await _wait(
            () => !registry.windows.contains(entry) && !_viewIds.contains(viewId),
            'Partially opened owned native window removed',
          );
          _windows.remove(entry);
        });
      }
      // Never dispose a source while an uncancelled native task may borrow it.
      if (_pendingOperations.isEmpty) {
        for (final document in _documents.toList()) {
          await attempt(() async {
            await document.dispose().timeout(_deadline);
            _documents.remove(document);
          });
        }
      } else {
        await attempt(() async {
          throw StateError('Native work remains pending; source ownership retained.');
        });
      }
      await attempt(() async {
        await _wait(
          () => _viewIds.length == _initialViews.length &&
              _viewIds.toSet().containsAll(_initialViews),
          'Initial native view set restored',
        );
        _require(
          registry.windows.every(_initialWindows.contains),
          'New native windows remain after cleanup.',
        );
      });
    } finally {
      _record('teardown').addAll({
        'primaryDocumentEventsClosed': _primary?.closed.isCompleted == true,
        'primaryNativeDisposeAwaited': _primary?.nativeClosed == true,
        'ownedWindowsRemaining': _windows.length,
        'ownedDocumentsRemaining':
            _documents.length + _readers.length + _unreadyTabs.length,
        'pendingOperations': _pendingOperations.length,
        'indexingActive':
            TantivyDataProvider.instanceIfCreated?.isIndexing.value ?? false,
        'finalViewIds': _viewIds,
        if (errors.isNotEmpty) 'cleanupErrors': errors,
      });
    }
    if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
  }
}
