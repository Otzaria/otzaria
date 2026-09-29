import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/models/book_source.dart';

/// תוצאת מנוע האיתור בצורה שחוזה ה-bridge חושף לתוספים.
typedef PluginReferenceHit = ({
  String title,
  int index,
  bool isPdf,
  int bookId,
  String reference,
  String bookPath,
  bool isSourceLine,
  BookSource source,
});

/// מנוע האיתור שתוספים משתמשים בו ב-`library.resolveRef` וב-
/// `reader.openBookAtRef`.
///
/// הרשאת `library.books.read` כוללת את כל קטלוג הספרייה, לרבות ספרים
/// אישיים, ולכן החיפוש כולל אותם בכל מופע של תוסף (קדמי או רקע).
/// תוסף רשאי לפתור כמה ציונים במקביל, ולכן פתירה אינה מבטלת את קודמתה.
Future<List<PluginReferenceHit>> Function(String) buildPluginReferenceResolver(
  FindRefRepository findRefRepository,
) {
  return (reference) async {
    final results = await findRefRepository.findRefsConcurrently(
      reference,
      includePersonalBooks: true,
    );
    return results.map(_toPluginReferenceHit).toList();
  };
}

PluginReferenceHit _toPluginReferenceHit(DbReferenceResult result) => (
  title: result.title,
  index: result.segment.toInt(),
  isPdf: result.isPdf,
  bookId: result.bookId,
  reference: result.reference,
  bookPath: result.bookPath,
  isSourceLine: result.isSourceLine,
  source: result.source,
);
