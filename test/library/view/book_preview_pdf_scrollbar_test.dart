import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_fallback.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/pdf_document_dispose.dart';
import '../../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late PdfBook shortBook;
  late PdfBook longBook;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = await Directory.systemTemp.createTemp('preview-scrollbar-');

    Future<PdfBook> createBook(int pages) async {
      final file = File('${directory.path}/$pages.pdf');
      final document = pw.Document();
      for (var page = 1; page <= pages; page++) {
        document.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(400, 400),
            build: (_) => pw.Text('Page $page'),
          ),
        );
      }
      await file.writeAsBytes(await document.save());
      return PdfBook(title: 'מסמך $pages', path: file.path);
    }

    shortBook = await createBook(1);
    longBook = await createBook(3);
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  tearDownAll(() => directory.delete(recursive: true));

  final viewer = find.byType(PdfViewer);
  final thumb = find.byType(PdfViewerScrollThumb);

  Future<void> pumpPreview(
    WidgetTester tester,
    PdfBook book,
    TextDirection direction,
    List<int> openedPages, {
    Size size = const Size(640, 700),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = StubSettingsBloc();
    addTearDown(settings.close);
    final document = PdfFontFallback.documentRef(book.path).resolveListenable();
    final release = document.addListener(() {});
    addTearDown(() async {
      final loaded = document.document;
      await tester.pumpWidget(const SizedBox.shrink());
      release();
      if (loaded != null) await disposePdfDocument(tester, loaded);
    });
    await tester.runAsync(document.load);
    expect(document.error, isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: Directionality(
            textDirection: direction,
            child: BookPreviewPanel(
              book: book,
              onOpenInReader: (page, {forcePdf}) => openedPages.add(page),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> doubleClick(WidgetTester tester, Offset position) async {
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  for (final direction in TextDirection.values) {
    testWidgets('הרצועה בימין הפיזי והמחוון נגרר ב־$direction', (tester) async {
      final openedPages = <int>[];
      await pumpPreview(tester, longBook, direction, openedPages);
      final controller = tester.widget<PdfViewer>(viewer).controller!;
      expect(controller.isReady, isTrue);
      final view = tester.getRect(viewer);
      final handle = tester.getRect(thumb);
      expect(view.left, 0);
      expect(view.width, 640 - AppTokens.scrollbarGutter);
      expect(handle.width, AppTokens.scrollbarThickness);
      expect(handle.left - view.right, AppTokens.scrollbarContentGap);
      expect(640 - handle.right, AppTokens.scrollbarMargin);

      await doubleClick(tester, Offset(handle.center.dx, view.center.dy));
      expect(openedPages, isEmpty);
      final initialTop = controller.visibleRect.top;
      await tester.dragFrom(handle.center, const Offset(0, 260));
      await tester.pumpAndSettle();
      expect(controller.visibleRect.top, greaterThan(initialTop));
      await doubleClick(tester, view.center);
      expect(openedPages, [controller.pageNumber]);
    });
  }

  testWidgets('בהתאמת הפתיחה הדף כולו נראה והגלגלת פועלת בשוליים', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      longBook,
      TextDirection.rtl,
      [],
      size: const Size(640, 460),
    );
    final controller = tester.widget<PdfViewer>(viewer).controller!;
    final view = tester.getRect(viewer);
    final firstPage = controller.layout.pageLayouts.first;
    expect(
      controller.documentToGlobal(firstPage.topLeft)!.dx,
      greaterThanOrEqualTo(view.left),
    );
    expect(
      controller.documentToGlobal(firstPage.topRight)!.dx,
      lessThanOrEqualTo(view.right),
    );

    final scrollbarMargin = Offset(639, view.center.dy);
    final beforeWheel = controller.visibleRect.top;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: scrollbarMargin,
        scrollDelta: const Offset(0, 40),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.visibleRect.top - beforeWheel, closeTo(40, 0.01));

    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    final beforePan = controller.visibleRect.top;
    await trackpad.panZoomStart(scrollbarMargin);
    await trackpad.panZoomUpdate(scrollbarMargin, pan: const Offset(0, -80));
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(controller.visibleRect.top, greaterThan(beforePan));
  });

  testWidgets('בגובה קרוב להתאמה מלאה הרצועה מוסרת והזום נשאר יציב', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      shortBook,
      TextDirection.rtl,
      [],
      size: const Size(640, 634),
    );
    final controller = tester.widget<PdfViewer>(viewer).controller!;
    expect(tester.getSize(viewer).width, 640);
    expect(thumb, findsNothing);
    expect(
      controller.documentSize.height * controller.currentZoom,
      closeTo(634, 1e-6),
    );

    await tester.binding.setSurfaceSize(const Size(640, 700));
    await tester.pumpAndSettle();
    expect(tester.getSize(viewer).width, 640);
    expect(thumb, findsNothing);
    expect(tester.widget<PdfViewer>(viewer).controller, same(controller));
    expect(tester.takeException(), isNull);
  });

  testWidgets('זום פותח וסוגר את הרצועה בלי לחסום לחיצה כפולה', (tester) async {
    final openedPages = <int>[];
    await pumpPreview(tester, shortBook, TextDirection.rtl, openedPages);
    final controller = tester.widget<PdfViewer>(viewer).controller!;
    expect(controller.isReady, isTrue);
    expect(tester.getSize(viewer).width, 640);
    expect(thumb, findsNothing);
    final fit = controller.currentZoom;

    await controller.setZoom(Offset.zero, fit * 2, duration: Duration.zero);
    await tester.pumpAndSettle();
    expect(tester.getSize(viewer).width, 640 - AppTokens.scrollbarGutter);
    expect(thumb, findsOneWidget);

    await controller.setZoom(Offset.zero, fit, duration: Duration.zero);
    await tester.pumpAndSettle();
    expect(tester.getSize(viewer).width, 640);
    expect(thumb, findsNothing);
    expect(tester.widget<PdfViewer>(viewer).controller, same(controller));
    await doubleClick(tester, const Offset(636, 375));
    expect(openedPages, [1]);
  });
}
