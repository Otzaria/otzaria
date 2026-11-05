import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// Report entry points may read native SQLite/files before pushing a route.
/// Yield I/O and frames until the actual dialog appears, rather than assuming
/// that one fixed delay is long enough on a busy runner.
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
  // A post-frame metadata load can already be showing a progress animation.
  // Advance the route transition without waiting on that animation in FakeAsync.
  await tester.pump(const Duration(milliseconds: 350));
}

/// Finish the phone metadata I/O before a widget test closes its fake-clock zone.
/// Use the real tab and restore the selected tab, without resetting SQLite or
/// replacing the production data lookup with a fixture.
Future<void> waitForBookReportMetadata(
  WidgetTester tester, {
  required Finder dialog,
}) async {
  final tabBar = tester.widget<TabBar>(
    find.descendant(of: dialog, matching: find.byType(TabBar)),
  );
  final originalIndex = tabBar.controller!.index;
  final tabs = find.descendant(of: dialog, matching: find.byType(Tab));
  expect(tabs, findsNWidgets(2));
  if (originalIndex != 1) {
    await tester.tap(tabs.at(1));
    // Start the ticker before advancing its clock. The phone page must actually
    // appear before the absence of its progress indicator proves completion.
    await tester.pump();
  }

  final loading = find.descendant(
    of: dialog,
    matching: find.byType(CircularProgressIndicator),
  );
  var metadataFinished = false;
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (!tabBar.controller!.indexIsChanging &&
        loading.evaluate().isEmpty &&
        !SqliteDataProvider.instance.debugIsInitializing) {
      metadataFinished = true;
      break;
    }
  }
  expect(
    metadataFinished,
    isTrue,
    reason:
        'The phone tab transition and its native metadata read must finish.',
  );
  expect(tabBar.controller!.index, 1);
  expect(tabBar.controller!.animation!.value, closeTo(1, 0.001));
  expect(loading, findsNothing);
  expect(SqliteDataProvider.instance.debugIsInitializing, isFalse);

  if (originalIndex != 1) {
    await tester.tap(tabs.at(originalIndex));
    await tester.pump();
  }
  // Restoring the tab can resume widgets waiting on native I/O. Keep yielding
  // that I/O while enforcing the same five-second settling bound.
  var settled = false;
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame &&
        !tabBar.controller!.indexIsChanging &&
        loading.evaluate().isEmpty &&
        !SqliteDataProvider.instance.debugIsInitializing) {
      settled = true;
      break;
    }
  }
  expect(
    settled,
    isTrue,
    reason: 'The restored report tab must settle in five seconds.',
  );
  expect(tabBar.controller!.index, originalIndex);
  expect(tabBar.controller!.animation!.value, closeTo(originalIndex, 0.001));
  expect(loading, findsNothing);
  expect(SqliteDataProvider.instance.debugIsInitializing, isFalse);
}

/// A UI callback can queue a database future in FakeAsync. Awaiting that future
/// inside runAsync stops the fake clock it needs to finish. Observe completion
/// with a real-zone listener while advancing both frames and native I/O.
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
