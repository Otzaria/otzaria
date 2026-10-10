import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';

void main() {
  testWidgets('native jumps resume after detaching the external reader', (
    tester,
  ) async {
    final controller = JumpAwareItemScrollController();
    final positions = ItemPositionsListener.create();
    final external = <int>[];
    var jumps = 0;
    controller.addBeforeJumpListener(() => jumps++);
    controller.externalScroll = (index, {int? sourceLineIndex}) async {
      external.add(index);
    };
    expect(controller.isAttached, isTrue);
    controller.jumpTo(index: 23);
    await controller.scrollTo(
      index: 31,
      duration: const Duration(milliseconds: 100),
    );
    expect(external, [23, 31]);
    expect(jumps, 2);
    controller.externalScroll = null;
    expect(controller.isAttached, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollablePositionedList.builder(
          itemScrollController: controller,
          itemPositionsListener: positions,
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$i')),
        ),
      ),
    );
    controller.jumpTo(index: 12);
    await tester.pump();
    expect(positions.itemPositions.value.any((p) => p.index == 12), isTrue);
    expect(external, [23, 31]);
    expect(jumps, 3);
  });
}
