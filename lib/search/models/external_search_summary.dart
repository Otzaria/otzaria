class ExternalSearchBook {
  final int id;
  final String title;
  final int hits;

  const ExternalSearchBook({
    required this.id,
    required this.title,
    required this.hits,
  });
}

/// סיכום סיווג התוצאות של ספק חיפוש חיצוני (תוסף) עבור טאב חיפוש אחד.
///
/// נבנה ע"י מדור התוצאות החיצוני מתוך אינדקס התוצאות של הספק (ראו
/// PluginExternalSearchService), אחרי עידון מול קטלוג ההשוואות המקומי
/// ואימות מול עץ הספרייה. חלונית הסינון צורכת אותו כדי למזג את ספירות
/// הספרים לעץ הקטגוריות ולהציג את דלי "עוד מ<מקור>" לתוצאות שלא שויכו.
class ExternalSearchSummary {
  /// שם המקור להצגה (resultsTitle של שורת התוסף), למשל 'היברובוקס'.
  final String sourceTitle;

  final int totalBooks;

  /// ספירת ספרים לפי נתיב קטגוריה בספרייה (נתיבי עלים — בלי אבות; המיזוג
  /// לעץ מוסיף את האבות).
  final Map<String, int> categoryBookCounts;

  /// ספרים שלא שויכו לקטגוריה קיימת — מוצגים תחת [otherCategoryTitle].
  final int otherBooks;

  /// אותם ספרים לא-משויכים, כשהספק צירף את שמותיהם לאינדקס: מהם נבנות
  /// שורות הספרים שתחת הדלי בעץ. ריק כשהספק שלח אינדקס בלי שמות — ואז
  /// הדלי נשאר שורה שאי אפשר לפתוח.
  final List<ExternalSearchBook> namedOtherBooks;

  const ExternalSearchSummary({
    required this.sourceTitle,
    required this.totalBooks,
    required this.categoryBookCounts,
    required this.otherBooks,
    this.namedOtherBooks = const [],
  });

  String get otherCategoryTitle => 'עוד מ$sourceTitle';

  /// ה-facet הסינתטי של הדלי בעץ. אינו קיים במנוע — בחירתו מחזירה משם
  /// 0 תוצאות, והמדור החיצוני מציג את הספרים הלא-משויכים.
  String get otherCategoryFacet => '/$otherCategoryTitle';

  /// facet סינתטי של ספר יחיד בדלי. המקטע האחרון פותח ב-'#' ולא במפתח ספר
  /// של הספרייה ('id:'/'ext:'/…), ולכן הוא אינו מתקפל לקטגוריית האם בדרך
  /// אל המדור — שם הוא מזוהה כבחירה של ספר בודד.
  String bookFacetOf(int id) => '$otherCategoryFacet/#$id';

  /// המזהה שב-[facet] כשהוא facet של ספר בדלי; אחרת null.
  int? bookIdOfFacet(String facet) => bookIdIn(facet, otherCategoryFacet);

  /// כמו [bookIdOfFacet], למי שמחזיק את נתיב הדלי בלבד (בלי הסיכום).
  static int? bookIdIn(String facet, String otherCategoryFacet) {
    final prefix = '$otherCategoryFacet/#';
    if (!facet.startsWith(prefix)) return null;
    return int.tryParse(facet.substring(prefix.length));
  }
}
