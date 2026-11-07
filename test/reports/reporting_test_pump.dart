import 'package:flutter_test/flutter_test.dart';

/// ממתין ל-I/O של פתיחת הדיווח ולהופעת הדיאלוג בפועל.
Future<void> waitForReportDialog(
  WidgetTester tester, {
  required Finder dialog,
}) async {
  for (var attempt = 0; attempt < 200 && dialog.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    dialog,
    findsOneWidget,
    reason: 'The report entry must finish I/O and display one dialog.',
  );
  // משלימים את אנימציית פתיחת הדיאלוג.
  await tester.pump(const Duration(milliseconds: 350));
}

/// ממתין לכתיבת המסד תוך קידום השעון המדומה וה-I/O האמיתי.
Future<T> reportIo<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  var completed = false;
  late T value;
  Object? failure;
  StackTrace? failureStack;
  await tester.runAsync(() async {
    Future<T>.sync(operation).then<void>(
      (result) {
        value = result;
        completed = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        completed = true;
      },
    );
  });
  for (var attempt = 0; attempt < 200 && !completed; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(completed, isTrue, reason: 'The real report operation must finish.');
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return value;
}

/// סוגר את הדיווח לאחר השלמת ה-I/O והפריים שמסיר את הדיאלוג.
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
