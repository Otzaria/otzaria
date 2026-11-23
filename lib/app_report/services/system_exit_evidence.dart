import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// ראיה ממערכת ההפעלה שתהליך מסוים קרס, נסגר כשהיה תקוע או נהרג על זיכרון.
/// מכילה שדות מובנים בלבד — לא שורת יומן, נתיב, שם משתמש או שם מחשב.
@immutable
class SystemExitEvidence {
  const SystemExitEvidence({
    required this.isHang,
    required this.signature,
    required this.details,
  });

  final bool isHang;
  final CrashSignature signature;

  /// שורות `key: value` לאבחון הפרטי.
  final String details;
}

/// מחפש ראיה לסיום של התהליך [pid] שרץ מ-[start] ועד לכל המאוחר [end].
typedef SystemExitEvidenceReader =
    Future<SystemExitEvidence?> Function(int pid, DateTime start, DateTime end);

const int _maxEvents = 8;

/// Application Error/Hang ב-Windows, הריגת OOM של הקרנל בלינוקס; אחרת null.
/// לעולם לא זורק — כשל בקריאה פירושו "אין ראיה".
Future<SystemExitEvidence?> readSystemExitEvidence(
  int pid,
  DateTime start,
  DateTime end, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (kIsWeb) return null;
  try {
    if (Platform.isWindows) {
      final exe = p.basename(Platform.resolvedExecutable);
      // wevtapi סינכרוני: מחוץ ל-isolate הראשי, שלא יעצור את ה-UI.
      return await Isolate.run(
        () => windowsExitEvidence(
          queryWindowsEventXml(windowsEventQuery(pid, start, end)),
          pid: pid,
          exeName: exe,
          start: start,
          end: end,
        ),
      ).timeout(timeout);
    }
    if (Platform.isLinux) {
      return await _readLinuxOomKill(pid, start, end, timeout);
    }
  } catch (error) {
    debugPrint('readSystemExitEvidence: $error');
  }
  return null;
}

/// XPath מצומצם לספקים, לטווח הזמן ולערך ה-pid (בשמות ובלי שמות שדות).
@visibleForTesting
String windowsEventQuery(int pid, DateTime start, DateTime end) {
  String at(DateTime time) => time.toUtc().toIso8601String();
  final hex = pid.toRadixString(16);
  return "*[System[Provider[@Name='Application Error' or "
      "@Name='Application Hang'] and (EventID=1000 or EventID=1002) and "
      "TimeCreated[@SystemTime>='${at(start)}' and "
      "@SystemTime<='${at(end)}']]] and "
      "*[EventData[Data='0x$hex' or Data='0x${hex.toUpperCase()}' or "
      "Data='$pid']]";
}

@visibleForTesting
List<String> queryWindowsEventXml(String query) => using((arena) {
  final events = arena<IntPtr>(_maxEvents);
  final returned = arena<Uint32>();
  final handle = EvtQuery(
    null,
    arena.pcwstr('Application'),
    arena.pcwstr(query),
    EvtQueryChannelPath | EvtQueryReverseDirection,
  ).value;
  if (handle == 0) return const <String>[];
  try {
    if (!EvtNext(handle, _maxEvents, events, 2000, 0, returned).value) {
      return const <String>[];
    }
    final xml = <String>[];
    for (var i = 0; i < returned.value; i++) {
      final event = EVT_HANDLE(events[i]);
      try {
        final rendered = _renderXml(event, arena);
        if (rendered != null) xml.add(rendered);
      } finally {
        EvtClose(event);
      }
    }
    return xml;
  } finally {
    EvtClose(handle);
  }
});

String? _renderXml(EVT_HANDLE event, Arena arena) {
  final used = arena<Uint32>();
  final count = arena<Uint32>();
  EvtRender(null, event, EvtRenderEventXml, 0, null, used, count);
  final size = used.value;
  if (size == 0) return null;
  final buffer = arena<Uint8>(size);
  if (!EvtRender(
    null,
    event,
    EvtRenderEventXml,
    size,
    buffer,
    used,
    count,
  ).value) {
    return null;
  }
  return buffer.cast<Utf16>().toDartString();
}

/// הראיה מאירועי Windows: Application Error 1000 גובר על Application Hang 1002.
/// אירוע נספר רק אם ה-pid, שם קובץ ההפעלה וזמן היצירה הם של ההפעלה הקודמת.
@visibleForTesting
SystemExitEvidence? windowsExitEvidence(
  Iterable<String> eventXml, {
  required int pid,
  required String exeName,
  required DateTime start,
  required DateTime end,
}) {
  SystemExitEvidence? hang;
  for (final xml in eventXml) {
    final event = _WindowsEvent.tryParse(xml);
    if (event == null || !event.belongsTo(pid, exeName, start, end)) continue;
    if (event.id == 1000) {
      final crash = event.crashEvidence();
      if (crash != null) return crash;
    } else {
      hang ??= event.hangEvidence();
    }
  }
  return hang;
}

class _WindowsEvent {
  _WindowsEvent(this.id, this.time, this._named, this._positional);

  final int id;
  final DateTime time;
  final Map<String, String> _named;
  final List<String> _positional;

  static final _idPattern = RegExp(r'<EventID[^>]*>(\d+)</EventID>');
  static final _timePattern = RegExp('SystemTime=[\'"]([^\'"]+)[\'"]');
  static final _dataPattern = RegExp(
    '<Data(?:\\s+Name=[\'"]([^\'"]*)[\'"])?\\s*(?:/>|>([^<]*)</Data>)',
  );

  static _WindowsEvent? tryParse(String xml) {
    final id = int.tryParse(_idPattern.firstMatch(xml)?.group(1) ?? '');
    final time = DateTime.tryParse(
      _timePattern.firstMatch(xml)?.group(1) ?? '',
    );
    if ((id != 1000 && id != 1002) || time == null) return null;
    final named = <String, String>{};
    final positional = <String>[];
    for (final match in _dataPattern.allMatches(xml)) {
      final value = _unescape(match.group(2) ?? '').trim();
      positional.add(value);
      final name = match.group(1);
      if (name != null) named[name] = value;
    }
    return _WindowsEvent(id!, time, named, positional);
  }

  /// שדה לפי שם, ובאירועים ישנים בלי שמות — לפי המיקום הקבוע.
  String? field(String name, int index) =>
      _named[name] ??
      (_named.isEmpty && index < _positional.length
          ? _positional[index]
          : null);

  bool belongsTo(int pid, String exeName, DateTime start, DateTime end) {
    final isCrash = id == 1000;
    if (_parsePid(field('ProcessId', isCrash ? 8 : 2)) != pid) return false;
    final app = field('AppName', 0);
    if (app == null || app.toLowerCase() != exeName.toLowerCase()) {
      return false;
    }
    if (time.isBefore(start) || time.isAfter(end)) return false;
    // יצירת התהליך יכולה להקדים את ציר העלייה של Dart; זמן חסר אינו ראיה.
    final created = _fileTime(
      field(isCrash ? 'ProcessCreationTime' : 'StartTime', isCrash ? 9 : 3),
    );
    return created != null &&
        !created.isAfter(start.add(const Duration(seconds: 2)));
  }

  SystemExitEvidence? crashEvidence() {
    final code = _hex(field('ExceptionCode', 6));
    if (code == null) return null;
    final codeText = '0x${code.toRadixString(16).padLeft(8, '0')}';
    final module = _safeName(field('ModuleName', 3));
    final offset = _hex(field('FaultingOffset', 7));
    final frame = module == null || offset == null
        ? null
        : CrashSignature.normalizeFrame(
            '$module+0x${offset.toRadixString(16)}',
          );
    final type = frame == null ? codeText : '$codeText $frame';
    final version = _safeVersion(field('ModuleVersion', 4));
    return SystemExitEvidence(
      isHang: false,
      signature: CrashSignature(
        exceptionType: type.length <= CrashSignature.maxExceptionTypeLength
            ? type
            : type.substring(0, CrashSignature.maxExceptionTypeLength),
        frames: [?frame],
      ),
      details: [
        'System event: Windows Application Error 1000',
        'Exception code: $codeText',
        if (module != null) 'Faulting module: $module',
        if (version != null) 'Module version: $version',
        if (offset != null) 'Fault offset: 0x${offset.toRadixString(16)}',
      ].join('\n'),
    );
  }

  SystemExitEvidence hangEvidence() {
    final hangType = field('HangType', 9);
    final safeType =
        hangType != null && RegExp(r'^[A-Za-z \-]{1,60}$').hasMatch(hangType)
        ? hangType
        : null;
    return SystemExitEvidence(
      isHang: true,
      signature: const CrashSignature(
        exceptionType: 'Application Hang',
        frames: [],
      ),
      details: [
        'System event: Windows Application Hang 1002',
        if (safeType != null) 'Hang type: $safeType',
      ].join('\n'),
    );
  }

  static int? _parsePid(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    return lower.startsWith('0x')
        ? int.tryParse(lower.substring(2), radix: 16)
        : int.tryParse(lower);
  }

  static int? _hex(String? value) {
    if (value == null) return null;
    final digits = value.toLowerCase().replaceFirst('0x', '');
    return RegExp(r'^[0-9a-f]{1,16}$').hasMatch(digits)
        ? int.tryParse(digits, radix: 16)
        : null;
  }

  static DateTime? _fileTime(String? value) {
    final ticks = _hex(value);
    if (ticks == null || ticks <= 0) return null;
    return DateTime.utc(1601).add(Duration(microseconds: ticks ~/ 10));
  }

  /// שם קובץ בלבד; שם עם תווים חריגים נשמט כדי שלא ידלוף תוכן אחר.
  static String? _safeName(String? value) {
    if (value == null) return null;
    final name = value.split(RegExp(r'[\\/]')).last;
    return RegExp(r'^[\w.\-]{1,100}$').hasMatch(name) ? name : null;
  }

  static String? _safeVersion(String? value) =>
      value != null && RegExp(r'^[\d.]{1,40}$').hasMatch(value) ? value : null;

  static String _unescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// מסנן לאירועי קרנל גם מאתחולים קודמים.
@visibleForTesting
List<String> linuxOomJournalArguments(DateTime start, DateTime end) => [
  '-q',
  '--no-pager',
  '-o',
  'short-unix',
  '--since',
  '@${start.millisecondsSinceEpoch ~/ 1000}',
  '--until',
  '@${end.millisecondsSinceEpoch ~/ 1000 + 1}',
  '_TRANSPORT=kernel',
];

Future<SystemExitEvidence?> _readLinuxOomKill(
  int pid,
  DateTime start,
  DateTime end,
  Duration timeout,
) async {
  final process = await Process.start(
    'journalctl',
    linuxOomJournalArguments(start, end),
  );
  unawaited(process.stderr.drain<void>());
  try {
    // סינון על הזרם: יומן קרנל של ימים לא נשמר בזיכרון.
    final lines = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where(
          (line) =>
              line.contains('Killed process $pid ') ||
              line.contains('pid=$pid,'),
        )
        .take(_maxEvents)
        .toList()
        .timeout(timeout);
    return linuxOomKillEvidence(
      lines,
      pid: pid,
      processName: p.basename(Platform.resolvedExecutable),
      start: start,
      end: end,
    );
  } finally {
    process.kill();
  }
}

/// הריגת OOM של [pid] ו-[processName] בדיוק (אין זמן יצירה נגד pid ממוחזר).
/// נשמרים רק סוג האירוע ונתוני הזיכרון — לא השורה (שם מחשב, uid, cgroup).
@visibleForTesting
SystemExitEvidence? linuxOomKillEvidence(
  Iterable<String> lines, {
  required int pid,
  required String processName,
  required DateTime start,
  required DateTime end,
}) {
  // שם התהליך בקרנל (comm) נחתך ל-15 תווים.
  final comm = RegExp.escape(
    processName.length > 15 ? processName.substring(0, 15) : processName,
  );
  final killed = RegExp('Killed process $pid \\($comm\\)');
  final oomKill = RegExp('oom-kill:.*[,:]task=$comm,pid=$pid,');
  var found = false;
  String? anonRss;
  String? totalVm;
  for (final line in lines) {
    if (!killed.hasMatch(line) && !oomKill.hasMatch(line)) continue;
    final seconds = double.tryParse(line.split(' ').first);
    if (seconds == null) continue;
    final at = DateTime.fromMicrosecondsSinceEpoch(
      (seconds * 1000000).round(),
      isUtc: true,
    );
    if (at.isBefore(start) || at.isAfter(end)) continue;
    found = true;
    String? kb(String name) =>
        RegExp('$name:(\\d+)kB').firstMatch(line)?.group(1);
    anonRss ??= kb('anon-rss');
    totalVm ??= kb('total-vm');
  }
  if (!found) return null;
  return SystemExitEvidence(
    isHang: false,
    signature: const CrashSignature(
      exceptionType: 'SIGKILL (oom-kill)',
      frames: [],
    ),
    details: [
      'System event: Linux kernel oom-kill',
      if (anonRss != null) 'Anon RSS: $anonRss kB',
      if (totalVm != null) 'Total VM: $totalVm kB',
    ].join('\n'),
  );
}
