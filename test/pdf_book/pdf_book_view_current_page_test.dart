import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_spread_layout.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import '../test_helpers/pdf_document_dispose.dart';

/// בתצוגת ספר העמוד הנוכחי שמדווח הקורא הוא של הכפולה המוצגת — ממנו מחושב
/// יעד החיצים.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const pageCount = 40;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => call.method == 'getTemporaryDirectory'
              ? '/tmp/otzaria-pdfrx-test'
              : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<PdfViewerController> pumpBookView(
    WidgetTester tester,
    Size surface,
  ) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final document = (await tester.runAsync(() async {
      final source = pw.Document();
      for (var i = 0; i < pageCount; i++) {
        source.addPage(pw.Page(build: (context) => pw.SizedBox()));
      }
      return PdfDocument.openData(
        await source.save(),
        sourceName: 'pdf-book-view-current-page-test.pdf',
        useProgressiveLoading: false,
      );
    }))!;
    addTearDown(() => disposePdfDocument(tester, document));
    final controller = PdfViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document),
          controller: controller,
          params: PdfViewerParams(
            layoutStrategy: const BookViewLayout(hasCover: true),
            calculateCurrentPageNumber: pdfCurrentPageCalculatorFor(
              PdfLayoutMode.bookView,
            ),
            sizeDelegateProvider: pdfSizeDelegateProviderForLayoutMode(
              PdfLayoutMode.bookView,
            ),
            behaviorControlParams: const PdfViewerBehaviorControlParams(
              trailingPageLoadingDelay: Duration.zero,
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    });

    var hasLayout = false;
    for (var i = 0; i < 50 && !hasLayout; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      try {
        if (controller.isReady) {
          controller.layout;
          controller.viewSize;
          hasLayout = true;
        }
      } catch (_) {
        // pdfrx מדווח isReady מעט לפני פריים הפריסה הראשון.
      }
    }
    expect(hasLayout, isTrue);
    return controller;
  }

  Future<int> pageWithCenterAt(
    WidgetTester tester,
    PdfViewerController controller,
    Offset center,
    double zoom,
  ) async {
    await tester.runAsync(
      () => controller.goTo(
        controller.calcMatrixFor(center, zoom: zoom),
        duration: Duration.zero,
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return controller.pageNumber!;
  }

  group('העמוד הנוכחי בתצוגת ספר (issue #1712)', () {
    testWidgets('מוגדל: חלקה התחתון של כפולה וראש כפולה בסוף הספר', (
      tester,
    ) async {
      final controller = await pumpBookView(tester, const Size(1400, 800));
      // נראה כשליש מגובה הכפולה, כמו 215% בדיווח.
      const zoom = 3.0;
      final viewHeight = controller.viewSize.height / zoom;
      Offset centerAt(int spreadStartPage, double fraction) {
        final rect = controller.layout.pageLayouts[spreadStartPage - 1];
        final top = rect.top + fraction * (rect.height - viewHeight);
        return Offset(rect.left, top + viewHeight / 2);
      }

      // תחילת הספר, תחתית (4,5): חץ שמאלה מעביר ל-(6,7).
      final nearStart = await pageWithCenterAt(
        tester,
        controller,
        centerAt(4, 0.9),
        zoom,
      );
      expect(pdfSpreadStartPage(nearStart), 4);
      expect(pdfNextSpreadFocusPage(nearStart, pageCount), 6);

      // סוף הספר, ראש (36,37): חץ ימינה חוזר ל-(34,35).
      final nearEnd = await pageWithCenterAt(
        tester,
        controller,
        centerAt(36, 0),
        zoom,
      );
      expect(pdfSpreadStartPage(nearEnd), 36);
      expect(pdfPreviousSpreadFocusPage(nearEnd), 35);
    });

    testWidgets('חלון גבוה מהכפולה: הכפולה הממורכזת היא הנוכחית', (
      tester,
    ) async {
      final controller = await pumpBookView(tester, const Size(900, 1000));
      final zoom =
          controller.viewSize.width / controller.layout.documentSize.width;
      for (final spreadStart in [4, 36]) {
        final pages = controller.layout.pageLayouts;
        final spread = pages[spreadStart - 1].expandToInclude(
          pages[spreadStart],
        );
        final page = await pageWithCenterAt(
          tester,
          controller,
          spread.center,
          zoom,
        );
        expect(pdfSpreadStartPage(page), spreadStart);
      }
    });
  });
}
