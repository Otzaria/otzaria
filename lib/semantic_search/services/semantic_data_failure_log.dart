import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';

/// רושם ב-errors.txt כשל בהורדה, בהתקנה או בפתיחה של נתוני החיפוש החכם,
/// כדי שדיווח מהתוכנה יכלול את הסיבה. כל צירוף של שלב וסוג נרשם לכל היותר
/// פעם ב-[interval].
class SemanticDataFailureLog {
  SemanticDataFailureLog({
    DateTime Function()? clock,
    void Function(SemanticFailure failure, Map<String, String?> details)? write,
    this.interval = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now,
       _write = write ?? _append;

  static final SemanticDataFailureLog shared = SemanticDataFailureLog();

  /// מצבים של המשתמש או של התזמון, לא תקלות.
  static const Set<SemanticFailureKind> _notFaults = {
    SemanticFailureKind.cancelled,
    SemanticFailureKind.offline,
    SemanticFailureKind.consentRequired,
    SemanticFailureKind.notReady,
    SemanticFailureKind.libraryMoving,
    SemanticFailureKind.vectorsBusy,
  };

  final DateTime Function() _clock;
  final void Function(SemanticFailure, Map<String, String?>) _write;
  final Duration interval;
  final Map<String, DateTime> _loggedAt = {};

  void record(
    String step,
    SemanticFailure failure, {
    Map<String, String?> details = const {},
  }) {
    if (_notFaults.contains(failure.kind)) return;
    final key = '$step:${failure.kind.name}';
    final now = _clock();
    final last = _loggedAt[key];
    if (last != null && now.difference(last) < interval) return;
    _loggedAt[key] = now;
    _write(failure, {'Step': step, ...details});
  }

  static void _append(SemanticFailure failure, Map<String, String?> details) {
    try {
      ErrorLogFile.append(
        title: 'חיפוש חכם: הכנת הנתונים נכשלה',
        error: failure,
        details: details,
      );
    } catch (error) {
      debugPrint('[SemanticDataFailureLog] $error');
    }
  }
}
