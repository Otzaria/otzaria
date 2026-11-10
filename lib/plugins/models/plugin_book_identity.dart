import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/document_format.dart';

typedef PluginBookIdentityKey = ({
  String bookId,
  int? id,
  String type,
  String source,
});

/// זהות ספר קנונית עבור ה-Plugin SDK.
class PluginBookIdentity {
  static int? parseId(Object? rawId) => switch (rawId) {
    int value => value,
    num value when value == value.toInt() => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };

  static String typeOf(Book book) => switch (book) {
    PdfBook() => 'pdf',
    ExternalLibraryBook() => 'external',
    // מסמך ועטיפת ה-TextBook שלו חייבים לחלוק את אותו סוג זהות.
    ConvertibleDocumentBook() || TextBook() => _formatIdentity(book.fileType),
    _ => 'text',
  };

  // שינוי סוג הזהות של TextBook מייתם נתוני תוספים קיימים.
  static String _formatIdentity(String? fileType) {
    final format = documentFormatFromFileType(fileType);
    return format != null && format.isDocumentBook ? format.extension : 'text';
  }

  /// כל הערכים ש-[typeOf] יכול להחזיר. מסנן שתוסף מצהיר (למשל `bookTypes`
  /// בפקד בסרגל) נבדק מולם, כדי ששגיאת כתיב תיתפס בהתקנה ולא תסתיר את הפקד
  /// בשקט.
  static final Set<String> knownTypes = Set.unmodifiable({
    'text',
    'pdf',
    'external',
    for (final format in DocumentFormat.values)
      if (format.isDocumentBook) format.extension,
  });

  /// כל הערכים ש-[sourceOf] יכול להחזיר — מאותה סיבה כמו [knownTypes].
  static const Set<String> knownSources = {
    'library',
    'user',
    'attached',
    'external',
  };

  static String sourceOf(Book book) => switch (book) {
    ExternalLibraryBook() => 'external',
    _ when book.isUserBook => 'user',
    _ when book.source.isAttached => 'attached',
    _ => 'library',
  };

  /// ערך `source` שבחוזה התוספים עבור [source] בלבד, כשאין ספר מהקטלוג.
  static String sourceOfBookSource(BookSource source) => switch (source) {
    UserBookSource() => 'user',
    AttachedBookSource() => 'attached',
    OfficialBookSource() => 'library',
  };

  /// מזהה ספר משותף לחיפוש ולתוספים, יציב בין עדכוני ספרייה והעברתה.
  static String uidOf(Book book) => BookIdentity.keyOf(book);

  static PluginBookIdentityKey keyOf(Book book) => (
    bookId: book.title,
    id: book.id,
    type: typeOf(book),
    source: sourceOf(book),
  );

  static ({String provider, Object id})? externalOf(Book book) {
    final value = book.externalLibraryId?.trim();
    if (value == null || value.isEmpty) return null;
    final separator = value.indexOf(':');
    if (separator <= 0 || separator == value.length - 1) return null;
    final prefix = value.substring(0, separator).toLowerCase();
    final rawId = value.substring(separator + 1).trim();
    final provider = switch (prefix) {
      'hb' || 'hebrew' || 'hebrewbooks' => 'hebrewbooks',
      'oh' || 'otz' || 'otzar' => 'otzar',
      _ => null,
    };
    if (provider == null || rawId.isEmpty) return null;
    return (provider: provider, id: int.tryParse(rawId) ?? rawId);
  }

  static Map<String, dynamic> toJson(Book book) => {
    'id': book.id,
    'type': typeOf(book),
    'bookId': book.title,
    'source': sourceOf(book),
    if (externalOf(book) case final external?)
      'external': {'provider': external.provider, 'id': external.id},
  };

  /// מוסיף `bookUid` לחוזה ה-bridge; [toJson] נשמר לתאימות צרכנים קיימים.
  static Map<String, dynamic> toJsonWithUid(Book book) => {
    ...toJson(book),
    'bookUid': uidOf(book),
  };

  static bool matches(
    Book book, {
    int? id,
    String? bookId,
    String? bookUid,
    String? type,
    String? source,
  }) {
    // `bookUid` הוא זהות מדויקת וחד-משמעית — אם סופק, הוא מכריע לבדו.
    if (bookUid != null && bookUid.trim().isNotEmpty) {
      return uidOf(book) == bookUid.trim();
    }
    if (id != null && book.id != id) return false;
    if (bookId != null && book.title != bookId) return false;
    if (type != null && typeOf(book) != type.trim().toLowerCase()) {
      return false;
    }
    if (source != null && sourceOf(book) != source.trim().toLowerCase()) {
      return false;
    }
    return true;
  }
}
