import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:path/path.dart' as p;

/// How diagnostics were requested at launch.
enum DiagnosticsLaunchMode { off, panel, logOnly }

const String devDiagnosticsFlag = 'dev-diagnostics';
const String devDiagnosticsEnv = 'OTZARIA_DEV_DIAGNOSTICS';
const String devDiagnosticsOutEnv = 'OTZARIA_DEV_DIAGNOSTICS_OUT';

/// Reads `--dev-diagnostics[=log]` from [args], falling back to the
/// `OTZARIA_DEV_DIAGNOSTICS` environment variable (`1`, `panel` or `log`).
DiagnosticsLaunchMode parseDiagnosticsLaunchMode(
  List<String> args,
  Map<String, String> environment,
) {
  for (final raw in args) {
    final arg = raw
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^(--|/)'), '')
        .replaceAll('_', '-');
    if (arg == devDiagnosticsFlag) return DiagnosticsLaunchMode.panel;
    if (arg == '$devDiagnosticsFlag=log') return DiagnosticsLaunchMode.logOnly;
  }
  return switch (environment[devDiagnosticsEnv]?.trim().toLowerCase()) {
    '1' || 'true' || 'panel' => DiagnosticsLaunchMode.panel,
    'log' => DiagnosticsLaunchMode.logOnly,
    _ => DiagnosticsLaunchMode.off,
  };
}

/// One presented frame, in milliseconds.
@immutable
class FrameSample {
  const FrameSample(this.buildMs, this.rasterMs, this.totalMs);

  final double buildMs;
  final double rasterMs;
  final double totalMs;
}

/// Frame statistics over the sliding window shown in the panel and logged.
@immutable
class FrameStats {
  const FrameStats({
    this.framesPerSecond = 0,
    this.buildAvgMs,
    this.buildMaxMs,
    this.rasterAvgMs,
    this.rasterMaxMs,
    this.slowInWindow = 0,
    this.slowTotal = 0,
    this.rssMb = 0,
    this.peakRssMb = 0,
    this.topRebuilds = const [],
  });

  final int framesPerSecond;
  final double? buildAvgMs;
  final double? buildMaxMs;
  final double? rasterAvgMs;
  final double? rasterMaxMs;
  final int slowInWindow;
  final int slowTotal;
  final int rssMb;
  final int peakRssMb;

  /// Widget types rebuilt most often in the window. Debug builds only.
  final List<MapEntry<String, int>> topRebuilds;

  Map<String, Object?> toJson() => {
    'fps': framesPerSecond,
    'buildAvgMs': buildAvgMs,
    'buildMaxMs': buildMaxMs,
    'rasterAvgMs': rasterAvgMs,
    'rasterMaxMs': rasterMaxMs,
    'slowInWindow': slowInWindow,
    'slowTotal': slowTotal,
    'rssMb': rssMb,
    'peakRssMb': peakRssMb,
    if (topRebuilds.isNotEmpty)
      'rebuilds': {for (final e in topRebuilds) e.key: e.value},
  };
}

/// Computes window statistics from [samples] presented during [window].
FrameStats computeFrameStats(
  List<FrameSample> samples, {
  required Duration window,
  required int slowTotal,
  int rssMb = 0,
  int peakRssMb = 0,
  List<MapEntry<String, int>> topRebuilds = const [],
}) {
  double? avg(Iterable<double> v) =>
      v.isEmpty ? null : _round1(v.reduce((a, b) => a + b) / v.length);
  double? max(Iterable<double> v) =>
      v.isEmpty ? null : _round1(v.reduce((a, b) => a > b ? a : b));
  final build = samples.map((s) => s.buildMs);
  final raster = samples.map((s) => s.rasterMs);
  return FrameStats(
    framesPerSecond: (samples.length * 1000 / window.inMilliseconds).round(),
    buildAvgMs: avg(build),
    buildMaxMs: max(build),
    rasterAvgMs: avg(raster),
    rasterMaxMs: max(raster),
    slowInWindow: samples
        .where((s) => s.totalMs > DeveloperDiagnostics.frameBudgetMs)
        .length,
    slowTotal: slowTotal,
    rssMb: rssMb,
    peakRssMb: peakRssMb,
    topRebuilds: topRebuilds,
  );
}

double _round1(double v) => (v * 10).round() / 10;

/// Collects frame, memory, startup and (in debug builds) rebuild data while
/// developer mode is on, and appends it as JSON lines to [outputPath].
///
/// Developer mode is turned on at launch (`--dev-diagnostics`) or at runtime
/// with Ctrl+Shift+I, and is never persisted.
///
/// Nothing is registered or written while it is off.
class DeveloperDiagnostics {
  DeveloperDiagnostics._();

  static final DeveloperDiagnostics instance = DeveloperDiagnostics._();

  static const Duration window = Duration(seconds: 2);
  static const double frameBudgetMs = 1000 / 60;

  /// A frame this slow is logged on its own, with the app context.
  static const double slowFrameLogMs = 100;

  DiagnosticsLaunchMode _launchMode = DiagnosticsLaunchMode.off;
  bool _toggledOn = false;
  bool _running = false;

  /// Whether the on-screen panel is shown.
  final ValueNotifier<bool> panelVisible = ValueNotifier(false);
  final ValueNotifier<FrameStats> stats = ValueNotifier(const FrameStats());

  /// Flutter's built-in performance graphs (MaterialApp.showPerformanceOverlay).
  final ValueNotifier<bool> performanceOverlay = ValueNotifier(false);

  /// Describes what the app is showing, for slow frame and context records.
  Map<String, Object?> Function()? contextProvider;

  late String outputPath = _defaultOutputPath();

  /// Receives the readable snapshot entry; errors.txt by default.
  void Function(String text) errorLogWriter = ErrorLogFile.appendText;

  final Queue<(DateTime, FrameSample)> _samples = Queue();
  List<String> _pending = [];
  Future<bool>? _flushInFlight;
  static const int _maxPendingRecords = 4096;
  final Map<String, int> _rebuildsInWindow = {};
  int _slowTotal = 0;
  int _peakRss = 0;
  Timer? _tick;
  Stopwatch? _clock;
  bool _startupWritten = false;
  String? _lastContext;
  RebuildDirtyWidgetCallback? _previousRebuildCallback;
  bool _previousRepaintRainbow = false;
  bool _previousPaintSize = false;

  bool get isCollecting => _running;
  DiagnosticsLaunchMode get launchMode => _launchMode;

  /// Called once from main(); cheap and does no I/O unless requested.
  void initFromLaunch(List<String> args, {Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    _launchMode = parseDiagnosticsLaunchMode(args, env);
    final out = env[devDiagnosticsOutEnv];
    if (out != null && out.trim().isNotEmpty) outputPath = out.trim();
    _update();
  }

  /// Turns developer mode on or off for this run (Ctrl+Shift+I).
  void toggle() {
    if (!_running && _pending.length >= _maxPendingRecords) {
      if (_flushInFlight == null) {
        unawaited(
          _flushAll().then((saved) {
            if (saved) toggle();
          }),
        );
      }
      return;
    }
    _toggledOn = !_running;
    // Turning it off also cancels a launch request, so the shortcut always
    // flips what is on screen.
    if (!_toggledOn) _launchMode = DiagnosticsLaunchMode.off;
    _update();
  }

  void _update() {
    final wanted = _toggledOn || _launchMode != DiagnosticsLaunchMode.off;
    if (wanted && !_running) _start();
    if (!wanted && _running) _stop();
    // An explicit log-only launch keeps the panel's own repaints out of
    // measurements.
    panelVisible.value = switch (_launchMode) {
      DiagnosticsLaunchMode.panel => true,
      DiagnosticsLaunchMode.logOnly => false,
      DiagnosticsLaunchMode.off => _toggledOn,
    };
  }

  void _start() {
    _running = true;
    _clock = Stopwatch()..start();
    _slowTotal = 0;
    _peakRss = 0;
    _startupWritten = false;
    _lastContext = null;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    if (kDebugMode) {
      _previousRebuildCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = _onRebuild;
      _previousRepaintRainbow = debugRepaintRainbowEnabled;
      _previousPaintSize = debugPaintSizeEnabled;
    }
    _write({
      'type': 'session',
      'time': DateTime.now().toIso8601String(),
      'version': ErrorLogFile.appVersion,
      'buildMode': kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      'os': Platform.operatingSystem,
      'osVersion': displayOsVersion(),
      'cores': Platform.numberOfProcessors,
      'pid': pid,
      'launchMode': _launchMode.name,
      'rebuildTracking': kDebugMode,
    });
    if (!_running) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _stop({bool flush = true}) {
    if (!_running) return;
    _running = false;
    _launchMode = DiagnosticsLaunchMode.off;
    _toggledOn = false;
    panelVisible.value = false;
    _tick?.cancel();
    _tick = null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    if (kDebugMode && debugOnRebuildDirtyWidget == _onRebuild) {
      debugOnRebuildDirtyWidget = _previousRebuildCallback;
    }
    _restoreDebugPaintFlags();
    _write({'type': 'end', 't': _elapsedMs});
    if (flush) unawaited(_flushAll());
    _samples.clear();
    _rebuildsInWindow.clear();
    stats.value = const FrameStats();
    performanceOverlay.value = false;
  }

  int get _elapsedMs => _clock?.elapsedMilliseconds ?? 0;

  void _onRebuild(Element element, bool builtOnce) {
    final type = element.widget.runtimeType.toString();
    _rebuildsInWindow[type] = (_rebuildsInWindow[type] ?? 0) + 1;
    _previousRebuildCallback?.call(element, builtOnce);
  }

  void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    for (final timing in timings) {
      if (!_running) return;
      final sample = FrameSample(
        timing.buildDuration.inMicroseconds / 1000,
        timing.rasterDuration.inMicroseconds / 1000,
        timing.totalSpan.inMicroseconds / 1000,
      );
      _samples.add((now, sample));
      if (sample.totalMs > frameBudgetMs) _slowTotal++;
      if (sample.totalMs >= slowFrameLogMs) {
        _write({
          'type': 'slow_frame',
          't': _elapsedMs,
          'buildMs': _round1(sample.buildMs),
          'rasterMs': _round1(sample.rasterMs),
          'totalMs': _round1(sample.totalMs),
          'context': _context(),
        });
      }
    }
  }

  void _onTick() {
    final cutoff = DateTime.now().subtract(window);
    while (_samples.isNotEmpty && _samples.first.$1.isBefore(cutoff)) {
      _samples.removeFirst();
    }
    final rss = ProcessInfo.currentRss;
    if (rss > _peakRss) _peakRss = rss;
    final top = _rebuildsInWindow.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _rebuildsInWindow.clear();
    final current = computeFrameStats(
      [for (final s in _samples) s.$2],
      window: window,
      slowTotal: _slowTotal,
      rssMb: rss >> 20,
      peakRssMb: _peakRss >> 20,
      topRebuilds: top.take(10).toList(),
    );
    stats.value = current;

    final context = _context();
    final encodedContext = jsonEncode(context);
    if (encodedContext != _lastContext) {
      _lastContext = encodedContext;
      _write({'type': 'context', 't': _elapsedMs, ...context});
    }
    if (current.framesPerSecond > 0 || current.topRebuilds.isNotEmpty) {
      _write({'type': 'stats', 't': _elapsedMs, ...current.toJson()});
    }
    final startup = StartupTimeline.instance.toJson();
    if (!_startupWritten && startup['revealMs'] != null) {
      _startupWritten = true;
      _write({
        'type': 'startup',
        't': _elapsedMs,
        'version': ErrorLogFile.appVersion,
        ...startup,
      });
    }
    unawaited(_flush());
  }

  Map<String, Object?> _context() {
    try {
      return contextProvider?.call() ?? const {};
    } catch (error) {
      return {'contextError': '$error'};
    }
  }

  /// שומר תמונת מצב בלוג וב-errors.txt; מחזיר נתיב, או null אם הכתיבה נכשלה.
  Future<String?> snapshot() async {
    if (_pending.length >= _maxPendingRecords && !await _flushAll()) {
      return null;
    }
    final record = {
      'type': 'snapshot',
      't': _elapsedMs,
      'time': DateTime.now().toIso8601String(),
      ...stats.value.toJson(),
      'context': _context(),
      'startup': StartupTimeline.instance.toJson(),
    };
    if (!_write(record) || !await _flushAll()) return null;
    try {
      errorLogWriter(
        '=== Developer snapshot ${record['time']} ===\n'
        'Version: ${ErrorLogFile.appVersion}\n'
        '${const JsonEncoder.withIndent('  ').convert(record)}\n\n',
      );
    } catch (error) {
      debugPrint('Developer snapshot to errors.txt failed: $error');
    }
    return outputPath;
  }

  /// Debug builds only: flashes repainted areas in changing colors.
  bool get repaintRainbow => debugRepaintRainbowEnabled;
  set repaintRainbow(bool value) => _setDebugPaintFlag(() {
    debugRepaintRainbowEnabled = value;
  });

  /// Debug builds only: outlines every render box and its padding.
  bool get paintSize => debugPaintSizeEnabled;
  set paintSize(bool value) => _setDebugPaintFlag(() {
    debugPaintSizeEnabled = value;
  });

  void _setDebugPaintFlag(VoidCallback apply) {
    if (!kDebugMode) return;
    apply();
    unawaited(WidgetsBinding.instance.reassembleApplication());
  }

  void _restoreDebugPaintFlags() {
    if (!kDebugMode ||
        (debugRepaintRainbowEnabled == _previousRepaintRainbow &&
            debugPaintSizeEnabled == _previousPaintSize)) {
      return;
    }
    _setDebugPaintFlag(() {
      debugRepaintRainbowEnabled = _previousRepaintRainbow;
      debugPaintSizeEnabled = _previousPaintSize;
    });
  }

  bool _write(Map<String, Object?> record) {
    // אחסון תקוע עוצר איסוף במקום לצבור זיכרון ללא גבול.
    if (_pending.length >= _maxPendingRecords) {
      _stop();
      return false;
    }
    _pending.add(jsonEncode(record));
    return true;
  }

  Future<bool> _flushAll() async {
    if (_flushInFlight != null && !await _flushInFlight!) return false;
    return _flush();
  }

  Future<bool> _flush() {
    if (_flushInFlight != null) return _flushInFlight!;
    late final Future<bool> operation;
    operation = _flushPending().whenComplete(() {
      if (identical(_flushInFlight, operation)) _flushInFlight = null;
    });
    return _flushInFlight = operation;
  }

  Future<bool> _flushPending() async {
    if (_pending.isEmpty) return true;
    final pending = _pending;
    final count = pending.length;
    final text = '${pending.join('\n')}\n';
    try {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(text, mode: FileMode.append, flush: true);
      pending.removeRange(0, count);
      return true;
    } catch (error) {
      debugPrint('Developer diagnostics write failed: $error');
      if (identical(pending, _pending)) _stop(flush: false);
      return false;
    }
  }

  static String _defaultOutputPath() => p.join(
    p.dirname(ErrorLogFile.resolvePath()),
    'developer_diagnostics.jsonl',
  );

  @visibleForTesting
  void resetForTesting() {
    if (_running) {
      _running = false;
      _tick?.cancel();
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      if (kDebugMode && debugOnRebuildDirtyWidget == _onRebuild) {
        debugOnRebuildDirtyWidget = _previousRebuildCallback;
      }
      _restoreDebugPaintFlags();
    }
    _launchMode = DiagnosticsLaunchMode.off;
    _toggledOn = false;
    _pending = [];
    _flushInFlight = null;
    _samples.clear();
    _rebuildsInWindow.clear();
    contextProvider = null;
    errorLogWriter = ErrorLogFile.appendText;
    panelVisible.value = false;
    performanceOverlay.value = false;
    stats.value = const FrameStats();
  }
}
