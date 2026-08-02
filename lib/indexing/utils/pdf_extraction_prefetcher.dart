import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';

/// תוצאת חילוץ עמודי PDF. שגיאת פתיחה נשמרת בתוצאה ולא נזרקת — הקורא
/// מכריע בין נפילה ל-sidecar לבין הפצת השגיאה.
typedef PdfExtraction = ({
  List<({String reference, String text, int pageIndex})> pages,
  List<PdfOutlineNode> outline,
  Object? error,
  StackTrace? stackTrace,
  int extractMs,
});

class _PrefetchSlot {
  _PrefetchSlot(this.book, this.fileBytes);

  final PdfBook book;
  final int fileBytes;

  /// נשלם תמיד בהצלחה; התוצאה או השגיאה נשמרות בשדות שלהלן. אחרת חילוץ
  /// שנכשל בזמן שהוא ממתין בתור היה מתפוצץ כשגיאה ללא-מטפל.
  late final Future<void> completion;

  PdfExtraction? result;
  Object? error;
  StackTrace? stackTrace;

  bool isReady = false;

  /// נשלף מהתור (או נזרק ב-dispose) — עדכוני התקציב שלו כבר בוצעו.
  bool detached = false;

  int chars = 0;
}

/// מזניק מראש חילוצי טקסט מקבצי PDF בזמן שהמנוע מאנדקס את הספרים שלפניהם.
///
/// חילוץ מוכן שממתין לאינדוקס מחזיק את מלוא טקסט הספר בזיכרון, ולכן ההזנקה
/// חסומה בשלוש תקרות: מספר חילוצים בו-זמנית, תווי התוצאות הממתינות (Dart
/// heap), וגודל קבצי ה-PDF הפתוחים (זיכרון נייטיבי של pdfium).
class PdfExtractionPrefetcher {
  PdfExtractionPrefetcher({
    required this.extract,
    this.maxInFlight = defaultMaxInFlight,
    this.maxPendingChars = defaultMaxPendingChars,
    this.maxInFlightBytes = defaultMaxInFlightBytes,
    @visibleForTesting int Function(String path)? fileSizeOf,
  }) : _fileSizeOf = fileSizeOf ?? _statFileSize;

  /// כמה חילוצים רשאים לרוץ או להמתין מוכנים בו-זמנית.
  static const int defaultMaxInFlight = 25;

  /// תקרת התווים של תוצאות שהושלמו וממתינות לאינדוקס. ‏String ב-Dart הוא
  /// UTF-16, כך שהתקרה שקולה לכ-24MB heap.
  static const int defaultMaxPendingChars = 12 * 1024 * 1024;

  /// תקרת גודל קבצי ה-PDF שחילוצם רץ בו-זמנית — ספר סרוק בודד שוקל מאות MB
  /// של זיכרון נייטיבי.
  static const int defaultMaxInFlightBytes = 256 * 1024 * 1024;

  final Future<PdfExtraction> Function(PdfBook book) extract;
  final int maxInFlight;
  final int maxPendingChars;
  final int maxInFlightBytes;
  final int Function(String path) _fileSizeOf;

  final List<_PrefetchSlot> _slots = [];
  int _pendingChars = 0;
  int _inFlightBytes = 0;
  int _scanIndex = 0;

  /// מספר החילוצים שרצים או ממתינים מוכנים.
  int get length => _slots.length;

  int get readyCount => _slots.where((slot) => slot.isReady).length;

  @visibleForTesting
  int get pendingChars => _pendingChars;

  @visibleForTesting
  int get inFlightBytes => _inFlightBytes;

  /// סורק את [books] קדימה מ-[fromIndex] ומזניק חילוץ לכל ספר PDF שעונה על
  /// [shouldPrefetch], עד שאחת התקרות מתמלאת. הסריקה מתקדמת בלבד.
  void fill(
    List<Book> books,
    int fromIndex, {
    required bool Function(PdfBook book) shouldPrefetch,
  }) {
    if (_scanIndex < fromIndex) _scanIndex = fromIndex;
    while (_scanIndex < books.length && _hasCapacity) {
      final candidate = books[_scanIndex];
      _scanIndex++;
      if (candidate is PdfBook && shouldPrefetch(candidate)) {
        _start(candidate);
      }
    }
  }

  /// שולף את החילוץ הראשון שהושלם, ומדלג על [exclude] — הספר שהלולאה עומדת
  /// עליו, שמסלול הצריכה הרגיל מטפל בו.
  ({PdfBook book, Future<PdfExtraction> extraction})? takeReady({
    Book? exclude,
  }) {
    for (final slot in _slots) {
      if (!slot.isReady || identical(slot.book, exclude)) continue;
      _remove(slot);
      return (book: slot.book, extraction: _resultOf(slot));
    }
    return null;
  }

  /// שולף את החילוץ של [book] אם הוזנק — מוכן או עדיין רץ. ‏null אם אינו
  /// בתור, ואז על הקורא לחלץ בעצמו.
  Future<PdfExtraction>? take(PdfBook book) {
    for (final slot in _slots) {
      if (!identical(slot.book, book)) continue;
      _remove(slot);
      return _resultOf(slot);
    }
    return null;
  }

  /// משליך את החילוצים שנותרו בתור, כדי שחילוץ שמסתיים אחרי עצירת האינדוקס
  /// לא יעדכן את מוני התקציב.
  void dispose() {
    for (final slot in _slots) {
      slot.detached = true;
    }
    _slots.clear();
    _pendingChars = 0;
    _inFlightBytes = 0;
  }

  bool get _hasCapacity {
    if (_slots.length >= maxInFlight) return false;
    // ספר יחיד החורג מהתקרות מוזנק בכל זאת, אחרת התור נתקע ריק לנצח.
    if (_slots.isEmpty) return true;
    return _pendingChars < maxPendingChars && _inFlightBytes < maxInFlightBytes;
  }

  void _start(PdfBook book) {
    final slot = _PrefetchSlot(book, _fileSizeOf(book.path));
    _slots.add(slot);
    _inFlightBytes += slot.fileBytes;
    slot.completion = extract(book).then(
      (result) {
        slot.result = result;
        _onSlotDone(slot, chars: _charsOf(result));
      },
      onError: (Object error, StackTrace stackTrace) {
        slot.error = error;
        slot.stackTrace = stackTrace;
        _onSlotDone(slot, chars: 0);
      },
    );
  }

  void _onSlotDone(_PrefetchSlot slot, {required int chars}) {
    slot.isReady = true;
    slot.chars = chars;
    // סלוט שנשלף כבר עדכן את התקציב בשליפה; עדכון שני כאן היה מזייף מונים.
    if (slot.detached) return;
    _pendingChars += chars;
    // הקובץ נסגר בסיום החילוץ — התקציב הנייטיבי משתחרר גם לפני הצריכה.
    _inFlightBytes -= slot.fileBytes;
  }

  void _remove(_PrefetchSlot slot) {
    _slots.remove(slot);
    slot.detached = true;
    if (slot.isReady) {
      _pendingChars -= slot.chars;
    } else {
      _inFlightBytes -= slot.fileBytes;
    }
  }

  /// ה-Future שנמסר לצרכן. נוצר רק בשליפה — כך שחילוץ שנכשל בזמן שהוא
  /// ממתין בתור אינו הופך לשגיאה ללא-מטפל.
  static Future<PdfExtraction> _resultOf(_PrefetchSlot slot) async {
    await slot.completion;
    final error = slot.error;
    if (error != null) {
      Error.throwWithStackTrace(error, slot.stackTrace!);
    }
    return slot.result!;
  }

  static int _charsOf(PdfExtraction extraction) {
    var chars = 0;
    for (final page in extraction.pages) {
      chars += page.text.length;
    }
    return chars;
  }

  static int _statFileSize(String path) {
    try {
      return File(path).statSync().size;
    } catch (_) {
      return 0;
    }
  }
}
