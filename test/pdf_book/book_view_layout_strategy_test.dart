import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_book_layout.dart';
import 'package:pdfrx/pdfrx.dart';

class _FakeDocument extends Fake implements PdfDocument {}

class _FakePage extends Fake implements PdfPage {
  _FakePage(this.document, this._width, this._height);

  @override
  final PdfDocument document;

  double _width;
  double _height;
  int sizeReads = 0;

  @override
  double get width {
    sizeReads++;
    return _width;
  }

  @override
  double get height {
    sizeReads++;
    return _height;
  }
}

List<_FakePage> _pages(int count) {
  final document = _FakeDocument();
  return [
    for (var i = 0; i < count; i++)
      _FakePage(document, 400.0 + i % 3, 600.0 + i % 5),
  ];
}

PdfPageLayout _resolve(
  PdfPageLayoutStrategy strategy,
  List<PdfPage> pages, {
  Size viewport = Size.zero,
}) => strategy.resolve(PdfPageLayoutContext(pages: pages, viewport: viewport));

void main() {
  test('השוויון של האסטרטגיה נקבע לפי מצב הכריכה', () {
    expect(
      const BookViewLayout(hasCover: true),
      const BookViewLayout(hasCover: true),
    );
    expect(
      const BookViewLayout(hasCover: true),
      isNot(const BookViewLayout(hasCover: false)),
    );
  });

  test('מדווחת את המרווח של התצוגה הרציפה וגלילה אנכית', () {
    final pages = _pages(5);
    final layout = _resolve(const BookViewLayout(hasCover: true), pages);
    expect(layout.margin, const SequentialPagesLayout().margin);
    expect(layout.primaryAxis, Axis.vertical);
    expect(
      layout.pageLayouts,
      buildBookViewPageLayout(
        pageSizes: [for (final page in pages) Size(page.width, page.height)],
        hasCover: true,
        verticalMargin: BookViewLayout.margin * 2,
      ).pageLayouts,
    );
  });

  test('שינוי חלון או החלפת הרשימה במידות זהות מחזירים אותה פריסה', () {
    final pages = _pages(10000);
    const strategy = BookViewLayout(hasCover: true);
    final first = _resolve(strategy, pages, viewport: const Size(900, 700));

    for (final page in pages) {
      expect(page.sizeReads, 2);
      page.sizeReads = 0;
    }
    final resized = _resolve(
      strategy,
      pages,
      viewport: const Size(1200, 800),
    );
    expect(resized, same(first));
    expect(pages.map((page) => page.sizeReads), everyElement(2));

    final replacement = [
      for (final page in pages)
        _FakePage(page.document, page._width, page._height),
    ];
    expect(_resolve(strategy, replacement), same(first));
  });

  test('מדידה חדשה מעדכנת עמודים ומיקומים בסריקה אחת', () {
    final pages = _pages(5);
    const strategy = BookViewLayout(hasCover: true);
    final first = _resolve(strategy, pages);
    for (final page in pages) {
      page.sizeReads = 0;
    }
    pages[2]._width = 500;
    pages[2]._height = 700;
    final second = _resolve(strategy, pages);
    expect(second, isNot(same(first)));
    expect(second.pageLayouts[2].size, const Size(500, 700));
    expect(second.pageLayouts[3].top, greaterThan(first.pageLayouts[3].top));
    expect(pages.map((page) => page.sizeReads), everyElement(2));
    expect(_resolve(strategy, pages), same(second));
  });

  test('מצבי כריכה ומסמכים מחזיקים פריסות נפרדות', () {
    final pages = _pages(5);
    const cover = BookViewLayout(hasCover: true);
    const noCover = BookViewLayout(hasCover: false);
    final first = _resolve(cover, pages);
    final withoutCover = _resolve(noCover, pages);
    expect(first.pageLayouts, isNot(withoutCover.pageLayouts));
    expect(_resolve(cover, _pages(5)), isNot(same(first)));
    expect(_resolve(cover, pages), same(first));
    expect(_resolve(noCover, pages), same(withoutCover));

    final shorter = _resolve(cover, pages.sublist(0, 3));
    expect(shorter.pageLayouts, hasLength(3));
    expect(_resolve(cover, pages).pageLayouts, first.pageLayouts);
    expect(_resolve(noCover, pages), same(withoutCover));
  });
}
