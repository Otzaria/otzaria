import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:pdfrx/pdfrx.dart';

class _FakePage extends Fake implements PdfPage {
  _FakePage(this.width, this.height);

  @override
  double width;

  @override
  double height;
}

PdfPageLayout _resolve(PdfPageLayoutStrategy strategy, List<PdfPage> pages) =>
    strategy.resolve(PdfPageLayoutContext(pages: pages, viewport: Size.zero));

void main() {
  test('שוויון לפי הכריכה בלבד — pdfrx מחשב פריסה מחדש רק כשהיא משתנה', () {
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
    final pages = [for (var i = 0; i < 5; i++) _FakePage(400, 600)];
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

  test('עמוד שנמדד מחדש משנה את הפריסה', () {
    final pages = [for (var i = 0; i < 5; i++) _FakePage(400, 600)];
    const strategy = BookViewLayout(hasCover: true);
    final first = _resolve(strategy, pages);
    pages[3].height = 700;
    final second = _resolve(strategy, pages);
    expect(second, isNot(first));
    expect(second.pageLayouts[3].height, 700);
  });
}
