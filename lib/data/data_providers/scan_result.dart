/// תוצאת סריקת תיקייה חיצונית.
///
/// [addedBooks]  - מספר הספרים שנוספו ל-DB בהצלחה.
/// [updatedBooks] - מספר הספרים שעודכנו (שינוי metadata).
/// [failedBooks]  - מספר הספרים שנכשלו בעיבוד (שגיאה חלקית).
/// [fatalError]   - שגיאה קטלנית שמנעה את הסריקה כולה (Isolate נפל וכד׳).
///                  כאשר שגיאה זו קיימת, ספירות הספרים הן 0.
class ScanResult {
  final int addedBooks;
  final int updatedBooks;
  final int failedBooks;
  final Object? fatalError;
  final List<(String title, String reason)> failedDetails;

  /// מזהי ספרים (ב-user_books.db) שקובצם השתנה מאז הסריקה הקודמת —
  /// דורשים אינדוקס מחדש בחיפוש.
  final List<int> updatedBookIds;

  const ScanResult({
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.failedBooks = 0,
    this.fatalError,
    this.failedDetails = const [],
    this.updatedBookIds = const [],
  });

  bool get isSuccess => fatalError == null;
  bool get hasPartialFailure => fatalError == null && failedBooks > 0;
  bool get hasChanges => addedBooks > 0 || updatedBooks > 0;
}
