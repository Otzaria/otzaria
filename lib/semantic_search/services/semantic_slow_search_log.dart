import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/diagnostics/memory_info.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticSearchResponse, SemanticTimings;

/// רושם ב-errors.txt חיפוש חכם שנמשך [threshold] ומעלה, עם זמני השלבים של
/// המנוע, כדי שדיווח יראה היכן הלך הזמן. לכל היותר פעם ב-[interval].
class SemanticSlowSearchLog {
  SemanticSlowSearchLog({
    DateTime Function()? clock,
    void Function(Duration total, Map<String, String?> details)? write,
    this.threshold = const Duration(seconds: 10),
    this.interval = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now,
       _write = write ?? _append;

  static final SemanticSlowSearchLog shared = SemanticSlowSearchLog();

  final DateTime Function() _clock;
  final void Function(Duration, Map<String, String?>) _write;
  final Duration threshold;
  final Duration interval;
  DateTime? _loggedAt;

  /// [prepare] הוא זמן ההמתנה ל-ensureOpen, כולל בדיקת הזמינות.
  void record({
    required Duration total,
    required Duration? prepare,
    required SemanticSearchResponse response,
    required int Function() countQueryWords,

    /// מספר ה-facets שמגבילים את ההיקף; 0 = כל הספרייה.
    required int facets,
    required int offset,
  }) {
    if (total < threshold) return;
    final now = _clock();
    final last = _loggedAt;
    if (last != null && now.difference(last) < interval) return;
    _loggedAt = now;
    _write(total, {
      'Prepare ms': prepare?.inMilliseconds.toString(),
      'Engine ms': response.latencyMs.toString(),
      'Stages': formatStages(response.timings),
      'Mode': '${response.requestedMode.name} -> ${response.executedMode.name}',
      'Scope': facets == 0 ? 'all books' : '$facets facets',
      'Query words': '${countQueryWords()}',
      'Page offset': '$offset',
      'Results': '${response.results.length}',
    });
  }

  @visibleForTesting
  static String formatStages(SemanticTimings? timings) {
    if (timings == null) return 'not reported';
    String ms(double? value) => value?.round().toString() ?? 'n/a';
    return 'expansions=${timings.expansions}'
        ' lexical=${ms(timings.lexicalMs)}'
        ' semantic=${ms(timings.semanticMs)}'
        ' embed=${ms(timings.embedMs)}'
        ' scan=${ms(timings.scanMs)}'
        ' resolve=${ms(timings.resolveMs)}'
        ' fuse=${ms(timings.fuseMs)}'
        ' hydrate=${ms(timings.hydrateMs)}'
        ' page=${ms(timings.pageMs)}'
        ' total=${ms(timings.totalMs)}';
  }

  static void _append(Duration total, Map<String, String?> details) {
    unawaited(_collectAndAppend(total, details, DateTime.now()));
  }

  static Future<void> _collectAndAppend(
    Duration total,
    Map<String, String?> details,
    DateTime timestamp,
  ) async {
    try {
      final memory = await Isolate.run(memoryInfo);
      ErrorLogFile.appendInBackground(
        title: 'Slow smart search',
        error: 'Smart search took ${total.inMilliseconds} ms',
        timestamp: timestamp,
        details: {...details, 'Memory': formatMemoryLine(memory)},
      );
    } catch (error) {
      debugPrint('[SemanticSlowSearchLog] $error');
    }
  }
}
