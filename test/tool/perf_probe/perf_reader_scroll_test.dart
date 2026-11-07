import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../integration_test/support/perf_reader_scroll.dart';

void main() {
  testWidgets('scrolls the attached reader while a long side list is visible', (
    tester,
  ) async {
    final reader = ItemScrollController();
    final side = ScrollController();
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              Expanded(child: _sideList(side)),
              Expanded(
                child: ScrollablePositionedList.builder(
                  itemScrollController: reader,
                  itemCount: 100,
                  itemBuilder: (_, index) => SizedBox(
                    height: 80,
                    child: Text('ספר $index'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .where(
              (state) =>
                  state.position.axis == Axis.vertical &&
                  state.position.maxScrollExtent > 500,
            ),
        hasLength(2),
      );

      final position = perfReaderScrollPosition(reader.scrollController);
      final readerOffset = position.pixels;
      final readerTop = tester.getTopLeft(find.text('ספר 0')).dy;
      final sideOffset = side.offset;
      position.jumpTo(readerOffset + 30);
      await tester.pump();

      expect(position.pixels, closeTo(readerOffset + 30, 0.001));
      expect(
        tester.getTopLeft(find.text('ספר 0')).dy,
        closeTo(readerTop - 30, 0.001),
      );
      expect(side.offset, sideOffset);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      side.dispose();
    }
    expect(
      () => perfReaderScrollPosition(reader.scrollController),
      throwsStateError,
    );
  });

  testWidgets('rejects a controller with multiple attached positions', (
    tester,
  ) async {
    final controller = ScrollController();
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              Expanded(child: _sideList(controller)),
              Expanded(child: _sideList(controller)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.positions, hasLength(2));
      expect(() => perfReaderScrollPosition(controller), throwsStateError);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('rejects a horizontal reader position', (tester) async {
    final reader = ItemScrollController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: ScrollablePositionedList.builder(
          itemScrollController: reader,
          scrollDirection: Axis.horizontal,
          itemCount: 100,
          itemBuilder: (_, index) => SizedBox(width: 80, child: Text('$index')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      () => perfReaderScrollPosition(reader.scrollController),
      throwsStateError,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _sideList(ScrollController controller) => ListView.builder(
  controller: controller,
  itemExtent: 80,
  itemCount: 100,
  itemBuilder: (_, index) => Text('צד $index'),
);
