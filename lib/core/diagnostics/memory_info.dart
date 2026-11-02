import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// זיכרון המחשב והתהליך ב-MB, לדוחות. שדה שלא ניתן לקרוא חסר; לעולם לא זורק.
Map<String, int> memoryInfo() {
  final info = <String, int>{};
  try {
    info['processRssMb'] = ProcessInfo.currentRss >> 20;
    info['processPeakRssMb'] = ProcessInfo.maxRss >> 20;
    if (Platform.isWindows) {
      info.addAll(_windowsMemory());
    } else if (Platform.isLinux) {
      info.addAll(parseMemInfo(File('/proc/meminfo').readAsStringSync()));
    }
  } catch (_) {}
  return info;
}

/// שורה אחת לרשומות errors.txt.
String formatMemoryLine(Map<String, int> info) =>
    info.entries.map((e) => '${e.key}=${e.value}').join(' ');

/// `MemTotal` ו-`MemAvailable` מתוך `/proc/meminfo`.
@visibleForTesting
Map<String, int> parseMemInfo(String text) {
  int? kb(String key) {
    final match = RegExp(
      '^$key:\\s+(\\d+)\\s+kB',
      multiLine: true,
    ).firstMatch(text);
    return match == null ? null : int.parse(match.group(1)!);
  }

  return {
    if (kb('MemTotal') case final total?) 'totalRamMb': total >> 10,
    if (kb('MemAvailable') case final available?)
      'availableRamMb': available >> 10,
  };
}

// ב-Windows 8 ומעלה PagefileUsage הוא ה-commit הפרטי של התהליך.
Map<String, int> _windowsMemory() {
  final info = <String, int>{};
  final status = calloc<MEMORYSTATUSEX>();
  final counters = calloc<PROCESS_MEMORY_COUNTERS>();
  try {
    status.ref.dwLength = sizeOf<MEMORYSTATUSEX>();
    if (GlobalMemoryStatusEx(status).value) {
      info['totalRamMb'] = status.ref.ullTotalPhys >> 20;
      info['availableRamMb'] = status.ref.ullAvailPhys >> 20;
    }
    final size = sizeOf<PROCESS_MEMORY_COUNTERS>();
    counters.ref.cb = size;
    if (GetProcessMemoryInfo(GetCurrentProcess(), counters, size).value) {
      info['processCommitMb'] = counters.ref.PagefileUsage >> 20;
      info['processPeakCommitMb'] = counters.ref.PeakPagefileUsage >> 20;
    }
  } finally {
    calloc.free(status);
    calloc.free(counters);
  }
  return info;
}
