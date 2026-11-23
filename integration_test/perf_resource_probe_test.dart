// Opt-in real-app benchmark. See tool/perf_probe/README.md.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../tool/perf_probe/src/probe_binding.dart';
import 'support/perf_resource_workload.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final probe = createPerfResourceProbeSession(
    binding,
    bindingMode: PerfBindingMode.integration,
  );
  unawaited(
    binding.allTestsPassed.future.then(
      (passed) => probe.complete(
        passed: passed,
        testFailures: [
          for (final failure in binding.failureMethodsDetails)
            failure.details ?? failure.toString(),
        ],
      ),
    ),
  );
  testWidgets(
    'reproducible resource probe',
    probe.run,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
