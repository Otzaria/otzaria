import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final root = Directory(
    Platform.environment['INSTALLED_PROBE_REPORTS'] ??
        'build/installed_plugin_probe',
  );
  await root.create(recursive: true);
  final output = await root.createTemp('run-');
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      await File(p.join(output.path, 'report.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      // ignore: avoid_print
      print('Installed plugin probe report: ${output.absolute.path}');
    },
  );
}
