import 'dart:async';

import 'macos_font_probe.dart';

Future<void> runIosFontProbeCase({
  required Map<String, Object?> entry,
  required Map<String, Object?> report,
  required List<FontProbeViewProgress> progress,
  required Future<void> Function() run,
  required void Function() unmount,
  Duration cleanupTimeout = const Duration(seconds: 10),
}) async {
  Object? firstError;
  StackTrace? firstStack;
  try {
    await run();
    entry['status'] = 'completed';
  } catch (error, stack) {
    entry['status'] = 'failed';
    entry['error'] = error.toString();
    report['status'] = 'failed';
    for (final item in progress) {
      if (item.isActive && item.report['status'] != 'completed') {
        item.fail(error, stack);
      }
    }
    firstError = error;
    firstStack = stack;
    await Future.wait(progress.map((p) => p.captureFailureSnapshot()));
  } finally {
    try {
      unmount();
      await Future.wait(
        progress
            .where(
              (p) => (p.report['events'] as List).any(
                (e) => e['event'] == 'widget-mounted',
              ),
            )
            .map((p) => p.whenDisposed),
      ).timeout(cleanupTimeout);
      entry['cleanupStatus'] = 'completed';
      if (firstError == null &&
          progress.any((p) => p.report['status'] != 'completed')) {
        throw StateError('Font probe received a late or incomplete result');
      }
    } catch (error, stack) {
      entry['cleanupStatus'] = 'failed';
      entry['cleanupError'] = error.toString();
      entry['status'] = 'failed';
      report['status'] = 'failed';
      firstError ??= error;
      firstStack ??= stack;
    }
  }
  if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
}
