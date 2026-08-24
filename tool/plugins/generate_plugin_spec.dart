// ignore_for_file: avoid_print
//
// מייצר `docs/plugin-sdk/spec.json` מקבועי האפליקציה.
//
//   dart run tool/plugins/generate_plugin_spec.dart          # כותב
//   dart run tool/plugins/generate_plugin_spec.dart --check   # רק בודק
//
// `--check` יוצא בקוד 1 אם הקובץ שבדיסק מיושן — כך CI חוסם סחיפה.

import 'dart:io';

import 'plugin_spec_generator.dart';

void main(List<String> args) {
  final check = args.contains('--check');
  try {
    final result = generatePluginSpec(Directory.current, check: check);
    if (check && result.changed) {
      stderr.writeln(
        '${result.outputPath} מיושן. הרץ: '
        'dart run tool/plugins/generate_plugin_spec.dart',
      );
      exit(1);
    }
    stdout.writeln(
      result.changed
          ? 'נכתב ${result.outputPath}.'
          : '${result.outputPath} מעודכן.',
    );
  } on PluginSpecError catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}
