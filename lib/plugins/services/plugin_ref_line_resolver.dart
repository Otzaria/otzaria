import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/line_ref_matcher.dart';

/// זוג (lineIndex, heRef) של שורה בספר, כפי שמוחזר משכבת הנתונים.
typedef LineRefEntry = ({int lineIndex, String heRef});

/// פותר הפניה של תוסף לאינדקס שורה מדויק, דרך עמודת ה-heRef הפר-שורתית ב-DB.
///
/// ליבת ההתאמה (טוקניזציה, מילות-מיקום, סימוני דף) חולצה ל-
/// `utils/navigation/line_ref_matcher.dart` ומשותפת עם "איתור מקורות".
///
/// מחזיר `null` כשאין התאמה ברמת שורה — ואז הקורא נופל למסלולי ה-TOC הקיימים.
class PluginRefLineResolver {
  /// מקור זוגות ה-(lineIndex, heRef) של ספר. ברירת המחדל קוראת מה-DB הנכון
  /// (רשמי או ספרים אישיים); ניתן להזרקה בבדיקות.
  final Future<List<LineRefEntry>> Function(TextBook book) fetchLineRefs;

  PluginRefLineResolver({
    Future<List<LineRefEntry>> Function(TextBook book)? fetchLineRefs,
  }) : fetchLineRefs = fetchLineRefs ?? _fetchFromDatabase;

  /// פותר את [ref] לאינדקס שורה בתוך [book], או `null` אם אין התאמה מדויקת.
  Future<int?> resolve({required TextBook book, required String ref}) async {
    final refTokens = lineRefQueryTokens(ref);
    if (refTokens.length < 2) return null;

    final entries = await fetchLineRefs(book);
    if (entries.isEmpty) return null;

    final idx = matchLineRefIndex(
      heRefs: [for (final e in entries) e.heRef],
      bookTitle: book.title,
      refTokens: refTokens,
    );
    return idx == null ? null : entries[idx].lineIndex;
  }

  /// ברירת המחדל בייצור: קריאה מה-DB המתאים לפי [TextBook.isUserBook] —
  /// ה-namespaces של seforim.db ו-user_books.db נפרדים ואסור לערבבם.
  static Future<List<LineRefEntry>> _fetchFromDatabase(TextBook book) async {
    final id = book.id;
    if (id == null) return const [];
    try {
      final repo = book.isUserBook
          ? await UserBooksDatabaseHolder.instance.repository
          : SqliteDataProvider.instance.repository;
      if (repo == null) return const [];
      return await repo.getLineRefs(id);
    } catch (_) {
      return const [];
    }
  }
}
