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
    await tester.pump(const Duration(milliseconds: 350));
  }

  final loading = find.descendant(
    of: dialog,
    matching: find.byType(CircularProgressIndicator),
  );
  for (
    var attempt = 0;
    attempt < 200 && loading.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(loading, findsNothing);
  expect(SqliteDataProvider.instance.debugIsInitializing, isFalse);

  if (originalIndex != 1) {
    await tester.tap(tabs.at(originalIndex));
    await tester.pump(const Duration(milliseconds: 350));
  }
  expect(tabBar.controller!.index, originalIndex);
  // Metadata is complete, so settling no longer competes with native I/O.
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
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
