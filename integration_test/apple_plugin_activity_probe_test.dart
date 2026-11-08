// Opt-in actual-app experiment. See tool/perf_probe/apple_plugin_activity/README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
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
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/view/plugin_background_host.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../tool/perf_probe/apple_plugin_activity/contract.dart';
import 'support/apple_plugin_activity_fixture.dart';
import 'support/installed_plugin_completion.dart';
import 'support/ios_simulator_vm_service.dart';
import 'support/perf_fixture.dart';
import 'support/perf_recorder.dart' show perfBuildMode;
import 'support/webview_probe_window.dart';

const _phaseNames = [
  'visible',
  'offstage',
  'minimize',
  'hide',
  'neverShownBackground',
  'osBackground',
  'idleExpiryControl',
];
const _deadline = Duration(seconds: 45);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final appBoot = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  final report = <String, dynamic>{
    'schemaVersion': 1,
    'status': 'running',
    'runId': const String.fromEnvironment('APPLE_QUIET_RUN_ID'),
    'hostPid': pid,
    'hostExecutable': Platform.resolvedExecutable,
    'appBootToken': appBoot,
    'platform': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'buildMode': perfBuildMode,
    'dartVersion': Platform.version,
    'flutterVersion': const String.fromEnvironment('APPLE_QUIET_FLUTTER'),
    'commit': const String.fromEnvironment('APPLE_QUIET_COMMIT'),
    'nativeFork': const String.fromEnvironment('APPLE_QUIET_NATIVE_FORK'),
    'fixtureSha256': appleActivityFixtureSha256,
    'physicalDeviceAcceptance': false,
    'physicalDevice': const bool.fromEnvironment('APPLE_QUIET_EXTERNAL'),
    'observers': {
      'flutterDriver': !const bool.fromEnvironment('APPLE_QUIET_EXTERNAL'),
      'vmServiceBuiltIn': perfBuildMode != 'release',
      'flutterTestFramePolicy': 'fullyLive',
      'framePolicyScope':
          'Real Flutter frames are allowed; integration-test scheduling is observer overhead, not a production baseline.',
      'developerDiagnostics': false,
      'quietCoordination':
          'one completed HTTP arm; disconnected until deadline',
      'nativeProcessListing': 'none; verified host PID only at boundaries',
      'nativeEnginePid': 'unavailable: no public per-WKWebView PID getter',
      'productionTimers': 'unchanged',
    },
    'platformMatrix': createAppleActivityPlatformMatrix(),
    'phases': [
      for (final name in _phaseNames)
        <String, dynamic>{
          'name': name,
          'status': 'notRun',
          'reason': 'Not reached.',
        },
    ],
    'errors': <String>[],
    'lifecycle': <Map<String, Object?>>[],
  };
  binding.reportData = {'applePluginActivity': report};
  final protocol = _Protocol();
  File? localReport;
  final finished = Completer<void>();
  registerInstalledPluginReportFinalizer(binding, (passed) async {
    try {
      await finished.future.timeout(const Duration(seconds: 30));
      finalizeAppleActivityReport(
        report,
        frameworkPassed: passed,
        failureDetails: binding.failureMethodsDetails.map(
          (failure) => failure.details,
        ),
        platform: Platform.operatingSystem,
        buildMode: perfBuildMode,
      );
      await localReport?.writeAsString(jsonEncode(report), flush: true);
      if (const bool.fromEnvironment('APPLE_QUIET_EXTERNAL')) {
        await protocol.post('framework-complete', report);
      }
    } catch (error) {
      (report['errors'] as List).add('Final report completion failed: $error');
      finalizeAppleActivityReport(
        report,
        frameworkPassed: false,
        failureDetails: binding.failureMethodsDetails.map(
          (failure) => failure.details,
        ),
        platform: Platform.operatingSystem,
        buildMode: perfBuildMode,
      );
      rethrow;
    }
  });

  testWidgets('Apple scheduling through installed Otzaria plugin hosts', (
    tester,
  ) async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      report['status'] = 'notSupported';
      finished.complete();
      return;
    }
    final oldFlutterError = FlutterError.onError;
    final oldPlatformError = PlatformDispatcher.instance.onError;
    final oldFailureFileLog = debugForcePluginWebViewFailureFileLog;
    final lifecycle = _Lifecycle(
      report['lifecycle'] as List<Map<String, Object?>>,
    );
    Object? failure;
    StackTrace? failureStack;
    WidgetsBinding.instance.addObserver(lifecycle);
    try {
      // A new private directory always precedes app.main. No production data,
      // settings, startup policy, idle timeout or discard limits are modified.
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      final root = await Directory(temp).createTemp('otzaria-apple-quiet-');
      final fixture = PerfFixture(Directory(p.join(root.path, 'data')));
      await fixture.prepare(preparationOnly: true);
      localReport = File(p.join(root.path, 'apple-plugin-activity.json'));
      report['isolatedRoot'] = root.path;
      report['dataFixture'] = fixture.id;
      await localReport!.writeAsString(jsonEncode(report), flush: true);
      debugForcePluginWebViewFailureFileLog = true;
      app.main(const []);
      await _wait(
        () =>
            find.byType(App).evaluate().isNotEmpty &&
            StartupTimeline.instance.toJson()['revealMs'] is int,
        'actual app reveal',
        timeout: const Duration(minutes: 3),
      );
      if (Platform.isIOS &&
          perfBuildMode == 'debug' &&
          !const bool.fromEnvironment('APPLE_QUIET_EXTERNAL')) {
        await binding.waitUntilFirstFrameRasterized;
        report['startupFirstFrameRasterized'] = binding.firstFrameRasterized;
        report.addAll(await iosSimulatorVmService());
        await protocol.post('checkpoint', report);
      }
      FlutterError.onError = (details) {
        (report['errors'] as List).add(details.exceptionAsString());
        oldFlutterError?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        (report['errors'] as List).add('$error');
        oldFlutterError?.call(
          FlutterErrorDetails(exception: error, stack: stack),
        );
        return true;
      };
      if (DeveloperDiagnostics.instance.isCollecting) {
        throw StateError(
          'Periodic diagnostics must be off for quiet collection.',
        );
      }
      if (PluginLazyActivationService.instance.idleDelayOverride != null) {
        throw StateError('The real idle timeout must not be overridden.');
      }
      report['backgroundIdleTimeoutMs'] =
          PluginLazyActivationService.idleTeardownDelay.inMilliseconds;
      await prepareWebViewProbeWindow(
        platform: Platform.operatingSystem,
        pumpFrame: () => tester.pump(),
      );
      final context = tester.element(find.byType(App));
      final scenario = _Scenario(context, fixture, report, protocol, appBoot);
      await scenario.install(appleForegroundId);
      final tab = ToolTab(
        toolId: appleForegroundId,
        title: 'Apple activity fixture',
      );
      context.read<TabsBloc>().add(AddTab(tab));
      scenario.navigate(Screen.reading);
      final foreground = (
        pluginId: appleForegroundId,
        instanceId: tab.instanceId,
      );
      await scenario.ready(foreground, 'foreground');
      if (find.byType(PluginTabPage, skipOffstage: false).evaluate().isEmpty) {
        throw StateError('The fixture did not use PluginTabPage.');
      }
      final settings = analyzeAppleFixtureSettings({
        'observedAtMs': DateTime.now().millisecondsSinceEpoch,
        'storeInitialized': Settings.isInitialized,
        if (Settings.isInitialized) ...{
          'defaultsInitialized': Settings.getValue<bool>(
            'settings_initialized',
          ),
          'offlineMode': Settings.getValue<bool>(
            SettingsRepository.keyOfflineMode,
          ),
          'updatesEnabled': Settings.getValue<bool>(
            SettingsRepository.keySoftwareAndBookUpdatesEnabled,
          ),
          'autoUpdateIndex': Settings.getValue<bool>(
            SettingsRepository.keyAutoUpdateIndex,
          ),
          'indexUpdateMode': Settings.getValue<String>(
            SettingsRepository.keyIndexUpdateMode,
          ),
          'autoSync': Settings.getValue<bool>(SettingsRepository.keyAutoSync),
          'appCrashReportMode': Settings.getValue<String>(
            SettingsRepository.keyAppCrashReportMode,
          ),
          'autoBackupFrequency': Settings.getValue<String>(
            'key-auto-backup-frequency',
          ),
          'showLocalHebrewBooks': Settings.getValue<bool>(
            SettingsRepository.keyShowLocalHebrewBooks,
          ),
          'fontFamily': Settings.getValue<String>(
            SettingsRepository.keyFontFamily,
          ),
          'fontSize': Settings.getValue<double>(SettingsRepository.keyFontSize),
        },
      });
      report['settingsAfterStartup'] = settings;
      await protocol.post('checkpoint', report);
      if (settings['status'] != 'passed') {
        throw StateError(
          'Fixture settings changed before quiet: ${settings['mismatches']}',
        );
      }
      await scenario.phase('visible', [foreground], shown: true);
      await scenario.phase(
        'offstage',
        [foreground],
        shown: false,
        visibility: (
          hide: () async => scenario.navigate(Screen.library),
          show: () async {
            scenario.navigate(Screen.reading);
            await scenario.waitShown(foreground, true);
          },
        ),
      );
      if (Platform.isMacOS) {
        await windowManager.minimize();
        await _waitAsync(windowManager.isMinimized, 'native window minimized');
        await scenario.phase('minimize', [foreground], shown: false);
        await windowManager.hide();
        await _waitAsync(
          () async => !await windowManager.isVisible(),
          'native window hidden',
        );
        await scenario.phase('hide', [foreground], shown: false);
      } else {
        for (final name in ['minimize', 'hide']) {
          scenario.record(name).addAll({
            'status': 'notSupported',
            'reason':
                'Desktop window operations; iOS Home is a separate phase.',
          });
        }
      }
      await scenario.install(
        appleKeepAliveId,
        background: true,
        keepAlive: true,
      );
      const background = (
        pluginId: appleKeepAliveId,
        instanceId: PluginInstanceIds.background,
      );
      await scenario.ready(background, 'background');
      if (find
          .byType(PluginBackgroundHost, skipOffstage: false)
          .evaluate()
          .isEmpty) {
        throw StateError('The fixture did not use PluginBackgroundHost.');
      }
      await scenario.phase('neverShownBackground', [background]);
      await scenario.phase('osBackground', [
        foreground,
        background,
      ], action: Platform.isIOS ? 'iosHome' : 'macAppHide');

      // Real three-minute expiry, not an accelerated test override. This page
      // has the same JS work, without either keepAlive declaration or grant.
      await scenario.install(appleIdleControlId, background: true);
      const idle = (
        pluginId: appleIdleControlId,
        instanceId: PluginInstanceIds.background,
      );
      await scenario.ready(idle, 'background');
      await scenario.phase(
        'idleExpiryControl',
        [background, idle],
        seconds: 190,
        expectedDisposed: idle,
      );
      await protocol.post('checkpoint', report);
      if ((report['errors'] as List).isNotEmpty) {
        throw StateError(
          'The app recorded framework errors during collection.',
        );
      }
      report['status'] = 'collected';
    } catch (error, stack) {
      report['status'] = 'failed';
      (report['errors'] as List).add('$error');
      failure = error;
      failureStack = stack;
    } finally {
      WidgetsBinding.instance.removeObserver(lifecycle);
      FlutterError.onError = oldFlutterError;
      PlatformDispatcher.instance.onError = oldPlatformError;
      debugForcePluginWebViewFailureFileLog = oldFailureFileLog;
      try {
        if (report['status'] == 'collected') {
          report['status'] = 'passed';
          (report['platformMatrix'] as Map)[Platform.operatingSystem] = {
            'status': 'passed',
            'buildMode': perfBuildMode,
            'physicalDeviceAcceptance': false,
          };
          // Send scenario completion before the driver can close the app.
          // The outer runner separately requires flutter drive exit 0, which
          // includes framework failures discovered after this test body.
          await protocol.post('complete', report);
        }
        await localReport?.writeAsString(jsonEncode(report), flush: true);
      } catch (error, stack) {
        report['status'] = 'failed';
        (report['errors'] as List).add('Scenario completion failed: $error');
        failure ??= error;
        failureStack ??= stack;
      } finally {
        finished.complete();
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _Lifecycle extends WidgetsBindingObserver {
  _Lifecycle(this.events);
  final List<Map<String, Object?>> events;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => events.add({
    'state': state.name,
    'receivedAtMs': DateTime.now().millisecondsSinceEpoch,
    'scope': 'Dart delivery time, not proof of an exact OS transition time',
  });
}

class _Protocol {
  final uri = Uri.parse(
    const String.fromEnvironment('APPLE_QUIET_COORDINATOR'),
  );
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw StateError('Use the Apple quiet runner to supply its coordinator.');
    }
    final client = HttpClient()..connectionTimeout = _deadline;
    try {
      final request = await client.postUrl(uri.resolve('/$endpoint'));
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(
        'X-Apple-Quiet-Token',
        const String.fromEnvironment('APPLE_QUIET_TOKEN'),
      );
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
      final response = await request.close().timeout(_deadline);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_deadline);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'Coordinator $endpoint failed: ${response.statusCode} $text',
        );
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}

class _Scenario {
  _Scenario(
    this.context,
    this.fixture,
    this.report,
    this.protocol,
    this.appBoot,
  );
  final BuildContext context;
  final PerfFixture fixture;
  final Map<String, dynamic> report;
  final _Protocol protocol;
  final String appBoot;
  final dispatcher = PluginRuntimeDispatcher.instance;
  final controllerIds = Expando<int>();
  var nextControllerId = 0;
  Map<String, dynamic> record(String name) => (report['phases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == name);

  void navigate(Screen screen) =>
      context.read<NavigationBloc>().add(NavigateToScreen(screen));

  Future<void> install(
    String id, {
    bool background = false,
    bool keepAlive = false,
  }) async {
    await installAppleActivityFixture(
      fixture.root,
      id,
      background: background,
      keepAlive: keepAlive,
    );
    final grants = await PluginRegistryRepository().getGrantedPermissionNames(
      id,
    );
    if (grants.contains('app.background_keep_alive') != keepAlive) {
      throw StateError('Keep-alive permission does not match the fixture.');
    }
    final bloc = context.read<PluginSystemBloc>();
    bloc.add(LoadPlugins());
    await _wait(
      () =>
          bloc.state is PluginSystemLoaded &&
          (bloc.state as PluginSystemLoaded).plugins.any(
            (p) => p.pluginId == id && p.enabled,
          ),
      'installed registry $id',
    );
    (report['fixtures'] ??= <String, dynamic>{})[id] = {
      'startupKeepAlive': keepAlive,
      'grantedPermissions': grants,
      'everOpenedAsTab': !background,
      'activation': background
          ? 'real app.startup lazy activation'
          : 'AddTab(ToolTab)',
    };
  }

  InAppWebViewController? controller(PluginInstanceKey key) =>
      dispatcher.controllerOf(key.pluginId, instanceId: key.instanceId);

  Future<Map<String, dynamic>> read(
    InAppWebViewController controller,
    String source,
  ) async {
    final result = await controller
        .evaluateJavascript(source: 'JSON.stringify($source)')
        .timeout(_deadline);
    if (result is! String) {
      throw StateError('No fixture result from JavaScript.');
    }
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Future<void> ready(PluginInstanceKey key, String runMode) async {
    await _wait(() => controller(key) != null, 'real controller $key');
    final clock = Stopwatch()..start();
    while (true) {
      final result = await read(
        controller(key)!,
        'window.appleActivity?.read() ?? {}',
      );
      if ((result['errors'] as List?)?.isNotEmpty ?? false) {
        throw StateError(
          'Fixture JavaScript failed before readiness: ${result['errors']}',
        );
      }
      if (result['ready'] == true) {
        if ((result['boot'] as Map)['runMode'] != runMode ||
            result['bootCount'] != 1) {
          throw StateError('Incorrect SDK boot/run mode for $key');
        }
        if (runMode == 'background') {
          await _wait(
            () =>
                PluginLazyActivationService.instance.canTeardown(key.pluginId),
            'background boot and SDK work complete',
          );
        }
        return;
      }
      if (clock.elapsed >= _deadline) {
        throw TimeoutException('Actual SDK boot $key');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> identity(InAppWebViewController controller) => {
    'hostPid': pid,
    'appBootToken': appBoot,
    'controllerToken': controllerIds[controller] ??= ++nextControllerId,
  };

  Future<void> waitShown(PluginInstanceKey key, bool shown) => _wait(() {
    final instances =
        dispatcher.describeForegroundResources()['instances'] as List;
    final state = instances
        .cast<Map>()
        .where(
          (instance) =>
              instance['pluginId'] == key.pluginId &&
              instance['instanceId'] == key.instanceId,
        )
        .firstOrNull;
    return dispatcher.isInstanceShown(key) == shown &&
        state?['suspensionState'] == (shown ? 'active' : 'hidden');
  }, 'dispatcher shown=$shown and lifecycle transition complete');

  Future<Map<String, dynamic>> nativeBoundary(
    InAppWebViewController controller,
  ) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    final clock = Stopwatch()..start();
    final native = await controller.getAppleWebViewActivitySnapshot().timeout(
      _deadline,
    );
    final end = DateTime.now().millisecondsSinceEpoch;
    final result = <String, dynamic>{
      'requestStartMs': start,
      'replyMs': end,
      'elapsedMs': clock.elapsedMicroseconds / 1000,
      'captureToReplyMs': native.capturedAt == null
          ? null
          : end - native.capturedAt!.millisecondsSinceEpoch,
      'snapshot': native.toJson(),
      'scope':
          'Capture-time metadata only; a post-resume read is not historical background state.',
    };
    if (native.availability != AppleWebViewActivityAvailability.available) {
      throw StateError('The public Apple getter is unavailable: $result');
    }
    return result;
  }

  Future<void> phase(
    String name,
    List<PluginInstanceKey> keys, {
    bool? shown,
    String action = 'quiet',
    int? seconds,
    PluginInstanceKey? expectedDisposed,
    ({Future<void> Function() hide, Future<void> Function() show})? visibility,
  }) async {
    final entry = record(name)..['status'] = 'running';
    entry.remove('reason');
    final pages = <Map<String, dynamic>>[];
    entry['pages'] = pages;
    try {
      for (final key in keys) {
        final webview = controller(key);
        if (webview == null) {
          throw StateError('Missing controller before quiet: $key');
        }
        pages.add({
          'pluginId': key.pluginId,
          'instanceId': key.instanceId,
          'identityBefore': identity(webview),
          'before': await read(
            webview,
            'window.appleActivity.arm(${jsonEncode(name)})',
          ),
        });
      }
      // Arm once before hiding; the same identity and canary survive showing.
      if (visibility != null) await visibility.hide();
      if (shown != null) await waitShown(keys.first, shown);
      await Future<void>.delayed(const Duration(seconds: 1));
      entry['windowBefore'] = await readWebViewProbeWindow(
        Platform.operatingSystem,
      );
      for (var i = 0; i < keys.length; i++) {
        final webview = controller(keys[i]);
        if (webview == null) {
          throw StateError('Controller disposed before quiet: ${keys[i]}');
        }
        final page = pages[i];
        final beforeQuietIdentity = identity(webview);
        if (visibility != null) {
          page['identityWhileHidden'] = beforeQuietIdentity;
        }
        verifyAppleRuntimeIdentity(
          page['identityBefore'] as Map<String, dynamic>,
          beforeQuietIdentity,
        );
        if (visibility != null) {
          page['whileHidden'] = await read(
            webview,
            'window.appleActivity.read()',
          );
          verifyAppleDocumentIdentity(
            page['before'] as Map<String, dynamic>,
            page['whileHidden'] as Map<String, dynamic>,
          );
        }
        page['nativeBefore'] = await nativeBoundary(webview);
      }
      entry['dispatcherBefore'] = dispatcher.describeForegroundResources();
      if (DeveloperDiagnostics.instance.isCollecting) {
        throw StateError('Periodic diagnostics became active.');
      }
      await protocol.post('checkpoint', report);
      final duration =
          seconds ??
          const int.fromEnvironment('APPLE_QUIET_SECONDS', defaultValue: 12);
      final prepared = await protocol.post('prepare', {
        'hostPid': pid,
        'appBootToken': appBoot,
        'runId': report['runId'],
      });
      entry['controllerPreparation'] = prepared;
      final armStart = DateTime.now().millisecondsSinceEpoch;
      final arm = await protocol.post('arm', {
        ...prepared,
        'phase': name,
        'action': action,
        'seconds': duration,
        'hostPid': pid,
        'appBootToken': appBoot,
        'runId': report['runId'],
        'platform': Platform.operatingSystem,
      });
      final armEnd = DateTime.now().millisecondsSinceEpoch;
      entry['arm'] = {
        'requestStartMs': armStart,
        'requestEndMs': armEnd,
        ...arm,
      };
      // The arm connection is closed. No probe JS/IPC, polling or samples run
      // during this wait; the product's timers remain unchanged.
      await Future<void>.delayed(Duration(milliseconds: arm['waitMs'] as int));
      final driver = await protocol.post('result', {'jobId': arm['jobId']});
      entry['driver'] = driver;
      if (action != 'quiet') {
        entry['nativeHistoricalBackgroundState'] = {
          'status': 'unavailable',
          'reason':
              'No native getter was requested between the external OS transition and resume; before/after snapshots do not reconstruct that history.',
        };
      }
      if (driver['status'] != 'passed') {
        throw StateError('External quiet/OS action failed: ${driver['error']}');
      }
      // The quiet interval has ended externally BEFORE restoring a window or
      // delivering any app command. Resume observations are not history.
      if (Platform.isMacOS && (name == 'minimize' || name == 'hide')) {
        await windowManager.restore();
        await windowManager.show();
        await windowManager.focus();
      }
      entry['dispatcherAfter'] = dispatcher.describeForegroundResources();
      for (var i = 0; i < keys.length; i++) {
        final key = keys[i];
        final page = pages[i];
        final webview = controller(key);
        if (key == expectedDisposed) {
          page['disposedAfterQuiet'] = webview == null;
          page['cause'] =
              'idle-expiry control: no keepAlive declaration or grant';
          if (webview != null) {
            throw StateError(
              'The real three-minute idle control did not expire.',
            );
          }
          continue;
        }
        if (webview == null) {
          throw StateError('Unexpected controller disposal: $key');
        }
        page['identityAfter'] = identity(webview);
        verifyAppleRuntimeIdentity(
          page['identityBefore'] as Map<String, dynamic>,
          page['identityAfter'] as Map<String, dynamic>,
        );
        page['nativeAfterResume'] = await nativeBoundary(webview);
        // First probe-initiated JS after quiet uses the actual command route.
        // Production lifecycle/OS resume may already have woken the page.
        final nonce =
            '$name-${key.pluginId}-${DateTime.now().microsecondsSinceEpoch}';
        page['command'] = {
          'nonce': nonce,
          'startMs': DateTime.now().millisecondsSinceEpoch,
          'scope':
              'First probe-initiated JS after the external end; production lifecycle delivery is unchanged.',
        };
        await dispatcher.dispatchEventToPlugin(
          key.pluginId,
          'reader.context_menu_item_clicked',
          {'probeNonce': nonce},
          instanceId: key.instanceId,
        );
        final after = await read(webview, 'window.appleActivity.read()');
        page['afterCommand'] = after;
        (page['command'] as Map)['readEndMs'] =
            DateTime.now().millisecondsSinceEpoch;
        if (!(after['commands'] as List).any(
          (c) => (c as Map)['nonce'] == nonce,
        )) {
          throw StateError('The actual dispatcher/SDK command did not arrive.');
        }
        page['analysis'] = analyzeAppleQuietWindow(
          before: page['before'] as Map<String, dynamic>,
          after: after,
          driver: driver,
          armStartMs: armStart,
          armEndMs: armEnd,
        );
        if (name == 'visible') {
          final streams = (page['analysis'] as Map)['streams'] as Map;
          for (final stream in ['interval', 'raf', 'localAsync']) {
            if ((streams[stream] as Map)['classification'] !=
                'callbacksObservedInsideQuiet') {
              throw StateError('Visible positive control failed: $stream');
            }
          }
        }
      }
      if (visibility != null) {
        await visibility.show();
        for (var i = 0; i < keys.length; i++) {
          final webview = controller(keys[i]);
          if (webview == null) {
            throw StateError('Controller missing after showing: ${keys[i]}');
          }
          final page = pages[i];
          page['identityAfterShow'] = identity(webview);
          verifyAppleRuntimeIdentity(
            page['identityBefore'] as Map<String, dynamic>,
            page['identityAfterShow'] as Map<String, dynamic>,
          );
          page['afterShow'] = await read(
            webview,
            'window.appleActivity.read()',
          );
          verifyAppleVisibilityRoundTrip(
            (
              identity: page['identityBefore'] as Map<String, dynamic>,
              document: page['before'] as Map<String, dynamic>,
            ),
            (
              identity: page['identityWhileHidden'] as Map<String, dynamic>,
              document: page['whileHidden'] as Map<String, dynamic>,
            ),
            (
              identity: page['identityAfterShow'] as Map<String, dynamic>,
              document: page['afterShow'] as Map<String, dynamic>,
            ),
          );
          page['nativeAfterShow'] = await nativeBoundary(webview);
        }
      }
      final errorFile = ErrorLogFile.resolveFile();
      final log = await errorFile.exists()
          ? await errorFile.readAsString()
          : '';
      entry['nativeFailureLog'] = log;
      entry['nativeFailureLogScope'] =
          'Dedicated callback log; production rate limit remains. Absence is not a count of zero native exits.';
      if (log.contains('WebView process gone') ||
          RegExp(
            r'^=== (FlutterError|Unhandled Error)',
            multiLine: true,
          ).hasMatch(log)) {
        throw StateError(
          'A native WebView exit or unhandled app error was logged.',
        );
      }
      entry['status'] = 'passed';
      await protocol.post('checkpoint', report);
    } catch (error) {
      entry['status'] = 'failed';
      entry['error'] = '$error';
      rethrow;
    }
  }
}

Future<void> _wait(
  bool Function() ready,
  String description, {
  Duration timeout = _deadline,
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed >= timeout) throw TimeoutException(description, timeout);
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<void> _waitAsync(
  Future<bool> Function() ready,
  String description,
) async {
  final clock = Stopwatch()..start();
  while (!await ready().timeout(_deadline)) {
    if (clock.elapsed >= _deadline) {
      throw TimeoutException(description, _deadline);
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
