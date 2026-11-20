import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// מה שמערכת ההפעלה רשמה על סיום ההפעלה הקודמת: ב-Windows אירועי
/// Application Error (1000) ו-Application Hang (1002), בלינוקס הריגת OOM.
/// נקרא רק בדוח על סגירה לא תקינה; לעולם לא זורק.
Future<List<Map<String, Object?>>> readPreviousRunSystemEvents(
  SessionLock session, {
  DateTime? until,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (kIsWeb) return const [];
  final end = (until ?? DateTime.now()).toUtc();
  final start = session.startedAt.toUtc().subtract(const Duration(minutes: 1));
  try {
    if (Platform.isWindows) {
      final exe = p.basename(Platform.resolvedExecutable);
      final pid = session.pid;
      return await Isolate.run(
        () => _queryWindowsEvents(exe, pid, start, end),
      ).timeout(timeout, onTimeout: () => const []);
    }
    if (Platform.isLinux) {
      return await _queryLinuxOom(session.pid, start, end, timeout);
    }
  } catch (error) {
    debugPrint('readPreviousRunSystemEvents: $error');
  }
  return const [];
}

const int _maxEvents = 8;
const int _maxFields = 16;
const int _maxValueChars = 200;

List<Map<String, Object?>> _queryWindowsEvents(
  String exe,
  int pid,
  DateTime start,
  DateTime end,
) {
  final query = windowsEventQuery(exe, start, end);
  final channel = 'Application'.toPcwstr();
  final xpath = query.toPcwstr();
  final events = calloc<IntPtr>(_maxEvents);
  final returned = calloc<Uint32>();
  final used = calloc<Uint32>();
  final count = calloc<Uint32>();
  final results = <Map<String, Object?>>[];
  var handle = 0;
  try {
    handle = EvtQuery(
      null,
      channel,
      xpath,
      EvtQueryChannelPath | EvtQueryReverseDirection,
    ).value;
    if (handle == 0) return results;
    if (!EvtNext(
      EVT_HANDLE(handle),
      _maxEvents,
      events,
      2000,
      0,
      returned,
    ).value) {
      return results;
    }
    for (var i = 0; i < returned.value; i++) {
      final event = events[i];
      try {
        final xml = _renderXml(event, used, count);
        final parsed = xml == null ? null : parseWindowsEvent(xml, pid);
        if (parsed != null) results.add(parsed);
      } finally {
        EvtClose(EVT_HANDLE(event));
      }
    }
  } finally {
    if (handle != 0) EvtClose(EVT_HANDLE(handle));
    malloc.free(channel);
    malloc.free(xpath);
    calloc.free(events);
    calloc.free(returned);
    calloc.free(used);
    calloc.free(count);
  }
  return results;
}

String? _renderXml(int event, Pointer<Uint32> used, Pointer<Uint32> count) {
  EvtRender(null, EVT_HANDLE(event), EvtRenderEventXml, 0, null, used, count);
  final size = used.value;
  if (size == 0) return null;
  final buffer = calloc<Uint8>(size);
  try {
    if (!EvtRender(
      null,
      EVT_HANDLE(event),
      EvtRenderEventXml,
      size,
      buffer,
      used,
      count,
    ).value) {
      return null;
    }
    return buffer.cast<Utf16>().toDartString();
  } finally {
    calloc.free(buffer);
  }
}

/// XPath מצומצם: שני הספקים, טווח הזמן ושם קובץ ההפעלה.
@visibleForTesting
String windowsEventQuery(String exe, DateTime start, DateTime end) {
  String at(DateTime time) => time.toUtc().toIso8601String();
  final name = exe.replaceAll("'", '');
  return "*[System[Provider[@Name='Application Error' or "
      "@Name='Application Hang'] and (EventID=1000 or EventID=1002) and "
      "TimeCreated[@SystemTime>='${at(start)}' and "
      "@SystemTime<='${at(end)}']]] and *[EventData[Data='$name']]";
}

/// האירוע רק אם ה-pid שלו (הקסדצימלי, עם 0x או בלי) הוא של ההפעלה הקודמת.
/// נתיבים נשמטים: הם עלולים להכיל את שם המשתמש.
@visibleForTesting
Map<String, Object?>? parseWindowsEvent(String xml, int pid) {
  final id = RegExp(r'<EventID[^>]*>(\d+)</EventID>').firstMatch(xml);
  final provider = RegExp(r"<Provider Name='([^']*)'").firstMatch(xml);
  final time = RegExp(r"SystemTime='([^']*)'").firstMatch(xml);
  final hex = pid.toRadixString(16);
  var matchesPid = false;
  final data = <String, String>{};
  var index = 0;
  for (final match in RegExp(
    r"<Data(?: Name='([^']*)')?\s*(?:/>|>([^<]*)</Data>)",
  ).allMatches(xml)) {
    index++;
    final value = _unescape(match.group(2) ?? '').trim();
    final lower = value.toLowerCase();
    if (lower == '0x$hex' || lower == hex) matchesPid = true;
    if (value.isEmpty || value.contains(r'\') || data.length >= _maxFields) {
      continue;
    }
    data[match.group(1) ?? '$index'] = value.length > _maxValueChars
        ? value.substring(0, _maxValueChars)
        : value;
  }
  if (!matchesPid || id == null) return null;
  return {
    'provider': provider?.group(1),
    'eventId': int.parse(id.group(1)!),
    'time': time?.group(1),
    'data': data,
  };
}

String _unescape(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

Future<List<Map<String, Object?>>> _queryLinuxOom(
  int pid,
  DateTime start,
  DateTime end,
  Duration timeout,
) async {
  final process = await Process.start('journalctl', [
    '-k',
    '-q',
    '--no-pager',
    '-o',
    'short-iso',
    '--since',
    '@${start.millisecondsSinceEpoch ~/ 1000}',
    '--until',
    '@${end.millisecondsSinceEpoch ~/ 1000 + 60}',
  ]);
  unawaited(process.stderr.drain<void>());
  final output = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  try {
    final lines = await output.timeout(timeout);
    return [
      for (final line in matchLinuxOomLines(lines, pid)) {'line': line},
    ];
  } on TimeoutException {
    process.kill();
    return const [];
  }
}

/// שורות הקרנל על הריגת התהליך, או על OOM כללי באותו זמן.
@visibleForTesting
List<String> matchLinuxOomLines(List<String> lines, int pid) => lines
    .where(
      (line) =>
          line.contains('Killed process $pid ') ||
          (line.contains('oom-kill:') && line.contains('pid=$pid,')) ||
          line.contains('Out of memory'),
    )
    .take(_maxEvents)
    .toList();
