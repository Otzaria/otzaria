import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';

/// בחירה מרובה של ספרים בספרייה, לפתיחה בבת אחת.
///
/// נפרדת מהתצוגה המקדימה: ספר בודד שנבחר לתצוגה לא משתתף כאן. הסדר הוא סדר
/// הצירוף לבחירה (טווח נוסף לפי סדר התצוגה שלו), והבחירה שורדת מעבר בין
/// תיקיות כדי שאפשר יהיה לאסוף ספרים מכמה מקומות.
class LibraryBookSelection extends ChangeNotifier {
  // Book משווה לפי זהות; טעינת ספרייה מחדש מחליפה מופעים ([reconcile]).
  final LinkedHashSet<Book> _books = LinkedHashSet<Book>.identity();
  Book? _anchor;

  /// הספרים הנבחרים, לפי סדר הצירוף.
  List<Book> get books => List.unmodifiable(_books);

  int get length => _books.length;

  bool get isEmpty => _books.isEmpty;

  bool get isNotEmpty => _books.isNotEmpty;

  bool contains(Book book) => _books.contains(book);

  /// ספר חיצוני אינו נפתח כטאב קריאה (הוא פותח דף הורדה), ולכן אינו נבחר.
  static bool canSelect(Book book) => book is! ExternalLibraryBook;

  /// הוספה או הסרה של [book] (Ctrl/Cmd+לחיצה). הוא גם נקודת העוגן לטווח.
  void toggle(Book book) {
    if (!canSelect(book)) return;
    if (!_books.remove(book)) _books.add(book);
    _anchor = book;
    notifyListeners();
  }

  /// הוספת הטווח שבין העוגן האחרון ל-[book] (Shift+לחיצה), לפי סדר
  /// [visibleBooks]. בלי עוגן, או כשהעוגן לא ברשימה הנוכחית, נבחר [book] בלבד.
  void selectRange(Book book, List<Book> visibleBooks) {
    if (!canSelect(book)) return;
    final to = visibleBooks.indexOf(book);
    final anchor = _anchor;
    final from = anchor == null ? -1 : visibleBooks.indexOf(anchor);
    if (to == -1 || from == -1) {
      _books.add(book);
      _anchor = book;
    } else {
      final start = from < to ? from : to;
      final end = from < to ? to : from;
      _books.addAll(visibleBooks.sublist(start, end + 1).where(canSelect));
    }
    notifyListeners();
  }

  /// מתאים את הבחירה לספרייה שנבנתה מחדש: ספר מוחלף במופע הנוכחי שלו, וספר
  /// ש-[resolve] מחזיר עבורו null (נמחק או הוסתר) יוצא מהבחירה. הסדר נשמר.
  void reconcile(Book? Function(Book book) resolve) {
    final before = _books.toList();
    final after = [for (final book in before) resolve(book)].nonNulls.toList();
    final unchanged =
        after.length == before.length &&
        [
          for (var i = 0; i < after.length; i++) identical(after[i], before[i]),
        ].every((same) => same);
    if (unchanged) return;
    final anchor = _anchor;
    _anchor = anchor == null ? null : resolve(anchor);
    _books
      ..clear()
      ..addAll(after);
    notifyListeners();
  }

  void clear() {
    if (_books.isEmpty) return;
    _books.clear();
    _anchor = null;
    notifyListeners();
  }
}
