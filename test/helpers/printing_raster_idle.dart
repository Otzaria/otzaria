import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/view/printing_screen.dart';

/// אחרי unmount, ממתין לסיום העבודה הנייטיבית לפני סגירת ה־FakeAsync.
/// תשובות native דורשות זמן אמיתי; pump באורך אפס מפעיל את המשכיהן והטיימרים.
Future<void> drainPrintingRasterQueue(WidgetTester tester) async {
  var done = false;
  unawaited(
    PrintingScreen.debugRasterIdle.then((_) {
      done = true;
    }),
  );
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(Duration.zero);
  }
  expect(done, isTrue, reason: 'Native printing cleanup did not finish.');
}
