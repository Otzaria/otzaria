import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// מפתחות הספרים השמורים בקטלוג, בחיפוש ובחוזה התוספים.
class BookIdentity {
  BookIdentity._();

  static bool _hasExternalIdentity(Book book) =>
      book.externalLibraryId != null && book.externalLibraryId!.isNotEmpty;

  /// מזהה ל-UID ול-facet; עבור מסמכי חיפוש יש להשתמש ב-[indexedFilePath].
  static String keyOf(Book book) {
    // נתיב הקטגוריה נבנה בהליכה על העץ, ורק מפתח בלי id או מזהה חיצוני זקוק לו.
    if (book.id != null || _hasExternalIdentity(book)) {
      return fromParts(
        title: book.title,
        externalLibraryId: book.externalLibraryId,
        bookId: book.id,
        source: book.source,
      );
    }
    return fromParts(
      title: book.title,
      source: book.source,
      categoryKey: book.category?.path ?? book.categoryPath,
      fileTypeKey: book.fileType ?? book.runtimeType.toString(),
      pathKey: book is FileBook ? book.path : book.filePath,
    );
  }

  /// אותו מזהה מרכיבים גולמיים, כשאין בידינו [Book].
  static String fromParts({
    required String title,
    String? externalLibraryId,
    int? bookId,
    BookSource source = BookSource.official,
    String? categoryKey,
    String? fileTypeKey,
    String? pathKey,
  }) {
    // מסד מצורף קובע את externalLibraryId בעצמו — מפתח ext: היה מתנגש בספר רשמי.
    if (source is AttachedBookSource && bookId != null) {
      return attachedBookKey(source.slug, bookId);
    }

    if (externalLibraryId != null && externalLibraryId.isNotEmpty) {
      return externalIdentityKey(externalLibraryId);
    }

    if (bookId != null) {
      // id טבעי חופף בין המסדים — בלי תיוג המקור ספר אישי 'id:5' מתנגש
      // בספר רשמי 'id:5' ומדולג באינדוקס.
      return switch (source) {
        OfficialBookSource() => officialBookKey(bookId),
        UserBookSource() => userBookKey(bookId),
        AttachedBookSource(:final slug) => attachedBookKey(slug, bookId),
      };
    }

    return '$title|${categoryKey ?? ''}|${fileTypeKey ?? ''}|${pathKey ?? ''}';
  }

  /// מפתח ספר אישי (user_books.db) לפי id גולמי.
  static String userBookKey(int id) => 'uid:$id';

  /// מפתח ספר רשמי (seforim.db) לפי id גולמי.
  static String officialBookKey(int id) => 'id:$id';

  /// מפתח ספר ממסד מצורף [slug] לפי id גולמי.
  static String attachedBookKey(String slug, int id) => 'db:$slug:$id';

  /// מפתח ספר בעל מזהה חיצוני יציב.
  static String externalIdentityKey(String externalLibraryId) =>
      'ext:$externalLibraryId';

  /// מפתח מסמך PDF כשאין בידינו [Book], תואם ל-[indexedFilePath].
  static String indexedPdfFilePath({
    required String? externalLibraryId,
    required String? filePath,
    BookSource source = BookSource.official,
    int? bookId,
  }) {
    if (source is AttachedBookSource && bookId != null) {
      return attachedBookKey(source.slug, bookId);
    }
    return externalLibraryId != null && externalLibraryId.isNotEmpty
        ? externalIdentityKey(externalLibraryId)
        : (filePath ?? '');
  }

  /// המפתח שנשמר בשדה filePath של מסמכי החיפוש.
  /// אפשר להעביר ל-[catalogueKey] את תוצאת [keyOf] שכבר חושבה עבור [book].
  static String indexedFilePath(Book book, {String? catalogueKey}) {
    // ב-PDF רגיל ה-id עשוי להיות שאול מספר הטקסט המקביל.
    // למסד מצורף יש id עצמאי, ול-PDF בעל מזהה חיצוני יש זהות יציבה.
    if (book is PdfBook &&
        !_hasExternalIdentity(book) &&
        !(book.source.isAttached && book.id != null)) {
      return book.path;
    }
    return catalogueKey ?? keyOf(book);
  }

  /// הספר שמסמך האינדקס מתאר, רק אם הקטלוג עדיין מחזיק שם את אותו ספר.
  static Book? bookForIndexedDocument(
    Map<String, Book>? booksByIndexedFilePath, {
    required String indexedFilePath,
    required String indexedTitle,
  }) => validatedIndexedBook(
    booksByIndexedFilePath?[indexedFilePath],
    indexedTitle: indexedTitle,
  );

  /// מזהה שהוקצה מחדש במסד אינו מספיק: גם כותרת מסמך החיפוש חייבת להתאים.
  static Book? validatedIndexedBook(
    Book? book, {
    required String indexedTitle,
  }) => book?.title == indexedTitle ? book : null;

  /// האם העברת קבצי הספרייה עשויה לדרוש ניקוי של רשומת האינדקס.
  static bool hasPathKeyedIndexEntry(Book book) {
    if (book is PdfBook) return !_hasExternalIdentity(book);
    if (book is! FileBook) return false;
    return book.id == null && !_hasExternalIdentity(book);
  }

  /// ה-slug שבמפתח `db:<slug>:<id>`, או null למפתח אחר.
  static String? attachedSlugOfKey(String key) {
    if (!key.startsWith('db:')) return null;
    final separator = key.lastIndexOf(':');
    if (separator <= 3) return null;
    return key.substring(3, separator);
  }
}
