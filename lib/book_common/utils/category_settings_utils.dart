/// עזרי קטגוריה משותפים להגדרות פר-קטגוריה (צורת הדף והתצוגה הרגילה).
///
/// המקור לשרשרת הקטגוריות הוא `heCategories` של הספר ("הלכה, משנה תורה,
/// ספר מדע"), והסריקה תמיד מהקטגוריה הספציפית ביותר לכללית ביותר.
library;

import 'package:otzaria/models/books.dart';

/// קטגוריות כלליות מדי שלא כדאי לשמור עליהן הגדרות.
const List<String> tooGeneralCategories = [
  'אוצריא',
  'הלכה',
  'מדרש',
  'תנ"ך',
  'תלמוד',
  'קבלה',
  'מוסר',
  'מחשבה',
  'שו"ת',
];

/// שרשרת הקטגוריות של [book]: heCategories, ובהיעדרו categoryPath (אותו
/// פורמט פסיקים). ה-fallback חיוני לספרי PDF — heCategories מועשר ברקע רק
/// בספרי טקסט.
String? bookCategoriesSource(Book book) {
  final heCategories = book.heCategories;
  if (heCategories != null && heCategories.trim().isNotEmpty) {
    return heCategories;
  }
  return book.categoryPath;
}

/// חילוץ רשימת קטגוריות מ-heCategories (מסנן קטגוריות כלליות מדי).
/// למשל: "הלכה, משנה תורה, ספר מדע" → ["משנה תורה", "ספר מדע"].
/// אם אין קטגוריות אחרי הסינון, מחזיר את כל הקטגוריות (כולל הכלליות).
List<String> parseBookCategories(String? heCategories) {
  if (heCategories == null || heCategories.isEmpty) {
    return [];
  }
  final allCategories = heCategories
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();

  final filtered = allCategories
      .where((c) => !tooGeneralCategories.contains(c))
      .toList();

  return filtered.isNotEmpty ? filtered : allCategories;
}

/// קבלת קטגוריית האב הראשית (למשל "משנה תורה" מתוך "הלכה, משנה תורה, ספר מדע").
String? parentBookCategory(String? heCategories) {
  final categories = parseBookCategories(heCategories);
  return categories.isNotEmpty ? categories.first : null;
}

/// הקטגוריה הראשונה בשרשרת (ספציפי→כללי) ש-[hasSettings] מחזיר עליה true.
String? findActiveCategory(
  String? heCategories,
  bool Function(String category) hasSettings,
) {
  final categories = parseBookCategories(heCategories);
  for (var i = categories.length - 1; i >= 0; i--) {
    if (hasSettings(categories[i])) {
      return categories[i];
    }
  }
  return null;
}
