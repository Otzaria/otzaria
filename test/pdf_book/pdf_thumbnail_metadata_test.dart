import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../test_helpers/pdf_document_dispose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('otzaria-thumb-metadata-');
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    directory.deleteSync(recursive: true);
  });

  Future<_NativeDocument> openNative(
    WidgetTester tester, {
    bool holdLoading = false,
  }) async => (await tester.runAsync(() async {
    await pdfrxFlutterInitialize();
    final pdf = pw.Document();
    for (var i = 0; i < 60; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: i.isEven
              ? const PdfPageFormat(200, 300)
              : const PdfPageFormat(300, 200),
          build: (_) => pw.SizedBox(),
        ),
      );
    }
    return _NativeDocument(
      await PdfDocument.openData(
        await pdf.save(),
        sourceName: '${directory.path}/mixed.pdf',
        useProgressiveLoading: true,
      ),
      holdLoading: holdLoading,
    );
  }))!;

  testWidgets('צפיין אמיתי ותמונותיו משתפים טעינת מטא־דאטה יחידה', (
    tester,
  ) async {
    final document = await openNative(tester, holdLoading: true);
    final ref = PdfDocumentRefDirect(document, autoDispose: false);
    final controller = PdfViewerController();
    Widget host({bool thumbnails = true}) => MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: PdfViewer(
                ref,
                controller: controller,
                initialPageNumber: 20,
                params: const PdfViewerParams(
                  behaviorControlParams: PdfViewerBehaviorControlParams(
                    trailingPageLoadingDelay: Duration.zero,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: thumbnails
                  ? ThumbnailsView(
                      documentRef: ref,
                      controller: controller,
                      isPaneOpen: false,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
    try {
      await tester.pumpWidget(host());
      await _until(tester, () => document.loadStarts.contains(20));
      debugPrint('native thumbnail metadata loaders: ${document.loadStarts}');
      expect(document.loadStarts, [20]);
      expect(document.delegate.pages.any((page) => !page.isLoaded), isTrue);

      for (var i = 0; i < 10; i++) {
        ref.resolveListenable().notifyListeners();
        await tester.pump();
      }
      expect(document.loadStarts, [20]);
      document.releaseLoading();
      await _until(
        tester,
        () => document.pages.every((page) => page.isLoaded),
      );
      expect(document.pages[1].size, const Size(300, 200));
      expect(document.pages.last.size, const Size(300, 200));

      await tester.pumpWidget(host(thumbnails: false));
      await tester.pump();
      expect(controller.isReady, isTrue);
      expect(controller.document, same(document));
      expect(document.disposeCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      document.releaseLoading();
      await tester.pumpWidget(const SizedBox.shrink());
      await _until(tester, () => document.activeLoads == 0);
      await disposePdfDocument(tester, document);
    }
  });

  testWidgets('תצוגה עצמאית ממשיכה למדוד מסמך הדרגתי ולצייר את מידותיו', (
    tester,
  ) async {
    final document = await openNative(tester);
    expect(document.pages[1].isLoaded, isFalse);
    final ref = PdfDocumentRefDirect(document, autoDispose: false);
    try {
      await tester.pumpWidget(
        _host(ThumbnailsView(documentRef: ref, controller: null)),
      );
      await _until(
        tester,
        () =>
            document.pages.every((page) => page.isLoaded) &&
            find.byType(RawImage).evaluate().isNotEmpty,
      );
      expect(document.loadStarts, [null]);
      expect(document.pages[1].size, const Size(300, 200));
      final ratios = tester.widgetList<AspectRatio>(
        find.descendant(
          of: find.byType(ThumbnailsView),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(ratios.map((widget) => widget.aspectRatio), contains(1.5));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
    }
  });

  testWidgets('אירועי עמודים מעדכנים מידות, סדר וסימון בלי להתחיל loader', (
    tester,
  ) async {
    final document = _MetadataDocument('events', count: 3);
    final controller = _Controller()..page = 2;
    final ref = PdfDocumentRefDirect(document, autoDispose: false);
    final listenable = ref.resolveListenable();
    final releaseOwner = listenable.addListener(() {});
    listenable.setDocument(document);
    final navigations = <int>[];
    try {
      await tester.pumpWidget(
        _host(
          ThumbnailsView(
            documentRef: ref,
            controller: controller,
            shownPagesFor: (_) => (startPage: 2, endPageExclusive: 4),
            onNavigateToPage: (page) async => navigations.add(page),
          ),
        ),
      );
      await tester.pump();
      expect(document.progressiveLoads, 0);
      expect(document.activeSubscriptions, 1);

      document.replacePages(const [Size(300, 200), Size(210, 297)]);
      await tester.pump();
      final ratios = tester.widgetList<AspectRatio>(
        find.descendant(
          of: find.byType(ThumbnailsView),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(ratios.map((widget) => widget.aspectRatio), [1.5, 210 / 297]);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      final selected = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(ThumbnailsView),
          matching: find.byType(Container),
        ),
      );
      expect(
        selected.where((widget) => widget.decoration != null),
        hasLength(1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).at(1));
      expect(navigations, [2]);
      expect(document.progressiveLoads, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      releaseOwner();
      await document.dispose();
      await document.closeEvents();
    }
  });

  testWidgets('החלפת מסמך מנתקת אירועים ישנים ושומרת את בעלות המציג', (
    tester,
  ) async {
    final first = _MetadataDocument('first', count: 3);
    final second = _MetadataDocument('second', count: 1);
    final ref = PdfDocumentRefDirect(first);
    final listenable = ref.resolveListenable();
    final releaseOwner = listenable.addListener(() {});
    listenable.setDocument(first);
    final controller = _Controller();
    try {
      await tester.pumpWidget(
        _host(
          ThumbnailsView(documentRef: ref, controller: controller),
        ),
      );
      await tester.pump();
      expect(first.activeSubscriptions, 1);
      expect(first.disposeCount, 0);
      listenable.setDocument(second);
      await tester.pump();
      expect(first.activeSubscriptions, 0);
      expect(first.disposeCount, 1);
      expect(second.activeSubscriptions, 1);
      expect(find.text('2'), findsNothing);

      first.emit();
      await tester.pump();
      expect(find.text('2'), findsNothing);
      second.replacePages(const [Size(180, 240), Size(240, 180)]);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(second.activeSubscriptions, 0);
      expect(second.disposeCount, 0);
      second.emit();
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      releaseOwner();
      await first.closeEvents();
      await second.closeEvents();
    }
    expect(second.disposeCount, 1);
  });

  for (final count in [100, 1000, 10000]) {
    testWidgets('התראות ref אינן מוסיפות סריקות מטא־דאטה ב־$count עמודים', (
      tester,
    ) async {
      final document = _MetadataDocument('count-$count', count: count);
      final ref = PdfDocumentRefDirect(document, autoDispose: false);
      final listenable = ref.resolveListenable();
      final releaseOwner = listenable.addListener(() {});
      listenable.setDocument(document);
      final controller = _Controller();
      try {
        await tester.pumpWidget(
          _host(
            ThumbnailsView(
              documentRef: ref,
              controller: controller,
              isPaneOpen: false,
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          listenable.notifyListeners();
          await tester.pump();
        }
        debugPrint(
          'thumbnail metadata: pages=$count, notifications=20, '
          'extraLoaders=${document.progressiveLoads}',
        );
        expect(document.progressiveLoads, 0);
        expect(document.activeSubscriptions, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        releaseOwner();
        await document.closeEvents();
      }
    });
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 200, height: 600, child: child),
      ),
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

class _NativeDocument extends Fake implements PdfDocument {
  _NativeDocument(this.delegate, {required bool holdLoading}) {
    if (!holdLoading) releaseLoading();
  }

  final PdfDocument delegate;
  final _loadGate = Completer<void>();
  final loadStarts = <int?>[];
  int activeLoads = 0;
  int disposeCount = 0;
  void releaseLoading() {
    if (!_loadGate.isCompleted) _loadGate.complete();
  }

  @override
  String get sourceName => delegate.sourceName;
  @override
  PdfPermissions? get permissions => delegate.permissions;
  @override
  bool get isEncrypted => delegate.isEncrypted;
  @override
  List<PdfPage> get pages => delegate.pages;
  @override
  Stream<PdfDocumentEvent> get events => delegate.events;
  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      identical(other, this) || delegate.isIdenticalDocumentHandle(other);
  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) =>
      delegate.reloadPages(pageNumbersToReload: pageNumbersToReload);
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {
    loadStarts.add(startPageNumber);
    activeLoads++;
    try {
      await _loadGate.future;
      await delegate.loadPagesProgressively(
        onPageLoadProgress: onPageLoadProgress,
        data: data,
        loadUnitDuration: loadUnitDuration,
        startPageNumber: startPageNumber,
      );
    } finally {
      activeLoads--;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await delegate.dispose();
  }
}

class _MetadataDocument extends Fake implements PdfDocument {
  _MetadataDocument(this.sourceName, {required int count}) {
    _events = StreamController<PdfDocumentEvent>.broadcast(
      sync: true,
      onListen: () => activeSubscriptions++,
      onCancel: () => activeSubscriptions--,
    );
    pages = List.generate(
      count,
      (index) => _Page(this, index + 1, const Size(200, 300)),
    );
  }

  @override
  final String sourceName;
  @override
  late List<PdfPage> pages;
  late final StreamController<PdfDocumentEvent> _events;
  int activeSubscriptions = 0;
  int progressiveLoads = 0;
  int disposeCount = 0;
  @override
  Stream<PdfDocumentEvent> get events => _events.stream;
  void replacePages(List<Size> sizes) {
    pages = [
      for (var i = 0; i < sizes.length; i++) _Page(this, i + 1, sizes[i]),
    ];
    emit();
  }

  void emit() => _events.add(
    PdfDocumentPageStatusChangedEvent(
      this,
      changes: {
        for (final page in pages)
          page.pageNumber: PdfPageStatusChange.modified(page: page),
      },
    ),
  );
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {
    progressiveLoads++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  Future<void> closeEvents() => _events.close();
}

class _Page extends Fake implements PdfPage {
  _Page(this.document, this.pageNumber, this.size);
  @override
  final PdfDocument document;
  @override
  final int pageNumber;
  final Size size;
  @override
  double get width => size.width;
  @override
  double get height => size.height;
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
  }) async => null;
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _Controller extends PdfViewerController {
  int page = 1;
  @override
  bool get isReady => true;
  @override
  int? get pageNumber => page;
}
