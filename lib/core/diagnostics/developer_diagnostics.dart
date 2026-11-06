import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:path/path.dart' as p;
import 'package:positioned_sliver_list/positioned_list.dart';

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

/// Refreshes of estimated item extents during one tick, summed over lists.
@immutable
class EstimateRefreshWindow {
  const EstimateRefreshWindow({
    this.count = 0,
    this.totalMs,
    this.items = 0,
    this.deferred = 0,
    this.skipped = 0,
  });

  final int count;

  /// Null when a list refreshed more than once: only its last duration is known.
  final double? totalMs;
  final int items;
  final int deferred;
  final int skipped;

  bool get isEmpty => count == 0 && deferred == 0 && skipped == 0;

  Map<String, Object?> toJson() => {
    'count': count,
    if (totalMs != null) 'totalMs': totalMs,
    'items': items,
    'deferred': deferred,
    'skipped': skipped,
  };
}

/// Sums the change from each `before` (null for a new list) to its `after`.
EstimateRefreshWindow estimateRefreshDelta(
  Iterable<(EstimateRefreshStats?, EstimateRefreshStats)> lists,
) {
  var count = 0, items = 0, deferred = 0, skipped = 0;
  var totalMicros = 0;
  var exact = true;
  for (final (before, after) in lists) {
    final refreshes = after.refreshCount - (before?.refreshCount ?? 0);
    deferred += after.deferredResizeCount - (before?.deferredResizeCount ?? 0);
    skipped += after.skippedResizeCount - (before?.skippedResizeCount ?? 0);
    if (refreshes <= 0) continue;
    count += refreshes;
    items += refreshes * after.lastRefreshItemCount;
    if (refreshes > 1) exact = false;
    totalMicros += after.lastRefreshDuration.inMicroseconds;
  }
  return EstimateRefreshWindow(
    count: count,
    totalMs: exact && count > 0 ? _round1(totalMicros / 1000) : null,
    items: items,
    deferred: deferred,
    skipped: skipped,
  );
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
    this.processes,
    this.estimates,
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

  /// הדגימה האחרונה של עץ התהליכים, או null כשאין (כבוי, לפני reveal, או
  /// פלטפורמה בלי מימוש).
  final ProcessTreeSample? processes;

  /// Estimate refreshes of the reader lists since the previous tick, if any.
  final EstimateRefreshWindow? estimates;

  Map<String, Object?> toJson({bool includeProcesses = true}) => {
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
    if (includeProcesses && processes != null) 'processes': processes!.toJson(),
    if (estimates != null) 'estimates': estimates!.toJson(),
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
  ProcessTreeSample? processes,
  EstimateRefreshWindow? estimates,
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
    processes: processes,
    estimates: estimates == null || estimates.isEmpty ? null : estimates,
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

  /// The process tree is sampled every this many ticks (seconds), after the
  /// window is revealed.
  static const int processSampleEveryTicks = 5;

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

  /// Lists the WebView processes; registered by the plugin layer.
  WebViewProcessLister? webViewProcessLister;

  /// Samples the app and WebView processes; replaced in tests.
  late ProcessTreeSampler processSampler = _sampleProcessTree;

  Future<ProcessTreeSample?> _sampleProcessTree() =>
      sampleProcessTree(webViewProcesses: webViewProcessLister);

  /// Receives the readable snapshot entry; errors.txt by default.
  void Function(String text) errorLogWriter = ErrorLogFile.appendText;

  final Queue<(DateTime, FrameSample)> _samples = Queue();
  List<String> _pending = [];
  Future<bool>? _flushInFlight;
  static const int _maxPendingRecords = 4096;
  final Map<String, int> _rebuildsInWindow = {};
  final Map<ItemScrollController, int> _estimateLists = {};
  Expando<EstimateRefreshStats> _lastEstimates = Expando();
  int _slowTotal = 0;
  int _peakRss = 0;
  Timer? _tick;
  Stopwatch? _clock;
  bool _startupWritten = false;
  String? _lastContext;
  String? _lastOsVersion;

  @visibleForTesting
  String Function() osVersionForTesting = displayOsVersion;
  RebuildDirtyWidgetCallback? _previousRebuildCallback;
  bool _previousRepaintRainbow = false;
  bool _previousPaintSize = false;
  ProcessTreeSample? _processes;
  DateTime? _processesAt;
  int _ticksUntilProcessSample = 0;
  bool _processesFresh = false;
  bool _processSampleFailureLogged = false;
  Future<void>? _processSampling;

  /// A sample started in an earlier collection is dropped when it lands.
  int _session = 0;

  bool get isCollecting => _running;

  /// רשימה שעלות רענון ההערכות שלה נכנסת ל-stats. נרשמת גם כשהאיסוף כבוי,
  /// כדי שהפעלה ב-Ctrl+Shift+I תכלול רשימות שכבר פתוחות.
  void trackEstimateRefreshes(ItemScrollController controller) => _estimateLists
      .update(controller, (count) => count + 1, ifAbsent: () => 1);

  // נספר: מופע חדש נרשם ב-initState לפני ש-dispose של הקודם מסיר את אותו בקר.
  void untrackEstimateRefreshes(ItemScrollController controller) {
    final count = _estimateLists[controller];
    if (count == null) return;
    if (count > 1) {
      _estimateLists[controller] = count - 1;
    } else {
      _estimateLists.remove(controller);
    }
  }

  EstimateRefreshWindow _estimateRefreshesSinceLastTick() {
    final lists = <(EstimateRefreshStats?, EstimateRefreshStats)>[];
    for (final controller in _estimateLists.keys) {
      final list = controller.listController;
      final stats = list?.estimateRefreshStats;
      if (list == null || stats == null) continue;
      lists.add((_lastEstimates[list], stats));
      _lastEstimates[list] = stats;
    }
    return estimateRefreshDelta(lists);
  }

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
    _session++;
    _clock = Stopwatch()..start();
    _slowTotal = 0;
    _peakRss = 0;
    _startupWritten = false;
    _lastContext = null;
    _lastOsVersion = osVersionForTesting();
    _resetProcesses();
    // רענונים שקדמו לאיסוף אינם נספרים.
    _lastEstimates = Expando();
    _estimateRefreshesSinceLastTick();
    SmartTextRenderStats.reset();
    SmartTextRenderStats.enabled = true;
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
      'osVersion': _lastOsVersion,
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
    SmartTextRenderStats.enabled = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    if (kDebugMode && debugOnRebuildDirtyWidget == _onRebuild) {
      debugOnRebuildDirtyWidget = _previousRebuildCallback;
    }
    _restoreDebugPaintFlags();
    _write({'type': 'end', 't': _elapsedMs});
    if (flush) unawaited(_flushAll());
    _samples.clear();
    _rebuildsInWindow.clear();
    _resetProcesses();
    stats.value = const FrameStats();
    performanceOverlay.value = false;
  }

  void _resetProcesses() {
    _processes = null;
    _processesAt = null;
    _ticksUntilProcessSample = 0;
    _processesFresh = false;
    _processSampleFailureLogged = false;
    _processSampling = null;
  }

  /// psapi.dll וה-COM של WebView2 נטענים בדגימה הראשונה — לכן רק אחרי reveal.
  void _maybeSampleProcesses({required bool revealed}) {
    if (!revealed || _processSampling != null) return;
    if (_ticksUntilProcessSample-- > 0) return;
    _ticksUntilProcessSample = processSampleEveryTicks - 1;
    unawaited(_sampleProcesses());
  }

  Future<void> _sampleProcesses() {
    final running = _processSampling;
    if (running != null) return running;
    late final Future<void> operation;
    operation = _runProcessSample().whenComplete(() {
      if (identical(_processSampling, operation)) _processSampling = null;
    });
    return _processSampling = operation;
  }

  Future<void> _runProcessSample() async {
    final session = _session;
    try {
      final sample = await processSampler().timeout(
        const Duration(seconds: 2),
      );
      if (!_running || session != _session || sample == null) return;
      _processes = sample;
      _processesAt = DateTime.now();
      _processesFresh = true;
    } catch (error) {
      if (_processSampleFailureLogged) return;
      _processSampleFailureLogged = true;
      debugPrint('Developer diagnostics process sample failed: $error');
    }
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
    if (!_running) return;
    final osVersion = osVersionForTesting();
    if (osVersion != _lastOsVersion) {
      _lastOsVersion = osVersion;
      _write({'type': 'os_version', 't': _elapsedMs, 'osVersion': osVersion});
      if (!_running) return;
    }
    final startup = StartupTimeline.instance.toJson();
    _maybeSampleProcesses(revealed: startup['revealMs'] != null);
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
      processes: _processes,
      estimates: _estimateRefreshesSinceLastTick(),
    );
    stats.value = current;
    final freshProcesses = _processesFresh;
    _processesFresh = false;

    final context = _context();
    final encodedContext = jsonEncode(context);
    if (encodedContext != _lastContext) {
      _lastContext = encodedContext;
      _write({'type': 'context', 't': _elapsedMs, ...context});
    }
    final smartText = SmartTextRenderStats.takeAndReset();
    if (current.framesPerSecond > 0 ||
        current.topRebuilds.isNotEmpty ||
        current.estimates != null ||
        freshProcesses ||
        smartText != null) {
      _write({
        'type': 'stats',
        't': _elapsedMs,
        ...current.toJson(includeProcesses: freshProcesses),
        'smartText': ?smartText,
      });
    }
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
    await _sampleProcesses();
    final processesAt = _processesAt;
    final record = {
      'type': 'snapshot',
      'osVersion': osVersionForTesting(),
      't': _elapsedMs,
      'time': DateTime.now().toIso8601String(),
      ...stats.value.toJson(includeProcesses: false),
      'processes': ?_processes?.toJson(
        ageMs: processesAt == null
            ? null
            : DateTime.now().difference(processesAt).inMilliseconds,
      ),
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
  void debugTick() => _onTick();

  @visibleForTesting
  void resetForTesting() {
    if (_running) {
      _running = false;
      _tick?.cancel();
      SmartTextRenderStats.enabled = false;
      SmartTextRenderStats.reset();
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
    _estimateLists.clear();
    _lastEstimates = Expando();
    contextProvider = null;
    osVersionForTesting = displayOsVersion;
    _lastOsVersion = null;
    errorLogWriter = ErrorLogFile.appendText;
    processSampler = _sampleProcessTree;
    webViewProcessLister = null;
    _resetProcesses();
    panelVisible.value = false;
    performanceOverlay.value = false;
    stats.value = const FrameStats();
  }
}
