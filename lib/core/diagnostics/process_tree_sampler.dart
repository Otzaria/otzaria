import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
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

/// מדידת קבוצת תהליכים מאותו סוג. שמות ה-Mb נשמרים לתאימות; היחידה MiB.
/// [pages] הן כתובות שדווחו על ידי המנוע; אין התאמה הכרחית של תהליך לטאב.
typedef ProcessKindMemory = ({
  int count,
  int privMb,
  List<int> eachMb,
  List<({String page, int mb})> pages,
});

/// מדידות התהליך והמנוע, כולן לפי [metric] וב-MiB.
/// שמות ה-privMb ההיסטוריים אינם מעידים על סוג המדד.
@immutable
class ProcessTreeSample {
  const ProcessTreeSample({
    this.hostPrivMb,
    this.webview = const {},
    this.metric = ProcessMemoryMetric.unknown,
  });

  final int? hostPrivMb;
  final Map<String, ProcessKindMemory> webview;
  final ProcessMemoryMetric metric;

  int get webviewPrivMb =>
      webview.values.fold(0, (sum, kind) => sum + kind.privMb);

  ProcessKindMemory? get renderers => webview['RENDERER'];

  Map<String, Object?> toJson({int? ageMs}) => {
    'metric': metric.jsonName,
    'source': ?metric.source,
    'unit': 'MiB',
    'ageMs': ?ageMs,
    'hostPrivMb': ?hostPrivMb,
    if (webview.isNotEmpty) ...{
      'webviewPrivMb': webviewPrivMb,
      'webview': {
        for (final e in webview.entries)
          e.key: {
            'count': e.value.count,
            'privMb': e.value.privMb,
            if (e.key == 'RENDERER') 'eachMb': e.value.eachMb,
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

/// מסכם את [processes] לפי סוג. תהליך בלי ערך (שכבר יצא) מדולג.
@visibleForTesting
ProcessTreeSample buildProcessTreeSample({
  required int? hostBytes,
  required Iterable<({String kind, int? bytes, String? page})> processes,
  ProcessMemoryMetric metric = ProcessMemoryMetric.unknown,
}) {
  final byKind = <String, List<({int bytes, String? page})>>{};
  for (final process in processes) {
    final bytes = process.bytes;
    if (bytes == null) continue;
    byKind.putIfAbsent(process.kind, () => []).add((
      bytes: bytes,
      page: process.page,
    ));
  }
  return ProcessTreeSample(
    metric: metric,
    hostPrivMb: hostBytes == null ? null : _toMb(hostBytes),
    webview: {
      for (final e in byKind.entries)
        e.key: (
          count: e.value.length,
          privMb: _toMb(e.value.fold(0, (sum, p) => sum + p.bytes)),
          eachMb:
              (e.value.map((p) => _toMb(p.bytes)).toList()
                    ..sort((a, b) => b - a))
                  .take(_maxEachMb)
                  .toList(),
          pages: ([
            for (final p in e.value)
              if (p.page case final page?) (page: page, mb: _toMb(p.bytes)),
          ]..sort((a, b) => b.mb - a.mb)).take(_maxEachMb).toList(),
        ),
    },
  );
}

/// תהליך WebView שהאפליקציה מחזיקה: סוגו, ה-pid וה-main frame שלו.
typedef WebViewProcess = ({String kind, int pid, String? page});

/// מונה את תהליכי ה-WebView. נרשם בשכבת התוספים, שמחזיקה את הסביבה.
typedef WebViewProcessLister = Future<List<WebViewProcess>> Function();

/// דוגם Windows ו-Linux בלבד. בפלטפורמות האחרות אין כאן איסוף תהליכי
/// WebView; null אינו מדידת אפס.
Future<ProcessTreeSample?> sampleProcessTree({
  WebViewProcessLister? webViewProcesses,
}) async {
  if (kIsWeb) return null;
  if (Platform.isWindows) return _sampleWindows(webViewProcesses);
  if (Platform.isLinux) return Isolate.run(_sampleLinux);
  return null;
}

Future<ProcessTreeSample> _sampleWindows(
  WebViewProcessLister? webViewProcesses,
) async {
  final processes = await webViewProcesses?.call() ?? const [];
  final ids = [pid, for (final process in processes) process.pid];
  // OpenProcess לכל pid הוא קריאה נייטיבית סינכרונית — לא על ה-isolate הראשי.
  final bytes = await Isolate.run(
    () => [for (final id in ids) _windowsPrivateBytes(id)],
  );
  return buildProcessTreeSample(
    metric: ProcessMemoryMetric.privateCommit,
    hostBytes: bytes.first,
    processes: [
      for (var i = 0; i < processes.length; i++)
        (
          kind: processes[i].kind,
          bytes: bytes[i + 1],
          page: processes[i].page,
        ),
    ],
  );
}

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

ProcessTreeSample _sampleLinux() {
  final parents = <int, int>{};
  final names = <int, String>{};
  for (final entry in Directory('/proc').listSync(followLinks: false)) {
    final id = int.tryParse(
      entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    );
    if (id == null) continue;
    try {
      final stat = parseProcStat(File('/proc/$id/stat').readAsStringSync());
      if (stat == null) continue;
      parents[id] = stat.ppid;
      names[id] = stat.name;
    } on FileSystemException {
      // התהליך יצא באמצע הסריקה.
    }
  }
  int? anonBytes(int id) {
    try {
      return parseRssAnonBytes(File('/proc/$id/status').readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  final descendants = <int>[];
  final queue = [pid];
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
    hostBytes: anonBytes(pid),
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
  if (open < 0 || close < open) return null;
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
