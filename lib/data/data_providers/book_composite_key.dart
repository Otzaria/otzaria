import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// מפתח ספר אחיד לכל שכבות ה-provider: title + categoryId + fileType מנורמל
/// + המקור. אותו categoryId יכול להופיע בכמה מסדים, ולכן המקור הוא חלק מהמפתח.
///
/// סיריאליזציה (`toStorageKey`): `title|categoryId|fileType|<wireKey>` —
/// `o` רשמי, `u` אישי, `d:<slug>` מצורף. מחרוזת בלי החלק הרביעי היא רשמי.
class BookCompositeKey {
  final String title;
  final int categoryId;
  final String fileType;
  final BookSource source;

  const BookCompositeKey({
    required this.title,
    required this.categoryId,
    required this.fileType,
    this.source = BookSource.official,
  });

  bool get isUserBook => source.isUser;

  factory BookCompositeKey.create({
    required String title,
    required int categoryId,
    String? fileType,
    BookSource source = BookSource.official,
  }) {
    return BookCompositeKey(
      title: title,
      categoryId: categoryId,
      fileType: normalizeFileType(fileType),
      source: source,
    );
  }

  static BookCompositeKey? fromBook(Book book) {
    if (book.categoryId == null) return null;
    return BookCompositeKey.create(
      title: book.title,
      categoryId: book.categoryId!,
      fileType: book.fileType,
      source: book.source,
    );
  }

  static BookCompositeKey? tryParse(String key) {
    final parts = key.split('|');
    if (parts.length < 3) return null;
    final categoryId = int.tryParse(parts[1]);
    if (categoryId == null) return null;

    final source =
        (parts.length >= 4 ? BookSource.tryParse(parts[3]) : null) ??
        BookSource.official;

    return BookCompositeKey.create(
      title: parts[0],
      categoryId: categoryId,
      fileType: parts[2],
      source: source,
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

  String toStorageKey() => '$title|$categoryId|$fileType|${source.wireKey}';

  @override
  String toString() => toStorageKey();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookCompositeKey &&
        other.title == title &&
        other.categoryId == categoryId &&
        other.fileType == fileType &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(title, categoryId, fileType, source);
}
