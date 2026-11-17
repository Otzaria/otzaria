import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/search/active_lexical_searches.dart';
import 'package:path/path.dart' as p;

/// מה שהתוכנה הציגה וחיפשה, נשמר לדיסק לדוח על ההפעלה הקודמת.
class SessionContextSnapshot {
  SessionContextSnapshot({
    String? path,
    Map<String, Object?> Function()? capture,
    DateTime Function()? clock,
    this.interval = const Duration(seconds: 3),
  }) : _pathOverride = path,
       _capture = capture ?? _defaultCapture,
       _clock = clock ?? DateTime.now;

  static final SessionContextSnapshot instance = SessionContextSnapshot();

  static const String fileName = 'last_context.json';

  final String? _pathOverride;
  final Map<String, Object?> Function() _capture;
  final DateTime Function() _clock;
  final Duration interval;

  Future<Map<String, dynamic>?>? _previous;
  Timer? _timer;
  bool _started = false;
  bool _writing = false;
  String? _lastWritten;

  String get path =>
      _pathOverride ?? p.join(p.dirname(ErrorLogFile.resolvePath()), fileName);

  /// התמונה שההפעלה הקודמת השאירה. נקראת פעם אחת, לפני הכתיבה הראשונה כאן.
  Future<Map<String, dynamic>?> get previous => _previous ??= _read();

  /// התמונה רק אם נשמרה בהפעלה [session]. בלי נעילה (ANR) אין זיהוי אמין
  /// של ההפעלה: מספר תהליך עלול להיות בשימוש חוזר, וזמן יציאה אינו זמן התחלה.
  Future<Map<String, dynamic>?> previousFor(SessionLock? session) async {
    if (session == null) return null;
    final snapshot = await previous;
    if (snapshot == null) return null;
    final savedAt = DateTime.tryParse('${snapshot['savedAt']}');
    final matches =
        snapshot['pid'] == session.pid &&
        savedAt != null &&
        !savedAt.isBefore(session.startedAt);
    return matches ? snapshot : null;
  }

  /// מתחיל לשמור. פעם אחת לתהליך.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await previous;
    await record();
    _timer = Timer.periodic(interval, (_) => unawaited(record()));
  }

  @visibleForTesting
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// כותב רק כשהתוכן השתנה. הכתיבה לקובץ זמני ושינוי שם: תהליך שנהרג באמצע
  /// אינו משאיר קובץ חתוך.
  @visibleForTesting
  Future<void> record() async {
    if (_writing) return;
    final Map<String, Object?> snapshot;
    final String encoded;
    try {
      snapshot = _capture();
      encoded = jsonEncode(snapshot);
    } catch (error) {
      debugPrint('SessionContextSnapshot: capture failed: $error');
      return;
    }
    if (encoded == _lastWritten) return;
    _writing = true;
    try {
      final target = File(path);
      await target.parent.create(recursive: true);
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'savedAt': _clock().toUtc().toIso8601String(),
          'pid': pid,
          ...snapshot,
        }),
        flush: true,
      );
      await temp.rename(target.path);
      _lastWritten = encoded;
    } catch (error) {
      debugPrint('SessionContextSnapshot: write failed: $error');
    } finally {
      _writing = false;
    }
  }

  Future<Map<String, dynamic>?> _read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? json : null;
    } catch (error) {
      debugPrint('SessionContextSnapshot: read failed: $error');
      return null;
    }
  }

  static Map<String, Object?> _defaultCapture() => {
    'context':
        DeveloperDiagnostics.instance.contextProvider?.call() ?? const {},
    'searches': ActiveLexicalSearches.instance.collect(),
  };
}
