import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../tool/perf_probe/src/installed_pdf_runtime_contract.dart';
import 'support/installed_plugin_completion.dart';
import 'support/installed_plugin_pdf_runtime.dart';
import 'support/installed_plugin_app.dart';
import 'support/perf_fixture.dart';
import 'support/perf_recorder.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'scenario': 'installed-pdf-ios-simulator-v1',
    'status': 'running',
    'platform': Platform.operatingSystem,
    'buildMode': perfBuildMode,
    'pid': pid,
    'runId': '$pid-${DateTime.now().toUtc().microsecondsSinceEpoch}',
    'campaign': const String.fromEnvironment('INSTALLED_PDF_IOS_CAMPAIGN'),
    'commit': const String.fromEnvironment('INSTALLED_PROBE_COMMIT'),
    'flutterVersion': const String.fromEnvironment(
      'INSTALLED_PROBE_FLUTTER_VERSION',
    ),
    'osVersion': Platform.operatingSystemVersion,
    'physicalDeviceAcceptance': false,
    'physicalPrinter': 'notRun',
    'webViewScenario': {
      'status': 'notRun',
      'reason':
          'Independent PDF scenario; the manual WKWebView scroll-restoration test is unchanged.',
    },
    'bootstrap': <String, Object?>{'status': 'notRun'},
    'pdfRuntime': <String, Object?>{'status': 'notRun'},
    'errors': <String>[],
    'appUnmounted': false,
  };
  binding.reportData = {'installedPdfIosProbe': report};
  final finished = Completer<void>();
  File? reportFile;
  Future<void> checkpoint() async {
    await reportFile?.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
  }

  registerInstalledPluginReportFinalizer(binding, (passed) async {
    await finished.future.timeout(const Duration(seconds: 30));
    report['frameworkPassed'] = passed;
    report['testFailures'] = [
      for (final failure in binding.failureMethodsDetails) failure.details,
    ];
    final errors = <String>[
      ...installedPdfRuntimeErrors(report['pdfRuntime'], platform: 'ios'),
      if ((report['bootstrap'] as Map)['status'] != 'passed')
        'App bootstrap did not finish',
      if (report['appUnmounted'] != true) 'App did not unmount',
      if (!passed) 'Integration framework did not pass',
    ];
    report['contractErrors'] = errors;
    report['status'] = errors.isEmpty && (report['errors'] as List).isEmpty
        ? 'passed'
        : 'failed';
    await checkpoint();
    if (report['status'] != 'passed') {
      throw StateError('iOS PDF scenario did not complete: $errors');
    }
  });

  testWidgets('installed iOS Simulator PDF runtime', (
    tester,
  ) async {
    final previousFlutterError = FlutterError.onError;
    final previousPlatformError = PlatformDispatcher.instance.onError;
    final errors = report['errors'] as List<String>;
    var appStarted = false;
    void captureErrors() {
      FlutterError.onError = (details) {
        errors.add(details.exceptionAsString());
        previousFlutterError?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        errors.add(error.toString());
        previousFlutterError?.call(
          FlutterErrorDetails(exception: error, stack: stack),
        );
        return true;
      };
    }

    try {
      expect(Platform.isIOS && perfBuildMode == 'debug', true);
      expect(report['campaign'], isNotEmpty);
      expect(DeveloperDiagnostics.instance.isCollecting, false);
      final temporary = Directory(
        await Directory.systemTemp.resolveSymbolicLinks(),
      );
      final root = await temporary.createTemp('otzaria-pdf-ios-');
      final output = await Directory(p.join(root.path, 'output')).create();
      final fixture = PerfFixture(Directory(p.join(root.path, 'fixture')));
      report['isolatedPaths'] = {
        'root': root.path,
        'fixture': fixture.root.path,
        'output': output.path,
      };
      reportFile = File(p.join(output.path, 'installed-pdf-ios-report.json'));
      await checkpoint();
      await fixture.prepare(preparationOnly: true);
      final errorLog = ErrorLogFile.resolveFile();
      final errorsBefore = await errorLog.exists()
          ? await errorLog.readAsString()
          : '';
      captureErrors();
      appStarted = true;
      final context = await startInstalledProbeApp(
        tester,
        onPoll: captureErrors,
      );
      report['bundleIdentifier'] =
          (await PackageInfo.fromPlatform()).packageName;
      report['bootstrap'] = {
        'status': 'passed',
        'fixtureSha256': fixture.id,
        'startupTimeline': StartupTimeline.instance.toJson(),
      };
      await checkpoint();
      await runInstalledPdfRuntime(
        tester: tester,
        context: context,
        output: output,
        report: report['pdfRuntime'] as Map<String, Object?>,
        checkpoint: checkpoint,
      );
      final errorsAfter = await errorLog.exists()
          ? await errorLog.readAsString()
          : '';
      expect(
        errorsAfter,
        errorsBefore,
        reason: 'The app logged a native/runtime error',
      );
      expect(errors, isEmpty);
    } catch (error, stack) {
      errors.add('$error\n$stack');
      rethrow;
    } finally {
      try {
        if (appStarted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await tester.pump();
          report['appUnmounted'] = find.byType(App).evaluate().isEmpty;
        }
      } finally {
        FlutterError.onError = previousFlutterError;
        PlatformDispatcher.instance.onError = previousPlatformError;
        finished.complete();
        await checkpoint();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
