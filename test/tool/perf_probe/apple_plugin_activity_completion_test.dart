import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';

import '../../../integration_test/support/installed_plugin_completion.dart';
import '../../../tool/perf_probe/apple_plugin_activity/contract.dart';

void main() {
  late Future<Map<String, dynamic>> driverResponse;
  late Directory directory;
  final scenarioFinished = Completer<void>();
  var driverReturned = false;
  var flushed = false;
  final report = <String, dynamic>{
    // The scenario has reported success, but framework completion is pending.
    'status': 'passed',
    'errors': <String>[],
    'platformMatrix': createAppleActivityPlatformMatrix(),
  };
  tearDownAll(() async {
    try {
      final result = await driverResponse.timeout(const Duration(seconds: 5));
      final response = Response.fromJson(
        result['response']['message'] as String,
      );
      expect(response.allTestsPassed, isTrue);
      expect(flushed, isTrue);
      final saved = jsonDecode(
        await File('${directory.path}/apple-report.json').readAsString(),
      );
      expect(response.data!['applePluginActivity'], saved);
      expect(saved['status'], 'passed');
      expect(saved['testFailures'], isEmpty);
      expect(saved['platformMatrix']['ios'], {
        'status': 'passed',
        'buildMode': 'debug',
        'physicalDeviceAcceptance': false,
      });
    } finally {
      await directory.delete(recursive: true);
    }
  });
  final binding = IntegrationTestWidgetsFlutterBinding();
  binding.reportData = {'applePluginActivity': report};
  registerInstalledPluginReportFinalizer(binding, (passed) async {
    await scenarioFinished.future;
    finalizeAppleActivityReport(
      report,
      frameworkPassed: passed,
      failureDetails: binding.failureMethodsDetails.map(
        (value) => value.details,
      ),
      platform: 'ios',
      buildMode: 'debug',
    );
    expect(driverReturned, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(driverReturned, isFalse);
    await File('${directory.path}/apple-report.json').writeAsString(
      jsonEncode(report),
      flush: true,
    );
    flushed = true;
  });

  test(
    'Apple driver completion includes the final flushed framework report',
    () async {
      directory = await Directory.systemTemp.createTemp('apple-completion-');
      driverResponse = binding.callback({'command': 'request_data'}).then((
        value,
      ) {
        driverReturned = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(driverReturned, isFalse);
      scenarioFinished.complete();
    },
  );

  test('a late framework failure replaces preliminary Apple success', () async {
    final original = Failure('framework', 'late framework failure');
    final failed = <String, dynamic>{
      'status': 'passed',
      'errors': <String>[],
      'platformMatrix': createAppleActivityPlatformMatrix(),
    };
    binding.results['framework'] = original;
    try {
      await finalizeInstalledPluginReport(binding, (passed) async {
        finalizeAppleActivityReport(
          failed,
          frameworkPassed: passed,
          failureDetails: binding.failureMethodsDetails.map(
            (value) => value.details,
          ),
          platform: 'ios',
          buildMode: 'debug',
        );
      });
      expect(failed['status'], 'failed');
      expect(failed['testFailures'], ['late framework failure']);
      expect(failed['platformMatrix']['ios']['status'], 'failed');
      expect(binding.failureMethodsDetails, [same(original)]);
    } finally {
      binding.results.clear();
    }
  });

  test(
    'an Apple report write failure preserves the earlier framework failure',
    () async {
      final original = Failure('framework', 'original framework failure');
      final writeFailure = FileSystemException(
        'Apple final report flush failed',
      );
      binding.results['framework'] = original;
      try {
        await expectLater(
          finalizeInstalledPluginReport(binding, (passed) async {
            expect(passed, isFalse);
            throw writeFailure;
          }),
          throwsA(same(writeFailure)),
        );
        expect(binding.failureMethodsDetails.first, same(original));
        expect(
          binding.failureMethodsDetails.last.details,
          contains('Apple final report flush failed'),
        );
      } finally {
        binding.results.clear();
      }
    },
  );
}
