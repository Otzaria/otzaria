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

class _CountingPage extends Fake implements PdfPage {
  _CountingPage(this._width, this._height);

  final double _width;
  final double _height;
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

void main() {
  test('בנייה חדשה ושינוי פרמטרים קוראים את מידות כל עמוד פעם אחת', () {
    const count = 10000;
    final pages = [
      for (var i = 0; i < count; i++)
        _CountingPage(400.0 + i % 3, 600.0 + i % 5),
    ];
    final memo = BookViewLayoutMemo();
    for (final (hasCover, margin) in [
      (true, 16.0),
      (false, 16.0),
      (false, 8.0),
    ]) {
      for (final page in pages) {
        page.sizeReads = 0;
      }
      final layout = memo.layout(
        pages,
        hasCover: hasCover,
        verticalMargin: margin,
      );
      expect(pages.fold(0, (sum, page) => sum + page.sizeReads), count * 2);
      expect(layout.pageLayouts, hasLength(count));
      for (var i = 0; i < count; i++) {
        expect(layout.pageLayouts[i].width, 400.0 + i % 3);
        expect(layout.pageLayouts[i].height, 600.0 + i % 5);
      }
    }
  });

  test('פריסה שמורה עדיין נבדקת בסריקת מידות אחת ומחזירה אותו מופע', () {
    final pages = [for (var i = 0; i < 10000; i++) _CountingPage(400, 600)];
    final memo = BookViewLayoutMemo();
    final first = memo.layout(pages, hasCover: true, verticalMargin: 16);
    for (final page in pages) {
      page.sizeReads = 0;
    }

    final cached = memo.layout(pages, hasCover: true, verticalMargin: 16);

    expect(cached, same(first));
    expect(
      pages.fold(0, (sum, page) => sum + page.sizeReads),
      pages.length * 2,
    );
  });

  test('מידות זהות — אותו מופע פריסה', () {
    final memo = BookViewLayoutMemo();
    final pages = [for (var i = 0; i < 5; i++) _FakePage(400, 600)];
    final first = memo.layout(pages, hasCover: true, verticalMargin: 16);
    expect(
      memo.layout(List.of(pages), hasCover: true, verticalMargin: 16),
      same(first),
    );
  });

  test('עמוד שנמדד מחדש (אותו אובייקט, מידה אחרת) — פריסה חדשה', () {
    final memo = BookViewLayoutMemo();
    final pages = [for (var i = 0; i < 5; i++) _FakePage(400, 600)];
    final first = memo.layout(pages, hasCover: true, verticalMargin: 16);
    pages[3].height = 700;
    final second = memo.layout(pages, hasCover: true, verticalMargin: 16);
    expect(second, isNot(same(first)));
    expect(second.pageLayouts[3].height, 700);
  });

  test('שינוי כריכה, מרווח או מספר עמודים — פריסה חדשה', () {
    final memo = BookViewLayoutMemo();
    final pages = [for (var i = 0; i < 5; i++) _FakePage(400, 600)];
    final first = memo.layout(pages, hasCover: true, verticalMargin: 16);
    expect(
      memo.layout(pages, hasCover: false, verticalMargin: 16),
      isNot(same(first)),
    );
    final second = memo.layout(pages, hasCover: false, verticalMargin: 8);
    expect(second.pageLayouts, hasLength(5));
    expect(
      memo.layout(pages.sublist(1), hasCover: false, verticalMargin: 8),
      isNot(same(second)),
    );
  });
}
