import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../tool/perf_probe/src/probe_binding.dart';

void verifyPerfProbeBinding(WidgetsBinding binding, PerfBindingMode mode) {
  final dispatcher = binding.platformDispatcher;
  final matches = switch (mode) {
    PerfBindingMode.integration =>
      binding.runtimeType == IntegrationTestWidgetsFlutterBinding &&
          binding is LiveTestWidgetsFlutterBinding &&
          binding.framePolicy ==
              LiveTestWidgetsFlutterBindingFramePolicy.fullyLive &&
          dispatcher is TestPlatformDispatcher,
    PerfBindingMode.framework =>
      binding.runtimeType == WidgetsFlutterBinding &&
          dispatcher is! TestPlatformDispatcher,
  };
  if (!identical(binding, WidgetsBinding.instance) || !matches) {
    throw StateError('Unexpected binding or dispatcher for ${mode.name}.');
  }
}

/// Check a real deferred framework request before measuring the PDF workload.
/// No scheduling overrides, synthetic clock or zero-frame assertion are used.
Future<Map<String, Object?>> verifyDeferredFrameworkFrame(
  WidgetsBinding binding, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  verifyPerfProbeBinding(binding, PerfBindingMode.framework);
  final clock = Stopwatch()..start();
  final completed = Completer<Duration>();
  int? requestedAtUs;
  final timer = Timer(const Duration(milliseconds: 25), () {
    requestedAtUs = clock.elapsedMicroseconds;
    binding.addPostFrameCallback(completed.complete);
    binding.scheduleFrame();
  });
  try {
    final timestamp = await completed.future.timeout(timeout);
    verifyPerfProbeBinding(binding, PerfBindingMode.framework);
    return {
      'status': 'passed',
      'source': 'Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback',
      'deferredFrameDelivered': true,
      'requestedAtUs': requestedAtUs,
      'completedAtUs': clock.elapsedMicroseconds,
      'frameTimestampUs': timestamp.inMicroseconds,
      'bindingClass': binding.runtimeType.toString(),
      'nativePlatformDispatcher':
          binding.platformDispatcher is! TestPlatformDispatcher,
    };
  } finally {
    timer.cancel();
    clock.stop();
  }
}
