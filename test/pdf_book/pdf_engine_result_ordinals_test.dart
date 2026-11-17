import 'package:otzaria/pdf_book/utils/pdf_engine_result_ordinals.dart';
import 'package:test/test.dart';

void main() {
  test('מחשבים את הקידומת של עמוד אחד פעם אחת גם בבחירות בסדר משתנה', () {
    final before = List.generate(800, (_) => _Result(1, 'ממון'));
    final page = List.generate(100, (i) => _Result(2, i.isEven ? 'ממון' : 'לו'));
    final after = List.generate(50, (_) => _Result(3, 'לו'));
    final results = [...before, ...page, ...after];
    var pageReads = 0;
    var spanReads = 0;
    final index = PdfEngineResultOrdinals(
      results,
      pageOf: (result) {
        pageReads++;
        return result.page;
      },
      spanOf: (result) {
        spanReads++;
        return result.span;
      },
    );

    expect(index.positionOf(page[2], 2), (offset: 2, span: 'ממון', spanOffset: 1));
    expect(index.positionOf(page[99], 2), (
      offset: 99,
      span: 'לו',
      spanOffset: 49,
    ));
    for (var i = 98; i >= 0; i--) {
      expect(index.positionOf(page[i], 2), (
        offset: i,
        span: page[i].span,
        spanOffset: i ~/ 2,
      ));
    }
    expect(spanReads, 100);
    expect(pageReads, lessThan(30));
  });

  test('זהות, כפילויות ותוצאה חסרה משמרות את סדר הרשימה', () {
    final first = _Result(4, 'ממון');
    final second = _Result(4, 'ממון');
    final noSpan = _Result(4, null);
    final index = PdfEngineResultOrdinals(
      [first, first, noSpan, second],
      pageOf: (result) => result.page,
      spanOf: (result) => result.span,
    );

    expect(index.positionOf(noSpan, 4), (offset: 2, span: null, spanOffset: 0));
    expect(index.positionOf(second, 4), (offset: 3, span: 'ממון', spanOffset: 2));
    expect(index.positionOf(first, 4), (offset: 0, span: 'ממון', spanOffset: 0));
    expect(index.positionOf(_Result(4, 'ממון'), 4), (
      offset: 4,
      span: 'ממון',
      spanOffset: 3,
    ));
    expect(index.positionOf(_Result(2, 'לו'), 2), (
      offset: 0,
      span: 'לו',
      spanOffset: 0,
    ));
  });
}

class _Result {
  _Result(this.page, this.span);

  final int page;
  final String? span;

  @override
  bool operator ==(Object other) =>
      other is _Result && page == other.page && span == other.span;

  @override
  int get hashCode => Object.hash(page, span);
}
