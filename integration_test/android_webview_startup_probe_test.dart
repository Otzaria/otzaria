import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/android_startup_fixture.dart';
import 'support/android_startup_protocol.dart';
import 'support/perf_recorder.dart' show frameMeasurements, perfBuildMode;

void main(List<String> arguments) {
  if (!const bool.fromEnvironment('OTZARIA_ANDROID_STARTUP_PROBE') ||
      !Platform.isAndroid) {
    throw StateError('Use the isolated Android startup probe runner.');
  }
  final config = AndroidStartupConfig.fromArguments(arguments);
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final bootId = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final bodyDone = Completer<void>();
  final report = <String, Object?>{
    'schemaVersion': 1,
    'config': config.toJson(),
    'bootId': bootId,
    'pid': pid,
    'buildMode': perfBuildMode,
    'sourceRevision': const String.fromEnvironment(
      'OTZARIA_PROBE_SOURCE_REVISION',
    ),
    'sourceDirty': const bool.fromEnvironment(
      'OTZARIA_PROBE_SOURCE_DIRTY',
      defaultValue: true,
    ),
    'flutterVersion': const String.fromEnvironment(
      'OTZARIA_PROBE_FLUTTER_VERSION',
    ),
    'dartVersion': Platform.version,
    'appMainCalled': false,
    'nativePrewarmCalls': 0,
    'physicalDeviceAcceptance': false,
  };
  Directory? output;
  Object? runError;
  AndroidStartupSignals? signals;

  unawaited(
    binding.allTestsPassed.future.then((passed) async {
      await bodyDone.future;
      var reportSaved = false;
      try {
        await signals?.publish('completion', () async {
          final directory = output;
          if (directory == null) {
            throw runError ?? StateError('Probe output was not initialized.');
          }
          await _writeAtomic(directory, 'completion.json', {
            ...report,
            'status': passed && runError == null ? 'passed' : 'failed',
            'integrationTestsPassed': passed,
            'error': runError?.toString(),
            'testFailures': [
              for (final failure in binding.failureMethodsDetails)
                failure.details,
            ],
            'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
          });
          reportSaved = true;
        });
      } catch (error, stack) {
        stderr.writeln('Startup completion publication failed: $error\n$stack');
        if (!reportSaved) await signals?.failedCompletion(runError ?? error);
      } finally {
        await signals?.close();
      }
    }),
  );

  testWidgets(
    'Android startup ${config.scenario.name}/${config.prewarmMode.name}',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      final initialFlutterError = FlutterError.onError;
      final initialPlatformError = PlatformDispatcher.instance.onError;
      final errors = <String>[];
      final clock = Stopwatch();
      final frames = <FrameTiming>[];
      var droppedFrames = 0;
      Timer? heartbeat;
      final heartbeatIntervalsUs = <int>[];
      var lastHeartbeatUs = 0;
      var heartbeatDropped = 0;
      var captureInstalled = false;
      AndroidPrewarmObservation? prewarm;

      void onTimings(List<FrameTiming> values) {
        final available = 10000 - frames.length;
        frames.addAll(values.take(available));
        if (values.length > available) {
          droppedFrames += values.length - available;
        }
      }

      final timings = AndroidStartupTimings(binding, onTimings);

      void captureErrors() {
        captureInstalled = true;
        FlutterError.onError = (details) {
          errors.add(details.exceptionAsString());
          initialFlutterError?.call(details);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          errors.add('$error');
          initialFlutterError?.call(
            FlutterErrorDetails(exception: error, stack: stack),
          );
          return true;
        };
      }

      try {
        signals = await AndroidStartupSignals.connect(config, bootId, pid);
        final package = await PackageInfo.fromPlatform();
        expect(
          package.packageName,
          androidStartupProbePackage,
          reason: 'The probe cannot write the production application data.',
        );
        expect(perfBuildMode, config.buildMode);
        final support = await getApplicationSupportDirectory();
        final anchor = await support.resolveSymbolicLinks();
        final campaign = Directory(
          p.join(anchor, androidStartupProbeDirectory, config.campaignId),
        );
        await _rejectLinksBelow(anchor, campaign.path);
        final runDirectory = Directory(
          p.join(campaign.path, 'runs', config.runId),
        );
        await _rejectLinksBelow(anchor, runDirectory.path);
        if (await runDirectory.exists()) {
          throw StateError('This probe run already exists.');
        }
        output = await runDirectory.create(recursive: true);
        report['package'] = package.packageName;
        report['appVersion'] = package.version;
        report['appBuildNumber'] = package.buildNumber;

        final fixture = AndroidStartupFixture(
          Directory(p.join(campaign.path, 'fixtures', config.fixtureId)),
          enabledPlugin: config.enabledPlugin,
        );
        if (config.operation == 'prepare') {
          await fixture.prepare();
          report['fixtureIdentity'] = fixture.identity;
          report['appSettingsInitializedBeforeMain'] = Settings.isInitialized;
          expect(Settings.isInitialized, isFalse);
          return;
        }
        report['previousFixtureLaunches'] = await fixture.openForMeasurement(
          fixtureState: config.fixtureState,
        );
        report['fixtureIdentity'] = fixture.identity;
        report['appSettingsInitializedBeforeMain'] = Settings.isInitialized;
        expect(Settings.isInitialized, isFalse);
        final errorsFile = ErrorLogFile.resolveFile();
        final errorsBefore = await errorsFile.exists()
            ? await errorsFile.readAsString()
            : '';
        prewarm = AndroidPrewarmObservation(
          mode: config.prewarmMode,
          elapsedMicros: () => clock.elapsedMicroseconds,
          nativePrewarm: (settings) =>
              WebViewEnvironment.prewarm(settings: settings),
        );
        final revealAtPrewarm = <Object?>[];
        WebViewEnvironmentHolder.debugOverridePrewarm((settings) {
          revealAtPrewarm.add(StartupTimeline.instance.toJson()['revealMs']);
          return prewarm!.observe(settings);
        });
        expect(
          WebViewEnvironmentHolder.prewarmWaitLimit,
          const Duration(seconds: 30),
        );
        final measurement = <String, Object?>{};
        report['measurement'] = measurement;
        captureErrors();
        timings.start();
        clock.start();
        heartbeat = Timer.periodic(const Duration(milliseconds: 100), (_) {
          final now = clock.elapsedMicroseconds;
          if (heartbeatIntervalsUs.length < 4000) {
            heartbeatIntervalsUs.add(now - lastHeartbeatUs);
          } else {
            heartbeatDropped++;
          }
          lastHeartbeatUs = now;
        });
        report['appMainCalled'] = true;
        measurement['appMainInvokedAtUtc'] = DateTime.now()
            .toUtc()
            .toIso8601String();
        app.main(const []);
        await _wait(
          () {
            captureErrors();
            return find.byType(App).evaluate().isNotEmpty &&
                StartupTimeline.instance.toJson()['revealMs'] != null;
          },
          'real application reveal',
          timeout: const Duration(seconds: 120),
        );
        final context = tester.element(find.byType(App));
        measurement['revealObservedAtUs'] = clock.elapsedMicroseconds;
        measurement['startupTimeline'] = StartupTimeline.instance.toJson();
        report['viewport'] = {
          'widthPhysical': tester.view.physicalSize.width,
          'heightPhysical': tester.view.physicalSize.height,
          'devicePixelRatio': tester.view.devicePixelRatio,
        };
        final plugins = context.read<PluginSystemBloc>();
        await _wait(
          () => plugins.state is PluginSystemLoaded,
          'real plugin registry loaded',
        );
        final installed = (plugins.state as PluginSystemLoaded).plugins;
        expect(
          installed.map((v) => v.pluginId).toList(),
          config.enabledPlugin ? [androidStartupProbePlugin] : isEmpty,
        );
        measurement['registeredEnabledPlugins'] = installed
            .where((v) => v.enabled)
            .length;
        await _wait(
          () => config.enabledPlugin
              ? prewarm!.invocations > 0
              : WebView2CreationDiagnostics.prewarmOutcome?.startsWith(
                      'skipped: no enabled plugin',
                    ) ==
                    true,
          'the actual deferred prewarm eligibility path',
        );

        final revealObserved = measurement['revealObservedAtUs'] as int;
        if (config.scenario != AndroidStartupCase.overlap) {
          final remainingUs =
              config.observationMs * 1000 -
              (clock.elapsedMicroseconds - revealObserved);
          if (remainingUs > 0) {
            await Future<void>.delayed(Duration(microseconds: remainingUs));
          }
        }
        final dispatcher = PluginRuntimeDispatcher.instance;
        var javascriptPolls = 0;
        Map<String, Object?>? opened;
        final pendingAtRequest = prewarm.pending;
        if (config.opensPlugin) {
          final isBackground = config.scenario == AndroidStartupCase.background;
          final tab = ToolTab(
            toolId: androidStartupProbePlugin,
            title: 'מדידת Android',
          );
          final instanceId = isBackground
              ? PluginInstanceIds.background
              : tab.instanceId;
          if (isBackground) {
            final lazy = PluginLazyActivationService.instance;
            await _wait(
              () =>
                  lazy.backgroundActivator != null &&
                  lazy.isActivationCurrent(
                    androidStartupProbePlugin,
                    lazy.activationGeneration(androidStartupProbePlugin),
                  ),
              'production background activation registration',
            );
          }
          expect(dispatcher.describeForegroundResources()['live'], 0);
          expect(dispatcher.describeForegroundResources()['backgroundLive'], 0);
          final requestedAtUs = clock.elapsedMicroseconds;
          final actuallyPending = prewarm.pending;
          opened = {
            'instanceId': instanceId,
            'requestedAtUs': requestedAtUs,
            'nativePrewarmPendingAtRequest': actuallyPending,
            'host': isBackground ? 'PluginBackgroundHost' : 'PluginTabPage',
          };
          measurement['open'] = opened;
          if (isBackground) {
            await dispatcher.dispatchEventToPlugin(
              androidStartupProbePlugin,
              androidStartupProbeEvent,
              {'runId': config.runId},
              preferBackground: true,
            );
          } else {
            context.read<TabsBloc>().add(AddTab(tab));
            context.read<NavigationBloc>().add(
              NavigateToScreen(Screen.reading),
            );
          }
          await _wait(
            () =>
                dispatcher.controllerOf(
                  androidStartupProbePlugin,
                  instanceId: instanceId,
                ) !=
                null,
            'real plugin controller attachment',
            timeout: const Duration(seconds: 75),
          );
          opened['controllerObservedAfterRequestUs'] =
              clock.elapsedMicroseconds - requestedAtUs;
          final controller = dispatcher.controllerOf(
            androidStartupProbePlugin,
            instanceId: instanceId,
          )!;
          final readyDeadline = clock.elapsed + const Duration(seconds: 45);
          while (true) {
            if (clock.elapsed > readyDeadline) {
              throw TimeoutException('Real plugin SDK readiness');
            }
            if (!identical(
              controller,
              dispatcher.controllerOf(
                androidStartupProbePlugin,
                instanceId: instanceId,
              ),
            )) {
              throw StateError(
                'The first plugin controller changed before readiness.',
              );
            }
            javascriptPolls++;
            final value = await controller
                .evaluateJavascript(
                  source:
                      'JSON.stringify(window.androidStartupFixture || null)',
                )
                .timeout(const Duration(seconds: 5));
            final document = value is String ? jsonDecode(value) : null;
            if (document is Map<String, dynamic> &&
                document['sdkBooted'] == true &&
                (isBackground
                    ? document['eventRunId'] == config.runId
                    : document['twoAnimationFrames'] == true)) {
              expect(document['boots'], 1);
              expect(document['pluginId'], androidStartupProbePlugin);
              expect(
                document['runMode'],
                isBackground ? 'background' : 'foreground',
              );
              if (isBackground) expect(document['eventCount'], 1);
              opened['document'] = document;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 16));
          }
          opened['sdkReadinessObservedAfterRequestUs'] =
              clock.elapsedMicroseconds - requestedAtUs;
          opened['readiness'] = isBackground
              ? 'realSDKBootAndTargetedEvent'
              : 'realSDKBootAndTwoAnimationFrames';
          if (!isBackground) {
            expect(dispatcher.describeForegroundResources()['live'], 1);
          }
        }
        measurement['measurementEndedAtUs'] = clock.elapsedMicroseconds;
        heartbeat.cancel();
        heartbeat = null;
        timings.stop();
        measurement.addAll({
          'prewarm': prewarm.snapshot(),
          'revealMsAtPrewarmInvocation': revealAtPrewarm,
          'coordinatorOutcome': WebView2CreationDiagnostics.prewarmOutcome,
          'open': opened,
          'overlap': androidStartupOverlap(
            mode: config.prewarmMode,
            requested: config.scenario == AndroidStartupCase.overlap,
            nativePendingAtRequest:
                opened?['nativePrewarmPendingAtRequest'] as bool? ??
                pendingAtRequest,
          ),
          'javascriptPolls': javascriptPolls,
          'javascriptPollIntervalMs': 16,
          'resources': dispatcher.describeForegroundResources(),
          'hostRssBytes': ProcessInfo.currentRss,
          'hostRssSource':
              'ProcessInfo.currentRss; host only, not PSS or native-only memory',
          'flutterFrames': {
            ...frameMeasurements(frames),
            if (frames.isEmpty)
              'unavailableReason':
                  'No frame timing callback arrived before the measurement boundary.',
            'dropped': droppedFrames,
            'scope':
                'Flutter engine frames delivered during the interval, not WebView presentation',
          },
          'dartHeartbeat': {
            'requestedIntervalMs': 100,
            'intervalsUs': heartbeatIntervalsUs,
            'dropped': heartbeatDropped,
            'scope': 'Dart isolate only; not Android UI thread',
          },
          'nativeMainThreadResponsiveness': {
            'availability': 'notCollected',
            'value': null,
          },
          'nativeCpu': {'availability': 'notCollected', 'value': null},
        });
        report['nativePrewarmCalls'] = prewarm.nativeInvocations;
        expect(prewarm.invocations, config.enabledPlugin ? 1 : 0);
        expect(
          prewarm.nativeInvocations,
          config.enabledPlugin &&
                  config.prewarmMode == AndroidPrewarmMode.native
              ? 1
              : 0,
        );
        expect(prewarm.snapshot()['attemptsTruncated'], isFalse);
        for (final attempt in prewarm.snapshot()['attempts'] as List) {
          expect((attempt as Map)['settingsMatchAndroidDefaults'], isTrue);
        }
        if (!config.opensPlugin) {
          expect(dispatcher.describeForegroundResources()['live'], 0);
          expect(dispatcher.describeForegroundResources()['backgroundLive'], 0);
          expect(javascriptPolls, 0);
        }
        final errorsAfter = await errorsFile.exists()
            ? await errorsFile.readAsString()
            : '';
        final addedErrors = errorsAfter.startsWith(errorsBefore)
            ? errorsAfter.substring(errorsBefore.length)
            : errorsAfter;
        expect(
          RegExp(
            r'^=== (FlutterError|Unhandled Error)',
            multiLine: true,
          ).hasMatch(addedErrors),
          isFalse,
        );
        expect(errors, isEmpty);

        await signals!.publish(
          'ready',
          () => _writeAtomic(output!, 'ready.json', {
            ...report,
            'status': 'awaitingHostSample',
          }),
        );
        final ack = File(p.join(output!.path, 'sample-ack.json'));
        await _wait(
          () => ack.existsSync(),
          'external host memory sample acknowledgement',
          timeout: const Duration(seconds: 60),
          interval: const Duration(milliseconds: 100),
        );
        final acknowledged = jsonDecode(await ack.readAsString()) as Map;
        expect(acknowledged, {'runId': config.runId, 'bootId': bootId});
        report['hostSampleAcknowledgedAtUs'] = clock.elapsedMicroseconds;
        report['prewarmAfterHostSample'] = prewarm.snapshot();
        expect(errors, isEmpty);
      } catch (error, stack) {
        runError = error;
        report['failureStack'] = stack.toString();
        report['partialPrewarm'] = prewarm?.snapshot();
        rethrow;
      } finally {
        heartbeat?.cancel();
        timings.stop();
        WebViewEnvironmentHolder.debugOverridePrewarm(null);
        if (captureInstalled) {
          FlutterError.onError = initialFlutterError;
          PlatformDispatcher.instance.onError = initialPlatformError;
        }
        bodyDone.complete();
      }
    },
  );
}

Future<void> _wait(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 40),
  Duration interval = const Duration(milliseconds: 16),
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > timeout) throw TimeoutException(description);
    await Future<void>.delayed(interval);
  }
}

Future<void> _writeAtomic(
  Directory directory,
  String name,
  Map<String, Object?> value,
) async {
  final temporary = File(p.join(directory.path, '$name.pending'));
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(p.join(directory.path, name));
}

Future<void> _rejectLinksBelow(String anchor, String path) async {
  if (!p.isWithin(anchor, path)) {
    throw StateError('Probe path escaped application support.');
  }
  var current = path;
  while (current != anchor) {
    if (await FileSystemEntity.isLink(current)) {
      throw StateError('Probe path contains a symlink.');
    }
    current = p.dirname(current);
  }
}
