import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/utils/pdf_image_budget.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/pdf.dart' show PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
// This engine 0.9.3 test adapter preserves native proxy unwrapping; its internal
// import must be checked when the pinned engine is upgraded.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:pdfrx_engine/src/pdf_page_proxies.dart' show PdfPageRenumbered;

import '../helpers/memory_settings_cache.dart';
import '../helpers/pdf_viewer_mounted.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  testWidgets('native render keys across viewer, spreads and thumbnails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue(SettingsRepository.keyPdfBookViewByDefault, true);
    await Settings.setValue(SettingsRepository.keyEnablePerBookSettings, false);
    final directory = Directory.systemTemp.createTempSync('pdf-render-keys-');
    addTearDown(() => directory.deleteSync(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final originalModule = Pdfrx.pdfiumModulePath;
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModule);

    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var page = 1; page <= 8; page++) {
        pdf.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(200, 300),
            build: (_) => pw.Center(
              child: pw.Container(
                width: 100,
                height: page * 20.0,
                color: PdfColors.black,
              ),
            ),
          ),
        );
      }
      await file.writeAsBytes(await pdf.save());
    });
    final probe = _RenderProbe();
    final originalBackend = PdfrxEntryFunctions.instance;
    PdfrxEntryFunctions.instance = _ObservedBackend(originalBackend, probe);
    probe.observeImages();
    addTearDown(() {
      PdfrxEntryFunctions.instance = originalBackend;
      probe.restoreImageCallbacks();
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'בדיקת מפתחות רינדור', path: file.path),
      pageNumber: 1,
    );
    final other = PdfBookTab(
      book: PdfBook(title: 'טאב אחר', path: '${directory.path}/other.pdf'),
      pageNumber: 1,
    );
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab, other], currentTabIndex: 0));
    final settings = StubSettingsBloc(
      SettingsState.initial().copyWith(pdfBookViewByDefault: true),
    );
    final tour = TourCubit();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(tour.close);

    Future<void> frame() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      for (final widget in tester.widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString() ==
                  '_BookPageTurnBackgroundPainter',
        ),
      )) {
        final dynamic painter = widget.painter;
        probe.observeSnapshot(painter.snapshot as ui.Image);
        final target = painter.targetSnapshot as ui.Image?;
        if (target != null) probe.observeSnapshot(target);
      }
    }

    Future<void> settled({bool visible = true}) async {
      var stable = 0;
      var previous = -1;
      for (var i = 0; i < 300; i++) {
        await frame();
        final controller = tab.pdfViewerController;
        final ready =
            !visible ||
            (controller.isReady &&
                controller.visibleRenderState.value ==
                    PdfVisibleRenderState.ready);
        final quiet =
            ready &&
            probe.active == 0 &&
            pdfSharedImageBudget.pendingBytes == 0 &&
            probe.renders.length == previous;
        stable = quiet ? stable + 1 : 0;
        if (stable == 20) return;
        previous = probe.renders.length;
      }
      fail('PDF render probe did not settle in phase ${probe.phase}');
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            mui.DefaultMaterialLocalizations.delegate,
          ],
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<TourCubit>.value(value: tour),
            ],
            child: Scaffold(body: PdfBookScreen(tab: tab)),
          ),
        ),
      );
      final bloc = await pumpUntilPdfViewer(tester);
      await settled();
      expect(bloc.state, isA<PdfBookLoaded>());
      expect((bloc.state as PdfBookLoaded).layoutMode, PdfLayoutMode.bookView);
      expect(probe.documents, contains(same(tab.pdfViewerController.document)));
      expect(probe.owners, contains('viewer'));
      final warmed = probe.renders.length;
      await settled();
      expect(probe.renders.length, warmed, reason: 'idle re-rendered a key');

      for (final (phase, key, page) in [
        ('forward', LogicalKeyboardKey.pageDown, 2),
        ('backward', LogicalKeyboardKey.pageUp, 1),
      ]) {
        probe.phase = phase;
        await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
        await tester.sendKeyEvent(key);
        await settled();
        expect(tab.pdfViewerController.pageNumber, page);
      }
      expect(probe.owners, contains('spread'));
      expect(
        probe.images.where((image) => image.owner == 'snapshot'),
        isNotEmpty,
      );

      probe.phase = 'thumbnails';
      bloc.add(const ToggleLeftPane(true));
      for (var i = 0; i < 12; i++) {
        await frame();
      }
      await tester.tap(find.text('דפים'));
      await settled();
      expect(probe.owners, contains('thumbnail'));

      probe.phase = 'zoom';
      final controller = tab.pdfViewerController;
      await controller.setZoom(
        controller.layout.pageLayouts.first.center,
        controller.currentZoom * 2,
        duration: Duration.zero,
      );
      await settled();
      probe.phase = 'hidden';
      // ignore: invalid_use_of_visible_for_testing_member
      tabs.emit(TabsState(tabs: [tab, other], currentTabIndex: 1));
      await settled(visible: false);
      final hidden = probe.renders.length;
      await settled(visible: false);
      expect(probe.renders.length, hidden, reason: 'hidden viewer rendered');
      expect(tester.takeException(), isNull);
    } finally {
      probe.phase = 'close';
      await tester.pumpWidget(const SizedBox.shrink());
      for (final document in probe.documents) {
        await disposePdfDocument(tester, document);
      }
      for (var i = 0; i < 10; i++) {
        await frame();
      }
      debugPrint('PDF_RENDER_DUPLICATION ${jsonEncode(probe.toJson())}');
    }
    expect(probe.active, 0);
    expect(probe.documents.every((document) => document.disposed), isTrue);
    expect(pdfSharedImageBudget.pendingBytes, 0);
    expect(
      probe.images.where(
        (image) => image.owner == 'snapshot' && !image.disposed,
      ),
      isEmpty,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String _owner(String stack) {
  if (stack.contains('pdf_thumbnails_screen.dart')) return 'thumbnail';
  if (stack.contains('_renderSpreadPagesNow')) return 'spread';
  if (stack.contains('pdfrx/src/widgets/pdf_viewer.dart')) return 'viewer';
  if (stack.contains('_capturePdfViewportSnapshot') ||
      stack.contains('_composeCachedSpreadSnapshot')) {
    return 'snapshot';
  }
  return 'unknown';
}

class _RenderProbe {
  String phase = 'warm';
  int active = 0;
  int sequence = 0;
  final documents = <_ObservedDocument>[];
  final renders = <Map<String, Object?>>[];
  final images = <_ImageHandle>[];
  final imageRecords = Expando<_ImageHandle>();
  ui.ImageEventCallback? previousCreate;
  ui.ImageEventCallback? previousDispose;

  Set<String> get owners => renders.map((r) => r['owner'] as String).toSet();

  void observeImages() {
    previousCreate = ui.Image.onCreate;
    previousDispose = ui.Image.onDispose;
    ui.Image.onCreate = (image) {
      previousCreate?.call(image);
      final record = _ImageHandle(
        _owner(StackTrace.current.toString()),
        phase,
        image.width,
        image.height,
      );
      imageRecords[image] = record;
      images.add(record);
    };
    ui.Image.onDispose = (image) {
      previousDispose?.call(image);
      imageRecords[image]?.disposed = true;
    };
  }

  void observeSnapshot(ui.Image image) {
    final record = imageRecords[image];
    if (record != null) record.owner = 'snapshot';
  }

  void restoreImageCallbacks() {
    ui.Image.onCreate = previousCreate;
    ui.Image.onDispose = previousDispose;
  }

  Map<String, Object?> toJson() {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final render in renders) {
      grouped.putIfAbsent(jsonEncode(render['key']), () => []).add(render);
    }
    return {
      'scope': 'native PDFium, 8 pages, 1400x900, DPR 1',
      'limitations': [
        'Test-only proxy import is tied to pdfrx_engine 0.9.3 and must be reviewed on upgrade; native only.',
        'Request counters with stack capture; not CPU, latency or allocation measurements.',
        'Snapshot handles are composited images, not PdfPage.render requests.',
        'Image handles include clones; unknown owners remain explicitly unknown.',
        'Page generation follows native page-object identity; the fixture performs no content edits.',
        'Keys retain raw render arguments and intrinsic page dimensions; equivalent defaults or rounding are not coalesced.',
        'Repeated keys after eviction, cancellation or navigation are observations, not automatically redundant work.',
      ],
      'requests': renders.length,
      'uniqueKeys': grouped.length,
      'repeatedRequests': renders.length - grouped.length,
      'crossOwnerKeys': grouped.values
          .where(
            (records) => records.map((r) => r['owner']).toSet().length > 1,
          )
          .length,
      'byOwner': {
        for (final owner in [
          'viewer',
          'spread',
          'thumbnail',
          'snapshot',
          'unknown',
        ])
          owner: renders.where((r) => r['owner'] == owner).length,
      },
      'images': {
        for (final owner in [
          'viewer',
          'spread',
          'thumbnail',
          'snapshot',
          'unknown',
        ])
          owner: {
            'createdHandles': images
                .where((image) => image.owner == owner)
                .length,
            'disposedHandles': images
                .where((image) => image.owner == owner && image.disposed)
                .length,
          },
      },
      'documents': [
        for (final document in documents)
          {'id': document.id, 'disposed': document.disposed},
      ],
      'imageHandles': [
        for (final (id, image) in images.indexed)
          {
            'id': id,
            'owner': image.owner,
            'phase': image.phase,
            'width': image.width,
            'height': image.height,
            'disposed': image.disposed,
          },
      ],
      'renders': renders,
    };
  }
}

class _ImageHandle {
  _ImageHandle(this.owner, this.phase, this.width, this.height);
  String owner;
  final String phase;
  final int width;
  final int height;
  bool disposed = false;
}

class _ObservedPage extends PdfPageRenumbered {
  _ObservedPage(this.document, PdfPage page, this.generation)
    : super(page, pageNumber: page.pageNumber);
  @override
  final _ObservedDocument document;
  final int generation;

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
    final probe = document.probe;
    final key = {
      'document': document.id,
      'pageGeneration': generation,
      'page': pageNumber,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'fullWidth': fullWidth,
      'fullHeight': fullHeight,
      'pageWidth': this.width,
      'pageHeight': this.height,
      'pageRotation': rotation.name,
      'rotationOverride': rotationOverride?.name,
      'background': backgroundColor,
      'annotations': annotationRenderingMode.name,
      'flags': flags,
    };
    final record = <String, Object?>{
      'key': key,
      'owner': _owner(StackTrace.current.toString()),
      'phase': probe.phase,
      'priority': priority?.name,
      'started': ++probe.sequence,
    };
    probe.renders.add(record);
    probe.active++;
    try {
      final image = await super.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: backgroundColor,
        rotationOverride: rotationOverride,
        annotationRenderingMode: annotationRenderingMode,
        flags: flags,
        cancellationToken: cancellationToken,
        priority: priority,
      );
      record['result'] = image == null ? 'null' : 'image';
      record['returnedWidth'] = image?.width;
      record['returnedHeight'] = image?.height;
      return image;
    } catch (error) {
      record['result'] = 'error';
      rethrow;
    } finally {
      record['cancelled'] = cancellationToken?.isCanceled ?? false;
      record['completed'] = ++probe.sequence;
      probe.active--;
    }
  }
}

class _ObservedDocument extends PdfDocument {
  _ObservedDocument(this.base, this.probe, this.id)
    : super(sourceName: base.sourceName);
  final PdfDocument base;
  final _RenderProbe probe;
  final int id;
  bool disposed = false;
  int pageGeneration = 0;
  final wrapped = Expando<_ObservedPage>();
  List<PdfPage>? previousPages;
  List<PdfPage> observedPages = const [];
  Future<void>? closing;

  _ObservedPage wrap(PdfPage page) =>
      wrapped[page] ??= _ObservedPage(this, page, ++pageGeneration);

  @override
  List<PdfPage> get pages {
    final latest = base.pages;
    if (!identical(latest, previousPages)) {
      previousPages = latest;
      observedPages = List.unmodifiable(latest.map(wrap));
    }
    return observedPages;
  }

  @override
  set pages(List<PdfPage> value) => base.pages = [
    for (final page in value) page is _ObservedPage ? page.basePage : page,
  ];

  @override
  late final Stream<PdfDocumentEvent> events = base.events.map((event) {
    return switch (event) {
      PdfDocumentLoadCompleteEvent() => PdfDocumentLoadCompleteEvent(this),
      PdfDocumentMissingFontsEvent() => PdfDocumentMissingFontsEvent(
        this,
        event.missingFonts,
      ),
      PdfDocumentPageStatusChangedEvent() => PdfDocumentPageStatusChangedEvent(
        this,
        changes: {
          for (final entry in event.changes.entries)
            entry.key: switch (entry.value) {
              PdfPageStatusMoved change => PdfPageStatusChange.moved(
                page: wrap(change.page),
                oldPageNumber: change.oldPageNumber,
              ),
              PdfPageStatusModified change => PdfPageStatusChange.modified(
                page: wrap(change.page),
              ),
              _ => throw StateError('Unknown page change ${entry.value}'),
            },
        },
      ),
      _ => throw StateError('Unknown document event $event'),
    };
  });

  @override
  PdfPermissions? get permissions => base.permissions;
  @override
  bool get isEncrypted => base.isEncrypted;
  @override
  Future<void> dispose() => closing ??= base.dispose().then((_) {
    disposed = true;
  });
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) => base.loadPagesProgressively(
    onPageLoadProgress: onPageLoadProgress,
    data: data,
    loadUnitDuration: loadUnitDuration,
    startPageNumber: startPageNumber,
  );
  @override
  Future<List<PdfOutlineNode>> loadOutline() => base.loadOutline();
  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      base.isIdenticalDocumentHandle(
        other is _ObservedDocument ? other.base : other,
      );
  @override
  Future<bool> assemble() => base.assemble();
  @override
  Future<Uint8List> encodePdf({
    bool incremental = false,
    bool removeSecurity = false,
  }) =>
      base.encodePdf(incremental: incremental, removeSecurity: removeSecurity);
  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int) task) =>
      base.useNativeDocumentHandle(task);
  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) =>
      base.reloadPages(pageNumbersToReload: pageNumbersToReload);
}

class _ObservedBackend implements PdfrxEntryFunctions {
  _ObservedBackend(this.base, this.probe);
  final PdfrxEntryFunctions base;
  final _RenderProbe probe;
  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    final document = _ObservedDocument(
      await base.openFile(
        filePath,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        useProgressiveLoading: useProgressiveLoading,
      ),
      probe,
      probe.documents.length,
    );
    probe.documents.add(document);
    return document;
  }

  @override
  Future<void> init() => base.init();
  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(FutureOr<T> Function() action) =>
      base.suspendPdfiumWorkerDuringAction(action);
  @override
  Future<R> compute<M, R>(FutureOr<R> Function(M) callback, M message) =>
      base.compute(callback, message);
  @override
  Future<void> stopBackgroundWorker() => base.stopBackgroundWorker();
  @override
  PdfrxBackendType get backendType => base.backendType;
  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) => base.openAsset(
    name,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
  );
  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) => base.openData(
    data,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    sourceName: sourceName,
    allowDataOwnershipTransfer: allowDataOwnershipTransfer,
    useProgressiveLoading: useProgressiveLoading,
    maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
    onDispose: onDispose,
  );
  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List, int, int) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) => base.openCustom(
    read: read,
    fileSize: fileSize,
    sourceName: sourceName,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
    onDispose: onDispose,
  );
  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
    Duration? timeout,
  }) => base.openUri(
    uri,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    progressCallback: progressCallback,
    preferRangeAccess: preferRangeAccess,
    headers: headers,
    withCredentials: withCredentials,
    timeout: timeout,
  );
  @override
  Future<PdfDocument> createNew({required String sourceName}) =>
      base.createNew(sourceName: sourceName);
  @override
  Future<PdfDocument> createFromJpegData(
    Uint8List jpegData, {
    required double width,
    required double height,
    required String sourceName,
  }) => base.createFromJpegData(
    jpegData,
    width: width,
    height: height,
    sourceName: sourceName,
  );
  @override
  Future<void> configureFontEnvironment({
    String? fontCachePath,
    List<String> fontPaths = const [],
  }) => base.configureFontEnvironment(
    fontCachePath: fontCachePath,
    fontPaths: fontPaths,
  );
  @override
  Future<void> reloadFonts() => base.reloadFonts();
  @override
  Future<void> addFontData({
    required String face,
    required Uint8List data,
    String? resolvedFace,
  }) => base.addFontData(face: face, data: data, resolvedFace: resolvedFace);
  @override
  Future<void> addFontFile({
    required String face,
    required String filePath,
    String? resolvedFace,
  }) => base.addFontFile(
    face: face,
    filePath: filePath,
    resolvedFace: resolvedFace,
  );
  @override
  Future<void> clearAllFontData() => base.clearAllFontData();
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}
