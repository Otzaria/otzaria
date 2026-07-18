import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// זוג (lineIndex, heRef) של שורה בספר, כפי שמוחזר משכבת הנתונים.
typedef LineRefEntry = ({int lineIndex, String heRef});

/// פותר הפניה של תוסף לאינדקס שורה מדויק, דרך עמודת ה-heRef הפר-שורתית ב-DB.
///
/// ה-TOC מגיע רק עד רמת פרק/סימן, אבל לכל שורה (פסוק/סעיף) יש heRef מלא
/// כמו "במדבר לג, ה" — כך "לג:ה" נפתר לשורת הפסוק עצמו ולא לתחילת הפרק.
///
/// מחזיר `null` כשאין התאמה ברמת שורה — ואז הקורא נופל למסלולי ה-TOC הקיימים.
class PluginRefLineResolver {
  /// מקור זוגות ה-(lineIndex, heRef) של ספר. ברירת המחדל קוראת מה-DB הנכון
  /// (רשמי או ספרים אישיים); ניתן להזרקה בבדיקות.
  final Future<List<LineRefEntry>> Function(TextBook book) fetchLineRefs;

  PluginRefLineResolver({
    Future<List<LineRefEntry>> Function(TextBook book)? fetchLineRefs,
  }) : fetchLineRefs = fetchLineRefs ?? _fetchFromDatabase;

  /// מילות-מיקום שאינן חלק מערכי ההפניה עצמם ("פרק לג פסוק ה" ↔ "לג ה").
  static const Set<String> _locatorWords = {
    'פרק',
    'פסוק',
    'פסקה',
    'סעיף',
    'סימן',
    'הלכה',
    'משנה',
    'דף',
    'עמוד',
    'אות',
  };

  /// פותר את [ref] לאינדקס שורה בתוך [book], או `null` אם אין התאמה מדויקת.
  ///
  /// ההתאמה דורשת שוויון-טוקנים מלא בין ההפניה לחלק שאחרי כותרת הספר ב-heRef,
  /// כדי שהפניה דו-רכיבית לא תיתפס בטעות ע"י שורה ברמה אחרת.
  Future<int?> resolve({required TextBook book, required String ref}) async {
    final refTokens = _refTokens(ref);
    // רכיב יחיד ("לג") הוא ברמת TOC — אין מה לחפש ברמת שורה.
    if (refTokens.length < 2) return null;

    final entries = await fetchLineRefs(book);
    if (entries.isEmpty) return null;

    final titleTokens = _tokenize(book.title);
    for (final entry in entries) {
      final heTokens = _tokenize(entry.heRef);
      if (heTokens.length <= titleTokens.length) continue;

      var titleMatches = true;
      for (var i = 0; i < titleTokens.length; i++) {
        if (heTokens[i] != titleTokens[i]) {
          titleMatches = false;
          break;
        }
      }
      if (!titleMatches) continue;

      final remainder = _filterLocators(heTokens.sublist(titleTokens.length));
      if (remainder.length != refTokens.length) continue;
      var matches = true;
      for (var i = 0; i < refTokens.length; i++) {
        if (remainder[i] != refTokens[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return entry.lineIndex;
    }
    return null;
  }

  /// טוקני ההפניה לאחר נרמול: טווח ("לג:ה-ז") נחתך לתחילתו, מילות-מיקום
  /// מוסרות, ו-"ע\"א"/"ע\"ב" ממופים לטוקני העמוד של פורמט הגמרא.
  List<String> _refTokens(String ref) {
    final dashIndex = ref.indexOf(RegExp('[-–]'));
    final trimmed = dashIndex > 0 ? ref.substring(0, dashIndex) : ref;
    return _filterLocators(_tokenize(trimmed));
  }

  static List<String> _tokenize(String s) =>
      normalizeForFindRefMatch(_expandDafMarks(s))
          .split(' ')
          .where((t) => t.isNotEmpty)
          .toList();

  /// מרחיב סימון עמוד גמרא ("ב." / "ב:") לטוקן עמוד מפורש — כמו הנרמול
  /// הכללי, אבל גם כשאחרי הסימן בא פסיק ("ברכות ב., א"), תבנית ה-heRef ב-DB
  /// שבה הנרמול הכללי מפספס ומידע העמוד אובד.
  static String _expandDafMarks(String s) => s
      .replaceAllMapped(
        RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=[,\s]|$)'''),
        (m) => '${m[1]} א',
      )
      .replaceAllMapped(
        RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=[,\s]|$)'''),
        (m) => '${m[1]} ב',
      );

  static List<String> _filterLocators(List<String> tokens) => tokens
      .where((t) => !_locatorWords.contains(t))
      .map((t) => t == 'עא' ? 'א' : (t == 'עב' ? 'ב' : t))
      .toList();

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
