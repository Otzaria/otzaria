import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_personal_note_anchor.dart';
import 'package:otzaria/personal_notes/models/pdf_note_anchor.dart';
import 'package:pdfrx/pdfrx.dart';

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber, this.rotation, {this.isLoaded = true});

  @override
  final int pageNumber;
  @override
  final PdfPageRotation rotation;
  @override
  final bool isLoaded;
  @override
  double get width => rotation.index.isOdd ? 400 : 200;
  @override
  double get height => rotation.index.isOdd ? 200 : 400;
}

class _Document extends Fake implements PdfDocument {}

class _Controller extends PdfViewerController {
  _Controller(this.pages, this.layout);

  @override
  bool isReady = true;
  @override
  final List<PdfPage> pages;
  @override
  int get pageCount => pages.length;
  @override
  final PdfPageLayout layout;
  @override
  PdfDocument document = _Document();
  @override
  double get currentZoom => 2.75;

  Offset? destination;
  double? usedZoom;
  int? selectedPage;

  @override
  Matrix4 calcMatrixFor(Offset position, {double? zoom, Size? viewSize}) {
    destination = position;
    usedZoom = zoom ?? currentZoom;
    return Matrix4.identity();
  }

  @override
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {}

  @override
  void setCurrentPageNumber(int pageNumber) => selectedPage = pageNumber;
}

void main() {
  const anchor = PdfNoteAnchor(pageNumber: 2, x: .25, y: .75);

  test('גלילה רציפה כוללת גם עמוד סמוך שנראה חלקית', () {
    const pages = [
      Rect.fromLTWH(10, 10, 200, 400),
      Rect.fromLTWH(10, 420, 200, 400),
      Rect.fromLTWH(10, 830, 200, 400),
    ];
    expect(
      visiblePdfNotePageNumbers(
        pageLayouts: pages,
        visibleRect: const Rect.fromLTWH(10, 300, 200, 200),
      ),
      [1, 2],
    );
    expect(
      visiblePdfNotePageNumbers(
        pageLayouts: pages,
        visibleRect: const Rect.fromLTWH(10, 425, 200, 390),
      ),
      [2],
    );
    expect(
      visiblePdfNotePageNumbers(
        pageLayouts: pages,
        visibleRect: const Rect.fromLTWH(10, 411, 200, 8),
      ),
      isEmpty,
    );
  });

  test('נקודה נשמרת בממדים המקוריים בכל ארבעת הסיבובים', () {
    const expectedOffsets = [
      Offset(50, 100),
      Offset(300, 50),
      Offset(150, 300),
      Offset(100, 150),
    ];
    for (final rotation in PdfPageRotation.values) {
      final page = _Page(2, rotation);
      final uiPoint = expectedOffsets[rotation.index];
      final saved = pdfNoteAnchorFromHit(
        PdfPageHitTestResult(
          page: page,
          offset: uiPoint.toPdfPoint(page: page),
        ),
      );
      expect(saved, anchor, reason: 'rotation ${rotation.index}');
      for (final scale in [.5, 1.0, 3.0]) {
        final pageRect = Rect.fromLTWH(
          725,
          40,
          page.width * scale,
          page.height * scale,
        );
        final restored = pdfNoteAnchorDocumentPosition(
          saved!,
          page: page,
          pageRect: pageRect,
        );
        expect(
          restored,
          Offset(725, 40) + uiPoint * scale,
          reason: 'rotation ${rotation.index}, scale $scale',
        );
      }
    }
  });

  test('hit-test שומר את עמוד הלחיצה בכפולה ולא את עמוד הבקר', () {
    final rightPage = _Page(3, PdfPageRotation.none);
    expect(
      pdfNoteAnchorFromHit(
        PdfPageHitTestResult(
          page: rightPage,
          offset: const PdfPoint(50, 300),
        ),
      )?.pageNumber,
      3,
    );
  });

  test('עמוד שממדיו עדיין משוערים אינו מייצר עוגן שגוי', () {
    expect(
      pdfNoteAnchorFromHit(
        PdfPageHitTestResult(
          page: _Page(2, PdfPageRotation.none, isLoaded: false),
          offset: const PdfPoint(50, 300),
        ),
      ),
      isNull,
    );
    expect(pdfNoteAnchorFromHit(null), isNull);
  });

  test('ניווט חוזר למקום בכפולה ושומר זום בלי להתבסס על שורת טקסט', () async {
    final controller = _Controller(
      [_Page(1, PdfPageRotation.none), _Page(2, PdfPageRotation.none)],
      PdfPageLayout(
        pageLayouts: const [
          Rect.fromLTWH(0, 0, 400, 800),
          Rect.fromLTWH(420, 0, 400, 800),
        ],
        documentSize: const Size(820, 800),
      ),
    );
    expect(await navigateToPdfNoteAnchor(controller, anchor), isTrue);
    expect(controller.destination, const Offset(520, 200));
    expect(controller.usedZoom, 2.75);
    expect(controller.selectedPage, 2);
  });

  test('בקשה מבוטלת או עמוד שאינו קיים אינם מנווטים למקום אחר', () async {
    final controller = _Controller(
      [_Page(1, PdfPageRotation.none)],
      PdfPageLayout(
        pageLayouts: const [Rect.fromLTWH(0, 0, 200, 400)],
        documentSize: const Size(200, 400),
      ),
    );
    expect(await navigateToPdfNoteAnchor(controller, anchor), isFalse);
    expect(
      await navigateToPdfNoteAnchor(
        controller,
        const PdfNoteAnchor(pageNumber: 1, x: .5, y: .5),
        isActive: () => false,
      ),
      isFalse,
    );
    expect(controller.destination, isNull);
    expect(controller.selectedPage, isNull);
  });
}
