import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';

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

/// מפתח תוצאה לצמצום ה-fallback הגלובלי; [reference] כפי שהוא מוצג (עם שם הספר).
typedef AltTocResultKey = ({
  int bookId,
  String title,
  num segment,
  String reference,
});

/// לכל ספר: תקרת התוצאות הסופית ועוד מרווח לשוויונות בדירוג.
const int maxGlobalAltTocMatchesPerBook = findRefMaxResultCap + 200;

/// מה שהדירוג היה מסיר ממילא: כפילות (כמו `_dedupeRefs`, מול [occupied]),
/// צאצא של התאמה, וגלישה מעבר ל-[perBookCap] לפי סדר הדירוג בתוך הספר.
List<T> pruneGlobalAltTocMatches<T>(
  List<T> matches, {
  required AltTocResultKey Function(T) keyOf,
  required List<String> queryTokens,
  required bool suppressDescendants,
  Iterable<AltTocResultKey> occupied = const [],
  int perBookCap = maxGlobalAltTocMatchesPerBook,
}) {
  // שני המפתחות נרשמים תמיד, גם לתוצאה שנזרקת — בדיוק כמו ב-_dedupeRefs.
  final seen = <String>{};
  bool isNew(AltTocResultKey k) {
    final newSegment = seen.add('${k.bookId}|${k.title}|${k.segment}');
    final newReference = seen.add('${k.bookId}|${k.title}|ref:${k.reference}');
    return newSegment && newReference;
  }

  occupied.forEach(isNew);
  final kept = <T>[];
  final keys = <AltTocResultKey>[];
  for (final m in matches) {
    final key = keyOf(m);
    if (!isNew(key)) continue;
    kept.add(m);
    keys.add(key);
  }

  var survivors = List<int>.generate(kept.length, (i) => i);
  if (suppressDescendants && survivors.length > 1) {
    final referencesByBook = <int, Set<String>>{};
    for (final k in keys) {
      (referencesByBook[k.bookId] ??= {}).add(k.reference);
    }
    survivors = [
      for (final i in survivors)
        if (!_hasAncestorIn(
          keys[i].reference,
          referencesByBook[keys[i].bookId]!,
        ))
          i,
    ];
  }

  final byBook = <int, List<int>>{};
  for (final i in survivors) {
    (byBook[keys[i].bookId] ??= []).add(i);
  }
  final isDafCitation = queryLooksDafCitation(queryTokens);
  FindRefInBookKey inBook(int i) => (
    reference: keys[i].reference,
    segment: keys[i].segment,
    isSourceLine: false,
    isAltToc: true,
    tocLevel: 0,
    isPartialTocMatch: false,
  );
  final dropped = <int>{};
  for (final group in byBook.values) {
    if (group.length <= perBookCap) continue;
    final ranked = [...group]
      ..sort((a, b) {
        final c = compareWithinBook(
          inBook(a),
          inBook(b),
          isDafCitation: isDafCitation,
        );
        return c != 0 ? c : a.compareTo(b);
      });
    dropped.addAll(ranked.skip(perBookCap));
  }
  return [
    for (final i in survivors)
      if (!dropped.contains(i)) kept[i],
  ];
}

/// מפתח התוצאה של שורת AltToc גולמית מהקאש השטוח.
AltTocResultKey altTocRowKey(Map<String, dynamic> row) {
  final title = row['bookTitle'] as String;
  return (
    bookId: row['bookId'] as int,
    title: title,
    segment: row['segment'] as int? ?? 0,
    reference: qualifyAltTocReference(title, row['reference'] as String),
  );
}

Map<String, Object> encodeAltTocResultKey(AltTocResultKey key) => {
  'bookId': key.bookId,
  'title': key.title,
  'segment': key.segment,
  'reference': key.reference,
};

AltTocResultKey decodeAltTocResultKey(Map<dynamic, dynamic> map) => (
  bookId: map['bookId'] as int,
  title: map['title'] as String,
  segment: map['segment'] as num,
  reference: map['reference'] as String,
);

/// מצרף את שם הספר ל-reference יחסי מ-AltToc, אלא אם כבר מתחיל בו.
String qualifyAltTocReference(String bookTitle, String reference) {
  if (bookTitle.isEmpty) return reference;
  if (reference == bookTitle) return reference;
  if (reference.startsWith('$bookTitle ')) return reference;
  return '$bookTitle $reference';
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
