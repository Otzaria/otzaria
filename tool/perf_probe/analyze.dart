import 'dart:convert';
import 'dart:io';

import 'src/report.dart';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart tool/perf_probe/analyze.dart <run-dir> '
      '[--baseline <run-dir-or-report.json>]',
    );
    exitCode = args.isEmpty ? 64 : 0;
    return;
  }
  if (args.length != 1 && (args.length != 3 || args[1] != '--baseline')) {
    stderr.writeln('ארגומנטים לא מוכרים. להוראות: --help');
    exitCode = 64;
    return;
  }
  try {
    final root = Directory(args.first);
    final phases = File('${root.path}/phases.jsonl');
    final manifest = File('${root.path}/manifest.json');
    final samples = File('${root.path}/samples.csv');
    final sampleErrors = File('${root.path}/samples.csv.errors.jsonl');
    final manifestData = manifest.existsSync()
        ? jsonDecode(manifest.readAsStringSync())
        : <String, dynamic>{};
    if (manifestData is! Map<String, dynamic>) {
      throw const FormatException('manifest.json חייב להיות אובייקט');
    }
    if (sampleErrors.existsSync()) {
      final errors = sampleErrors
          .readAsLinesSync()
          .where((line) => line.trim().isNotEmpty)
          .map(jsonDecode)
          .toList();
      manifestData['samplerErrorCount'] = errors.length;
    }
    final report = buildProbeReport(
      records: parseProbeRecords(phases.readAsStringSync()),
      metadata: manifestData,
      samples: samples.existsSync()
          ? parseProcessSamples(samples.readAsStringSync())
          : const [],
    );
    if (args.length == 3) {
      final baselinePath = Directory(args[2]).existsSync()
          ? '${args[2]}/report.json'
          : args[2];
      final baseline = jsonDecode(File(baselinePath).readAsStringSync());
      report['comparison'] = compareProbeReports(
        baseline is Map<String, dynamic>
            ? baseline
            : {'sourceSchemaVersion': 1},
        report,
      );
    }
    final markdown = renderProbeMarkdown(report);
    File('${root.path}/report.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    File('${root.path}/report.md').writeAsStringSync(markdown);
    stdout.write(markdown);
    stdout.writeln('\nהדוחות נשמרו ב-${root.path}/report.{json,md}');
  } on FileSystemException catch (error) {
    stderr.writeln('קריאה או כתיבה של דוח המדידה נכשלה: $error');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('קלט מדידה לא תקין: $error');
    exitCode = 65;
  }
}
