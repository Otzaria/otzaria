import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';

/// רושם ל-errors.txt סיכום של ריצת אינדוקס שכשלה בחלקה, או שנמשכה זמן רב.
///
/// ריצה נקייה וקצרה אינה נרשמת. ריצה נקייה שחרגה מסף העלייה האיטית כן —
/// אינדוקס מלא אחרי עדכון ספרייה מקפיא את התוכנה לדקות ומדווח כ"לא נפתחת"
/// (issue #1192), ובלי הרשומה אין דרך להבדיל בינו לעלייה איטית באמת.
class IndexingFailureReporter {
  const IndexingFailureReporter._();

  /// אותו סף כמו [StartupTimeline.slowThreshold] — מושג "איטי" אחד לכל היומן.
  static bool isSlowRun(Duration elapsed) =>
      elapsed >= StartupTimeline.instance.slowThreshold;

  static void write(IndexingRunResult result, Duration elapsed) {
    if (result.failures.isEmpty && !isSlowRun(elapsed)) return;
    try {
      ErrorLogFile.appendText(formatReport(result, elapsed: elapsed));
    } catch (error) {
      debugPrint('⚠️ כתיבת דוח כשלי האינדוקס נכשלה: $error');
    }
  }

  @visibleForTesting
  static void writeForTesting(
    IndexingRunResult result, {
    required String tempPath,
    DateTime? timestamp,
    String? version,
    Duration elapsed = Duration.zero,
  }) {
    if (result.failures.isEmpty && !isSlowRun(elapsed)) return;
    ErrorLogFile.appendText(
      formatReport(
        result,
        timestamp: timestamp,
        version: version,
        elapsed: elapsed,
      ),
      environment: const {},
      platform: ErrorLogPlatform.other,
      tempPath: tempPath,
    );
  }

  static String formatReport(
    IndexingRunResult result, {
    DateTime? timestamp,
    String? version,
    Duration? elapsed,
  }) {
    final title = result.failures.isEmpty
        ? 'Indexing run'
        : 'Indexing failures';
    final buffer = StringBuffer()
      ..writeln(
        '=== $title ${(timestamp ?? DateTime.now()).toIso8601String()} ===',
      )
      ..writeln('Version: ${version ?? ErrorLogFile.appVersion}');
    if (elapsed != null) buffer.writeln('Duration: ${elapsed.inSeconds}s');
    buffer
      ..writeln('Completed: ${result.completed}')
      ..writeln('Processed: ${result.processedBooks}/${result.totalBooks}')
      ..writeln('Indexed: ${result.indexedBooks}')
      ..writeln('Failures: ${result.failures.length}')
      ..writeln('Retryable: ${result.retryableFailures.length}')
      ..writeln('Warnings: ${result.warningCount}');

    for (var i = 0; i < result.failures.length; i++) {
      final failure = result.failures[i];
      buffer
        ..writeln()
        ..writeln('--- Failure ${i + 1} ---')
        ..writeln('Kind: ${failure.kind.name}')
        ..writeln('Retryable: ${failure.isRetryable}')
        ..writeln('Book: ${failure.bookTitle}')
        ..writeln('Path: ${failure.bookPath}')
        ..writeln('Error: ${failure.error}');
      final stackTrace = failure.stackTrace;
      if (stackTrace != null && stackTrace.trim().isNotEmpty) {
        buffer
          ..writeln('Stack:')
          ..writeln(stackTrace);
      }
    }
    buffer.writeln();
    return buffer.toString();
  }
}
