import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/view/printing_screen.dart';

/// Wait for native printing cleanup before this widget test's FakeAsync ends.
///
/// Unmount or close the screen first so that it cannot queue more preview work.
/// Native responses need real time, while their Dart continuations may still
/// belong to FakeAsync and therefore need a pump. A completed unrelated future
/// cannot establish that the PDF document was actually disposed.
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
    await tester.pump();
  }
  expect(done, isTrue, reason: 'Native printing cleanup did not finish.');
}
