import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';

/// תוצאת חיפוש שנבחרה לתצוגה מקדימה — הספר שפוענח מהאינדקס יחד עם נתוני
/// המיקום, כדי שלחיצה כפולה/פתיחה מהחלונית תעבור באותו מסלול ניתוב של
/// לחיצה על תוצאה.
class SearchPreviewTarget {
  final Book book;
  final String title;
  final String reference;
  final int segment;
  final bool isPdf;
  final String filePath;

  /// פתיחה בעיון עבור תוצאה שאינה מהמנוע המובנה (מקור חיצוני של תוסף):
  /// המסלול הרגיל מאמת את הנתיב מול האינדקס, ושם אין רשומה כזו.
  final VoidCallback? openInReader;

  /// הביטוי נמשך מסוף השורה אל השורה הבאה — גם היא שורת תוצאה.
  final bool continuesToNextLine;

  const SearchPreviewTarget({
    required this.book,
    required this.title,
    required this.reference,
    required this.segment,
    required this.isPdf,
    required this.filePath,
    this.openInReader,
    this.continuesToNextLine = false,
  });

  /// זהות תוצאה: המפתח היציב של האינדקס + המקטע. משמשת ל"לחיצה חוזרת על
  /// אותה תוצאה סוגרת את התצוגה המקדימה".
  bool matchesResult({
    required String filePath,
    required int segment,
    required bool isPdf,
  }) =>
      this.filePath == filePath &&
      this.segment == segment &&
      this.isPdf == isPdf;
}
