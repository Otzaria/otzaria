import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';

void main() {
  testWidgets('אינדקס הפסקה שומר את המופע הראשון ומתעדכן עם השורות', (
    tester,
  ) async {
    Future<void> pump(List<ReaderParagraphLineData> lines) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: ReaderParagraphLines(
          lines: lines,
          child: RichText(text: const TextSpan(text: 'א ב\nג')),
        ),
      ),
    );

    const first = ReaderParagraphLineData(
      lineIndex: 70,
      range: TextRange(start: 0, end: 1),
    );
    const following = ReaderParagraphLineData(
      lineIndex: 20,
      range: TextRange(start: 2, end: 3),
    );
    const duplicate = ReaderParagraphLineData(
      lineIndex: 70,
      range: TextRange(start: 4, end: 5),
    );
    final fillers = [
      for (var i = 0; i < 6; i++)
        ReaderParagraphLineData(
          lineIndex: 100 + i,
          range: const TextRange.collapsed(5),
        ),
    ];

    await pump([first, following, duplicate, ...fillers]);
    final paragraph = tester.renderObject<RenderReaderParagraphLines>(
      find.byType(ReaderParagraphLines),
    );
    expect(paragraph.rangeForLine(70), first.range);
    expect(paragraph.rangeForLine(999), isNull);
    expect(paragraph.flowExtent(999), isNull);
    final firstExtent = paragraph.lineExtent(70)!;
    expect(firstExtent.bottom, greaterThan(firstExtent.top));
    expect(
      paragraph.flowExtent(70),
      (top: firstExtent.top, bottom: firstExtent.top),
    );

    await pump([
      ReaderParagraphLineData(lineIndex: 40, range: first.range),
      ReaderParagraphLineData(lineIndex: 70, range: following.range),
      ReaderParagraphLineData(lineIndex: 80, range: duplicate.range),
      ...fillers,
    ]);
    expect(
      tester.renderObject<RenderReaderParagraphLines>(
        find.byType(ReaderParagraphLines),
      ),
      same(paragraph),
    );
    expect(paragraph.rangeForLine(20), isNull);
    expect(paragraph.rangeForLine(70), following.range);
    expect(paragraph.flowExtent(70), paragraph.lineExtent(70));
  });
}
