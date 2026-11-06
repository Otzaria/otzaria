import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// המדדים אינם בני השוואה: commit כולל הקצאות שאינן תושבות בזיכרון,
/// ו-RssAnon הוא זיכרון אנונימי תושב, לא כלל הזיכרון הפרטי.
enum ProcessMemoryMetric {
  unknown('unknown', 'memory', null),
  privateCommit(
    'privateCommit',
    'commit',
    'GetProcessMemoryInfo.PagefileUsage',
  ),
  anonymousRss('anonymousRss', 'RssAnon', '/proc/<pid>/status:RssAnon');

  const ProcessMemoryMetric(this.jsonName, this.label, this.source);

  final String jsonName;
  final String label;
  final String? source;
}

enum ProcessCollectionStatus { collected, unsupported, unavailable }

enum ProcessMemoryCoverage { allObserved, partial, unavailable }

/// זמינות מניית התהליכים, בנפרד מקריאת הזיכרון של כל תהליך שנצפה.
@immutable
class ProcessCollection {
  const ProcessCollection({
    required this.status,
    this.source,
    this.reason,
    this.stage,
    this.hresult,
    this.partial,
  });

  const ProcessCollection.collected({String? source, bool? partial})
    : this(
        status: ProcessCollectionStatus.collected,
        source: source,
        partial: partial,
      );

  const ProcessCollection.unavailable(String reason, {String? source})
    : this(
        status: ProcessCollectionStatus.unavailable,
        source: source,
        reason: reason,
      );

  final ProcessCollectionStatus status;
  final String? source;
  final String? reason;
  final String? stage;
  final int? hresult;
  final bool? partial;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'source': ?source,
    'reason': ?reason,
    'stage': ?stage,
    'hresult': ?hresult,
    'partial': partial,
  };
}

/// count נשמר כמספר הקריאות שהצליחו לתאימות; observedCount כולל גם חסרות.
/// [pages] הן כתובות שדווחו על ידי המנוע; אין התאמה הכרחית של תהליך לטאב.
typedef ProcessKindMemory = ({
  int count,
  int observedCount,
  int? privMb,
  List<int> eachMb,
  List<({String page, int mb})> pages,
  int measuredPageCount,
});

extension ProcessKindMemoryCoverage on ProcessKindMemory {
  int get measuredCount => count;
  int get unavailableCount => observedCount - measuredCount;
  bool get eachMbTruncated => eachMb.length < measuredCount;
  bool get pagesTruncated => pages.length < measuredPageCount;
  ProcessMemoryCoverage get memoryCoverage => _memoryCoverage(
    measuredCount,
    unavailableCount,
  );
}

ProcessMemoryCoverage _memoryCoverage(int? measured, int? unavailable) =>
    measured == null || measured == 0
    ? ProcessMemoryCoverage.unavailable
    : unavailable == 0
    ? ProcessMemoryCoverage.allObserved
    : ProcessMemoryCoverage.partial;

/// מדידות התהליך והמנוע, כולן לפי [metric] וב-MiB.
/// שמות ה-privMb ההיסטוריים אינם מעידים על סוג המדד.
@immutable
class ProcessTreeSample {
  const ProcessTreeSample({
    this.hostPrivMb,
    this.webview = const {},
    this.metric = ProcessMemoryMetric.unknown,
    this.webviewCollection = const ProcessCollection.unavailable(
      'not_collected',
    ),
  });

  final int? hostPrivMb;
  final Map<String, ProcessKindMemory> webview;
  final ProcessMemoryMetric metric;
  final ProcessCollection webviewCollection;

  int? get observedProcessCount =>
      webviewCollection.status == ProcessCollectionStatus.collected
      ? webview.values.fold<int>(0, (sum, kind) => sum + kind.observedCount)
      : null;

  int? get measuredProcessCount => observedProcessCount == null
      ? null
      : webview.values.fold<int>(0, (sum, kind) => sum + kind.measuredCount);

  int? get unavailableProcessCount => observedProcessCount == null
      ? null
      : observedProcessCount! - measuredProcessCount!;

  ProcessMemoryCoverage get memoryCoverage => _memoryCoverage(
    measuredProcessCount,
    unavailableProcessCount,
  );

  int? get webviewPrivMb => (measuredProcessCount ?? 0) == 0
      ? null
      : webview.values.fold<int>(0, (sum, kind) => sum + (kind.privMb ?? 0));

  ProcessKindMemory? get renderers => webview['RENDERER'];

  Map<String, Object?> toJson({int? ageMs}) => {
    'schemaVersion': 2,
    'metric': metric.jsonName,
    'source': ?metric.source,
    'unit': 'MiB',
    'ageMs': ?ageMs,
    'hostPrivMb': ?hostPrivMb,
    'hostMemoryStatus': hostPrivMb != null
        ? 'collected'
        : metric == ProcessMemoryMetric.unknown &&
              webviewCollection.status == ProcessCollectionStatus.unsupported
        ? 'unsupported'
        : 'unavailable',
    'webviewCollection': webviewCollection.toJson(),
    'observedProcessCount': observedProcessCount,
    'measuredProcessCount': measuredProcessCount,
    'unavailableProcessCount': unavailableProcessCount,
    'memoryCoverage': memoryCoverage.name,
    'engineComplete': null,
    'webviewPrivMb': ?webviewPrivMb,
    if (webview.isNotEmpty) ...{
      'webview': {
        for (final e in webview.entries)
          e.key: {
            'count': e.value.count,
            'observedCount': e.value.observedCount,
            'measuredCount': e.value.measuredCount,
            'unavailableCount': e.value.unavailableCount,
            'memoryCoverage': e.value.memoryCoverage.name,
            'privMb': ?e.value.privMb,
            if (e.key == 'RENDERER') ...{
              'eachMb': e.value.eachMb,
              'eachMbTruncated': e.value.eachMbTruncated,
            },
            'measuredPageCount': e.value.measuredPageCount,
            'pagesTruncated': e.value.pagesTruncated,
            if (e.value.pages.isNotEmpty)
              'pages': [
                for (final page in e.value.pages)
                  {'page': page.page, 'mb': page.mb},
              ],
          },
      },
    },
  };
}

typedef ProcessTreeSampler = Future<ProcessTreeSample?> Function();

const int _maxEachMb = 12;

int _toMb(int bytes) => (bytes / (1 << 20)).round();

/// מסכם את כל התהליכים שנצפו; רק הפירוט מוגבל, וערך חסר אינו אפס.
@visibleForTesting
ProcessTreeSample buildProcessTreeSample({
  required int? hostBytes,
  required Iterable<({String kind, int? bytes, String? page})> processes,
  ProcessMemoryMetric metric = ProcessMemoryMetric.unknown,
  ProcessCollection webviewCollection = const ProcessCollection.collected(),
}) {
  final byKind = <String, List<({int? bytes, String? page})>>{};
  for (final process in processes) {
    byKind.putIfAbsent(process.kind, () => []).add((
      bytes: process.bytes,
      page: process.page,
    ));
  }
  ProcessKindMemory summarize(List<({int? bytes, String? page})> observed) {
    final measured = observed.where((p) => p.bytes != null).toList();
    final pages = [
      for (final p in measured)
        if (p.page case final page?) (page: page, mb: _toMb(p.bytes!)),
    ]..sort((a, b) => b.mb - a.mb);
    return (
      count: measured.length,
      observedCount: observed.length,
      privMb: measured.isEmpty
          ? null
          : _toMb(measured.fold(0, (sum, p) => sum + p.bytes!)),
      eachMb:
          (measured.map((p) => _toMb(p.bytes!)).toList()..sort((a, b) => b - a))
              .take(_maxEachMb)
              .toList(),
      pages: pages.take(_maxEachMb).toList(),
      measuredPageCount: pages.length,
    );
  }

  return ProcessTreeSample(
    metric: metric,
    webviewCollection: webviewCollection,
    hostPrivMb: hostBytes == null ? null : _toMb(hostBytes),
    webview: {
      for (final e in byKind.entries) e.key: summarize(e.value),
    },
  );
}

/// תהליך WebView שהאפליקציה מחזיקה: סוגו, ה-pid וה-main frame שלו.
typedef WebViewProcess = ({String kind, int? pid, String? page});

@immutable
class WebViewProcessSnapshot {
  const WebViewProcessSnapshot({
    required this.collection,
    this.processes = const [],
  });

  const WebViewProcessSnapshot.collected(this.processes)
    : collection = const ProcessCollection.collected(
        source: _windowsProcessSource,
      );

  final ProcessCollection collection;
  final List<WebViewProcess> processes;
}

/// מונה את תהליכי ה-WebView. נרשם בשכבת התוספים, שמחזיקה את הסביבה.
typedef WebViewProcessLister = Future<WebViewProcessSnapshot> Function();

const _windowsProcessSource = 'WebViewEnvironment.getProcessInfos';

Future<WebViewProcessSnapshot> _collectWindowsProcesses(
  WebViewProcessLister? lister,
  Duration timeout,
) async {
  if (lister == null) {
    return const WebViewProcessSnapshot(
      collection: ProcessCollection.unavailable(
        'webview_environment_unavailable',
        source: _windowsProcessSource,
      ),
    );
  }
  try {
    // מגביל Future שלא חזר; אינו יכול לעצור קריאה נייטיבית סינכרונית.
    return await lister().timeout(timeout);
  } catch (error) {
    const codes = {
      'process_info_unsupported',
      'webview_environment_unavailable',
      'process_info_collection_failed',
    };
    final code = error is PlatformException && codes.contains(error.code)
        ? error.code
        : error is TimeoutException
        ? 'process_info_timeout'
        : error is UnsupportedError || error is MissingPluginException
        ? 'process_info_unsupported'
        : 'process_info_collection_failed';
    final details = error is PlatformException && error.details is Map
        ? error.details as Map
        : const {};
    final stage = details['stage'];
    final hresult = details['hresult'];
    return WebViewProcessSnapshot(
      collection: ProcessCollection(
        status: code == 'process_info_unsupported'
            ? ProcessCollectionStatus.unsupported
            : ProcessCollectionStatus.unavailable,
        source: _windowsProcessSource,
        reason: code,
        stage:
            stage is String &&
                RegExp(r'^[A-Za-z0-9_.\[\]]{1,100}$').hasMatch(stage)
            ? stage
            : null,
        hresult:
            hresult is int && hresult >= -0x80000000 && hresult <= 0x7fffffff
            ? hresult
            : null,
      ),
    );
  }
}

/// דוגם Windows ו-Linux בלבד; בפלטפורמות האחרות מסומן unsupported.
Future<ProcessTreeSample?> sampleProcessTree({
  WebViewProcessLister? webViewProcesses,
}) async {
  if (!kIsWeb && Platform.isWindows) {
    return sampleWindowsProcessTree(
      webViewProcesses: webViewProcesses,
      readBytes: _windowsProcessBytes,
    );
  }
  if (!kIsWeb && Platform.isLinux) return Isolate.run(sampleLinuxProcessTree);
  return const ProcessTreeSample(
    webviewCollection: ProcessCollection(
      status: ProcessCollectionStatus.unsupported,
      reason: 'platform_unsupported',
    ),
  );
}

/// המארח נקרא במקביל למניית המנוע; כשל שלה אינו מבטל את הדגימה שלו.
@visibleForTesting
Future<ProcessTreeSample> sampleWindowsProcessTree({
  WebViewProcessLister? webViewProcesses,
  required Future<List<int?>> Function(List<int>) readBytes,
  Duration enumerationTimeout = const Duration(seconds: 1),
}) async {
  final hostBytes = _readProcessBytes([pid], readBytes);
  final snapshot = await _collectWindowsProcesses(
    webViewProcesses,
    enumerationTimeout,
  );
  final ids = {
    for (final process in snapshot.processes) ?process.pid,
  }..remove(pid);
  final engineIds = ids.toList();
  final engineBytes = engineIds.isEmpty
      ? Future.value(const <int?>[])
      : _readProcessBytes(engineIds, readBytes);
  final host = (await hostBytes).single;
  final bytes = await engineBytes;
  final byPid = {
    pid: host,
    for (var i = 0; i < engineIds.length; i++) engineIds[i]: bytes[i],
  };
  return buildProcessTreeSample(
    metric: ProcessMemoryMetric.privateCommit,
    webviewCollection: snapshot.collection,
    hostBytes: host,
    processes: [
      for (final process in snapshot.processes)
        (
          kind: process.kind,
          bytes: byPid[process.pid],
          page: process.page,
        ),
    ],
  );
}

Future<List<int?>> _readProcessBytes(
  List<int> ids,
  Future<List<int?>> Function(List<int>) readBytes,
) async {
  try {
    return await readBytes(ids);
  } catch (_) {
    return List<int?>.filled(ids.length, null);
  }
}

// OpenProcess סינכרונית; הקריאות למארח ולמנוע נשארות ב-isolate עזר.
Future<List<int?>> _windowsProcessBytes(List<int> ids) => Isolate.run(
  () => [for (final id in ids) _windowsPrivateBytes(id)],
);

/// ב-Windows 8 ומעלה `PagefileUsage` הוא ה-PrivateUsage של התהליך.
int? _windowsPrivateBytes(int processId) {
  final handle = OpenProcess(
    PROCESS_QUERY_LIMITED_INFORMATION,
    false,
    processId,
  );
  if (!handle.value.isValid) return null;
  final counters = calloc<PROCESS_MEMORY_COUNTERS>();
  try {
    final size = sizeOf<PROCESS_MEMORY_COUNTERS>();
    counters.ref.cb = size;
    final ok = GetProcessMemoryInfo(handle.value, counters, size);
    return ok.value ? counters.ref.PagefileUsage : null;
  } finally {
    calloc.free(counters);
    handle.value.close();
  }
}

/// מניית צאצאי WPE וקריאת RssAnon, ללא פנייה למנוע עצמו.
@visibleForTesting
ProcessTreeSample sampleLinuxProcessTree({
  String procRoot = '/proc',
  int? hostProcessId,
}) {
  final hostPid = hostProcessId ?? pid;
  int? anonBytes(int id) {
    try {
      return parseRssAnonBytes(File('$procRoot/$id/status').readAsStringSync());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  final hostBytes = anonBytes(hostPid);
  List<FileSystemEntity> entries;
  try {
    entries = Directory(procRoot).listSync(followLinks: false);
  } on FileSystemException {
    return buildProcessTreeSample(
      metric: ProcessMemoryMetric.anonymousRss,
      hostBytes: hostBytes,
      processes: const [],
      webviewCollection: const ProcessCollection.unavailable(
        'proc_scan_failed',
        source: '/proc/<pid>/stat',
      ),
    );
  }
  final parents = <int, int>{};
  final names = <int, String>{};
  var partial = false;
  for (final entry in entries) {
    final id = int.tryParse(
      entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    );
    if (id == null) continue;
    try {
      final stat = parseProcStat(File('$procRoot/$id/stat').readAsStringSync());
      if (stat == null) {
        partial = true;
        continue;
      }
      parents[id] = stat.ppid;
      names[id] = stat.name;
    } on FileSystemException {
      partial = true;
    } on FormatException {
      partial = true;
    }
  }

  final descendants = <int>[];
  final queue = [hostPid];
  while (queue.isNotEmpty) {
    final parent = queue.removeLast();
    for (final e in parents.entries) {
      if (e.value == parent && !descendants.contains(e.key)) {
        descendants.add(e.key);
        queue.add(e.key);
      }
    }
  }
  return buildProcessTreeSample(
    metric: ProcessMemoryMetric.anonymousRss,
    hostBytes: hostBytes,
    webviewCollection: ProcessCollection.collected(
      source: '/proc/<pid>/stat',
      partial: partial,
    ),
    processes: [
      for (final id in descendants)
        if (wpeProcessKind(names[id] ?? '') case final kind?)
          (kind: kind, bytes: anonBytes(id), page: null),
    ],
  );
}

/// השם וה-ppid מתוך `/proc/<pid>/stat`. השם בסוגריים עשוי להכיל רווחים.
@visibleForTesting
({String name, int ppid})? parseProcStat(String stat) {
  final open = stat.indexOf('(');
  final close = stat.lastIndexOf(')');
  if (open < 0 || close < open || close + 2 >= stat.length) return null;
  final rest = stat.substring(close + 2).split(' ');
  final ppid = rest.length > 1 ? int.tryParse(rest[1]) : null;
  if (ppid == null) return null;
  return (name: stat.substring(open + 1, close), ppid: ppid);
}

/// `RssAnon` מתוך `/proc/<pid>/status` — זיכרון אנונימי תושב, בבייטים.
@visibleForTesting
int? parseRssAnonBytes(String status) {
  final match = RegExp(
    r'^RssAnon:\s+(\d+)\s+kB',
    multiLine: true,
  ).firstMatch(status);
  return match == null ? null : int.parse(match.group(1)!) * 1024;
}

/// הסוג של תהליך WPE לפי `comm`, שנחתך ל-15 תווים (`WPENetworkProce`).
@visibleForTesting
String? wpeProcessKind(String comm) => switch (comm) {
  'WPEWebProcess' => 'RENDERER',
  'WPEGPUProcess' => 'GPU',
  _ when comm.startsWith('WPENetworkProc') => 'UTILITY',
  _ => null,
};
