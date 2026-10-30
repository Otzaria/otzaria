import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';

/// רושם ב-errors.txt למה החלק הסמנטי לא שירת חיפוש, כדי שדיווח יראה את
/// הסיבה. כל סוג נרשם לכל היותר פעם ב-[interval].
class SemanticFallbackLog {
  SemanticFallbackLog({
    DateTime Function()? clock,
    void Function(SemanticFailure failure, Map<String, String?> details)? write,
    this.interval = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now,
       _write = write ?? _append;

  static final SemanticFallbackLog shared = SemanticFallbackLog();

  final DateTime Function() _clock;
  final void Function(SemanticFailure, Map<String, String?>) _write;
  final Duration interval;
  final Map<SemanticFailureKind, DateTime> _loggedAt = {};

  void record(
    SemanticFailureKind kind,
    String? reason, {
    required String requestedMode,
    required String executedMode,
  }) {
    final now = _clock();
    final last = _loggedAt[kind];
    if (last != null && now.difference(last) < interval) return;
    _loggedAt[kind] = now;
    _write(SemanticFailure(kind, reason ?? ''), {
      'Requested mode': requestedMode,
      'Executed mode': executedMode,
    });
  }

  static void _append(SemanticFailure failure, Map<String, String?> details) {
    try {
      ErrorLogFile.append(
        title: 'חיפוש חכם: החלק הסמנטי נכשל',
        error: failure,
        details: details,
      );
    } catch (error) {
      debugPrint('[SemanticFallbackLog] $error');
    }
  }
}
