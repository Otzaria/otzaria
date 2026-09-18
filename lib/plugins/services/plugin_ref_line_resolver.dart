import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_key.dart';

/// פותר הפניה של תוסף לאינדקס שורה מדויק, דרך אינדקס ההפניות `line_ref`.
///
/// ה-TOC מגיע רק עד רמת פרק/סימן, אבל לכל שורה (פסוק/סעיף) יש מפתח קנוני
/// מאונדקס — כך "לג:ה" נפתר לשורת הפסוק עצמו ולא לתחילת הפרק.
///
/// מחזיר `null` כשאין התאמה ברמת שורה או כשהמסד נבנה לפני האינדקס — ואז
/// הקורא נופל למסלולי ה-TOC הקיימים.
class PluginRefLineResolver {
  /// חיפוש המפתח הקנוני במסד הנכון. ניתן להזרקה בבדיקות.
  final Future<int?> Function(TextBook book, String refKey) lookup;

  PluginRefLineResolver({Future<int?> Function(TextBook, String)? lookup})
    : lookup = lookup ?? _lookupInDatabase;

  /// פותר את [ref] לאינדקס שורה בתוך [book], או `null` אם אין התאמה מדויקת.
  Future<int?> resolve({required TextBook book, required String ref}) async {
    final tokens = refKeyTokens(ref);
    // רכיב יחיד ("לג") הוא ברמת TOC — אין מה לחפש ברמת שורה.
    if (tokens.length < 2) return null;
    return lookup(book, tokens.join(' '));
  }

  /// ברירת המחדל בייצור: חיפוש במסד של מקור הספר — מרחבי המזהים של
  /// המסדים נפרדים ואסור לערבבם.
  static Future<int?> _lookupInDatabase(TextBook book, String refKey) async {
    final id = book.id;
    if (id == null) return null;
    try {
      final repo = switch (book.source) {
        OfficialBookSource() => SqliteDataProvider.instance.repository,
        UserBookSource() => await UserBooksDatabaseHolder.instance.repository,
        AttachedBookSource() =>
          await AttachedLibraryRegistry.instance.repositoryForSource(
            book.source,
          ),
      };
      if (repo == null) return null;
      return (await repo.resolveRefKeyInBook(id, refKey))?.lineIndex;
    } catch (_) {
      return null;
    }
  }
}
