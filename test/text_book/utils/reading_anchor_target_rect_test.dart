import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

const _line = 9004;

void main() {
  testWidgets('עוגן פנימי נמדד ומוצג במקומו כבר בציור הראשון', (tester) async {
    final harness = _Harness();
    var jumps = 0;
    harness.controller.addBeforeJumpListener(() => jumps++);
    await tester.pumpWidget(harness.view(initial: true));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(_line))).dy + 25,
      closeTo(210, 0.01),
    );
    expect(jumps, 0);
    expect(harness.built, lessThan(100));
    expect(harness.segments.debugBuiltCount, lessThan(10));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('קפיצה לשורה פנימית מסתיימת בפריסה אחת ושומרת בחירה ביעד גלוי', (
    tester,
  ) async {
    final harness = _Harness();
    var jumps = 0;
    harness.controller.addBeforeJumpListener(() => jumps++);
    await tester.pumpWidget(harness.view());
    await tester.pumpAndSettle();
    var completed = false;
    final navigation = scrollToSourceLine(
      scrollController: harness.controller,
      positionsListener: harness.positions,
      segments: harness.segments,
      lineIndex: _line,
      intraLineFraction: 0.25,
      alignment: 0.35,
      duration: Duration.zero,
      measure: harness.boxes.lineExtent,
    ).then((_) => completed = true);
    await tester.pump();
    expect(completed, isTrue);
    await navigation;
    expect(jumps, 1);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(_line))).dy + 25,
      closeTo(210, 0.01),
    );
    final sameTarget = scrollToSourceLine(
      scrollController: harness.controller,
      positionsListener: harness.positions,
      segments: harness.segments,
      lineIndex: _line,
      intraLineFraction: 0.25,
      alignment: 0.35,
      duration: Duration.zero,
      measure: harness.boxes.lineExtent,
    );
    await tester.pumpAndSettle();
    await sameTarget;
    expect(jumps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Harness {
  final controller = JumpAwareItemScrollController();
  final positions = ItemPositionsListener.create();
  final boxes = ReaderItemBoxes();
  final segments = ReadingSegments(
    layout: ReadingLayout.continuous(
      lineCount: 10000,
      breakLines: [for (var line = 0; line < 10000; line += 10) line],
    ),
    content: List<String>.filled(10000, 'שורת מקור'),
  );
  var built = 0;

  Widget view({bool initial = false}) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 600,
        child: ScrollablePositionedList.builder(
          itemScrollController: controller,
          itemPositionsListener: positions,
          initialScrollIndex: initial ? segments.layout.itemForLine(_line) : 0,
          initialAlignment: 0.35,
          initialTargetRectResolver: initial
              ? readingAnchorTargetRectResolver(
                  segments: () => segments,
                  lineIndex: _line,
                  intraLineFraction: 0.25,
                  measure: boxes.lineExtent,
                )
              : null,
          estimateExtent: (_, _) => 1,
          itemCount: segments.length,
          itemBuilder: (_, item) {
            built++;
            if (item != segments.layout.itemForLine(_line)) {
              return const SizedBox(height: 100);
            }
            return wrapReaderItem(
              item: item,
              layout: segments.layout,
              boxes: boxes,
              child: Column(
                children: [
                  for (
                    var line = segments.layout.firstLineOf(item);
                    line <= segments.layout.lastLineOf(item);
                    line++
                  )
                    ReaderLineBlock(
                      lineIndex: line,
                      child: SizedBox(
                        key: ValueKey(line),
                        height: line == 9003 ? 1400 : 100,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
