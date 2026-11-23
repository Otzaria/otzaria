import 'dart:convert';
import 'dart:io';

import 'probe_binding.dart';

/// Publish completion after the caller has closed any journal it opened.
Future<void> writePerfProbeCompletion({
  required Directory output,
  required int launchIndex,
  required PerfBindingMode bindingMode,
  required bool successful,
  required String? error,
  required String? fixtureId,
  required bool preparationOnly,
  List<String> testFailures = const [],
}) async {
  final pending = File('${output.path}/completion.pending');
  final completion = File('${output.path}/completion.json');
  final journal = File('${output.path}/phases.jsonl');
  final passed = successful && error == null && testFailures.isEmpty;
  if (await pending.exists() || await completion.exists()) {
    throw StateError('The output directory already contains a completion.');
  }
  if (passed && !await journal.exists()) {
    throw StateError('Successful completion requires a closed probe journal.');
  }
  if (passed && (fixtureId == null || fixtureId.isEmpty)) {
    throw StateError('A successful probe must identify its fixture.');
  }
  final status = passed ? 'passed' : 'failed';
  await journal.writeAsString(
    '${jsonEncode({
      'type': 'done',
      'launchIndex': launchIndex,
      'status': status,
      'endedAt': DateTime.now().millisecondsSinceEpoch,
    })}\n',
    mode: FileMode.append,
    flush: true,
  );
  await pending.writeAsString(
    jsonEncode({
      'status': status,
      'error': error,
      'fixtureId': fixtureId,
      'preparationOnly': preparationOnly,
      'testFailures': testFailures,
      ...bindingMode.toComparisonJson(),
    }),
    flush: true,
  );
  await pending.rename(completion.path);
}
