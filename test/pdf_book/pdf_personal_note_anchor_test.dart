import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_personal_note_anchor.dart';
import 'package:otzaria/personal_notes/models/pdf_note_anchor.dart';
import 'package:pdfrx/pdfrx.dart';

class _CountingRects extends ListBase<Rect> {
  _CountingRects(this._pages);

  final List<Rect> _pages;
  int reads = 0;

  @override
  int get length => _pages.length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  Rect operator [](int index) {
    reads++;
    return _pages[index];
  }

  @override
  void operator []=(int index, Rect value) =>
      throw UnsupportedError('read-only');
}

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
    final lookup = PdfNotePageLookup();
    final layout = PdfPageLayout(
      pageLayouts: const [
        Rect.fromLTWH(10, 10, 200, 400),
        Rect.fromLTWH(10, 420, 200, 400),
        Rect.fromLTWH(10, 830, 200, 400),
      ],
      documentSize: const Size(210, 1230),
    );
    expect(
      lookup.visiblePages(layout, const Rect.fromLTWH(10, 300, 200, 200)),
      [1, 2],
    );
    expect(
      lookup.visiblePages(layout, const Rect.fromLTWH(10, 425, 200, 390)),
      [2],
    );
    expect(
      lookup.visiblePages(layout, const Rect.fromLTRB(10, 410, 210, 420)),
      isEmpty,
    );
    expect(
      lookup.visiblePages(layout, const Rect.fromLTWH(210, 300, 200, 200)),
      isEmpty,
    );
  });

  test('גלילה בפריסה קבועה בודקת רק עמודים ליד אזור התצוגה', () {
    final lookup = PdfNotePageLookup();
    final pages = _CountingRects(
      List.generate(20000, (index) => Rect.fromLTWH(0, index * 100.0, 100, 90)),
    );
    final layout = PdfPageLayout(
      pageLayouts: pages,
      documentSize: const Size(100, 2000000),
    );
    lookup.visiblePages(layout, const Rect.fromLTWH(0, 0, 100, 90));

    pages.reads = 0;
    expect(
      lookup.visiblePages(layout, const Rect.fromLTWH(0, 999990, 100, 130)),
      [10001, 10002],
    );
    expect(pages.reads, lessThan(30));
  });

  test('פריסה מעודכנת נבדקת מחדש ושומרת סדר בפריסה לא ממוינת', () {
    final lookup = PdfNotePageLookup();
    const viewport = Rect.fromLTRB(0, 55, 100, 75);
    final initial = PdfPageLayout(
      pageLayouts: const [Rect.fromLTWH(0, 0, 100, 50)],
      documentSize: const Size(100, 50),
    );
    expect(lookup.visiblePages(initial, viewport), isEmpty);

    final updated = PdfPageLayout(
      pageLayouts: const [
        Rect.fromLTWH(0, 20, 100, 100),
        Rect.fromLTWH(0, 30, 100, 10),
        Rect.fromLTWH(0, 0, 100, 80),
      ],
      documentSize: const Size(100, 120),
    );
    expect(lookup.visiblePages(updated, viewport), [1, 3]);
  });

  test('כפולה מסוננת לפי טווח העמודים והחיתוך המדויק', () {
    final lookup = PdfNotePageLookup();
    final layout = PdfPageLayout(
      pageLayouts: const [
        Rect.fromLTWH(0, 0, 100, 90),
        Rect.fromLTWH(110, 100, 100, 90),
        Rect.fromLTWH(0, 100, 100, 70),
      ],
      documentSize: const Size(210, 190),
    );
    const spread = (startPage: 2, endPageExclusive: 4);
    expect(
      lookup.visiblePages(
        layout,
        const Rect.fromLTWH(0, 0, 210, 190),
        spread: spread,
      ),
      [2, 3],
    );
    expect(
      lookup.visiblePages(
        layout,
        const Rect.fromLTWH(0, 0, 110, 190),
        spread: spread,
      ),
      [3],
    );
    expect(
      lookup.visiblePages(
        layout,
        const Rect.fromLTWH(0, 0, 210, 190),
        spread: (startPage: 3, endPageExclusive: 5),
      ),
      [3],
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
