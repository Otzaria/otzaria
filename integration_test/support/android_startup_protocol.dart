import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const androidStartupProbePackage = 'org.otzaria.otzaria.startupprobe';
const androidStartupProbeDirectory = 'android-webview-startup-probe';
const androidStartupProbePlugin = 'org.otzaria.android-startup-fixture';
const androidStartupProbeEvent = 'probe.android_startup';

enum AndroidStartupCase { noEnabled, noOpen, foreground, background, overlap }

enum AndroidPrewarmMode { native, bypass }

class AndroidStartupTimings {
  AndroidStartupTimings(this._binding, this._callback);

  final SchedulerBinding _binding;
  final TimingsCallback _callback;
  bool _registered = false;

  void start() {
    if (_registered) throw StateError('Frame timings are already registered.');
    _binding.addTimingsCallback(_callback);
    _registered = true;
  }

  void stop() {
    if (!_registered) return;
    _binding.removeTimingsCallback(_callback);
    _registered = false;
  }
}

class AndroidStartupConfig {
  AndroidStartupConfig.fromJson(Map<String, dynamic> json) {
    const keys = {
      'schemaVersion',
      'campaignId',
      'runId',
      'fixtureId',
      'operation',
      'scenario',
      'prewarmMode',
      'fixtureState',
      'buildMode',
      'observationMs',
      'signalPort',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json.length != keys.length ||
        json['schemaVersion'] != 1) {
      throw const FormatException(
        'Unknown or incomplete startup probe config.',
      );
    }
    campaignId = _identifier(json['campaignId']);
    runId = _identifier(json['runId']);
    fixtureId = _identifier(json['fixtureId']);
    operation = _choice(json['operation'], const ['prepare', 'measure']);
    scenario = AndroidStartupCase.values.byName(
      _choice(json['scenario'], AndroidStartupCase.values.map((v) => v.name)),
    );
    prewarmMode = AndroidPrewarmMode.values.byName(
      _choice(
        json['prewarmMode'],
        AndroidPrewarmMode.values.map((v) => v.name),
      ),
    );
    fixtureState = _choice(json['fixtureState'], const ['prepared', 'reused']);
    buildMode = _choice(json['buildMode'], const ['debug', 'profile']);
    final duration = json['observationMs'];
    if (duration is! int || duration < 1000 || duration > 60000) {
      throw const FormatException('observationMs must be 1000..60000.');
    }
    observationMs = duration;
    final port = json['signalPort'];
    if (port is! int || port < 1 || port > 65535) {
      throw const FormatException('signalPort must be 1..65535.');
    }
    signalPort = port;
    if (operation == 'prepare' && fixtureState != 'prepared') {
      throw const FormatException('Preparation requires a new fixture.');
    }
  }

  factory AndroidStartupConfig.fromArguments(List<String> arguments) {
    if (arguments.length != 1 || arguments.single.length > 4096) {
      throw const FormatException('Pass exactly one bounded base64url config.');
    }
    final value = jsonDecode(utf8.decode(base64Url.decode(arguments.single)));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Startup probe config must be an object.');
    }
    return AndroidStartupConfig.fromJson(value);
  }

  late final String campaignId;
  late final String runId;
  late final String fixtureId;
  late final String operation;
  late final AndroidStartupCase scenario;
  late final AndroidPrewarmMode prewarmMode;
  late final String fixtureState;
  late final String buildMode;
  late final int observationMs;
  late final int signalPort;

  bool get enabledPlugin => scenario != AndroidStartupCase.noEnabled;
  bool get opensPlugin => ![
    AndroidStartupCase.noEnabled,
    AndroidStartupCase.noOpen,
  ].contains(scenario);

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'campaignId': campaignId,
    'runId': runId,
    'fixtureId': fixtureId,
    'operation': operation,
    'scenario': scenario.name,
    'prewarmMode': prewarmMode.name,
    'fixtureState': fixtureState,
    'buildMode': buildMode,
    'observationMs': observationMs,
    'signalPort': signalPort,
  };

  static String _identifier(Object? value) {
    if (value is! String ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{7,63}$').hasMatch(value)) {
      throw const FormatException('Invalid startup probe identifier.');
    }
    return value;
  }

  static String _choice(Object? value, Iterable<String> choices) {
    if (value is! String || !choices.contains(value)) {
      throw const FormatException('Invalid startup probe option.');
    }
    return value;
  }
}

class AndroidStartupSignals {
  AndroidStartupSignals._(
    this.config,
    this.bootId,
    this.processId,
    this._socket,
  ) {
    _socket.listen(
      (_) => _transportError ??= StateError('Unexpected host signal data.'),
      onError: (Object error) => _transportError ??= error,
      onDone: () =>
          _transportError ??= StateError('Host signal channel closed.'),
    );
    _socket.done.ignore();
  }

  final AndroidStartupConfig config;
  final String bootId;
  final int processId;
  final Socket _socket;
  Object? _transportError;

  static Future<AndroidStartupSignals> connect(
    AndroidStartupConfig config,
    String bootId,
    int processId,
  ) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      config.signalPort,
      timeout: const Duration(seconds: 10),
    );
    final signals = AndroidStartupSignals._(config, bootId, processId, socket);
    try {
      await signals._send('connected', reportAvailable: false);
      return signals;
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  Future<void> publish(String event, Future<void> Function() persist) async {
    await persist();
    await _send(event, reportAvailable: true);
  }

  Future<void> failedCompletion(Object error) => _send(
    'completion',
    reportAvailable: false,
    error: String.fromCharCodes(error.toString().runes.take(512)),
  );

  Future<void> _send(
    String event, {
    required bool reportAvailable,
    String? error,
  }) async {
    if (_transportError case final error?) throw error;
    _socket.write(
      '${jsonEncode({
        'schemaVersion': 1,
        'campaignId': config.campaignId,
        'runId': config.runId,
        'bootId': bootId,
        'pid': processId,
        'event': event,
        'reportAvailable': reportAvailable,
        'error': error,
      })}\n',
    );
    await _socket.flush().timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    try {
      await _socket.close().timeout(const Duration(seconds: 5));
    } finally {
      _socket.destroy();
    }
  }
}

class AndroidPrewarmObservation {
  AndroidPrewarmObservation({
    required this.mode,
    required this.elapsedMicros,
    required this.nativePrewarm,
  });

  final AndroidPrewarmMode mode;
  final int Function() elapsedMicros;
  final Future<WebViewEnvironmentPrewarmResult?> Function(
    WebViewEnvironmentSettings,
  )
  nativePrewarm;
  final List<Map<String, Object?>> _attempts = [];
  int invocations = 0;
  int nativeInvocations = 0;
  int _pending = 0;
  bool get pending => _pending != 0;

  Future<WebViewEnvironmentPrewarmResult?> observe(
    WebViewEnvironmentSettings settings,
  ) async {
    invocations++;
    final record = <String, Object?>{
      'enteredAtUs': elapsedMicros(),
      'settingsMatchAndroidDefaults':
          jsonEncode(settings.toMap()) ==
          jsonEncode(WebViewEnvironmentSettings().toMap()),
      'nativeCalled': mode == AndroidPrewarmMode.native,
      'status': mode == AndroidPrewarmMode.native
          ? 'pending'
          : 'bypassedForProbe',
    };
    if (_attempts.length < 4) _attempts.add(record);
    if (mode == AndroidPrewarmMode.bypass) {
      record['completedAtUs'] = elapsedMicros();
      return const WebViewEnvironmentPrewarmResult(
        status: 'bypassed_for_probe',
        duration: Duration.zero,
      );
    }
    nativeInvocations++;
    _pending++;
    try {
      final result = await nativePrewarm(settings);
      record['status'] = result?.status ?? 'unsupported';
      record['nativeDurationMs'] = result?.duration.inMilliseconds;
      record['nativeErrorCode'] = result?.errorCode;
      return result;
    } catch (error) {
      record['status'] = 'exception';
      record['errorType'] = error.runtimeType.toString();
      rethrow;
    } finally {
      _pending--;
      record['completedAtUs'] = elapsedMicros();
    }
  }

  Map<String, Object?> snapshot() => {
    'mode': mode.name,
    'invocations': invocations,
    'nativeInvocations': nativeInvocations,
    'pending': pending,
    'attempts': [for (final value in _attempts) Map<String, Object?>.of(value)],
    'attemptsTruncated': invocations > _attempts.length,
  };
}

String androidStartupOverlap({
  required AndroidPrewarmMode mode,
  required bool requested,
  required bool nativePendingAtRequest,
}) => !requested
    ? 'notRequested'
    : mode == AndroidPrewarmMode.bypass
    ? 'notApplicableToBypass'
    : nativePendingAtRequest
    ? 'observedAtRequest'
    : 'notObserved';
