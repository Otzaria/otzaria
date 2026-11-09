// Opt-in real-app scenario; see tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_diagnostics.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/services/webview_backend_observation.dart';
import 'package:otzaria/plugins/view/plugin_background_host.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../tool/perf_probe/src/installed_plugin_contract.dart';
import 'support/installed_plugin_android_control.dart';
import 'support/installed_plugin_catalog.dart';
import 'support/installed_plugin_completion.dart';
import 'support/installed_plugin_fixture.dart';
import 'support/perf_recorder.dart';
import 'support/webview_probe_metrics.dart';
import 'support/webview_probe_window.dart';

const _deadline = Duration(seconds: 45);
const _busyTitle = 'Installed resource probe: pending RPC';
const _assemblyLimits = PluginDiscardLimits(
  maxLiveSuspended: 100,
  maxSuspendedAge: Duration(days: 1),
);
const _desktop = {'windows', 'macos', 'linux'};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'status': 'running',
    'runId': '$pid-${DateTime.now().toUtc().microsecondsSinceEpoch}',
    'platform': Platform.operatingSystem,
    'buildMode': perfBuildMode,
    'pid': pid,
    'osVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version,
    'flutterVersion': const String.fromEnvironment(
      'INSTALLED_PROBE_FLUTTER_VERSION',
      defaultValue: 'unavailable',
    ),
    'commit': const String.fromEnvironment(
      'INSTALLED_PROBE_COMMIT',
      defaultValue: 'unavailable',
    ),
    'machineId': perfOption(
      'INSTALLED_PROBE_MACHINE_ID',
      const String.fromEnvironment(
        'INSTALLED_PROBE_MACHINE_ID',
        defaultValue: 'unavailable',
      ),
    ),
    'physicalDeviceAcceptance': false,
    'acceptanceScope':
        'Controlled installed-plugin integration; no resource-saving threshold or default-policy tuning.',
    'cacheState':
        'fresh isolated app data; OS, engine and filesystem caches are not cleared',
    'platformMatrix': <String, Object?>{
      for (final os in installedPluginPlatforms)
        os: <String, Object?>{
          'status': 'notRun',
          'reason': 'No result for this platform in this process.',
        },
    },
    'phases': [
      for (final name in [
        ...installedPluginRequiredPhases,
        'minimize',
        'hide',
        'osBackground',
      ])
        <String, Object?>{
          'name': name,
          'status': 'notRun',
          'reason': 'Not reached.',
        },
    ],
    'restorations': <Map<String, Object?>>[],
    'protectedControls': <Map<String, Object?>>[],
    'quietWindows': <Map<String, Object?>>[],
    'boundaries': <Map<String, Object?>>[],
    'errors': <String>[],
    'policyRestored': false,
  };
  binding.reportData = {'installedPluginProbe': report};
  File? reportFile;
  InstalledAndroidControl? androidControl;
  final finished = Completer<void>();
  registerInstalledPluginReportFinalizer(binding, (passed) async {
    await finished.future.timeout(const Duration(seconds: 30));
    report['status'] = passed && (report['errors'] as List).isEmpty
        ? 'passed'
        : 'failed';
    report['testFailures'] = [
      for (final failure in binding.failureMethodsDetails) failure.details,
    ];
    report['frameworkPassed'] = passed;
    (report['platformMatrix'] as Map)[Platform.operatingSystem] = {
      'status': report['status'],
      'runId': report['runId'],
      'buildMode': perfBuildMode,
      'physicalDeviceAcceptance': false,
    };
    Object? completionFailure;
    StackTrace? completionStack;
    void failed(String stage, Object error, StackTrace stack) {
      report['status'] = 'failed';
      (report['errors'] as List).add('$stage failed: $error');
      completionFailure ??= error;
      completionStack ??= stack;
    }

    try {
      await reportFile?.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      if (androidControl != null && reportFile != null) {
        await androidControl!.finish(reportFile!, frameworkPassed: passed);
      }
    } catch (error, stack) {
      failed('Final report completion', error, stack);
    }
    try {
      await androidControl?.close();
    } catch (error, stack) {
      failed('Android control cleanup', error, stack);
    }
    if (androidControl != null && reportFile != null) {
      try {
        report['frameworkPassed'] = passed && completionFailure == null;
        ((report['platformMatrix'] as Map)[Platform.operatingSystem]
                as Map)['status'] =
            report['status'];
        await reportFile!.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        if (completionFailure == null) {
          await androidControl!.writeCompletion(
            reportFile!,
            frameworkPassed: passed,
          );
        }
      } catch (error, stack) {
        failed('Android final completion receipt', error, stack);
      }
    }
    if (completionFailure != null) {
      Error.throwWithStackTrace(completionFailure!, completionStack!);
    }
  });

  testWidgets('installed plugins discard and restore through real app hosts', (
    tester,
  ) async {
    final catalog = InstalledProbeCatalog();
    _Scenario? scenario;
    final dispatcher = PluginRuntimeDispatcher.instance;
    final oldClock = dispatcher.clock;
    final oldLimits = dispatcher.discardLimitsOverride;
    final FlutterExceptionHandler? previousFlutterError = FlutterError.onError;
    final previousPlatformError = PlatformDispatcher.instance.onError;
    final errors = report['errors'] as List<String>;
    Object? failure;
    StackTrace? failureStack;
    Future<void> cleanup(
      String name,
      FutureOr<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error, stack) {
        errors.add('$name failed: $error');
        failure ??= error;
        failureStack ??= stack;
      }
    }

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
      String? androidPackage;
      if (const bool.fromEnvironment('INSTALLED_PROBE_ANDROID_CONTROL')) {
        if (!Platform.isAndroid || perfBuildMode != 'debug') {
          throw StateError(
            'The Android host control requires a debug Android APK',
          );
        }
        androidPackage = (await PackageInfo.fromPlatform()).packageName;
        if (androidPackage != installedAndroidPackage) {
          throw StateError(
            'The Android probe cannot write another application data directory',
          );
        }
      }
      final dataPath = perfOption(
        'INSTALLED_PROBE_DATA',
        const String.fromEnvironment('INSTALLED_PROBE_DATA'),
      );
      final sourcePath = perfOption(
        'INSTALLED_PROBE_STORE_SOURCE',
        const String.fromEnvironment('INSTALLED_PROBE_STORE_SOURCE'),
      );
      final outputPath = perfOption(
        'INSTALLED_PROBE_OUTPUT',
        const String.fromEnvironment('INSTALLED_PROBE_OUTPUT'),
      );
      const payload = String.fromEnvironment('INSTALLED_PROBE_STORE_PAYLOAD');
      if (sourcePath.isEmpty == payload.isEmpty) {
        throw ArgumentError(
          'Provide exactly one pinned store source directory or compiled store payload.',
        );
      }
      Directory? temporary;
      if (dataPath.isEmpty || outputPath.isEmpty || sourcePath.isEmpty) {
        final canonicalTemp = await Directory.systemTemp.resolveSymbolicLinks();
        temporary = await Directory(
          canonicalTemp,
        ).createTemp('otzaria-installed-probe-');
      }
      final root = Directory(
        dataPath.isEmpty ? p.join(temporary!.path, 'data') : dataPath,
      );
      final output = Directory(
        outputPath.isEmpty ? p.join(temporary!.path, 'output') : outputPath,
      );
      final source = sourcePath.isEmpty
          ? await materializeInstalledStorePayload(
              Directory(p.join(temporary!.path, 'source')),
              payload,
            )
          : Directory(sourcePath);
      report['isolatedPaths'] = {
        'allocatedPrivateTemp': temporary != null,
        'sourceTransport': sourcePath.isEmpty
            ? 'verified-gzip-json-build-input'
            : 'verified-local-directory',
        'output': output.path,
        'retention':
            'Fixture files remain for diagnosis while the app owns open database handles; remove only after process exit.',
      };
      for (final a in [root.path, source.path, output.path]) {
        if (!p.isAbsolute(a)) {
          throw ArgumentError(
            'Probe data, source and output paths must be absolute.',
          );
        }
        for (final b in [root.path, source.path, output.path]) {
          if (a != b && p.isWithin(a, b)) {
            throw ArgumentError('Probe paths must not contain one another.');
          }
        }
      }
      if ({
            p.normalize(root.path),
            p.normalize(source.path),
            p.normalize(output.path),
          }.length !=
          3) {
        throw ArgumentError('Probe paths must be distinct.');
      }
      await rejectInstalledProbeLinks(output.path);
      if (await output.exists() && !await output.list().isEmpty) {
        throw StateError('Probe output must be a fresh empty directory.');
      }
      await output.create(recursive: true);
      reportFile = File(p.join(output.path, 'installed-plugin-report.json'));
      if (androidPackage != null) {
        androidControl = await InstalledAndroidControl.start(
          support: await getApplicationSupportDirectory(),
          report: reportFile!,
          campaignId: const String.fromEnvironment(
            'INSTALLED_PROBE_ANDROID_CAMPAIGN',
          ),
          token: const String.fromEnvironment('INSTALLED_PROBE_ANDROID_TOKEN'),
          runId: report['runId']! as String,
          processId: pid,
          package: androidPackage,
        );
        report['androidControl'] = {
          ...androidControl!.identity,
          'transport':
              'Loopback push stream through one explicit-serial ADB forward',
          'hostObservations':
              'Setup, requested Home/resume boundaries and final retrieval only; no host polling during any quiet window.',
          'physicalProfileRelease': 'notRun',
        };
        await androidControl!.connected();
      }
      final fixture = InstalledPluginFixture(root, source);
      await catalog.start();
      await fixture.prepare();
      report['fixtureSha256'] = fixture.identity;
      report['pinnedStore'] = {
        'repository': 'https://github.com/Otzaria/otzaria-plugins-store',
        'commit': installedStoreCommit,
        'version': '2.13.0',
        'sha256': fixture.sourceHashes,
        'catalogSelection':
            'Store selected from the public download-ranked catalog; downloads are not active users.',
        'catalogFreshness':
            'No live catalog read during this run; requests use fixed inert service fixtures.',
        'workload':
            'Read-only filters, sort, local preference, scrolling and restore; no install/update/delete actions.',
        'otherCommonPlugins': {
          'status': 'notRun',
          'reason':
              'This runner executes only the pinned store and the controlled guard fixture.',
        },
      };
      report['observer'] = {
        'developerDiagnosticsCollecting':
            DeveloperDiagnostics.instance.isCollecting,
        'consolePolicy':
            'Unchanged production policy; this runner never enables DeveloperDiagnostics collection.',
        'boundaryReadsCanWakeWebViews': true,
        'quietWindows':
            'No probe JS/bridge polling, window queries or process enumeration during timed quiet windows.',
        'productionTimers':
            'Unchanged. Absence of probe calls is not absence of production bridge/native work.',
        'frames':
            'Passive Flutter FrameTiming callback only; not native WebView compositor or interaction latency.',
      };
      if (DeveloperDiagnostics.instance.isCollecting) {
        throw StateError(
          'Start this scenario with DeveloperDiagnostics collection disabled.',
        );
      }
      final errorsFile = ErrorLogFile.resolveFile();
      final errorsBefore = await errorsFile.exists()
          ? await errorsFile.readAsString()
          : '';
      final active = scenario = _Scenario(
        tester,
        fixture,
        report,
        reportFile!,
        catalog,
        androidControl,
      );
      captureErrors();
      await active.phase('startup', () async {
        app.main(const []);
        await active.wait(
          () {
            captureErrors();
            return find.byType(App).evaluate().isNotEmpty &&
                StartupTimeline.instance.toJson()['revealMs'] != null;
          },
          'actual app first content',
          timeout: const Duration(minutes: 3),
        );
        active.attach(tester.element(find.byType(App)));
        report['startupTimeline'] = StartupTimeline.instance.toJson();
        report['window'] = await prepareWebViewProbeWindow(
          platform: Platform.operatingSystem,
          pumpFrame: () => tester.pump(),
          // App startup already queued the Windows splash close. A second
          // pending close would overwrite Flutter's next-frame callback.
          closeNativeSplash: !Platform.isWindows,
        );
        final view = tester.view;
        report['viewport'] = {
          'physicalWidth': view.physicalSize.width,
          'physicalHeight': view.physicalSize.height,
          'devicePixelRatio': view.devicePixelRatio,
        };
        expect(
          find.byType(PluginBackgroundHost, skipOffstage: false),
          findsOneWidget,
        );
      });
      dispatcher.discardLimitsOverride = _assemblyLimits;
      report['policyControl'] = {
        'assembly': {
          'maxLiveSuspended': 100,
          'maxSuspendedAgeMs': _assemblyLimits.maxSuspendedAge.inMilliseconds,
        },
        'pressure':
            'Explicit checkDiscard(memoryPressure: true) after actual hidden candidates and first blockers exist.',
        'count':
            'Actual platform count limit; controlled long age while assembling above the limit.',
        'age':
            'Actual platform age limit; dispatcher clock advanced only for this labeled case.',
        'timers':
            'Production lifecycle, discard and background timers are not disabled.',
      };
      await active.run();
      final errorsAfter = await errorsFile.exists()
          ? await errorsFile.readAsString()
          : '';
      if (errorsAfter != errorsBefore) {
        errors.add(
          'App error log changed: ${errorsAfter.substring(errorsAfter.startsWith(errorsBefore) ? errorsBefore.length : 0)}',
        );
      }
    } catch (error, stack) {
      errors.add('$error\n$stack');
      failure = error;
      failureStack = stack;
    } finally {
      await cleanup('Owned fixture cleanup', () async {
        await scenario?.cleanup().timeout(const Duration(seconds: 20));
      });
      await cleanup('Policy restoration', () {
        dispatcher.clock = oldClock;
        dispatcher.discardLimitsOverride = oldLimits;
        report['policyRestored'] =
            identical(dispatcher.clock, oldClock) &&
            identical(dispatcher.discardLimitsOverride, oldLimits);
      });
      await cleanup('Frame observer cleanup', () => scenario?.detach());
      await cleanup('Catalog cleanup', catalog.stop);
      report['catalogFixture'] = catalog.toJson();
      if (catalog.unexpectedBlockedRequests.isNotEmpty) {
        errors.add(
          'Unexpected blocked HTTP requests remain in the catalog audit.',
        );
      }
      FlutterError.onError = previousFlutterError;
      PlatformDispatcher.instance.onError = previousPlatformError;
      await cleanup('Partial report write', () async {
        await reportFile?.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
      });
      finished.complete();
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
    final contractErrors = installedReportErrors(report);
    report['status'] = contractErrors.isEmpty && errors.isEmpty
        ? 'passed'
        : 'failed';
    report['contractErrors'] = contractErrors;
    (report['platformMatrix'] as Map)[Platform.operatingSystem] = {
      'status': report['status'],
      'runId': report['runId'],
      'buildMode': perfBuildMode,
      'physicalDeviceAcceptance': false,
    };
    await reportFile?.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    expect(contractErrors, isEmpty);
    expect(errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 18)));
}

class _Scenario {
  _Scenario(
    this.tester,
    this.fixture,
    this.report,
    this.file,
    this.catalog,
    this.androidControl,
  ) : _frameTimings = InstalledPluginFrameTimings(SchedulerBinding.instance);
  final WidgetTester tester;
  final InstalledPluginFixture fixture;
  final Map<String, Object?> report;
  final File file;
  final InstalledProbeCatalog catalog;
  final InstalledAndroidControl? androidControl;
  final dispatcher = PluginRuntimeDispatcher.instance;
  final restoreStore = PluginRestoreStateStore.instance;
  final InstalledPluginFrameTimings _frameTimings;
  final _tabs = <ToolTab>[];
  late BuildContext context;
  late TabsBloc tabs;
  late PluginDiscardLimits defaults;
  var jsCalls = 0;
  var nativeQueries = 0;
  var commands = 0;
  var _pendingBoundarySamples = 0;
  var _pendingNativeProcessLists = 0;
  var _attached = false;
  final _quietMs = int.parse(
    perfOption(
      'INSTALLED_PROBE_IDLE_MS',
      const String.fromEnvironment(
        'INSTALLED_PROBE_IDLE_MS',
        defaultValue: '1000',
      ),
    ),
  );

  void attach(BuildContext value) {
    context = value;
    tabs = context.read<TabsBloc>();
    defaults = PluginDiscardLimits.forPlatform(Theme.of(context).platform);
    if (_quietMs < 1000 || _quietMs > 60000) {
      throw ArgumentError('Idle interval must be 1000..60000 ms.');
    }
    report['defaultPolicy'] = {
      'maxLiveSuspended': defaults.maxLiveSuspended,
      'maxSuspendedAgeMs': defaults.maxSuspendedAge.inMilliseconds,
    };
    _attached = true;
  }

  void detach() {
    _frameTimings.dispose();
    report['droppedFlutterFrameTimings'] = _frameTimings.droppedFrames;
    report['probeBoundaryJsCalls'] = jsCalls;
    report['probeBoundaryNativeQueries'] = nativeQueries;
  }

  Future<void> cleanup() async {
    if (!_attached) return;
    final dialog = find.text(_busyTitle);
    if (dialog.evaluate().isNotEmpty) {
      Navigator.of(tester.element(dialog), rootNavigator: true).pop(false);
    }
    if (_tabs.isNotEmpty) await close(_tabs.toList());
    if (dispatcher.controllerOf(
          installedBackgroundId,
          instanceId: PluginInstanceIds.background,
        ) !=
        null) {
      await PluginRegistryRepository().saveEnabledChoice(
        installedBackgroundId,
        false,
      );
      await reloadPlugins();
      await wait(
        () =>
            dispatcher.controllerOf(
              installedBackgroundId,
              instanceId: PluginInstanceIds.background,
            ) ==
            null,
        'Owned background host cleanup',
      );
    }
  }

  Future<void> checkpoint() => file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );

  Map<String, Object?> phaseRecord(String name) => (report['phases'] as List)
      .cast<Map<String, Object?>>()
      .singleWhere((phase) => phase['name'] == name);

  Future<void> phase(String name, Future<void> Function() action) async {
    final record = phaseRecord(name)..remove('reason');
    final startUs = DateTime.now().microsecondsSinceEpoch;
    final elapsed = Stopwatch()..start();
    record.addAll({
      'status': 'running',
      'startedUtc': DateTime.now().toUtc().toIso8601String(),
    });
    await checkpoint();
    Object? failure;
    StackTrace? failureStack;
    void capture(Object error, StackTrace stack) {
      record['status'] = 'failed';
      if (failure == null) {
        failure = error;
        failureStack = stack;
        record['error'] = error.toString();
      } else {
        (record.putIfAbsent('secondaryErrors', () => <String>[]) as List).add(
          error.toString(),
        );
      }
    }

    try {
      if (_attached) await boundary(name, 'before');
      await action();
      record['status'] = 'passed';
    } catch (error, stack) {
      capture(error, stack);
    }
    elapsed.stop();
    final endUs = DateTime.now().microsecondsSinceEpoch;
    final lastFrameNumber = PlatformDispatcher.instance.frameData.frameNumber;
    record['durationMs'] = elapsed.elapsedMicroseconds / 1000;
    record['endedUtc'] = DateTime.fromMicrosecondsSinceEpoch(
      endUs,
      isUtc: true,
    ).toIso8601String();
    try {
      record['flutterFrames'] = await _frameTimings.finish(
        startUs: startUs,
        endUs: endUs,
        lastFrameNumber: lastFrameNumber,
        timeout: _deadline,
        requestFrameAfterWindow: () => submitInstalledPluginFrameFence(
          SchedulerBinding.instance,
          repaintViews: () {
            for (final view in RendererBinding.instance.renderViews) {
              view.markNeedsPaint();
            }
          },
          frameNumber: () => PlatformDispatcher.instance.frameData.frameNumber,
        ),
      );
    } catch (error, stack) {
      record['flutterFrames'] = {
        'availability': 'unavailable',
        'reason': error.toString(),
        'lastFrameNumber': lastFrameNumber,
      };
      capture(error, stack);
    }
    try {
      if (_attached) await boundary(name, 'after');
    } catch (error, stack) {
      capture(error, stack);
    }
    try {
      await checkpoint();
    } catch (error, stack) {
      capture(error, stack);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  Future<void> wait(
    bool Function() condition,
    String description, {
    Duration timeout = _deadline,
  }) async {
    final elapsed = Stopwatch()..start();
    while (!condition()) {
      if (elapsed.elapsed >= timeout) {
        throw TimeoutException(description, timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  InAppWebViewController? controller(ToolTab tab) =>
      dispatcher.controllerOf(tab.toolId, instanceId: tab.instanceId);
  PluginInstanceKey key(ToolTab tab) =>
      (pluginId: tab.toolId, instanceId: tab.instanceId);
  Map<String, Object?> resources() => dispatcher.describeForegroundResources();
  Map<String, Object?> instance(ToolTab tab) =>
      (resources()['instances'] as List)
          .cast<Map<String, Object?>>()
          .singleWhere(
            (entry) =>
                entry['pluginId'] == tab.toolId &&
                entry['instanceId'] == tab.instanceId,
          );

  Future<void> boundary(String phase, String side) async {
    if (DeveloperDiagnostics.instance.isCollecting) {
      throw StateError(
        'Diagnostics collection changed the production console policy during the run.',
      );
    }
    ProcessTreeSample? sample;
    WebViewProcessSnapshot? observedProcesses;
    String? error;
    nativeQueries++;
    try {
      _pendingBoundarySamples++;
      final pending = sampleProcessTree(
        webViewProcesses: () async {
          _pendingNativeProcessLists++;
          try {
            return observedProcesses = await collectPluginWebViewProcesses(
              WebViewEnvironmentHolder.environment,
            );
          } finally {
            _pendingNativeProcessLists--;
          }
        },
      );
      sample = await pending
          .whenComplete(() => _pendingBoundarySamples--)
          .timeout(const Duration(seconds: 10));
    } catch (exception) {
      error = exception.toString();
    }
    (report['boundaries'] as List).add({
      'phase': phase,
      'side': side,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'resources': resources(),
      'hostRss': probeMetric(
        availability: ProbeAvailability.collected,
        metric: 'residentSetSize',
        unit: 'bytes',
        scope: 'host',
        source: 'dart:io ProcessInfo.currentRss',
        value: ProcessInfo.currentRss,
      ),
      'processMemory': webViewProbeMemory(
        sample,
        platform: Platform.operatingSystem,
        error: error,
      ),
      'rawProcessSample': sample?.toJson(),
      'nativeProcessObservations': observedProcesses == null
          ? {
              'availability': 'unavailable',
              'reason':
                  'No native WebView process-list response in this boundary sample.',
            }
          : {
              'collection': observedProcesses!.collection.toJson(),
              'complete': null,
              'processes': [
                for (final process in observedProcesses!.processes.take(128))
                  {
                    'kind': process.kind,
                    'pid': process.pid,
                    'page': process.page,
                    'startTime': null,
                  },
              ],
              'detailsTruncated': observedProcesses!.processes.length > 128,
              'identityScope':
                  'Observed PID at this boundary only; process start time and PID reuse identity are not available from this API.',
            },
      'cpu': probeMetric(
        availability: ProbeAvailability.unavailable,
        metric: 'cpuUtilization',
        unit: 'percent',
        scope: 'host-and-engine',
        reason: 'No external CPU sampler is attached by this runner.',
      ),
      'pss': probeMetric(
        availability: ProbeAvailability.unavailable,
        metric: 'proportionalSetSize',
        unit: 'bytes',
        scope: 'host-and-engine',
        reason: 'The reused sampler does not measure PSS.',
      ),
      'gpuMemory': probeMetric(
        availability: ProbeAvailability.unavailable,
        metric: 'gpuMemory',
        unit: 'bytes',
        scope: 'engine',
        reason: 'Not exposed by this runner.',
      ),
      'nativeFrameLatency': probeMetric(
        availability: ProbeAvailability.unavailable,
        metric: 'nativeWebViewFrameLatency',
        unit: 'ms',
        scope: 'engine',
        reason: 'Flutter timings do not measure the native WebView compositor.',
      ),
    });
  }

  Future<void> quiet(String name, {Future<void> Function()? waitIdle}) async {
    if (_pendingBoundarySamples != 0 || _pendingNativeProcessLists != 0) {
      throw StateError(
        'A timed-out boundary observation is still pending; this is not a quiet window.',
      );
    }
    final startJs = jsCalls, startNative = nativeQueries;
    final clock = Stopwatch()..start();
    final startUtc = DateTime.now().toUtc().toIso8601String();
    if (waitIdle == null) {
      await Future<void>.delayed(Duration(milliseconds: _quietMs));
    } else {
      await waitIdle();
    }
    (report['quietWindows'] as List).add({
      'name': name,
      'startedUtc': startUtc,
      'requestedMs': _quietMs,
      'elapsedMs': clock.elapsedMicroseconds / 1000,
      'probeJsCalls': jsCalls - startJs,
      'probeNativeQueries': nativeQueries - startNative,
      'productionTimersDisabled': false,
    });
    expect(jsCalls, startJs);
    expect(nativeQueries, startNative);
  }

  Future<dynamic> evaluate(InAppWebViewController target, String source) async {
    jsCalls++;
    return target
        .evaluateJavascript(source: source)
        .timeout(const Duration(seconds: 10));
  }

  Future<Map<String, Object?>> read(ToolTab tab) =>
      readController(controller(tab)!);
  Future<Map<String, Object?>> readController(
    InAppWebViewController target,
  ) async {
    final value = await evaluate(
      target,
      'JSON.stringify(window.installedPluginProbe ? window.installedPluginProbe.read() : null)',
    );
    final result = decodeInstalledPluginSnapshot(value);
    if (result['error'] != null) {
      throw StateError('Controlled plugin JS error: ${result['error']}');
    }
    return result;
  }

  Future<Map<String, Object?>> ready(ToolTab tab) async {
    await wait(
      () => controller(tab) != null,
      'PluginTabPage controller ${tab.instanceId}',
    );
    final elapsed = Stopwatch()..start();
    while (true) {
      final value = await read(tab);
      if (value['ready'] == true) {
        expect(value['sdkBooted'], true);
        expect(value['bootCount'], 1);
        return value;
      }
      if (elapsed.elapsed >= _deadline) {
        throw TimeoutException('Actual SDK boot ${tab.instanceId}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> command(
    ToolTab tab,
    String action, [
    Map<String, Object?> args = const {},
  ]) async {
    final id = 'command-${commands++}';
    await evaluate(
      controller(tab)!,
      'window.installedPluginProbe.command(${jsonEncode(id)}, ${jsonEncode(action)}, ${jsonEncode(args)})',
    );
    final elapsed = Stopwatch()..start();
    while (true) {
      final value = await read(tab);
      final ack = (value['acks'] as Map? ?? {})[id];
      if (ack is Map) {
        if (ack['ok'] != true) throw StateError('Command failed: $ack');
        return;
      }
      if (elapsed.elapsed >= _deadline) {
        throw TimeoutException('SDK command $action');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> reloadPlugins() async {
    final bloc = context.read<PluginSystemBloc>();
    final previous = bloc.state;
    bloc.add(LoadPlugins());
    await wait(() {
      final state = bloc.state;
      return !identical(state, previous) &&
          state is PluginSystemLoaded &&
          fixture.installedIds.every(
            (id) => state.plugins.any((plugin) => plugin.pluginId == id),
          );
    }, 'PluginRegistryRepository loaded into PluginSystemBloc');
    await tester.pump();
  }

  Future<ToolTab> open({
    String id = installedProbeId,
    bool store = false,
  }) async {
    final tab = ToolTab(
      toolId: id,
      title: 'בדיקת תוסף',
      allowMultipleInstances: !store,
    );
    _tabs.add(tab);
    tabs.add(AddTab(tab));
    context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
    await wait(
      () => tabs.state.currentTab == tab && controller(tab) != null,
      'Real plugin tab open',
    );
    expect(
      find.byType(PluginTabPage, skipOffstage: false).evaluate().isNotEmpty,
      true,
    );
    if (!store) await ready(tab);
    return tab;
  }

  Future<void> select(ToolTab tab) async {
    final index = tabs.state.tabs.indexWhere((value) => value == tab);
    if (index < 0) throw StateError('Tab is no longer registered');
    tabs.add(SetCurrentTab(index));
    await wait(
      () =>
          tabs.state.currentTab == tab &&
          controller(tab) != null &&
          dispatcher.isInstanceShown(key(tab)) &&
          instance(tab)['suspensionState'] == 'active',
      'Visible restored plugin tab',
    );
  }

  Future<void> close(List<ToolTab> values) async {
    if (values.isEmpty) return;
    tabs.add(RemoveTabs(values));
    await wait(
      () => values.every(
        (tab) => !tabs.state.tabs.contains(tab) && controller(tab) == null,
      ),
      'Real tab hosts disposed',
    );
    _tabs.removeWhere(values.contains);
  }

  Map<String, Object?> identity(ToolTab tab, Map<String, Object?> js) => {
    'pluginId': tab.toolId,
    'instanceId': tab.instanceId,
    'controllerObjectId': identityHashCode(controller(tab)),
    'nativeViewId': controller(tab)!.getViewId()?.toString(),
    'documentToken': js['documentToken'],
    'backend': observeWebViewBackend(controller(tab)!),
    'userAgent': js['userAgent'],
  };

  Future<_Before> before(ToolTab tab, {bool store = false}) async {
    final js = store ? await storeRead(tab) : await read(tab);
    return _Before(
      tab,
      controller(tab)!,
      identity(tab, js),
      js,
      restoreStore.stateOf(key(tab)),
    );
  }

  Future<void> candidates(
    List<ToolTab> eligible, [
    Map<ToolTab, String> guards = const {},
  ]) => wait(() {
    return eligible.every((tab) => instance(tab)['discardEligible'] == true) &&
        guards.entries.every(
          (entry) =>
              instance(entry.key)['discardCandidate'] == true &&
              instance(entry.key)['firstBlockingReason'] == entry.value,
        );
  }, 'Actual hidden candidates and first blocking reasons');

  Future<void> released(_Before value) async {
    final page = find.byWidgetPredicate(
      (widget) =>
          widget is PluginTabPage &&
          widget.plugin.pluginId == value.tab.toolId &&
          widget.instanceId == value.tab.instanceId,
      skipOffstage: false,
    );
    await wait(
      () =>
          controller(value.tab) == null &&
          instance(value.tab)['released'] == true &&
          page.evaluate().length == 1 &&
          find
              .descendant(
                of: page,
                matching: find.byType(InAppWebView, skipOffstage: false),
                skipOffstage: false,
              )
              .evaluate()
              .isEmpty,
      'Dispatcher releaseWebView completed',
    );
    value.released = {...instance(value.tab), 'hostWidgetRemoved': true};
    expect(value.released!['lastDiscardedAt'], isNotNull);
    expect(value.released!['restoreAvailable'], true);
  }

  Future<void> restore(
    _Before value,
    String scenario, {
    bool store = false,
  }) async {
    final elapsed = Stopwatch()..start();
    await select(value.tab);
    var js = store ? await storeReady(value.tab) : await ready(value.tab);
    while (store && !_sameView(value.js['view'], js['view'])) {
      if (elapsed.elapsed >= _deadline) {
        throw TimeoutException('Store rendered restored DOM: ${js['view']}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      js = await storeRead(value.tab);
    }
    final after = identity(value.tab, js);
    final expectedView = value.js['view'];
    final actualView = js['view'];
    final sameView = _sameView(expectedView, actualView);
    final proof = <String, Object?>{
      'scenario': scenario,
      'before': value.identity,
      'after': after,
      'sameInstanceId': after['instanceId'] == value.identity['instanceId'],
      'releasedByDispatcher':
          value.released?['released'] == true &&
          value.released?['lastDiscardedAt'] != null,
      'controllerAbsentAfterDiscard': value.released != null,
      'hostWidgetRemovedBeforeRestore':
          value.released?['hostWidgetRemoved'] == true,
      'differentControllerObject': !identical(
        value.controller,
        controller(value.tab),
      ),
      'differentNativeViewId':
          after['nativeViewId'] == null ||
              value.identity['nativeViewId'] == null
          ? null
          : after['nativeViewId'] != value.identity['nativeViewId'],
      'differentDocument':
          after['documentToken'] != value.identity['documentToken'],
      'sdkBooted': js['sdkBooted'],
      'visibleStateMatches': sameView,
      'beforeVisibleState': expectedView,
      'afterVisibleState': actualView,
      'controlledSdkTrafficBefore': store ? null : _fixtureTraffic(value.js),
      'controlledSdkTrafficAfter': store ? null : _fixtureTraffic(js),
      'acceptedRestoreStateBeforeDiscard': value.saved,
      'receivedBootRestore': store
          ? {
              'availability': 'unavailable',
              'reason':
                  'Unmodified store does not expose boot payload; fresh document, real SDK and restored DOM are observed.',
            }
          : (js['boot'] as Map?)?['restore'],
      'resumeMs': elapsed.elapsedMicroseconds / 1000,
      'resumeEndpoint':
          'Actual selected host, new controller, SDK boot and observed DOM state; boundary JS read included.',
    };
    (report['restorations'] as List).add(proof);
    expect(installedRestoreErrors(proof), isEmpty);
    if (!store) {
      final restore = (js['boot'] as Map)['restore'] as Map;
      expect(restore['reason'], 'discarded');
      expect(restore['state'], value.saved);
    }
  }

  Map<String, Object?> _fixtureTraffic(Map<String, Object?> js) => {
    'scope':
        'Only controlled-fixture SDK calls in this document; excludes SDK internals, host bridge traffic and the unmodified store.',
    for (final field in [
      'requests',
      'replies',
      'requestJsonBytes',
      'replyJsonBytes',
    ])
      field: js[field],
  };

  bool _sameView(Object? expected, Object? actual) {
    if (expected is! Map || actual is! Map) return false;
    final a = Map<String, Object?>.from(expected);
    final b = Map<String, Object?>.from(actual);
    final aScroll = a.remove('scrollTop'), bScroll = b.remove('scrollTop');
    return aScroll is num &&
        bScroll is num &&
        (aScroll - bScroll).abs() <= 2 &&
        a.keys.length == b.keys.length &&
        a.keys.every((key) => a[key] == b[key]);
  }

  Future<void> run() async {
    Future<void> setupStep(String name) async {
      report['setupStep'] = name;
      await checkpoint();
    }

    await setupStep('install $installedProbeId');
    await fixture.installControlled(installedProbeId);
    for (final suffix in ['no-snapshot', 'unsaved', 'busy', 'service']) {
      await setupStep('install $installedProbeId.$suffix');
      await fixture.installControlled('$installedProbeId.$suffix');
    }
    await setupStep('install pinned store');
    await fixture.installStore();
    await setupStep('reload installed plugins');
    await reloadPlugins();
    await setupStep('complete');
    late ToolTab first;
    await phase('firstOpen', () async {
      first = await open();
      final js = await read(first);
      phaseRecord('firstOpen')['identity'] = identity(first, js);
      report['webViewRuntime'] = {
        'userAgent': {
          'source': 'navigator.userAgent boundary read',
          'value': js['userAgent'],
        },
        'windowsRuntimeVersion': {
          'availability': WebView2CreationDiagnostics.runtimeVersion == null
              ? 'unavailable'
              : 'collected',
          'source':
              'WebViewEnvironment.getAvailableVersion cached during real app initialization',
          'value': WebView2CreationDiagnostics.runtimeVersion,
        },
      };
    });
    await phase('visibleIdle', () => quiet('visibleIdle'));
    await phase('stateAndScroll', () async {
      await command(first, 'state', {
        'text': 'restored first instance',
        'scrollTop': 480,
      });
      expect((await read(first))['view'], {
        'version': 1,
        'text': 'restored first instance',
        'scrollTop': 480,
      });
    });
    await desktopVisibility(first);
    await androidVisibility(first);
    final eligible = <ToolTab>[first];
    final guards = <ToolTab, String>{};
    late ToolTab keeper;
    final beforeValues = <_Before>[];
    await phase('multipleOpen', () async {
      for (var i = 1; i <= defaults.maxLiveSuspended; i++) {
        final tab = await open();
        eligible.add(tab);
        await command(tab, 'state', {
          'text': 'instance $i',
          'scrollTop': 240 + i * 20,
        });
      }
      for (final entry in {
        'no-snapshot': 'noRestoreState',
        'unsaved': 'unsavedChanges',
        'service': 'contextMenu',
        'busy': 'busyRpc',
      }.entries) {
        final tab = await open(id: '$installedProbeId.${entry.key}');
        guards[tab] = entry.value;
        await command(tab, 'state', {'text': entry.key, 'scrollTop': 180});
        await command(
          tab,
          switch (entry.key) {
            'no-snapshot' => 'noSnapshot',
            'unsaved' => 'unsaved',
            'service' => 'service',
            _ => 'busy',
          },
          {'value': true},
        );
      }
      for (final tab in eligible) {
        // Capture identity/state while selected; do not wake suspended pages
        // with a measurement query after the quiet interval has started.
        await select(tab);
        beforeValues.add(await before(tab));
      }
      keeper = await open();
      await candidates(eligible, guards);
      phaseRecord('multipleOpen').addAll({
        'eligibleCount': eligible.length,
        'platformThreshold': defaults.maxLiveSuspended,
        'guardCount': guards.length,
        'keeperCount': 1,
        'resources': resources(),
      });
      expect(eligible.length, greaterThan(defaults.maxLiveSuspended));
    });
    await phase('hiddenIdle', () => quiet('hiddenIdle'));
    final guardedControllers = {
      for (final tab in guards.keys) tab: controller(tab),
    };
    const pressureRequest = 'shared-memory-pressure-1';
    await phase('memoryPressure', () async {
      await candidates(eligible, guards);
      phaseRecord('memoryPressure').addAll({
        'discardRequestId': pressureRequest,
        'requestResources': resources(),
        'memoryPressure': true,
      });
      await dispatcher.checkDiscard(memoryPressure: true);
      for (final value in beforeValues) {
        await released(value);
      }
    });
    await phase('protectedControls', () async {
      for (final entry in guards.entries) {
        final state = instance(entry.key);
        final proof = {
          'pluginId': entry.key.toolId,
          'instanceId': entry.key.instanceId,
          'discardRequestId': pressureRequest,
          'firstBlockingReason': state['firstBlockingReason'],
          'sameControllerAfterRequest': identical(
            guardedControllers[entry.key],
            controller(entry.key),
          ),
          'released': state['released'],
        };
        (report['protectedControls'] as List).add(proof);
        expect(proof['firstBlockingReason'], entry.value);
        expect(proof['sameControllerAfterRequest'], true);
        expect(proof['released'], false);
      }
      final dialog = find.text(_busyTitle);
      expect(dialog, findsOneWidget);
      Navigator.of(tester.element(dialog), rootNavigator: true).pop(false);
      for (final entry in guards.entries) {
        await select(entry.key);
        if (entry.value == 'unsavedChanges') {
          await command(entry.key, 'unsaved', {'value': false});
        }
        if (entry.value == 'contextMenu') {
          await command(entry.key, 'service', {'value': false});
        }
        if (entry.value == 'busyRpc') {
          final elapsed = Stopwatch()..start();
          while ((await read(entry.key))['busyPending'] == true) {
            if (elapsed.elapsed >= _deadline) {
              throw TimeoutException('Pending real RPC completion');
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
      }
      await close(guards.keys.toList());
    });
    await phase('restore', () async {
      for (final value in beforeValues) {
        await restore(value, 'pressure');
      }
      await close([...eligible, keeper]);
    });
    await phase('countPolicy', () => controlledPolicy(age: false));
    await phase('agePolicy', () => controlledPolicy(age: true));
    await phase('storeRestore', storeScenario);
    await backgroundScenario();
    await phase('close', () async {
      await close(_tabs.toList());
      expect(resources()['live'], 0);
      expect(resources()['backgroundLive'], 0);
    });
    await phase('closedIdle', () => quiet('closedIdle'));
  }

  Future<void> desktopVisibility(ToolTab tab) async {
    final os = Platform.operatingSystem;
    phaseRecord('osBackground').addAll({
      'status': 'notRun',
      'reason':
          'No mobile OS task-switch or background automation in this runner; Offstage and desktop minimize are recorded separately.',
    });
    if (!_desktop.contains(os)) {
      for (final name in ['minimize', 'hide']) {
        phaseRecord(name).addAll({
          'status': 'unsupported',
          'reason': 'Desktop window_manager action does not apply on $os.',
        });
      }
      return;
    }
    for (final name in ['minimize', 'hide']) {
      await phase(name, () async {
        final beforeIdentity = identity(tab, await read(tab));
        final clock = Stopwatch()..start();
        nativeQueries++;
        if (name == 'minimize') {
          await windowManager.minimize();
        } else {
          await windowManager.hide();
        }
        Map<String, Object?>? ack;
        final elapsed = Stopwatch()..start();
        while (true) {
          nativeQueries++;
          ack = await readWebViewProbeWindow(os);
          if (name == 'minimize'
              ? ack['minimized'] == true
              : ack['visible'] == false) {
            break;
          }
          if (elapsed.elapsed >= _deadline) {
            throw TimeoutException('OS $name acknowledgement: $ack');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        phaseRecord(name).addAll({
          'osAcknowledgement': ack,
          'acknowledgedAfterMs': clock.elapsedMicroseconds / 1000,
          'action': 'native desktop window $name, not Offstage',
        });
        await wait(
          () => instance(tab)['discardCandidate'] == true,
          'App completes the native $name hidden transition',
        );
        await quiet('${name}Idle');
        final resume = Stopwatch()..start();
        nativeQueries++;
        await windowManager.show();
        if (name == 'minimize') await windowManager.restore();
        await windowManager.focus();
        await wait(
          () =>
              dispatcher.isInstanceShown(key(tab)) &&
              instance(tab)['suspensionState'] == 'active',
          'Native window and plugin resumed',
        );
        Map<String, Object?> windowAfter;
        do {
          nativeQueries++;
          windowAfter = await readWebViewProbeWindow(os);
          if (resume.elapsed >= _deadline) {
            throw TimeoutException(
              'Native visible-window resume acknowledgement: $windowAfter',
            );
          }
          if (windowAfter['ready'] != true) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        } while (windowAfter['ready'] != true);
        final after = await ready(tab);
        expect(after['documentToken'], beforeIdentity['documentToken']);
        phaseRecord(name).addAll({
          'resumeMs': resume.elapsedMicroseconds / 1000,
          'sameDocumentAfterResume': true,
          'windowAfter': windowAfter,
        });
      });
    }
  }

  Future<void> androidVisibility(ToolTab tab) async {
    final control = androidControl;
    if (control == null) return;
    phaseRecord('osBackground').remove('reason');
    await phase('osBackground', () async {
      final original = await before(tab);
      final observed = original.identity;
      expect(
        SchedulerBinding.instance.lifecycleState,
        AppLifecycleState.resumed,
      );
      nativeQueries++;
      final home = await control.request('home', {'identity': observed});
      await wait(
        () =>
            SchedulerBinding.instance.lifecycleState ==
                AppLifecycleState.paused &&
            !dispatcher.isInstanceShown(key(tab)) &&
            instance(tab)['suspensionState'] == 'hidden' &&
            instance(tab)['discardCandidate'] == true,
        'Android Home delivered paused lifecycle and hidden real plugin host',
      );
      final lifecycleBeforeQuiet =
          SchedulerBinding.instance.lifecycleState!.name;
      phaseRecord('osBackground').addAll({
        'mechanism': 'External ADB Home and same-activity resume',
        'before': observed,
        'home': home,
        'lifecycleBeforeQuiet': lifecycleBeforeQuiet,
        'dispatcherBeforeQuiet': instance(tab)['suspensionState'],
        'shownBeforeQuiet': dispatcher.isInstanceShown(key(tab)),
        'discardCandidateBeforeQuiet': instance(tab)['discardCandidate'],
      });
      await checkpoint();
      Map<String, Object?>? hostQuiet;
      await quiet(
        'osBackgroundIdle',
        waitIdle: () async {
          hostQuiet = await control.request('quiet', {
            'identity': observed,
            'name': 'osBackgroundIdle',
            'durationMs': _quietMs,
          }, timeout: Duration(milliseconds: _quietMs + 45000));
        },
      );
      expect(
        SchedulerBinding.instance.lifecycleState,
        AppLifecycleState.paused,
      );
      phaseRecord('osBackground')['hostQuiet'] = hostQuiet;
      await checkpoint();
      final resumeClock = Stopwatch()..start();
      nativeQueries++;
      final resume = await control.request('resume', {'identity': observed});
      phaseRecord('osBackground')['resume'] = resume;
      await wait(
        () =>
            SchedulerBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            dispatcher.isInstanceShown(key(tab)) &&
            instance(tab)['suspensionState'] == 'active',
        'Same Android activity resumed with active real plugin host',
      );
      final js = await ready(tab);
      final after = identity(tab, js);
      final sameController = identical(original.controller, controller(tab));
      final sameDocument = after['documentToken'] == observed['documentToken'];
      final sameView = _sameView(original.js['view'], js['view']);
      phaseRecord('osBackground').addAll({
        'after': after,
        'lifecycleAfterResume': SchedulerBinding.instance.lifecycleState!.name,
        'dispatcherAfterResume': instance(tab)['suspensionState'],
        'shownAfterResume': dispatcher.isInstanceShown(key(tab)),
        'sameControllerAfterResume': sameController,
        'sameDocumentAfterResume': sameDocument,
        'visibleStateMatches': sameView,
        'beforeVisibleState': original.js['view'],
        'afterVisibleState': js['view'],
        'resumeMs': resumeClock.elapsedMicroseconds / 1000,
        'physicalDeviceAcceptance': false,
      });
      expect(sameController, true);
      expect(sameDocument, true);
      expect(sameView, true);
      expect(after['instanceId'], observed['instanceId']);
      expect(after['nativeViewId'], observed['nativeViewId']);
    });
  }

  Future<void> controlledPolicy({required bool age}) async {
    final oldClock = dispatcher.clock;
    final oldLimits = dispatcher.discardLimitsOverride;
    final values = <_Before>[];
    try {
      dispatcher.discardLimitsOverride = _assemblyLimits;
      final count = age ? 1 : defaults.maxLiveSuspended + 1;
      for (var i = 0; i < count; i++) {
        final tab = await open();
        await command(tab, 'state', {
          'text': '${age ? 'age' : 'count'} $i',
          'scrollTop': 300 + i * 10,
        });
        values.add(await before(tab));
      }
      final keeper = await open();
      await candidates(values.map((value) => value.tab).toList());
      final phaseName = age ? 'agePolicy' : 'countPolicy';
      final beforeResources = resources();
      if (age) {
        final future = DateTime.now().add(
          defaults.maxSuspendedAge + const Duration(seconds: 1),
        );
        dispatcher.clock = () => future;
        dispatcher.discardLimitsOverride = defaults;
        phaseRecord(phaseName)['controlledClockUtc'] = future
            .toUtc()
            .toIso8601String();
      } else {
        dispatcher.discardLimitsOverride = PluginDiscardLimits(
          maxLiveSuspended: defaults.maxLiveSuspended,
          maxSuspendedAge: const Duration(days: 1),
        );
      }
      phaseRecord(phaseName).addAll({
        'controlled': true,
        'memoryPressure': false,
        'before': beforeResources,
        'requestResources': resources(),
      });
      await dispatcher.checkDiscard();
      await released(values.first);
      if (!age) {
        expect(
          values
              .skip(1)
              .every(
                (value) => identical(controller(value.tab), value.controller),
              ),
          true,
        );
      }
      dispatcher.clock = oldClock;
      dispatcher.discardLimitsOverride = _assemblyLimits;
      await restore(values.first, age ? 'age' : 'count');
      await close([...values.map((value) => value.tab), keeper]);
    } finally {
      dispatcher.clock = oldClock;
      dispatcher.discardLimitsOverride = oldLimits;
    }
  }

  Future<Map<String, Object?>> storeRead(ToolTab tab) async {
    final token = '${report['runId']}-store-document-${commands++}';
    final value = await evaluate(controller(tab)!, '''JSON.stringify((() => {
      if (!window.__installedProbeDocumentToken) window.__installedProbeDocumentToken = ${jsonEncode(token)};
      const byId = id => document.getElementById(id);
      const pending = typeof pendingScroll === 'undefined' ? 'unavailable' : pendingScroll;
      return {documentToken:window.__installedProbeDocumentToken,
        sdkBooted:!!(window.Otzaria && Otzaria._booted), userAgent:navigator.userAgent,
        ready:!!byId('search') && !!byId('grid') && byId('grid').children.length > 0 && getComputedStyle(byId('loading')).display === 'none' && pending === null,
        rendering:{pendingScroll:pending, sequence:typeof renderSeq === 'number' ? renderSeq : null},
        view:byId('search') ? {search:byId('search').value, status:byId('status-filter').value,
          sort:byId('sort-select').value, hideInstalled:byId('hide-installed').checked,
          scrollTop:byId('app-content').scrollTop} : null};
    })())''');
    return decodeInstalledPluginSnapshot(value);
  }

  Future<Map<String, Object?>> storeReady(ToolTab tab) async {
    final elapsed = Stopwatch()..start();
    while (true) {
      final value = await storeRead(tab);
      if (value['sdkBooted'] == true &&
          value['ready'] == true &&
          restoreStore.has(key(tab))) {
        return value;
      }
      if (elapsed.elapsed >= _deadline) {
        throw TimeoutException(
          'Unmodified store SDK, catalog and first accepted snapshot: $value',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> storeScenario() async {
    final tab = await open(id: installedStoreId, store: true);
    await storeReady(tab);
    await evaluate(controller(tab)!, '''(() => {
      const byId = id => document.getElementById(id);
      byId('sort-select').value = 'updated'; byId('sort-select').dispatchEvent(new Event('change', {bubbles:true}));
      byId('status-filter').value = 'beta'; byId('status-filter').dispatchEvent(new Event('change', {bubbles:true}));
      byId('hide-installed').checked = true; byId('hide-installed').dispatchEvent(new Event('change', {bubbles:true}));
      byId('search').value = 'Fixture'; byId('search').dispatchEvent(new Event('input', {bubbles:true}));
      return true;
    })()''');
    await wait(() {
      final state = restoreStore.stateOf(key(tab));
      return state is Map &&
          state['search'] == 'Fixture' &&
          state['sort'] == 'updated' &&
          state['status'] == 'beta' &&
          state['hideInstalled'] == true;
    }, 'Store accepted view state through actual SDK');
    phaseRecord('storeRestore')['readyBeforeScroll'] = await storeReady(tab);
    final scroll = await evaluate(controller(tab)!, '''JSON.stringify((() => {
      const content = document.getElementById('app-content'); content.scrollTop = 420;
      content.dispatchEvent(new Event('scroll'));
      return {requestedScrollTop:420, actualScrollTop:content.scrollTop,
        scrollHeight:content.scrollHeight, clientHeight:content.clientHeight,
        documentToken:window.__installedProbeDocumentToken};
    })())''');
    phaseRecord('storeRestore')['scrollAssignment'] = jsonDecode(
      scroll as String,
    );
    await wait(() {
      final state = restoreStore.stateOf(key(tab));
      return state is Map &&
          state['scrollTop'] is num &&
          (state['scrollTop'] as num) > 200;
    }, 'Store accepted scroll snapshot');
    final value = await before(tab, store: true);
    final keeper = await open();
    await candidates([tab]);
    phaseRecord('storeRestore')['beforeDiscard'] = resources();
    await dispatcher.checkDiscard(memoryPressure: true);
    await released(value);
    await restore(value, 'store', store: true);
    expect(catalog.unexpectedBlockedRequests, isEmpty);
    expect(
      catalog.requests.where((request) => request['result'] == 'localFixture'),
      isNotEmpty,
    );
    await close([tab, keeper]);
  }

  Future<void> backgroundScenario() async {
    late InAppWebViewController background;
    await phase('backgroundOpen', () async {
      await fixture.installControlled(installedBackgroundId, background: true);
      await reloadPlugins();
      await wait(
        () => PluginLazyActivationService.instance.queueTargetedEvent(
          installedBackgroundId,
          'app.startup',
          {},
        ),
        'Actual lazy background activation',
      );
      await wait(
        () =>
            dispatcher.controllerOf(
              installedBackgroundId,
              instanceId: PluginInstanceIds.background,
            ) !=
            null,
        'PluginBackgroundHost controller',
      );
      background = dispatcher.controllerOf(
        installedBackgroundId,
        instanceId: PluginInstanceIds.background,
      )!;
      final elapsed = Stopwatch()..start();
      while (true) {
        final js = await readController(background);
        if (js['ready'] == true) {
          expect(
            (js['boot'] as Map)['app'],
            containsPair('runMode', 'background'),
          );
          phaseRecord('backgroundOpen')['observation'] = {
            'document': js,
            'nativeViewId': background.getViewId()?.toString(),
            'backend': observeWebViewBackend(background),
          };
          break;
        }
        if (elapsed.elapsed >= _deadline) {
          throw TimeoutException('Actual background SDK boot');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(resources()['backgroundLive'], 1);
    });
    await phase('backgroundIdle', () async {
      await quiet('backgroundIdle');
      expect(
        identical(
          background,
          dispatcher.controllerOf(
            installedBackgroundId,
            instanceId: PluginInstanceIds.background,
          ),
        ),
        true,
      );
    });
    await phase('backgroundClose', () async {
      await evaluate(
        background,
        'window.installedPluginProbe.command("background-finish", "backgroundDone", {})',
      );
      // Preserve native/SDK evidence on a real teardown failure. Do not
      // accept a JS acknowledgement as proof of controller disposal.
      try {
        await wait(
          () =>
              dispatcher.controllerOf(
                installedBackgroundId,
                instanceId: PluginInstanceIds.background,
              ) ==
              null,
          'Actual backgroundDone SDK teardown',
        );
      } catch (error, stack) {
        final liveController = dispatcher.controllerOf(
          installedBackgroundId,
          instanceId: PluginInstanceIds.background,
        );
        final evidence = <String, Object?>{
          'controllerStillRegistered': liveController != null,
          'resources': resources(),
          'failure': error.toString(),
        };
        if (liveController != null) {
          try {
            // Includes the real JS command ack, bridge request/reply counts,
            // and any unhandled SDK error, not a synthetic pass condition.
            evidence['document'] = await readController(liveController);
          } catch (snapshotError) {
            evidence['documentReadError'] = snapshotError.toString();
          }
        }
        phaseRecord('backgroundClose')['failureEvidence'] = evidence;
        Error.throwWithStackTrace(error, stack);
      }
      await PluginRegistryRepository().saveEnabledChoice(
        installedBackgroundId,
        false,
      );
      await reloadPlugins();
      expect(resources()['backgroundLive'], 0);
    });
  }
}

class _Before {
  _Before(this.tab, this.controller, this.identity, this.js, this.saved);
  final ToolTab tab;
  final InAppWebViewController controller;
  final Map<String, Object?> identity;
  final Map<String, Object?> js;
  final Object? saved;
  Map<String, Object?>? released;
}
