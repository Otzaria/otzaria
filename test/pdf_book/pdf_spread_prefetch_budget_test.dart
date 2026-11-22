import 'dart:async';
import 'dart:io';

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
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/pdf_viewer_mounted.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;
  final originalBudget = pdfSharedImageBudget.maximumBytes;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-spread-budget-');
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
    pdfSharedImageBudget.clear();
    pdfSharedImageBudget.maximumBytes = originalBudget;
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    directory.deleteSync(recursive: true);
  });

  Future<_Reader> pumpReader(
    WidgetTester tester,
    _ControlledDocument document,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var page = 1; page <= 30; page++) {
        pdf.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(200, 300),
            build: (_) => pw.Center(child: pw.Text('page $page')),
          ),
        );
      }
      await file.writeAsBytes(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: file.path),
      pageNumber: 1,
    );
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = StubSettingsBloc();
    final tour = TourCubit();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
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
          child: PdfBookScreen(tab: tab),
        ),
      ),
    );
    final bloc = await pumpUntilPdfViewer(tester);
    await _until(tester, () => bloc.state is PdfBookLoaded);
    final actual = tab.pdfViewerController;
    await _settle(tester, rounds: 20);
    final controller = _ControlledController(actual, document);
    tab.pdfViewerController = controller;
    bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
    await _settle(tester, rounds: 20);
    await _until(
      tester,
      () =>
          actual.visibleRenderState.value == PdfVisibleRenderState.ready &&
          pdfSharedImageBudget.pendingBytes == 0,
    );
    expect((bloc.state as PdfBookLoaded).layoutMode, PdfLayoutMode.bookView);
    expect(document.calls, isEmpty);
    controller.zoom = actual.currentZoom;
    controller.ready = true;
    final reader = _Reader(tester, tab, actual, controller);
    addTearDown(reader.dispose);
    return reader;
  }

  testWidgets('prefetch בתקציב קטן אינו מפנה תמונת צפיין נחוצה', (
    tester,
  ) async {
    final document = _ControlledDocument();
    final reader = await pumpReader(tester, document);
    const sentinelBytes = 8 * 1024 * 1024;
    pdfSharedImageBudget.maximumBytes =
        pdfSharedImageBudget.estimatedBytes + sentinelBytes;
    var evictions = 0;
    final needed = pdfSharedImageBudget
        .tryReserve(sentinelBytes)!
        .commit(
          retainedBytes: sentinelBytes,
          isNeeded: true,
          onEvict: () => evictions++,
        )!;
    try {
      reader.notifyPage();
      await _settle(tester);
      expect(evictions, 0);
      expect(needed.isDisposed, isFalse);
      expect(document.calls, isEmpty);
      expect(pdfSharedImageBudget.pendingBytes, 0);

      needed.touch(isNeeded: false);
      reader.notifyPage();
      await _until(tester, () => document.calls.length >= 3);
      await _settle(tester);
      expect(evictions, 1);
      expect(document.calls.map((call) => call.page), [2, 3, 1]);
      expect(
        document.calls.map((call) => call.priority),
        everyElement(PdfPageRenderPriority.low),
      );
    } finally {
      needed.dispose();
    }
  });

  testWidgets('כפולות נחוצות מוגנות ואינן מרונדרות שוב בעדכונים חוזרים', (
    tester,
  ) async {
    final document = _ControlledDocument();
    final reader = await pumpReader(tester, document);
    final neededBefore =
        pdfSharedImageBudget.reservableBytes() -
        pdfSharedImageBudget.reservableBytes(keepNeeded: true);
    reader.notifyPage();
    await _until(tester, () => document.calls.length == 3);
    await _settle(tester);
    final retainedPixels = document.calls.fold<int>(
      0,
      (sum, call) => sum + call.image.width * call.image.height,
    );
    final neededAfter =
        pdfSharedImageBudget.reservableBytes() -
        pdfSharedImageBudget.reservableBytes(keepNeeded: true);
    expect(neededAfter - neededBefore, retainedPixels * 8);
    for (var i = 0; i < 20; i++) {
      reader.notifyPage();
      await tester.pump();
    }
    expect(document.calls.map((call) => call.page), [2, 3, 1]);
    expect(
      document.calls.map((call) => call.image.disposeCount),
      everyElement(1),
    );
    expect(pdfSharedImageBudget.pendingBytes, 0);
  });

  testWidgets('קפיצה רחוקה מבטלת render נמוך ולא מתחילה את העמוד השני', (
    tester,
  ) async {
    final document = _ControlledDocument(holdPage: 2);
    final reader = await pumpReader(tester, document);
    reader.notifyPage();
    await _until(tester, () => document.calls.isNotEmpty);
    final stale = document.calls.single;
    reader.controller.page = 20;
    reader.notifyPage();
    await tester.pump();
    expect(stale.token.isCanceled, isTrue);
    stale.complete();
    await _until(tester, () => document.calls.length == 7);
    await _settle(tester);
    expect(document.calls.map((call) => call.page), [
      2,
      22,
      23,
      18,
      19,
      20,
      21,
    ]);
    expect(stale.image.disposeCount, 1);
    expect(pdfSharedImageBudget.pendingBytes, 0);
  });

  testWidgets('דור מסמך חדש יכול לתזמן אותה כפולה בזמן השלמה ישנה', (
    tester,
  ) async {
    final old = _ControlledDocument(holdPage: 2);
    final reader = await pumpReader(tester, old);
    reader.notifyPage();
    await _until(tester, () => old.calls.isNotEmpty);
    final stale = old.calls.single;
    final next = _ControlledDocument();
    reader.replaceDocument(next);
    reader.notifyPage();
    await tester.pump();
    expect(stale.token.isCanceled, isTrue);
    stale.complete();
    await _until(tester, () => next.calls.length == 3);
    await _settle(tester);
    expect(old.calls, hasLength(1));
    expect(next.calls.map((call) => call.page), [2, 3, 1]);
    expect(stale.image.disposeCount, 1);
    expect(pdfSharedImageBudget.pendingBytes, 0);
  });

  testWidgets('תוכן עמוד חדש באותן מידות אינו משתמש בכפולה הישנה', (
    tester,
  ) async {
    final document = _ControlledDocument();
    final reader = await pumpReader(tester, document);
    reader.notifyPage();
    await _until(tester, () => document.calls.length == 3);
    await _settle(tester);
    document.replacePage(2);
    reader.controller.page = 2;
    reader.notifyPage();
    await _until(
      tester,
      () => document.calls.where((call) => call.page == 2).length == 2,
    );
    await _settle(tester);
    final calls = document.calls.where((call) => call.page == 2).toList();
    expect(calls.map((call) => call.content), [0, 1]);
    expect(pdfSharedImageBudget.pendingBytes, 0);
  });

  testWidgets('הסתרה וחזרה מתזמנות מחדש כפולה שהרינדור שלה טרם הסתיים', (
    tester,
  ) async {
    final document = _ControlledDocument(holdPage: 2);
    final reader = await pumpReader(tester, document);
    reader.notifyPage();
    await _until(tester, () => document.calls.isNotEmpty);
    final stale = document.calls.single;
    final tabs = tester.element(find.byType(PdfBookScreen)).read<TabsBloc>();
    final other = PdfBookTab(
      book: PdfBook(title: 'אחר', path: '${directory.path}/other.pdf'),
      pageNumber: 1,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [reader.tab, other], currentTabIndex: 1));
    await tester.pump();
    expect(stale.token.isCanceled, isTrue);
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [reader.tab, other], currentTabIndex: 0));
    await _settle(tester, rounds: 20);
    reader.notifyPage();
    await tester.pump();
    expect(document.calls, hasLength(1));
    stale.complete();
    await _until(tester, () => document.calls.length == 4);
    await _settle(tester);
    expect(document.calls.map((call) => call.page), [2, 2, 3, 1]);
    expect(stale.image.disposeCount, 1);
    expect(pdfSharedImageBudget.pendingBytes, 0);
  });

  testWidgets('callback מסמך מאוחר אינו מפעיל בקר אנימציה שכבר נסגר', (
    tester,
  ) async {
    final reader = await pumpReader(tester, _ControlledDocument());
    final documentChanged = reader.params.onDocumentChanged!;
    await reader.dispose();
    documentChanged(_ControlledDocument());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefetch replaces stale spread under a tight budget', (
    tester,
  ) async {
    final document = _ControlledDocument();
    final reader = await pumpReader(tester, document);
    final baseline = pdfSharedImageBudget.estimatedBytes;
    reader.controller.zoom = 0.55;
    reader.notifyPage();
    await _until(tester, () => document.calls.length == 3);
    await _settle(tester);
    final sharpSpreadReservation = 2 * 300 * 450 * 12;
    pdfSharedImageBudget.maximumBytes = baseline + sharpSpreadReservation;
    reader.controller.zoom = 1.1;
    reader.notifyPage();
    await _settle(tester, rounds: 20);
    final sharpCalls = document.calls.where((call) => call.image.width == 300);
    expect(sharpCalls.map((call) => call.page), containsAll([2, 3]));
  });

  testWidgets('אותו מדרג זום משתמש בתמונות; מדרג גבוה מרנדר תמונה חדה', (
    tester,
  ) async {
    final document = _ControlledDocument();
    final reader = await pumpReader(tester, document);
    reader.controller.zoom = 0.55;
    reader.notifyPage();
    await _until(tester, () => document.calls.length == 3);
    await _settle(tester);
    expect(document.calls.map((call) => call.image.width), everyElement(200));
    reader.controller.zoom = 0.6;
    reader.notifyPage();
    await _settle(tester);
    expect(document.calls, hasLength(3));
    reader.controller.zoom = 1.1;
    reader.notifyPage();
    await _until(tester, () => document.calls.length == 6);
    await _settle(tester);
    expect(
      document.calls.skip(3).map((call) => call.image.width),
      everyElement(300),
    );
    expect(pdfSharedImageBudget.pendingBytes, 0);
  });
}

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await _settle(tester, rounds: 1);
  }
  expect(done(), isTrue);
}

class _Reader {
  _Reader(this.tester, this.tab, this.actual, this.controller)
    : realDocument = actual.document;
  final WidgetTester tester;
  final PdfBookTab tab;
  final PdfViewerController actual;
  final PdfDocument realDocument;
  final _ControlledController controller;
  final documents = <_ControlledDocument>{};
  bool _disposed = false;

  PdfViewerParams get params =>
      tester.widget<PdfViewer>(find.byType(PdfViewer)).params;

  void notifyPage() {
    documents.add(controller.document);
    params.onPageChanged!(controller.page);
  }

  void replaceDocument(_ControlledDocument document) {
    controller.document = document;
    params.onDocumentChanged!(document);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    controller.ready = false;
    for (final document in documents) {
      for (final call in document.calls) {
        call.complete();
      }
    }
    tab.pdfViewerController = actual;
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await disposePdfDocument(tester, realDocument);
    expect(pdfSharedImageBudget.pendingBytes, 0);
    expect(tester.takeException(), isNull);
  }
}

class _ControlledController extends PdfViewerController {
  _ControlledController(this.actual, this.document) : zoom = actual.currentZoom;
  final PdfViewerController actual;
  bool ready = false;
  int page = 1;
  double zoom;
  @override
  _ControlledDocument document;
  @override
  bool get isReady => ready;
  @override
  int? get pageNumber => page;
  @override
  int get pageCount => document.pages.length;
  @override
  double get currentZoom => zoom;
  @override
  Matrix4 get value => Matrix4.diagonal3Values(zoom, zoom, 1);
  @override
  PdfPageLayout get layout => actual.layout;
  @override
  PdfViewerParams get params => actual.params;
  @override
  Size get viewSize => actual.viewSize;
  @override
  Rect get visibleRect => actual.visibleRect;
  @override
  PdfDocumentRef get documentRef => actual.documentRef;
}

class _ControlledDocument extends Fake implements PdfDocument {
  _ControlledDocument({this.holdPage}) {
    pages = List.generate(30, (index) => _ControlledPage(this, index + 1, 0));
  }
  final int? holdPage;
  final calls = <_RenderCall>[];
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
  @override
  late List<PdfPage> pages;

  void replacePage(int page) {
    pages = [...pages]..[page - 1] = _ControlledPage(this, page, 1);
  }
}

class _ControlledPage extends Fake implements PdfPage {
  _ControlledPage(this.document, this.pageNumber, this.content);
  @override
  final _ControlledDocument document;
  @override
  final int pageNumber;
  final int content;
  @override
  double get width => 200;
  @override
  double get height => 300;
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
    final call = _RenderCall(
      pageNumber,
      content,
      priority!,
      cancellationToken!,
      _CountingImage(fullWidth!.ceil(), fullHeight!.ceil()),
    );
    document.calls.add(call);
    if (document.holdPage != pageNumber || document.calls.length > 1) {
      call.complete();
    }
    return call.result.future;
  }
}

class _RenderCall {
  _RenderCall(this.page, this.content, this.priority, this.token, this.image);
  final int page;
  final int content;
  final PdfPageRenderPriority priority;
  final PdfPageRenderCancellationToken token;
  final _CountingImage image;
  final result = Completer<PdfImage?>();
  void complete() {
    if (!result.isCompleted) result.complete(image);
  }
}

class _CountingImage implements PdfImage {
  _CountingImage(this.width, this.height)
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

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}
