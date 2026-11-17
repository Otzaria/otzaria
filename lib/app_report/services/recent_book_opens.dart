import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/models/books.dart';

enum BookOpenKind { text, pdf }

enum BookOpenOutcome { pending, loaded, failed, stalled, closed }

typedef BookLoadLogWriter =
    void Function({
      required String title,
      required Object error,
      StackTrace? stackTrace,
      Map<String, String?> details,
    });

/// ניסיונות פתיחת הספרים האחרונים, בזיכרון בלבד, למפתח `recentBookOpens` בדוח;
/// וגם רשומות `Book Load Error` / `Book Load Stalled` ב-errors.txt.
class RecentBookOpens {
  RecentBookOpens({
    this.capacity = 10,
    this.stallThreshold = const Duration(seconds: 20),
    DateTime Function()? now,
    BookLoadLogWriter? writeLog,
  }) : _now = now ?? DateTime.now,
       _writeLog = writeLog ?? _defaultWriter();

  static RecentBookOpens instance = RecentBookOpens();

  /// בבדיקות ובהרצת פיתוח לא נכתב: כתיבה ברקע לשורש נתונים זמני נועלת אותו
  /// בפני המחיקה בסוף הבדיקה.
  static BookLoadLogWriter _defaultWriter() =>
      kDebugMode ? _skipWrite : ErrorLogFile.appendInBackground;

  static void _skipWrite({
    required String title,
    required Object error,
    StackTrace? stackTrace,
    Map<String, String?> details = const {},
  }) {}

  final int capacity;

  /// `null` מכבה את גילוי התקיעות.
  final Duration? stallThreshold;
  final DateTime Function() _now;
  final BookLoadLogWriter _writeLog;
  final ListQueue<BookOpenAttempt> _attempts = ListQueue();

  List<BookOpenAttempt> get attempts => List.unmodifiable(_attempts);

  BookOpenAttempt start(
    Book book,
    BookOpenKind kind, {
    bool detectStall = true,
  }) {
    final attempt = BookOpenAttempt._(this, book, kind, _now());
    _attempts.addLast(attempt);
    while (_attempts.length > capacity) {
      _attempts.removeFirst();
    }
    final threshold = stallThreshold;
    if (detectStall && threshold != null) {
      attempt._stallTimer = Timer(threshold, attempt._onStall);
    }
    return attempt;
  }

  /// רושם כשל טעינה ב-errors.txt; גם בטעינה מחדש שאין לה ניסיון פתיחה.
  void logLoadError(
    Book book,
    BookOpenKind kind,
    Object error, {
    StackTrace? stackTrace,
    Map<String, String?> details = const {},
  }) {
    _write(
      title: 'Book Load Error (${kind.name})',
      error: error,
      stackTrace: stackTrace,
      details: {
        ...describeBook(book),
        'errorType': error.runtimeType.toString(),
        ...details,
      },
    );
  }

  /// המפתח `recentBookOpens` ב-diagnostics.json, מהחדש לישן.
  Map<String, dynamic> collect() => {
    'attempts': [
      for (final attempt in _attempts.toList().reversed) attempt.describe(),
    ],
  };

  /// פרטי זיהוי בלי נתיב הקובץ, שעלול לכלול את שם המשתמש.
  static Map<String, String?> describeBook(Book book) => {
    'book': book.title,
    'id': book.id?.toString(),
    'source': book.source.wireKey,
    'categoryId': book.categoryId?.toString(),
    if (book is TextBook && book.versionTitle != null)
      'versionTitle': book.versionTitle,
  };

  void _write({
    required String title,
    required Object error,
    StackTrace? stackTrace,
    required Map<String, String?> details,
  }) {
    try {
      _writeLog(
        title: title,
        error: error,
        stackTrace: stackTrace,
        details: details,
      );
    } catch (_) {}
  }
}

class BookOpenAttempt {
  BookOpenAttempt._(this._owner, Book book, this.kind, this.startedAt)
    : _bookDetails = RecentBookOpens.describeBook(book),
      _title = book.isUserBook ? null : book.title,
      _id = book.id;

  final RecentBookOpens _owner;
  // Book מחזיק את עץ הספרייה דרך הקטגוריה; נשמרים רק פרטי זיהוי פשוטים.
  final Map<String, String?> _bookDetails;
  final String? _title;
  final int? _id;
  final BookOpenKind kind;
  final DateTime startedAt;
  Timer? _stallTimer;
  bool _stalled = false;
  BookOpenOutcome? _finalOutcome;
  DateTime? _finishedAt;

  BookOpenOutcome get outcome {
    final finalOutcome = _finalOutcome;
    if (finalOutcome == null) {
      return _stalled ? BookOpenOutcome.stalled : BookOpenOutcome.pending;
    }
    // סגירת לשונית שנתקעה עדיין מתועדת כתקיעה.
    if (finalOutcome == BookOpenOutcome.closed && _stalled) {
      return BookOpenOutcome.stalled;
    }
    return finalOutcome;
  }

  bool get isFinished => _finalOutcome != null;

  /// [outcome] הוא loaded, failed או closed; קריאה נוספת אינה עושה דבר.
  void finish(BookOpenOutcome outcome) {
    if (_finalOutcome != null) return;
    _finalOutcome = outcome;
    _finishedAt = _owner._now();
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  Map<String, Object?> describe() => {
    'at': startedAt.toUtc().toIso8601String(),
    // כמו בהקשר החלון: כותרת ספר אישי היא לרוב שם קובץ של המשתמש.
    'title': _title,
    'kind': kind.name,
    'outcome': outcome.name,
    'durationMs': (_finishedAt ?? _owner._now())
        .difference(startedAt)
        .inMilliseconds,
    'source': _bookDetails['source'],
    if (_id != null) 'id': _id,
    if (_stalled) 'stalled': true,
  };

  void _onStall() {
    _stallTimer = null;
    if (_finalOutcome != null || _stalled) return;
    _stalled = true;
    final elapsed = _owner._now().difference(startedAt);
    _owner._write(
      title: 'Book Load Stalled',
      error:
          'Book "${_bookDetails['book']}" (${kind.name}) still loading after '
          '${elapsed.inSeconds}s',
      details: {
        ..._bookDetails,
        'elapsedMs': elapsed.inMilliseconds.toString(),
      },
    );
  }
}
