import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/main.dart' as app;

/// מפעיל את bootstrap האמיתי על נתוני התרחיש וממתין לחשיפת התוכן.
Future<BuildContext> startInstalledProbeApp(
  WidgetTester tester, {
  VoidCallback? onPoll,
}) async {
  app.main(const []);
  const timeout = Duration(minutes: 3);
  final elapsed = Stopwatch()..start();
  while (true) {
    onPoll?.call();
    if (find.byType(App).evaluate().isNotEmpty &&
        StartupTimeline.instance.toJson()['revealMs'] != null) {
      return tester.element(find.byType(App));
    }
    if (elapsed.elapsed >= timeout) {
      throw TimeoutException('actual app first content', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
