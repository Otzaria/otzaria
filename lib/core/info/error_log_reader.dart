import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;

/// רשומת שגיאה בודדת שנקראה מקובץ לוג.
class ErrorLogEntry {
  /// שם קובץ הלוג שממנו נקראה הרשומה.
  final String source;
  final DateTime? timestamp;
  final String title;
  final String? version;
  final String? message;

  /// ראש ה-stack trace (מספר פריימים ראשונים), אם קיים.
  final String? stackHead;

  const ErrorLogEntry({
    required this.source,
    required this.title,
    this.timestamp,
    this.version,
    this.message,
    this.stackHead,
  });

  Map<String, dynamic> toJson() => {
    'source': source,
    'title': title,
    if (timestamp != null) 'timestamp': utcIso(timestamp)!,
    if (version != null) 'version': version,
    if (message != null) 'message': message,
    if (stackHead != null) 'stack': stackHead,
  };
}

/// חותמת UTC עם סיומת `Z`. כל הזמנים בדוח אחידים — חותמת נאיבית אינה
/// ניתנת לפירוש ע"י צרכן חיצוני.
String? utcIso(DateTime? value) => value?.toUtc().toIso8601String();

/// קובץ לוג שנסקר, גם כשאין בו רשומות.
class ErrorLogFileSummary {
  final String path;
  final bool exists;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final int entryCount;

  /// סיבת הכשל כשהקובץ קיים אך לא ניתן לקרוא/לפענח אותו. בלעדיה מכונה
  /// שקורסת הייתה מקבלת דוח שמצהיר "אין שגיאות".
  final String? readError;

  const ErrorLogFileSummary({
    required this.path,
    required this.exists,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.entryCount = 0,
    this.readError,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'exists': exists,
    if (exists) 'sizeBytes': sizeBytes,
    if (modifiedAt != null) 'modifiedAt': utcIso(modifiedAt)!,
    if (exists) 'entryCount': entryCount,
    if (readError != null) 'readError': readError,
  };
}

/// תוצאת סריקה של כל קובצי הלוג.
class ErrorLogReport {
  final List<ErrorLogFileSummary> files;

  /// הרשומות האחרונות מכל הקבצים, מהחדשה לישנה.
  final List<ErrorLogEntry> recent;

  /// סך הרשומות בכל הקבצים (לפני החתך ל-[recent]).
  final int totalEntries;

  const ErrorLogReport({
    required this.files,
    required this.recent,
    required this.totalEntries,
  });

  Map<String, dynamic> toJson() => {
    'totalEntries': totalEntries,
    'returnedEntries': recent.length,
    'files': files.map((file) => file.toJson()).toList(),
    'recent': recent.map((entry) => entry.toJson()).toList(),
  };
}

/// קורא את קובצי הלוג של אוצריא ומחלץ מהם את הרשומות האחרונות.
///
/// שני פורמטים נתמכים:
/// * `logs/errors.txt` — בלוקים שמתחילים ב-`=== <כותרת> <ISO8601> ===`.
/// * `%TEMP%/otzaria_shutdown_errors.log` — שורה לכל רשומה: `<ISO8601> | סיבה`.
class ErrorLogReader {
  /// שם קובץ הלוג של כשלי סגירה מהירה ב-Windows (`window_listener.dart`).
  static const String shutdownLogFileName = 'otzaria_shutdown_errors.log';

  /// מספר פריימי ה-stack שנשמרים לכל רשומה — די כדי לזהות, בלי לנפח את הדוח.
  static const int _stackHeadFrames = 3;

  static final RegExp _blockHeader = RegExp(r'^===\s+(.*?)\s+(\S+)\s+===\s*$');
  static final RegExp _shutdownLine = RegExp(r'^(\S+)\s+\|\s+(.*)$');

  const ErrorLogReader._();

  /// אוסף דוח מכל קובצי הלוג המקומיים.
  static Future<ErrorLogReport> collect({int limit = 5}) async {
    final files = <ErrorLogFileSummary>[];
    final entries = <ErrorLogEntry>[];
    await ErrorLogFile.flushPending();

    for (final candidate in _candidatePaths()) {
      final file = File(candidate.path);
      if (!await file.exists()) {
        files.add(ErrorLogFileSummary(path: candidate.path, exists: false));
        continue;
      }

      List<ErrorLogEntry> parsed = const [];
      FileStat? stat;
      String? readError;
      try {
        stat = await file.stat();
        final content = await file.readAsString();
        parsed = candidate.isBlockFormat
            ? parseBlockLog(content, source: p.basename(candidate.path))
            : parseLineLog(content, source: p.basename(candidate.path));
      } catch (error) {
        // קובץ לוג פגום/נעול אינו מבטל את שאר הדוח, אבל הכשל מדווח בדוח
        // עצמו — לא רק ב-debugPrint שאינו קיים ב-release.
        readError = '$error';
        debugPrint('ErrorLogReader: failed reading ${candidate.path}: $error');
      }

      files.add(
        ErrorLogFileSummary(
          path: candidate.path,
          exists: true,
          sizeBytes: stat?.size ?? 0,
          modifiedAt: stat?.modified,
          entryCount: parsed.length,
          readError: readError,
        ),
      );
      entries.addAll(parsed);
    }

    return ErrorLogReport(
      files: files,
      recent: sortNewestFirst(entries).take(limit).toList(),
      totalEntries: entries.length,
    );
  }

  /// ממיין מהחדש לישן. רשומות בלי חותמת זמן נדחקות לסוף.
  @visibleForTesting
  static List<ErrorLogEntry> sortNewestFirst(List<ErrorLogEntry> entries) {
    final sorted = entries.toList()
      ..sort((a, b) {
        final left = a.timestamp;
        final right = b.timestamp;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
    return sorted;
  }

  /// מפענח לוג בפורמט הבלוקים של [ErrorLogFile].
  @visibleForTesting
  static List<ErrorLogEntry> parseBlockLog(
    String content, {
    required String source,
  }) {
    final entries = <ErrorLogEntry>[];
    String? title;
    DateTime? timestamp;
    var body = <String>[];

    void flush() {
      if (title == null) return;
      entries.add(_buildBlockEntry(source, title, timestamp, body));
    }

    for (final line in const LineSplitter().convert(content)) {
      final header = _blockHeader.firstMatch(line);
      if (header == null) {
        if (title != null) body.add(line);
        continue;
      }
      flush();
      title = header.group(1)!.trim();
      timestamp = DateTime.tryParse(header.group(2)!);
      body = <String>[];
    }
    flush();

    return entries;
  }

  /// מפענח לוג של שורה-לרשומה (`<ISO8601> | סיבה`).
  @visibleForTesting
  static List<ErrorLogEntry> parseLineLog(
    String content, {
    required String source,
  }) {
    final entries = <ErrorLogEntry>[];
    for (final line in const LineSplitter().convert(content)) {
      final match = _shutdownLine.firstMatch(line.trim());
      if (match == null) continue;
      final timestamp = DateTime.tryParse(match.group(1)!);
      if (timestamp == null) continue;
      entries.add(
        ErrorLogEntry(
          source: source,
          title: 'סגירה כפויה',
          timestamp: timestamp,
          message: match.group(2)!.trim(),
        ),
      );
    }
    return entries;
  }

  static ErrorLogEntry _buildBlockEntry(
    String source,
    String title,
    DateTime? timestamp,
    List<String> body,
  ) {
    String? version;
    String? message;
    final stack = <String>[];
    var inStack = false;

    for (final line in body) {
      if (inStack) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // דוח כשלי אינדוקס משרשר בלוקים `--- Failure N ---` אחרי ה-stack;
        // בלי העצירה הזו הכותרת הבאה נספרת כפריים.
        if (trimmed.startsWith('---')) {
          inStack = false;
          continue;
        }
        if (stack.length < _stackHeadFrames) stack.add(trimmed);
        continue;
      }
      if (line.trimRight() == 'Stack:') {
        inStack = true;
        continue;
      }
      if (version == null && line.startsWith('Version:')) {
        version = line.substring('Version:'.length).trim();
        continue;
      }
      if (message == null && line.startsWith('Exception:')) {
        message = line.substring('Exception:'.length).trim();
        continue;
      }
      // דוח כשלי אינדוקס אינו כותב Exception — השורה המסכמת היא המידע.
      if (message == null && line.startsWith('Failures:')) {
        message = line.trim();
      }
    }

    return ErrorLogEntry(
      source: source,
      title: title,
      timestamp: timestamp,
      version: (version == null || version.isEmpty) ? null : version,
      message: (message == null || message.isEmpty) ? null : message,
      stackHead: stack.isEmpty ? null : stack.join('\n'),
    );
  }

  static List<_LogCandidate> _candidatePaths() {
    final candidates = <_LogCandidate>[
      _LogCandidate(ErrorLogFile.resolvePath(), isBlockFormat: true),
    ];

    if (Platform.isWindows) {
      final temp = Platform.environment['TEMP'];
      if (temp != null && temp.isNotEmpty) {
        candidates.add(
          _LogCandidate(
            p.join(temp, shutdownLogFileName),
            isBlockFormat: false,
          ),
        );
      }
    }

    return candidates;
  }
}

class _LogCandidate {
  final String path;
  final bool isBlockFormat;
  const _LogCandidate(this.path, {required this.isBlockFormat});
}
