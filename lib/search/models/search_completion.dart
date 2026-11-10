import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';

/// סיכום חיפוש טקסט מלא שהסתיים בהצלחה. נפלט פעם אחת לכל ריצה של
/// `UpdateSearchQuery` שלא בוטלה, לא הוחלפה ולא נכשלה — ראו
/// `SearchBloc.completions`.
class SearchCompletion {
  const SearchCompletion({
    required this.requestId,
    required this.query,
    required this.negativeQuery,
    required this.facets,
    required this.configuration,
    required this.request,
    required this.total,
    required this.countsGroups,
    required this.truncated,
    required this.returned,
  });

  /// מזהה הריצה בתוך ה-bloc; עולה בכל חיפוש חדש, ולכן ייחודי יחד עם הטאב.
  final int requestId;

  final String query;
  final String negativeQuery;

  /// ה-facets שהחיפוש רץ עליהם בפועל (לאחר צמצום בעץ, אם היה).
  final List<String> facets;

  /// הגדרות החיפוש כפי שהיו בעת הריצה.
  final SearchConfiguration configuration;

  /// צילום הבקשה שנשלחה למנוע; אינו קורא אפשרויות שנערכו בינתיים בטאב.
  final SearchEngineRequest request;

  /// המונה שהמשתמש רואה בראש התוצאות: קבוצות כשהאיחוד פעיל, אחרת התאמות.
  final int total;

  /// האם [total] סופר קבוצות (איחוד תוצאות) ולא התאמות בודדות.
  final bool countsGroups;

  /// הספירה חלקית: המנוע עצר לפני סוף האינדקס, ו-[total] הוא חסם תחתון.
  final bool truncated;

  /// כמה תוצאות נטענו בפועל לרשימה (לכל היותר `numResults`).
  final int returned;
}
