import 'dart:async';

import 'package:flutter/scheduler.dart';

/// ממתין לפריים שכבר התבקש לפני תחילת אצוות רקע נוספת.
Future<void> yieldToIndexingForeground() async {
  final scheduler = SchedulerBinding.instance;
  if (scheduler.hasScheduledFrame && scheduler.framesEnabled) {
    await scheduler.endOfFrame.timeout(
      const Duration(milliseconds: 50),
      onTimeout: () {},
    );
  } else {
    await Future<void>.delayed(Duration.zero);
  }
}
