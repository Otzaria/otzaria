import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:otzaria/core/app_paths.dart';

/// שירות לרישום שגיאות ואירועים בתהליך האינדקס
class IndexingLogger {
  static final IndexingLogger _instance = IndexingLogger._internal();
  static IndexingLogger get instance => _instance;

  IndexingLogger._internal();

  File? _logFile;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// אתחול קובץ הלוג
  Future<void> initialize() async {
    try {
      final logPath = await AppPaths.getIndexingLogPath();
      _logFile = File(logPath);

      // יצירת התיקייה אם לא קיימת
      final directory = _logFile!.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // יצירת הקובץ אם לא קיים
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to initialize indexing logger: $e');
    }
  }

  /// רישום התחלת אינדוקס ספר ספציפי
  Future<void> logBookStart(String bookTitle, String bookType) async {
    await _writeLog(
      'INFO',
      'מתחיל אינדוקס: $bookTitle (סוג: $bookType)',
    );
  }

  /// רישום סיום מוצלח של אינדוקס ספר
  Future<void> logBookComplete(String bookTitle, String bookType) async {
    await _writeLog(
      'INFO',
      'הושלם אינדוקס: $bookTitle (סוג: $bookType)',
    );
  }

  /// רישום התקדמות כללית
  Future<void> logProgress(int processed, int total) async {
    await _writeLog(
      'INFO',
      'התקדמות: $processed/$total ספרים (${((processed / total) * 100).toStringAsFixed(1)}%)',
    );
  }

  /// רישום התחלת תהליך אינדקס
  Future<void> logIndexingStart(int totalBooks) async {
    await _writeLog(
      'INFO',
      'תהליך אינדקס התחיל - סה"כ $totalBooks ספרים לאינדוקס',
    );
  }

  /// רישום סיום מוצלח של תהליך אינדקס
  Future<void> logIndexingComplete(int processedBooks) async {
    await _writeLog(
      'INFO',
      'תהליך אינדקס הושלם בהצלחה - $processedBooks ספרים אוינדקסו',
    );
  }

  /// רישום ביטול תהליך אינדקס
  Future<void> logIndexingCancelled(int processedBooks, int totalBooks) async {
    await _writeLog(
      'WARNING',
      'תהליך אינדקס בוטל - אוינדקסו $processedBooks מתוך $totalBooks ספרים',
    );
  }

  /// רישום שגיאה באינדוקס ספר ספציפי
  Future<void> logBookError(
    String bookTitle,
    String bookType,
    String error,
    StackTrace? stackTrace,
  ) async {
    final message = StringBuffer();
    message.writeln('שגיאה באינדוקס ספר: $bookTitle (סוג: $bookType)');
    message.writeln('שגיאה: $error');
    if (stackTrace != null) {
      message.writeln('Stack trace:');
      message.writeln(stackTrace.toString());
    }

    await _writeLog('ERROR', message.toString());
  }

  /// רישום שגיאה כללית בתהליך האינדקס
  Future<void> logGeneralError(String error, StackTrace? stackTrace) async {
    final message = StringBuffer();
    message.writeln('שגיאה כללית בתהליך האינדקס');
    message.writeln('שגיאה: $error');
    if (stackTrace != null) {
      message.writeln('Stack trace:');
      message.writeln(stackTrace.toString());
    }

    await _writeLog('ERROR', message.toString());
  }

  /// רישום אזהרה
  Future<void> logWarning(String message) async {
    await _writeLog('WARNING', message);
  }

  /// רישום מידע כללי
  Future<void> logInfo(String message) async {
    await _writeLog('INFO', message);
  }

  /// כתיבה לקובץ הלוג
  Future<void> _writeLog(String level, String message) async {
    if (_logFile == null) {
      await initialize();
    }

    if (_logFile == null) {
      debugPrint('⚠️ Log file not initialized, printing to console instead:');
      debugPrint('[$level] $message');
      return;
    }

    try {
      final timestamp = _dateFormat.format(DateTime.now());
      final logEntry = '[$timestamp] [$level] $message\n';

      await _logFile!.writeAsString(
        logEntry,
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to write to log file: $e');
      debugPrint('[$level] $message');
    }
  }

  /// ניקוי קובץ הלוג (מחיקת תוכן ישן)
  Future<void> clearLog() async {
    if (_logFile == null) {
      await initialize();
    }

    if (_logFile != null && await _logFile!.exists()) {
      try {
        await _logFile!.writeAsString('');
        await logInfo('קובץ הלוג נוקה');
      } catch (e) {
        debugPrint('⚠️ Failed to clear log file: $e');
      }
    }
  }

  /// קריאת תוכן קובץ הלוג
  Future<String> readLog() async {
    if (_logFile == null) {
      await initialize();
    }

    if (_logFile != null && await _logFile!.exists()) {
      try {
        return await _logFile!.readAsString();
      } catch (e) {
        return 'שגיאה בקריאת קובץ הלוג: $e';
      }
    }

    return 'קובץ הלוג לא קיים';
  }
}
