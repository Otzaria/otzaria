import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final output = Platform.environment['APPLE_QUIET_OUTPUT'];
  if (output == null) throw StateError('Use the Apple quiet runner.');
  await integrationDriver(
    timeout: const Duration(minutes: 25),
    writeResponseOnFailure: true,
    responseDataCallback: (data) =>
        File(p.join(output, 'app-report.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
          flush: true,
        ),
  );
}
