import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/utils/indexing_yield.dart';

void main() {
  testWidgets('pending frame paints before the next indexing batch', (
    tester,
  ) async {
    tester.binding.scheduleFrame();
    var continued = false;
    final yielding = yieldToIndexingForeground().then((_) => continued = true);
    await tester.idle();
    expect(continued, isFalse);
    await tester.pump();
    await yielding;
    expect(continued, isTrue);
  });

  testWidgets('a suspended frame source cannot stall indexing indefinitely', (
    tester,
  ) async {
    tester.binding.scheduleFrame();
    await tester.runAsync(() async {
      await yieldToIndexingForeground().timeout(const Duration(seconds: 1));
    });
    await tester.pump();
  });
}
