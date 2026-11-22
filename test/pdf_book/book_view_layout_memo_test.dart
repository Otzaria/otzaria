import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_book_layout.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test_helpers/book_view_layout_document.dart';

class _FakePage extends Fake implements PdfPage {
  _FakePage(this.width, this.height);

  @override
  double width;

  @override
  double height;
}

void main() {
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

  for (final pageCount in [100, 1000, 10000]) {
    test('מסמך קשור: $pageCount עמודים אינם נסרקים ב־100 עדכוני פריסה', () {
      final document = CountingLayoutDocument(
        List.filled(pageCount, const Size(400, 600)),
      );
      final memo = BookViewLayoutMemo()..bindDocument(document);
      addTearDown(document.dispose);
      addTearDown(memo.dispose);
      final first = memo.layout(
        document.pages,
        hasCover: true,
        verticalMargin: 16,
      );
      expect(document.dimensionReads, pageCount * 2);
      document.dimensionReads = 0;
      for (var i = 0; i < 100; i++) {
        expect(
          memo.layout(document.pages, hasCover: true, verticalMargin: 16),
          same(first),
        );
      }
      expect(document.dimensionReads, 0);
    });
  }

  test('אירוע מידות באותה רשימה מעדכן רק את דור הפריסה הבא', () {
    final document = CountingLayoutDocument(
      List.filled(5, const Size(400, 600)),
    );
    final memo = BookViewLayoutMemo()..bindDocument(document);
    addTearDown(document.dispose);
    addTearDown(memo.dispose);
    final first = memo.layout(
      document.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    final page = document.pages[3] as CountingLayoutPage;
    page.size = const Size(450, 700);
    document.emit(
      PdfDocumentPageStatusChangedEvent(
        document,
        changes: {4: PdfPageStatusChange.modified(page: page)},
      ),
    );
    final changed = memo.layout(
      document.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    expect(changed, isNot(same(first)));
    expect(changed.pageLayouts[3].size, const Size(450, 700));
    expect(first.pageLayouts[3].size, const Size(400, 600));
    document.dimensionReads = 0;
    expect(
      memo.layout(document.pages, hasCover: true, verticalMargin: 16),
      same(changed),
    );
    expect(document.dimensionReads, 0);
  });

  test('החלפת רשימה נבדקת גם לפני מסירת אירוע אסינכרוני', () async {
    final document = CountingLayoutDocument(
      List.filled(5, const Size(400, 600)),
      syncEvents: false,
    );
    final memo = BookViewLayoutMemo()..bindDocument(document);
    addTearDown(document.dispose);
    addTearDown(memo.dispose);
    final first = memo.layout(
      document.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    document.replacePages([
      ...document.pages.take(4),
      CountingLayoutPage(document, 5, const Size(800, 900)),
    ]);
    final changed = memo.layout(
      document.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    expect(changed, isNot(same(first)));
    expect(changed.pageLayouts[4].size, const Size(800, 900));
    await Future<void>.delayed(Duration.zero);
    expect(
      memo.layout(document.pages, hasCover: true, verticalMargin: 16),
      same(changed),
    );
    document.dimensionReads = 0;
    memo.layout(document.pages, hasCover: true, verticalMargin: 16);
    expect(document.dimensionReads, 0);
  });

  for (final hasCover in [true, false]) {
    test('סיבוב, סידור ומחיקה שומרים פריסת RTL: כריכה=$hasCover', () {
      final document = CountingLayoutDocument(const [
        Size(400, 600),
        Size(300, 500),
        Size(450, 700),
        Size(500, 800),
      ]);
      final memo = BookViewLayoutMemo()..bindDocument(document);
      addTearDown(document.dispose);
      addTearDown(memo.dispose);
      PdfPageLayout layout() => memo.layout(
        document.pages,
        hasCover: hasCover,
        verticalMargin: 16,
      );
      void expectSizes(List<Size> sizes) {
        final expected = buildBookViewPageLayout(
          pageSizes: sizes,
          hasCover: hasCover,
          verticalMargin: 16,
        );
        final actual = layout();
        expect(actual.pageLayouts, expected.pageLayouts);
        expect(actual.documentSize, expected.documentSize);
      }

      final initial = layout();
      final pages = document.pages;
      document.replacePages([
        pages[0],
        pages[2].rotatedCW90().withPageNumber(2),
        pages[1].withPageNumber(3),
        pages[3],
      ]);
      expectSizes(const [
        Size(400, 600),
        Size(700, 450),
        Size(300, 500),
        Size(500, 800),
      ]);
      expect(layout(), isNot(same(initial)));
      final firstPair = hasCover ? 1 : 0;
      expect(
        layout().pageLayouts[firstPair].left,
        greaterThan(layout().pageLayouts[firstPair + 1].left),
      );
      document.replacePages(document.pages.take(3).toList(), changes: {});
      expectSizes(const [Size(400, 600), Size(700, 450), Size(300, 500)]);
      document.replacePages([], changes: {});
      expectSizes([]);
      document.replacePages([pages[0]]);
      expectSizes(const [Size(400, 600)]);
    });
  }

  test('כריכה ומרווח משנים פריסה בלי לקרוא שוב מידות תקפות', () {
    final document = CountingLayoutDocument(
      List.filled(5, const Size(400, 600)),
    );
    final memo = BookViewLayoutMemo()..bindDocument(document);
    addTearDown(document.dispose);
    addTearDown(memo.dispose);
    final first = memo.layout(
      document.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    document.dimensionReads = 0;
    final changed = memo.layout(
      document.pages,
      hasCover: false,
      verticalMargin: 8,
    );
    expect(changed, isNot(same(first)));
    expect(changed.pageLayouts[2].top, 608);
    expect(document.dimensionReads, 0);
  });

  test('אירועי תוכן ללא שינוי מידות משמרים את הפריסה', () {
    final document = CountingLayoutDocument(
      List.filled(5, const Size(400, 600)),
    );
    final memo = BookViewLayoutMemo()..bindDocument(document);
    addTearDown(document.dispose);
    addTearDown(memo.dispose);
    final first = memo.layout(
      document.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    document.replacePages(List.of(document.pages));
    expect(
      memo.layout(document.pages, hasCover: true, verticalMargin: 16),
      same(first),
    );
    document.dimensionReads = 0;
    document.emit(PdfDocumentLoadCompleteEvent(document));
    document.emit(PdfDocumentMissingFontsEvent(document, const []));
    memo.layout(document.pages, hasCover: true, verticalMargin: 16);
    expect(document.dimensionReads, 0);
  });

  test('החלפת מסמך מנתקת אירועים ישנים, וקישור חוזר אינו מאפס', () async {
    final firstDocument = CountingLayoutDocument(
      const [Size(400, 600)],
      syncEvents: false,
    );
    final secondDocument = CountingLayoutDocument(const [Size(400, 600)]);
    final memo = BookViewLayoutMemo()..bindDocument(firstDocument);
    addTearDown(firstDocument.dispose);
    addTearDown(secondDocument.dispose);
    addTearDown(memo.dispose);
    final first = memo.layout(
      firstDocument.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    firstDocument.replacePages([
      CountingLayoutPage(firstDocument, 1, const Size(500, 700)),
    ]);
    memo.bindDocument(secondDocument);
    expect(firstDocument.hasListener, isFalse);
    expect(secondDocument.hasListener, isTrue);
    final second = memo.layout(
      secondDocument.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    expect(second, isNot(same(first)));
    secondDocument.dimensionReads = 0;
    memo.bindDocument(secondDocument);
    expect(
      memo.layout(secondDocument.pages, hasCover: true, verticalMargin: 16),
      same(second),
    );
    expect(secondDocument.dimensionReads, 0);
    memo.bindDocument(firstDocument);
    final rebound = memo.layout(
      firstDocument.pages,
      hasCover: true,
      verticalMargin: 16,
    );
    expect(rebound.pageLayouts.single.size, const Size(500, 700));
    expect(secondDocument.hasListener, isFalse);
    firstDocument.dimensionReads = 0;
    await Future<void>.delayed(Duration.zero);
    expect(
      memo.layout(firstDocument.pages, hasCover: true, verticalMargin: 16),
      same(rebound),
    );
    expect(firstDocument.dimensionReads, 0);
  });

  test('רשימה חיצונית וניתוק מהמסמך נשארים עם בדיקת מידות', () {
    final document = CountingLayoutDocument(const [Size(400, 600)]);
    final memo = BookViewLayoutMemo()..bindDocument(document);
    addTearDown(document.dispose);
    addTearDown(memo.dispose);
    final externalPages = List.of(document.pages);
    memo.layout(externalPages, hasCover: true, verticalMargin: 16);
    final page = document.pages.single as CountingLayoutPage;
    page.size = const Size(400, 700);
    expect(
      memo
          .layout(externalPages, hasCover: true, verticalMargin: 16)
          .pageLayouts
          .single
          .height,
      700,
    );
    memo.bindDocument(null);
    expect(document.hasListener, isFalse);
    memo.layout(document.pages, hasCover: true, verticalMargin: 16);
    page.size = const Size(400, 800);
    expect(
      memo
          .layout(document.pages, hasCover: true, verticalMargin: 16)
          .pageLayouts
          .single
          .height,
      800,
    );
  });

  test('dispose מנתק את המאזין ואינו מאפשר קישור מאוחר', () {
    final document = CountingLayoutDocument(const [Size(400, 600)]);
    final memo = BookViewLayoutMemo()..bindDocument(document);
    addTearDown(document.dispose);
    expect(document.hasListener, isTrue);
    memo.dispose();
    expect(document.hasListener, isFalse);
    memo.bindDocument(document);
    expect(document.hasListener, isFalse);
  });
}
