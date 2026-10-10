/// דירוג תוצאות האיתור: המפתחות וההשוואה. משותף לדירוג ב-main ולבחירת
/// התאמות ה-AltToc הגלובלי ב-worker (isolate-safe).
library;

import 'package:otzaria/find_ref/book_name_match.dart';

/// תקרת-ביטחון מוחלטת על מספר תוצאות האיתור.
const int findRefMaxResultCap = 100;

/// issue #839: מכסת התאמות תת-מחרוזת המובטחת בזנב תוצאות של שאילתת
/// מילה-אחת — בלעדיה ה-cap מחק אותן כליל ("מא" לא הציג את יומא).
const int findRefSubstringTailQuota = 10;

/// מחזיר true כשהשאילתה נראית כציון בסגנון גמרא (דף + עמוד).
///
/// תנאי הזיהוי (כולם נדרשים):
///   1. הטוקן האחרון הוא "א" או "ב" (עמוד א/ב).
///   2. לפחות עוד טוקן קיים לפניו.
///   3. OR:  מופיע "דף" / "עמוד" במפורש בשאילתה
///      OR:  הטוקן לפני האחרון הוא מספר עברי של 2–4 אותיות (כמו "עא", "לט", "קה", "קמד"),
///           ואינו מילת מבנה ("פרק", "משנה", "פסוק", ...).
///           טוקן של אות בודדת או שם ספר ארוך אינם מפעילים את הבוסט.
///
/// דוגמות שמפעילות: ["שבת","עא","ב"], ["ברכות","דף","כ","א"], ["נדה","ל","ב"]
/// דוגמות שלא מפעילות: ["בראשית","א","ב"], ["ברכות","ב"], ["ברכות","פרק","א","ב"]
bool queryLooksDafCitation(List<String> tokens) {
  if (tokens.length < 2) return false;
  final last = tokens.last;
  if (last != 'א' && last != 'ב') {
    return false;
  }
  // מפורש — מילת "דף" או "עמוד" בשאילתה
  if (tokens.contains('דף') || tokens.contains('עמוד')) return true;
  // מספר דף עברי: 2–4 אותיות עבריות, ואינו מילת מבנה
  const structureWords = {
    'פרק',
    'משנה',
    'פסוק',
    'הלכה',
    'סעיף',
    'סימן',
    'חלק',
    'שאלה',
  };
  final penultimate = tokens[tokens.length - 2];
  if (structureWords.contains(penultimate)) return false;
  return penultimate.length >= 2 &&
      penultimate.length <= 4 &&
      penultimate.codeUnits.every(
        (c) => c >= 0x05D0 && c <= 0x05EA,
      ); // אותיות עבריות בלבד
}

/// בציון גמרא ערך שמכיל "דף" קודם לשאינו מכיל (גמרא לפני משנה ב"שבת עא ב").
bool findRefCitationMatch(bool isDafCitation, String reference) =>
    !isDafCitation || reference.contains('דף');

/// סדר הספציפיות בתוך אותו ספר: שורת מקור מדויקת < התאמת TOC מלאה <
/// התאמה חלקית; בתוך כל אחת: TOC L1 < TOC L2 < AltToc < TOC L3+.
int findRefSpecificityRank({
  required bool isSourceLine,
  required bool isAltToc,
  required int tocLevel,
  bool isPartialTocMatch = false,
}) {
  if (isSourceLine) return 0;
  final byLevel = isAltToc ? 4 : (tocLevel <= 2 ? tocLevel + 1 : tocLevel + 2);
  return isPartialTocMatch ? _partialTocRankOffset + byLevel : byLevel;
}

/// גדול מכל דרגת רמה אפשרית, כך שהתאמה חלקית תמיד אחרי כל התאמה מלאה.
const int _partialTocRankOffset = 1 << 16;

/// שובר-שוויון לתצוגה: ציון קצר יותר קודם, ואז לפי מיקום בספר — אחרת "כג."
/// ו-"כג:" שווי-האורך עלולים להופיע עמוד ב לפני עמוד א.
int compareFindRefDisplayOrder(
  String referenceA,
  num segmentA,
  String referenceB,
  num segmentB,
) {
  final lenCmp = referenceA.length.compareTo(referenceB.length);
  if (lenCmp != 0) return lenCmp;
  return segmentA.compareTo(segmentB);
}

/// מפתחות הספר שאינם תלויים בשאילתה: tier "ספר יסוד" (1=מקרא ... 10=שו"ע,
/// null=מפרש/ספרות עזר) וסדר הדור ([CommentaryEra.order]).
typedef FindRefBookRank = ({int? foundationalTier, int eraOrder});

/// הצורה של השאילתה שהדירוג צריך, מחושבת פעם אחת לכל שאילתה.
class FindRefRankQuery {
  FindRefRankQuery(this.tokens)
    : text = tokens.join(' '),
      matchTokens = tokens.map(bookNameMatchToken).toList(growable: false),
      isDafCitation = queryLooksDafCitation(tokens);

  final List<String> tokens;
  final String text;

  /// [tokens] ב-[bookNameMatchToken], להשוואה מול כותרות.
  final List<String> matchTokens;
  final bool isDafCitation;

  bool get needsTokenWiseRanking => tokens.length >= 2;

  /// מפתחות ההתאמה של כותרת מנורמלת לשאילתה — תלויים בספר בלבד.
  ({bool exactMatch, bool startsWithMatch, List<String> titleTokens})
  titleMatch(String normTitle) {
    final title = bookNameMatchForm(normTitle);
    final query = matchTokens.join(' ');
    return (
      exactMatch: title == query,
      startsWithMatch: title.startsWith(query),
      titleTokens: needsTokenWiseRanking
          ? title.split(' ').where((t) => t.isNotEmpty).toList()
          : const <String>[],
    );
  }
}

/// מפתחות המיון של תוצאה אחת (decorate-sort-undecorate), כך שההשוואה זולה.
class FindRefRankKey<T> {
  const FindRefRankKey({
    required this.item,
    required this.normTitle,
    required this.fuzzyBookMatch,
    required this.exactMatch,
    required this.startsWithMatch,
    required this.titleTokens,
    required this.citationMatch,
    required this.bookRank,
    required this.isOfficial,
    required this.orderIndex,
    required this.specificity,
    required this.reference,
    required this.segment,
    required this.bookId,
    this.categoryTokens = const {},
    this.punctuationAgrees = true,
  });

  final T item;
  final String normTitle;
  final bool fuzzyBookMatch;
  final bool exactMatch;
  final bool startsWithMatch;
  final List<String> titleTokens;

  /// true = ה-reference מתאים לסגנון הציון שהוזן (ראו [findRefCitationMatch]).
  final bool citationMatch;
  final FindRefBookRank bookRank;
  final bool isOfficial;
  final double orderIndex;

  /// ראו [findRefSpecificityRank].
  final int specificity;
  final String reference;
  final num segment;

  /// אינו מפתח דירוג; מכריע בין שורות שקולות כשבוחרים חלק מהרשימה.
  final int bookId;

  /// מילות שם התיקייה, לתוצאה שנמצאה לפיו (ריק לכל השאר).
  final Set<String> categoryTokens;

  /// הספר כותב בגרשיים את מילות השאילתה שנכתבו בגרשיים ("רמב"ם" ולא "רמבם").
  final bool punctuationAgrees;

  /// התאמת תת-מחרוזת בשם הספר, שהזנב של שאילתת מילה-אחת שומר לה מקום.
  bool isSubstringMatch(String query) =>
      !startsWithMatch && normTitle.contains(query);
}

/// משווה שתי תוצאות לפי **רלוונטיות** בלבד. סדר התצוגה אינו רלוונטיות, ולכן
/// אינו כאן — כך ה-cap לא חותך באמצע קבוצת תוצאות שווֹת-רלוונטיות.
int compareFindRefRelevance(
  FindRefRankKey<Object?> a,
  FindRefRankKey<Object?> b,
  FindRefRankQuery query,
) {
  // התאמה מקורבת בשם הספר תמיד מתחת להתאמה מילולית או לכינוי מדויק.
  if (a.fuzzyBookMatch != b.fuzzyBookMatch) {
    return a.fuzzyBookMatch ? 1 : -1;
  }

  // 1. התאמה מלאה של שם הספר
  if (a.exactMatch != b.exactMatch) return a.exactMatch ? -1 : 1;

  // 2. התאמה של התחלת שם הספר
  if (a.startsWithMatch != b.startsWithMatch) {
    return a.startsWithMatch ? -1 : 1;
  }

  // 3. התאמת מילים בודדות (מילה שנייה ואילך); אות בודדת היא מספר מיקום.
  if (query.needsTokenWiseRanking) {
    final queryTokens = query.tokens;
    for (int i = 1; i < queryTokens.length; i++) {
      final queryToken = queryTokens[i];
      if (queryToken.length == 1) continue;
      final matchToken = query.matchTokens[i];
      // התאמת תיקייה מספקת את המילה גם ללא כותרת; המפתח חייב להיות עצמאי
      // לכל תוצאה, אחרת שילוב עם התאמות TOC יוצר מעגל בהשוואה.
      final aHasMatch =
          a.categoryTokens.contains(queryToken) ||
          (i < a.titleTokens.length && a.titleTokens[i].startsWith(matchToken));
      final bHasMatch =
          b.categoryTokens.contains(queryToken) ||
          (i < b.titleTokens.length && b.titleTokens[i].startsWith(matchToken));
      if (aHasMatch != bHasMatch) return aHasMatch ? -1 : 1;
    }
  }

  // 4. התאמה לסגנון הציון (גמרא/משנה/תנ"ך)
  if (a.citationMatch != b.citationMatch) return a.citationMatch ? -1 : 1;

  // 5. ספר יסוד לפני כל שאינו יסוד, ובין היסודות לפי tier. לפני orderIndex
  // כדי ש"שבת יג" יחזיר את הספרים עצמם ולא את מפרשיהם.
  final aTier = a.bookRank.foundationalTier;
  final bTier = b.bookRank.foundationalTier;
  if (aTier != bTier) {
    if (aTier == null) return 1;
    if (bTier == null) return -1;
    return aTier.compareTo(bTier);
  }

  // 6. סדר הדורות בין מפרשים — orderIndex לבדו מערבב דורות מענפי-עץ שונים.
  if (aTier == null && a.bookRank.eraOrder != b.bookRank.eraOrder) {
    return a.bookRank.eraOrder.compareTo(b.bookRank.eraOrder);
  }

  // orderIndex של מסדים שונים אינו בר-השוואה.
  if (a.isOfficial != b.isOfficial) return a.isOfficial ? -1 : 1;
  // הנרמול מוחק גרשיים; בשוויון קודם ספר שכתוב כמו השאילתה.
  if (a.punctuationAgrees != b.punctuationAgrees) {
    return a.punctuationAgrees ? -1 : 1;
  }

  // 7. סדר ספר בספרייה
  final orderCmp = a.orderIndex.compareTo(b.orderIndex);
  if (orderCmp != 0) return orderCmp;

  // 8. סדר: TOC L1 < TOC L2 < AltToc < TOC L3+
  return a.specificity.compareTo(b.specificity);
}

/// סדר הדירוג: רלוונטיות ואז סדר תצוגה. שתי תוצאות ששוות בשניהם שקולות, והמיון
/// מציב אותן בסדר שרירותי.
int compareFindRefRank(
  FindRefRankKey<Object?> a,
  FindRefRankKey<Object?> b,
  FindRefRankQuery query,
) {
  final rel = compareFindRefRelevance(a, b, query);
  if (rel != 0) return rel;
  return compareFindRefDisplayOrder(
    a.reference,
    a.segment,
    b.reference,
    b.segment,
  );
}
