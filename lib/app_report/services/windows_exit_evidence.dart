import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';
import 'package:xml/xml.dart';

/// ראיה מיומן Application של Windows, בלי הטקסט הגולמי של האירוע.
class WindowsExitEvidence {
  const WindowsExitEvidence({
    required this.eventId,
    required this.occurredAt,
    this.exceptionCode,
  });

  final int eventId;
  final DateTime occurredAt;
  final String? exceptionCode;

  bool get isHang => eventId == 1002;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'exceptionCode': ?exceptionCode,
  };
}

typedef WindowsExitEvidenceReader =
    Future<WindowsExitEvidence?> Function(
      int processId,
      int creationFileTime,
      DateTime from,
      DateTime until,
    );

/// מחפש אירוע של אותו מופע בדיוק. הקריאה ל-Windows רצה ב-isolate.
Future<WindowsExitEvidence?> readWindowsExitEvidence(
  int processId,
  int creationFileTime,
  DateTime from,
  DateTime until,
) async {
  if (!Platform.isWindows || !from.isBefore(until)) return null;
  final executable = p.basename(Platform.resolvedExecutable);
  if (executable.contains("'")) return null;
  return Isolate.run(
    () => _findEvent(executable, processId, creationFileTime, from, until),
  ).timeout(const Duration(seconds: 4), onTimeout: () => null);
}

WindowsExitEvidence? _findEvent(
  String executable,
  int processId,
  int creationFileTime,
  DateTime from,
  DateTime until,
) {
  final deadline = Stopwatch()..start();
  final channel = 'Application'.toPcwstr();
  final xpath =
      ("*[System[((Provider[@Name='Application Error'] and EventID=1000) or "
              "(Provider[@Name='Application Hang'] and EventID=1002)) and "
              "TimeCreated[@SystemTime>='${from.toUtc().toIso8601String()}' and "
              "@SystemTime<='${until.toUtc().toIso8601String()}']]] "
              "and *[EventData[Data[@Name='AppName']='$executable']]")
          .toPcwstr();
  final event = calloc<IntPtr>();
  final returned = calloc<Uint32>();
  final bufferUsed = calloc<Uint32>();
  final propertyCount = calloc<Uint32>();
  var query = 0;
  try {
    query = EvtQuery(
      null,
      channel,
      xpath,
      EvtQueryChannelPath | EvtQueryReverseDirection,
    ).value;
    if (query == 0) return null;
    for (var i = 0; i < 32; i++) {
      final remaining = 3000 - deadline.elapsedMilliseconds;
      if (remaining <= 0 ||
          !EvtNext(EVT_HANDLE(query), 1, event, remaining, 0, returned).value ||
          returned.value != 1) {
        return null;
      }
      final handle = EVT_HANDLE(event.value);
      try {
        final xml = _renderEvent(handle, bufferUsed, propertyCount);
        if (xml == null) continue;
        final evidence = parseWindowsExitEvent(
          xml,
          executable: executable,
          processId: processId,
          creationFileTime: creationFileTime,
          from: from,
          until: until,
        );
        if (evidence != null) return evidence;
      } finally {
        EvtClose(handle);
      }
    }
    return null;
  } finally {
    if (query != 0) EvtClose(EVT_HANDLE(query));
    malloc.free(channel);
    malloc.free(xpath);
    calloc.free(event);
    calloc.free(returned);
    calloc.free(bufferUsed);
    calloc.free(propertyCount);
  }
}

String? _renderEvent(
  EVT_HANDLE handle,
  Pointer<Uint32> bufferUsed,
  Pointer<Uint32> propertyCount,
) {
  bufferUsed.value = 0;
  EvtRender(
    null,
    handle,
    EvtRenderEventXml,
    0,
    null,
    bufferUsed,
    propertyCount,
  );
  final bytes = bufferUsed.value;
  if (bytes < 2 || bytes > 64 * 1024) return null;
  final buffer = calloc<Uint8>(bytes);
  try {
    if (!EvtRender(
      null,
      handle,
      EvtRenderEventXml,
      bytes,
      buffer,
      bufferUsed,
      propertyCount,
    ).value) {
      return null;
    }
    return buffer.cast<Utf16>().toDartString(length: bufferUsed.value ~/ 2 - 1);
  } finally {
    calloc.free(buffer);
  }
}

@visibleForTesting
WindowsExitEvidence? parseWindowsExitEvent(
  String xml, {
  required String executable,
  required int processId,
  required int creationFileTime,
  required DateTime from,
  required DateTime until,
}) {
  final XmlElement event;
  try {
    event = XmlDocument.parse(xml).rootElement;
  } on XmlException {
    return null;
  }
  if (event.name.local != 'Event') return null;
  final system = event.getElement('System');
  final eventId = int.tryParse(system?.getElement('EventID')?.innerText ?? '');
  final provider = system?.getElement('Provider')?.getAttribute('Name');
  final expectedProvider = switch (eventId) {
    1000 => 'Application Error',
    1002 => 'Application Hang',
    _ => null,
  };
  if (expectedProvider == null || provider != expectedProvider) return null;
  final time = DateTime.tryParse(
    system?.getElement('TimeCreated')?.getAttribute('SystemTime') ?? '',
  );
  if (time == null || time.isBefore(from) || !time.isBefore(until)) return null;

  final payload = event.getElement('EventData');
  if (payload == null) return null;
  String? field(String key) => payload
      .findElements('Data')
      .where((data) => data.getAttribute('Name') == key)
      .singleOrNull
      ?.innerText
      .trim();

  final startField = eventId == 1000 ? 'ProcessCreationTime' : 'StartTime';
  if (field('AppName')?.toLowerCase() != executable.toLowerCase() ||
      _parseHex(field('ProcessId')) != processId ||
      _parseHex(field(startField)) != creationFileTime) {
    return null;
  }
  final code = eventId == 1000 ? _parseHex(field('ExceptionCode')) : null;
  return WindowsExitEvidence(
    eventId: eventId!,
    occurredAt: time,
    exceptionCode: code != null && code >= 0 && code <= 0xffffffff
        ? '0x${code.toRadixString(16).padLeft(8, '0')}'
        : null,
  );
}

int? _parseHex(String? value) {
  if (value == null) return null;
  final digits = value.toLowerCase();
  return int.tryParse(
    digits.startsWith('0x') ? digits.substring(2) : digits,
    radix: 16,
  );
}
