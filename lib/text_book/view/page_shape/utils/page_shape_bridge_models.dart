/// מודלים לתקשורת בין מסך "צורת הדף" (PageShapeScreen) לבין גשר התוספים.
///
/// המסך הוא היחיד שמחזיק את שיבוץ המפרשים לטורים ואת נראותם (מצב UI מקומי
/// שאינו חלק מ-TextBookState) — ולכן הגשר אינו יכול לקרוא/לשנות אותם ישירות.
/// שני האובייקטים כאן עוברים על גבי ValueNotifier-ים פר-טאב (ב-[TextBookTab]):
/// המסך מפרסם [PageShapeLayoutSnapshot] בכל שינוי תצורה, והגשר שולח
/// [PageShapeVisibilityRequest] כדי לבקש שינוי.
library;

/// תמונת מצב קריאה-בלבד של פריסת "צורת הדף" הנוכחית, כפי שהמסך מפרסם אותה.
class PageShapeLayoutSnapshot {
  /// שיבוץ הטורים היחידניים: 'left' | 'bottom' | 'bottomRight' -> שם המפרש
  /// המוצג בהם, או null אם אין שיבוץ. הטור הימני יכול להכיל כמה מפרשים
  /// בו-זמנית ולכן אינו מיוצג כאן — ראו [rightCommentators].
  final Map<String, String?> commentators;

  /// כל המפרשים המוצגים כרגע בטור הימני (יכול להיות אחד, כמה, או ריק).
  final List<String> rightCommentators;

  /// נראות כל טור: 'left' | 'right' | 'bottom' | 'bottomRight' -> מוצג/מוסתר.
  final Map<String, bool> columnVisibility;

  const PageShapeLayoutSnapshot({
    required this.commentators,
    required this.rightCommentators,
    required this.columnVisibility,
  });

  /// הטור ('left'/'right'/'bottom'/'bottomRight') שבו משובץ המפרש [name] כרגע,
  /// או null אם הוא אינו משובץ לאף טור בצורת הדף.
  String? columnForCommentator(String name) {
    if (commentators['left'] == name) return 'left';
    if (commentators['bottom'] == name) return 'bottom';
    if (commentators['bottomRight'] == name) return 'bottomRight';
    if (rightCommentators.contains(name)) return 'right';
    return null;
  }
}

/// בקשה חיצונית (מגשר התוספים) לשנות את נראות המפרש [commentator] בצורת הדף.
/// כל מופע חדש נחשב לבקשה נפרדת גם אם הערכים זהים לבקשה הקודמת, כי ההשוואה
/// היא לפי זהות המופע (identity) ולא לפי ==.
class PageShapeVisibilityRequest {
  final String commentator;
  final bool visible;

  const PageShapeVisibilityRequest(this.commentator, this.visible);
}
