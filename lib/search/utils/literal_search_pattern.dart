import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

/// מקור-אמת יחיד לתבנית ההתאמה הליטרלית של החיפוש בתוך ספר.
///
/// גם מציאת התוצאות (`section_search_utils`), גם ההדגשה בסרגל התוצאות
/// (`SnippetBuilder.highlightLiteral`) וגם חישוב מיקום ההתאמה משתמשים באותה
/// תבנית מהמנוע (`generateLiteralHighlightPattern`), כך שלא ייתכן פער ביניהם.

final RegExp _whitespaceRun = RegExp(r'\s+');

/// תבנית ליטרלית: מקור המחרוזת (לשליחה ל-isolate worker) והרגקס המקומפל
/// (לשימוש ב-isolate הראשי).
class LiteralSearchPattern {
  const LiteralSearchPattern(this.source, this.regExp);

  /// מחרוזת התבנית כפי שבנה אותה המנוע — ניתנת לשליחה בין isolate-ים.
  final String source;

  /// הרגקס המקומפל מ-[source].
  final RegExp regExp;
}

/// מנרמל שאילתה זהה ל-[cleanLineForSearch] של התוכן: מסיר ניקוד וממיר
/// מפרידים (מקף עברי/פסק) לרווח, ואז מכווץ רצפי רווח. חובה שיהיה זהה
/// לניקוי התוכן — אחרת שאילתה עם מקף ("אשר־שמע") לא תתאים לתוכן הנקי
/// ("אשר שמע"), וגם שאילתה מנוקדת ("הֲרֵעֹתִי") לא תתאים לטקסט ללא ניקוד.
String normalizeLiteralQuery(String query) =>
    utils.removeVolwels(query).replaceAll(_whitespaceRun, ' ').trim();

String? _cachedQuery;
LiteralSearchPattern? _cachedPattern;

/// בונה (עם קאש) תבנית ליטרלית לשאילתה, לאחר נרמול.
/// מחזיר `null` לשאילתה ריקה/רק-רווחים.
///
/// חובה להיקרא ב-isolate הראשי בלבד — קורא למנוע (flutter_rust_bridge)
/// שקשור אליו. ב-isolate worker יש לקמפל דרך [compileLiteralPattern].
LiteralSearchPattern? buildLiteralPattern(String query) {
  final q = normalizeLiteralQuery(query);
  if (q == _cachedQuery) return _cachedPattern;

  // בונים לפני עדכון ה-cache: אם המנוע זורק, ה-cache נשאר עקבי (שאילתה
  // קודמת + התבנית שלה) ולא מחזיר תבנית ישנה עבור השאילתה החדשה.
  LiteralSearchPattern? result;
  if (q.isNotEmpty) {
    final source = engine.generateLiteralHighlightPattern(query: q);
    if (source != null) {
      result = LiteralSearchPattern(source, compileLiteralPattern(source));
    }
  }

  _cachedQuery = q;
  _cachedPattern = result;
  return result;
}

/// מקמפל תבנית ליטרלית ממקור מחרוזת. בטוח ל-isolate worker — אינו קורא למנוע.
RegExp compileLiteralPattern(String source) =>
    RegExp(source, caseSensitive: false, unicode: true);
