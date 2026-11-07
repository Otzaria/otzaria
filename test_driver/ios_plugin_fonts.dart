import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

import '../integration_test/support/ios_font_probe_report.dart';

Future<void> main() async {
  final root = Directory(
    Platform.environment['IOS_FONT_PROBE_REPORTS'] ?? 'build/ios_font_probe',
  );
  await root.create(recursive: true);
  final output = await root.createTemp('run-');
  FlutterDriver? driver;
  try {
    driver = await FlutterDriver.connect();
    final raw = await driver.requestData(
      null,
      timeout: const Duration(minutes: 20),
    );
    // Preserve malformed/partial framework messages too, before deserialization.
    await File(
      '${output.path}/driver-response.txt',
    ).writeAsString(raw, flush: true);
    final response = Response.fromJson(raw);
    await writeIosFontProbeReport(output, response);
    if (!response.allTestsPassed) exitCode = 1;
  } catch (error, stack) {
    exitCode = 1;
    await File('${output.path}/driver-error.txt').writeAsString(
      '$error\n$stack',
      flush: true,
    );
    stderr.writeln(error);
  } finally {
    try {
      await driver?.close().timeout(const Duration(seconds: 10));
    } catch (error, stack) {
      exitCode = 1;
      await File('${output.path}/driver-close-error.txt').writeAsString(
        '$error\n$stack',
        flush: true,
      );
    }
    // ignore: avoid_print
    print('iOS font compatibility artifacts: ${output.path}');
  }
}
