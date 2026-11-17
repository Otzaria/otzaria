import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/utils/pdf_link_range_index.dart';

Link _link(int first, [int? last]) => Link(
  heRef: '',
  index1: first,
  index1End: last,
  path2: 'target.txt',
  index2: 1,
  connectionType: 'REFERENCE',
);

Iterable<Link> _scan(List<Link> links, int first, int last) sync* {
  for (final link in links) {
    if (link.index1 > last) break;
    if (link.overlapsSourceLines(first, last)) yield link;
  }
}

class _CountingLinks extends ListBase<Link> {
  _CountingLinks(this._links);

  final List<Link> _links;
  int reads = 0;

  @override
  int get length => _links.length;

  @override
  set length(int value) => throw UnsupportedError('Fixed snapshot');

  @override
  Link operator [](int index) {
    reads++;
    return _links[index];
  }

  @override
  void operator []=(int index, Link value) =>
      throw UnsupportedError('Fixed snapshot');
}

void main() {
  test('שומר סדר, כפילויות וקצוות כלולים גם בטווח רב-שורות', () {
    final links = [
      _link(1, 100),
      for (var line = 2; line < 80; line++) _link(line),
      _link(80, 81),
      _link(80),
      _link(81),
      _link(82),
    ];
    final index = PdfLinkRangeIndex(links);
    for (final (first, last) in [
      (0, 0),
      (2, 4),
      (80, 81),
      (100, 100),
      (101, 110),
    ]) {
      expect(
        index.overlapping(first, last),
        orderedEquals(_scan(links, first, last)),
      );
    }
  });

  test('חיפוש ראשון סורק רק את הקידומת הנדרשת גם בחלון חדש', () {
    for (final firstLine in [1, 5000]) {
      final links = _CountingLinks([
        for (var i = 0; i < 20000; i++) _link(firstLine + i),
      ]);
      final first = firstLine + 29;
      final last = firstLine + 32;
      final expected = _scan(links, first, last).toList();
      final scanReads = links.reads;
      links.reads = 0;

      final result = PdfLinkRangeIndex(links).overlapping(first, last);

      expect(result, orderedEquals(expected));
      expect(links.reads, scanReads);
    }
  });

  test('הרחבת הקידומת שומרת עוגנים חדשים בלי כפילויות', () {
    final links = [
      for (var i = 1; i <= 100; i++)
        if (i == 36 || i == 38) _link(i, 75) else _link(i),
    ];
    final index = PdfLinkRangeIndex(links);
    for (final (first, last) in [(30, 34), (36, 41), (37, 40), (70, 76)]) {
      expect(
        index.overlapping(first, last),
        orderedEquals(_scan(links, first, last)),
      );
    }
  });

  test('ריבוי עוגנים שומר את התוצאות גם במעבר לסריקה ישירה', () {
    final links = _CountingLinks([
      for (var i = 1; i <= 300; i++) _link(i, i + 50),
    ]);
    final index = PdfLinkRangeIndex(links);
    for (final (first, last) in [(15, 32), (70, 125)]) {
      expect(
        index.overlapping(first, last),
        orderedEquals(_scan(links, first, last)),
      );
    }

    links.reads = 0;
    final expected = _scan(links, 140, 160).toList();
    final scanReads = links.reads;
    links.reads = 0;
    expect(index.overlapping(140, 160), orderedEquals(expected));
    expect(links.reads, scanReads);
  });

  test('טווח עמוק מדלג על קידומת שכבר נסרקה ושומר עוגן חופף', () {
    final links = _CountingLinks([
      _link(1, 20000),
      for (var line = 2; line <= 20000; line++) _link(line),
    ]);
    final index = PdfLinkRangeIndex(links);

    final expected = _scan(links, 19992, 19995).toList();
    final scanReads = links.reads;
    links.reads = 0;
    index.overlapping(19992, 19996);
    expect(links.reads, scanReads + 1);

    links.reads = 0;
    final result = index.overlapping(19992, 19995);
    expect(result, orderedEquals(expected));
    expect(scanReads, 19996);
    expect(links.reads, lessThan(100));

    links.reads = 0;
    expect(index.overlapping(19992, 19995), same(result));
    expect(links.reads, 0);
  });
}
