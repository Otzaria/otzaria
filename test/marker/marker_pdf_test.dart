import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/view/pdf/marker_pdf.dart';

import 'marker_test_helpers.dart';

void main() {
  group('markerGraphemeRange', () {
    test('maps UTF-16 indices of the page text to graphemes', () {
      expect(markerGraphemeRange('אב גד', 3, 5), (start: 3, end: 5));
    });

    test('a letter selected without its vowels is taken whole', () {
      // "בְּ" is one grapheme of three code units.
      const text = 'א בְּרֵאשִׁית';
      expect(markerGraphemeRange(text, 2, 3), (start: 2, end: 3));
      expect(markerGraphemeRange(text, 3, 4), (start: 2, end: 3));
    });

    test('an empty or reversed range gives nothing', () {
      expect(markerGraphemeRange('אב', 1, 1), isNull);
      expect(markerGraphemeRange('אב', 2, 1), isNull);
    });
  });

  test('PDF marks and text marks of the same title stay apart', () async {
    final store = openTestMarkerStore();
    const line = 'בראשית ברא אלהים';
    await store.repository.importHighlights([
      highlightFor('text', [segmentFor(0, line, 'ברא')]),
      MarkerHighlight(
        id: 'pdf',
        bookTitle: 'בראשית',
        bookUid: 'pdf:1',
        segments: [segmentFor(1, line, 'אלהים')],
        pdf: true,
        text: 'אלהים',
        colorId: 'yellow',
        colorHex: '#F1E784',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ]);
    final text = await store.repository.loadBook(bookTitle: 'בראשית');
    final pdf = await store.repository.loadBook(
      bookTitle: 'בראשית',
      pdf: true,
    );
    expect(text.map((m) => m.id), ['text']);
    expect(pdf.map((m) => m.id), ['pdf']);
    expect(pdf.single.pdf, isTrue);
    expect((await store.repository.get('pdf'))!.pdf, isTrue);
    expect(MarkerHighlight.fromJson(pdf.single.toJson()), pdf.single);

    // רשימת הספרים והסינון מפרידים ביניהם.
    final books = await store.repository.books();
    expect(books, [
      (title: 'בראשית', pdf: false, count: 1),
      (title: 'בראשית', pdf: true, count: 1),
    ]);
    final onlyPdf = await store.repository.query(
      const MarkerQuery(bookTitle: 'בראשית', bookPdf: true),
      offset: 0,
      limit: 10,
    );
    expect(onlyPdf.map((m) => m.id), ['pdf']);
    final onlyText = await store.repository.query(
      const MarkerQuery(bookTitle: 'בראשית'),
      offset: 0,
      limit: 10,
    );
    expect(onlyText.map((m) => m.id), ['text']);
    store.db.close();
  });

  group('markerLineRects', () {
    // בקואורדינטות התצוגה: y גדל כלפי מטה.
    Rect word(double left, double right, {double top = 100}) =>
        Rect.fromLTRB(left, top, right, top + 10);

    test('words of one line become one rect, gaps included', () {
      final lines = markerLineRects([
        word(100, 130),
        word(135, 160),
        word(166, 200),
      ]);
      expect(lines, [const Rect.fromLTRB(100, 100, 200, 110)]);
    });

    test('each line stays a rect of its own', () {
      final lines = markerLineRects([word(100, 200), word(100, 180, top: 115)]);
      expect(lines, hasLength(2));
    });

    test('a second column at the same height is not joined', () {
      final lines = markerLineRects([word(50, 150), word(300, 400)]);
      expect(lines, hasLength(2));
    });

    test('a tall word between two lines does not pull them together', () {
      final lines = markerLineRects([
        word(100, 150),
        const Rect.fromLTRB(155, 100, 175, 125),
        word(100, 150, top: 115),
      ]);
      expect(lines, hasLength(3));
    });

    test('empty fragments are skipped', () {
      expect(markerLineRects([Rect.zero]), isEmpty);
    });
  });
}
