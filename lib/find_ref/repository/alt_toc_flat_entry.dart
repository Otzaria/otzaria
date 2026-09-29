/// רשומת AltToc שטוחה, מיועדת לחיפוש גלובלי על פני כל הספרים בבת אחת.
///
/// נוצרת מראש (lazy, פעם אחת ל-session) מתוך שאילתת DB אחת שמאחדת את כל
/// טבלאות ה-AltToc. כל שדה — כולל `refTokens` המנורמלים — מחושב פעם אחת
/// בעת בניית הקאש, כך שהפילטר לכל שאילתה הוא O(N) מעבר על הרשימה בלבד.
class AltTocFlatEntry {
  /// מזהה הספר ב-DB.
  final int bookId;

  /// שם הספר (כפי שמופיע ב-`book.title`).
  final String bookTitle;

  /// `book.orderIndex` של הספר — משמש למיון תוצאות, בלי לחפש שוב ב-cache.
  final double bookOrderIndex;

  /// הנתיב המלא של הערך, יחסי לספר (ללא שם הספר). למשל:
  ///   "פרשת לך לך עליה ו"
  final String reference;

  /// ה-`lineIndex` בספר שאליו יש לנווט; 0 אם הערך אינו מקושר לשורה.
  final int segment;

  /// רמת הערך (1 = שורש, 2 = ילד, ...).
  final int level;

  /// `line.id` הגלובלי של השורה המקושרת, אם קיים; 0 אם לא.
  final int dbLineId;

  /// טוקנים מנורמלים של [reference] (אחרי [normalizeForFindRefMatch]).
  /// משמש את הפילטר `queryTokens.every((qt) => refTokens.contains(qt))`.
  final List<String> refTokens;

  const AltTocFlatEntry({
    required this.bookId,
    required this.bookTitle,
    required this.bookOrderIndex,
    required this.reference,
    required this.segment,
    required this.level,
    required this.dbLineId,
    required this.refTokens,
  });
}

/// פילטר ההתאמה של ה-fallback הגלובלי — משותף למסלול המקומי (main isolate)
/// ול-worker isolate, כדי שהסמנטיקה תישאר זהה בשני המסלולים.
///
/// [maxRefTokens] מגביל את אורך הערך (מסלול מילה בודדת); `null` = ללא הגבלה.
bool altTocFlatMatches(
  List<String> refTokens,
  List<String> queryTokens, {
  int? maxRefTokens,
}) {
  if (maxRefTokens != null && refTokens.length > maxRefTokens) return false;
  return queryTokens.every(refTokens.contains);
}

/// תקרת ההתאמות של ה-fallback הגלובלי שמגיעות לדירוג — פי חמישה מתקרת
/// התוצאות המוחלטת של האיתור.
const int maxGlobalAltTocMatches = 500;

/// מצמצם את התאמות ה-fallback הגלובלי לפני הדירוג. [suppressDescendants]
/// מסיר ערך שאב שלו (תחילית עד רווח באותו ספר) גם הוא התאמה, כפי שהדירוג
/// היה מסיר; מעבר ל-[cap] נשמרים הקודמים בסדר הספרייה, והסדר המקורי נשמר.
List<T> pruneGlobalAltTocMatches<T>(
  List<T> matches, {
  required int Function(T) bookIdOf,
  required String Function(T) referenceOf,
  required double Function(T) orderOf,
  required bool suppressDescendants,
  int cap = maxGlobalAltTocMatches,
}) {
  var kept = matches;
  if (suppressDescendants && matches.length > 1) {
    final referencesByBook = <int, Set<String>>{};
    for (final m in matches) {
      (referencesByBook[bookIdOf(m)] ??= {}).add(referenceOf(m));
    }
    kept = [
      for (final m in matches)
        if (!_hasAncestorIn(referenceOf(m), referencesByBook[bookIdOf(m)]!)) m,
    ];
  }
  if (kept.length <= cap) return kept;
  final byOrder = List<int>.generate(kept.length, (i) => i)
    ..sort((a, b) {
      final c = orderOf(kept[a]).compareTo(orderOf(kept[b]));
      return c != 0 ? c : a.compareTo(b);
    });
  final keep = byOrder.take(cap).toSet();
  return [
    for (var i = 0; i < kept.length; i++)
      if (keep.contains(i)) kept[i],
  ];
}

bool _hasAncestorIn(String reference, Set<String> siblings) {
  for (
    var i = reference.indexOf(' ');
    i >= 0;
    i = reference.indexOf(' ', i + 1)
  ) {
    if (siblings.contains(reference.substring(0, i))) return true;
  }
  return false;
}
