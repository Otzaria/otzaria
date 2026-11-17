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

  test('טווח עמוק מדלג על בלוקים גם כשעוגן ראשון חופף לו', () {
    final links = _CountingLinks([
      _link(1, 20000),
      for (var line = 2; line <= 20000; line++) _link(line),
    ]);
    final index = PdfLinkRangeIndex(links);
    index.overlapping(500, 550);

    links.reads = 0;
    final expected = _scan(links, 19992, 19995).toList();
    final scanReads = links.reads;
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
