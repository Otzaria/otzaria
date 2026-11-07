import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final root = Directory(
    Platform.environment['PLUGIN_FONT_PROBE_REPORTS'] ??
        'build/macos_font_probe',
  );
  await root.create(recursive: true);
  final output = await root.createTemp('run-');
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final report = data?['fontProbe'];
      if (report is Map) {
        for (final entry in (report['cases'] as List? ?? const [])) {
          for (final view in (entry['views'] as List)) {
            final png = view.remove('screenshotBase64');
            if (png is String) {
              final name = '${entry['scenario']}-${view['index']}.png';
              await File(
                '${output.path}/$name',
              ).writeAsBytes(base64Decode(png));
              view['screenshot'] = name;
            }
          }
        }
      }
      await File('${output.path}/report.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      // ignore: avoid_print
      print('macOS font probe report: ${output.path}');
    },
  );
}
