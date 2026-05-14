import 'package:otzaria/models/books.dart';

/// מפתח ספר אחיד לכל שכבות ה-provider.
///
/// הפורמט הוא: title + categoryId + fileType מנורמל + `isUserBook`.
/// `isUserBook` מבדיל בין ספר שמקורו ב-`seforim.db` (הספרייה הרשמית) לבין ספר
/// שמקורו ב-`user_books.db`. בלי הדגל הזה — `categoryId=5` יכול להופיע בשני
/// ה-DBs ולגרום להתנגשות במפות keyed-by-key.
///
/// פורמט הסיריאליזציה (`toStorageKey`): `title|categoryId|fileType|u` עבור
/// ספרי משתמש, `title|categoryId|fileType|o` עבור ספרים רשמיים. מחרוזות
/// ישנות ללא הסיומת השלישית מתפרשות כספר רשמי (`isUserBook=false`).
class BookCompositeKey {
  final String title;
  final int categoryId;
  final String fileType;
  final bool isUserBook;

  const BookCompositeKey({
    required this.title,
    required this.categoryId,
    required this.fileType,
    this.isUserBook = false,
  });

  factory BookCompositeKey.create({
    required String title,
    required int categoryId,
    String? fileType,
    bool isUserBook = false,
  }) {
    return BookCompositeKey(
      title: title,
      categoryId: categoryId,
      fileType: normalizeFileType(fileType),
      isUserBook: isUserBook,
    );
  }

  static BookCompositeKey? fromBook(Book book) {
    if (book.categoryId == null) return null;
    return BookCompositeKey.create(
      title: book.title,
      categoryId: book.categoryId!,
      fileType: book.fileType,
      isUserBook: book.isUserBook,
    );
  }

  static BookCompositeKey? tryParse(String key) {
    final parts = key.split('|');
    if (parts.length < 3) return null;
    final categoryId = int.tryParse(parts[1]);
    if (categoryId == null) return null;

    // החלק הרביעי הוא דגל המקור: `u`=user_books, `o`=seforim. תאימות
    // לאחור: מחרוזות ישנות בלי הסיומת מתפרשות כ-seforim.
    final isUserBook = parts.length >= 4 && parts[3] == 'u';

    return BookCompositeKey.create(
      title: parts[0],
      categoryId: categoryId,
      fileType: parts[2],
      isUserBook: isUserBook,
    );
  }

  static String normalizeFileType(String? fileType) {
    final normalized = (fileType ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return 'txt';
    return normalized;
  }

  bool matchesTitle(String otherTitle) => title == otherTitle;

  bool matches(String otherTitle, {String? otherFileType}) {
    if (!matchesTitle(otherTitle)) return false;
    if (otherFileType == null) return true;
    return fileType == normalizeFileType(otherFileType);
  }

  String toStorageKey() =>
      '$title|$categoryId|$fileType|${isUserBook ? 'u' : 'o'}';

  @override
  String toString() => toStorageKey();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookCompositeKey &&
        other.title == title &&
        other.categoryId == categoryId &&
        other.fileType == fileType &&
        other.isUserBook == isUserBook;
  }

  @override
  int get hashCode => Object.hash(title, categoryId, fileType, isUserBook);
}
