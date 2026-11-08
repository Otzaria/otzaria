import 'dart:convert';
import 'dart:io';

import 'package:integration_test/common.dart';

/// Keep the framework verdict and the unmodified response before extracting PNGs.
Future<void> writeIosFontProbeReport(
  Directory output,
  Response response,
) async {
  await output.create(recursive: true);
  await File('${output.path}/framework-response.json').writeAsString(
    response.toJson(),
    flush: true,
  );
  final data = jsonDecode(jsonEncode(response.data));
  final envelope = {
    'schemaVersion': 1,
    'framework': {
      'allTestsPassed': response.allTestsPassed,
      'failures':
          response.failureDetails?.map((f) => f.toJson()).toList() ?? [],
    },
    'data': data,
  };
  final encoder = const JsonEncoder.withIndent('  ');
  await File('${output.path}/report.partial.json').writeAsString(
    encoder.convert(envelope),
    flush: true,
  );
  final probe = data is Map ? data['iosFontProbe'] : null;
  final screenshots = <String>{};
  if (probe is Map && probe['cases'] is List) {
    for (final entry in probe['cases'] as List) {
      if (entry is! Map || entry['views'] is! List) continue;
      for (final view in entry['views'] as List) {
        if (view is! Map || view['screenshotBase64'] is! String) continue;
        final name = '${entry['id']}-${view['index']}.png';
        if (!RegExp(r'^[a-z0-9-]+\.png$').hasMatch(name) ||
            !screenshots.add(name)) {
          throw FormatException('Unsafe probe screenshot name: $name');
        }
        await File('${output.path}/$name').writeAsBytes(
          base64Decode(view['screenshotBase64'] as String),
          flush: true,
        );
        view.remove('screenshotBase64');
        view['screenshot'] = name;
      }
    }
  }
  await File('${output.path}/report.json').writeAsString(
    encoder.convert(envelope),
    flush: true,
  );
}
