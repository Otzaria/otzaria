import 'package:flutter_test/flutter_test.dart';

/// A report may finish native SQLite work after the first frame following a
/// close action. Keep yielding real I/O and pumping frames until its route is
/// gone; awaiting the route inside runAsync first would prevent that frame.
Future<void> finishReportDialog(
  WidgetTester tester, {
  required Finder dialog,
  required Future<dynamic> reporting,
}) async {
  for (
    var attempt = 0;
    attempt < 200 && dialog.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    dialog,
    findsNothing,
    reason: 'The close action must complete and remove the report dialog.',
  );
  await tester.runAsync(
    () async => reporting.timeout(const Duration(seconds: 5)),
  );
}
