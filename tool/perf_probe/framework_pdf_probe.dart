// Opt-in real application target with Flutter's ordinary frame scheduling.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/perf_resource_workload.dart';
import 'src/probe_binding.dart';

void main() {
  unawaited(
    runZonedGuarded<Future<void>>(
      () async {
        final binding = WidgetsFlutterBinding.ensureInitialized();
        final probe = createPerfResourceProbeSession(
          binding,
          bindingMode: PerfBindingMode.framework,
        );
        var passed = false;
        try {
          await probe.run(LiveWidgetController(binding));
          passed = true;
        } catch (error, stack) {
          stderr.writeln('$error\n$stack');
          exitCode = 1;
        } finally {
          await probe.complete(passed: passed);
        }
      },
      (error, stack) {
        // This isolated benchmark process must not outlive an uncaught error
        // and publish a misleading successful host handshake.
        stderr.writeln('Unhandled framework probe error: $error\n$stack');
        exit(1);
      },
    ),
  );
}
