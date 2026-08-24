import 'package:otzaria/indexing/repository/indexing_repository.dart';
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
    // אותו ספר מגיע לכאן גם כמחלקת המסמך שלו וגם כ-`TextBook` (דרך
    // `toTextBook()` בחיפוש ובאינדוקס); שני המסלולים חייבים לחלוק את אותו
    // חישוב, אחרת אותו ספר מקבל שתי זהויות.
    ConvertibleDocumentBook() || TextBook() => _formatIdentity(book.fileType),
    _ => 'text',
  };

  /// הזהות היא הסיומת הקנונית עצמה — כך פורמט חדש מקבל identity יציב בלי
  /// ענף נוסף, וזהות ה-DOCX/EPUB הקיימת נשמרת בדיוק.
  ///
  /// פורמט שממודל כ-TextBook (טקסט, Markdown) הוא `text`, כפי שהיה: שינוי
  /// הזהות שלו היה מייתם את הנתונים ששמרו עליו תוספים קיימים.
  static String _formatIdentity(String? fileType) {
    final format = documentFormatFromFileType(fileType);
    return format != null && format.isDocumentBook ? format.extension : 'text';
  }

  static String sourceOf(Book book) => switch (book) {
    ExternalLibraryBook() => 'external',
    _ when book.isUserBook => 'user',
    _ => 'library',
  };

  /// מזהה ספר יציב חוצה-ספקים, יציב בין עדכוני ספרייה והעברת ספרייה.
  ///
  /// זהו בדיוק המפתח שמנוע החיפוש כבר משתמש בו — נגזר מ-`book.id` + תיוג
  /// המקור, ולכן שורד שינויי כותרת. תוסף מומלץ לאחסן ערך זה במקום כותרת.
  static String uidOf(Book book) => IndexingRepository.catalogueOrderKey(book);

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

  /// כמו [toJson] בתוספת `bookUid`. משמש את שכבת ה-bridge שחושפת את המזהה
  /// היציב; [toJson] עצמו נשאר רזה כי צרכנים אחרים (למשל round-trip דקלרטיבי
  /// עם רשימת שדות מותרת) אינם מכירים את השדה.
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
