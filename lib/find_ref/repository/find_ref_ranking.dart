/// דירוג תוצאות האיתור: המפתחות וההשוואה. משותף לדירוג ב-main ולבחירת
/// התאמות ה-AltToc הגלובלי ב-worker (isolate-safe).
library;

import 'package:otzaria/book_aliases/book_aliases.dart';
import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/utils/text/ref_key.dart';

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
  final penultimate = tokens[tokens.length - 2];
  if (_structureWords.contains(penultimate)) return false;
  return penultimate.length >= 2 &&
      penultimate.length <= 4 &&
      penultimate.codeUnits.every(
        (c) => c >= 0x05D0 && c <= 0x05EA,
      ); // אותיות עבריות בלבד
}

const _structureWords = {
  'פרק',
  'משנה',
  'פסוק',
  'הלכה',
  'סעיף',
  'סימן',
  'חלק',
  'שאלה',
};

/// מספר יחיד אחרי שם הספר שזוהה; "א" נשאר פרק כי הבבלי מתחיל בדף ב.
bool queryEndsWithBareNumber(
  List<String> tokens, {
  required int bookTokenCount,
}) =>
    bookTokenCount > 0 &&
    tokens.length == bookTokenCount + 1 &&
    tokens.last != 'א' &&
    isHebrewNumeral(tokens.last);

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
  FindRefRankQuery(
    this.tokens, {
    this.aliasFoundationalTiers = const {},
    this.preferBavli = false,
  }) : text = tokens.join(' '),
       matchTokens = tokens.map(bookNameMatchToken).toList(growable: false),
       isDafCitation = queryLooksDafCitation(tokens);

  final List<String> tokens;
  final Set<int> aliasFoundationalTiers;
  final String text;

  /// [tokens] ב-[bookNameMatchToken], להשוואה מול כותרות.
  final List<String> matchTokens;
  final bool isDafCitation;
  final bool preferBavli;

  bool get needsTokenWiseRanking => tokens.length >= 2;

  late final List<String> _nameWords = matchTokens.any(isTractateWord)
      ? [
          for (var i = 0; i < matchTokens.length; i++)
            if (i == matchTokens.length - 1 || !isTractateWord(matchTokens[i]))
              matchTokens[i],
        ]
      : matchTokens;

  /// מפתחות ההתאמה של כותרת מנורמלת לשאילתה — תלויים בספר בלבד.
  ({bool exactMatch, bool startsWithMatch, List<bool> titleWordMatches})
  titleMatch(String normTitle) {
    final title = bookNameMatchForm(normTitle);
    final query = matchTokens.join(' ');
    return (
      exactMatch: title == query,
      startsWithMatch: title.startsWith(query),
      titleWordMatches: needsTokenWiseRanking
          ? _titleWordMatches(
              title.split(' ').where((t) => t.isNotEmpty).toList(),
            )
          : const <bool>[],
    );
  }

  /// לכל מילת שאילתה: האם המילה שבמקומה בכותרת, מעוגנת למילה הראשונה, פותחת בה.
  /// "מסכת" אינה נספרת בשני הצדדים: "מסכת יבמות" היא הגמרא "יבמות" (#5609).
  List<bool> _titleWordMatches(List<String> titleTokens) {
    final words = _nameWords;
    if (words.length == matchTokens.length) {
      final start = _titleAnchor(titleTokens, matchTokens.first);
      return [
        for (var i = 0; i < matchTokens.length; i++)
          _titleTokenAt(titleTokens, start + i, matchTokens[i]),
      ];
    }
    final title = [
      for (var i = 0; i < titleTokens.length; i++)
        if (i == titleTokens.length - 1 || !isTractateWord(titleTokens[i]))
          titleTokens[i],
    ];
    final start = _titleAnchor(title, words.first);
    var k = 0;
    return [
      for (var i = 0; i < matchTokens.length; i++)
        (i < matchTokens.length - 1 && isTractateWord(matchTokens[i])) ||
            _titleTokenAt(title, start + k++, matchTokens[i]),
    ];
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
    required this.titleWordMatches,
    required this.citationMatch,
    required this.bookRank,
    required this.isOfficial,
    required this.orderIndex,
    required this.specificity,
    required this.reference,
    required this.segment,
    required this.bookId,
    this.answersDibbur = false,
    this.categoryTokens = const {},
    this.punctuationAgrees = true,
    this.directNameMatch = false,
    this.exactAliasMatch = false,
    this.namesBook = false,
  });

  final T item;
  final String normTitle;
  final bool fuzzyBookMatch;
  final bool exactMatch;

  /// שם או ציון מלא התואמים לשאילתה, כשמתחרים בכינוי מדויק.
  final bool directNameMatch;

  /// הספר נמצא לפי כינוי מדויק (טבלת הכינויים), ולא לפי מילות שמו.
  final bool exactAliasMatch;

  /// השאילתה היא שמו המדויק של הספר (כותרת או כינוי) ואחריו מיקום.
  final bool namesBook;
  final bool startsWithMatch;

  /// מ-[FindRefRankQuery.titleMatch]: נקבע פעם אחת לכותרת ולא בכל השוואה.
  final List<bool> titleWordMatches;

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

  /// דיבור-מתחיל שנמצא לשאילתת ד"ה.
  final bool answersDibbur;

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
  final classCmp = compareFindRefMatchClass(a, b, query);
  if (classCmp != 0) return classCmp;

  // 7. סדר ספר בספרייה
  final orderCmp = a.orderIndex.compareTo(b.orderIndex);
  if (orderCmp != 0) return orderCmp;

  // 8. סדר: TOC L1 < TOC L2 < AltToc < TOC L3+
  return a.specificity.compareTo(b.specificity);
}

/// מחלקת ההתאמה: כל מפתחות הרלוונטיות שלפני סדר המדף. שתי תוצאות ששוות
/// בה מוכרעות היום רק לפי מקום הספר בספרייה.
int compareFindRefMatchClass(
  FindRefRankKey<Object?> a,
  FindRefRankKey<Object?> b,
  FindRefRankQuery query,
) {
  // בשאילתת ד"ה הדיבור הוא התשובה, גם כשהספר שלו אינו הספר שנקרא בשמו.
  if (a.answersDibbur != b.answersDibbur) return a.answersDibbur ? -1 : 1;

  // התאמה מקורבת בשם הספר תמיד מתחת להתאמה מילולית או לכינוי מדויק.
  if (a.fuzzyBookMatch != b.fuzzyBookMatch) {
    return a.fuzzyBookMatch ? 1 : -1;
  }

  // 1. התאמה מלאה של שם הספר
  if (a.exactMatch != b.exactMatch) return a.exactMatch ? -1 : 1;

  if (a.directNameMatch != b.directNameMatch) {
    return a.directNameMatch ? -1 : 1;
  }

  // כינוי מדויק מקדם את כל קבוצת היסוד, כדי שכינויים חלקיים לא יפצלו אותה.
  if (!query.needsTokenWiseRanking) {
    final aAliasFoundation =
        a.directNameMatch &&
        query.aliasFoundationalTiers.contains(a.bookRank.foundationalTier);
    if (aAliasFoundation !=
        (b.directNameMatch &&
            query.aliasFoundationalTiers.contains(
              b.bookRank.foundationalTier,
            ))) {
      return aAliasFoundation ? -1 : 1;
    }
  }

  // 2. התאמה של התחלת שם הספר
  if (a.startsWithMatch != b.startsWithMatch) {
    return a.startsWithMatch ? -1 : 1;
  }

  // 3. התאמת מילים בודדות (מילה שנייה ואילך), מעוגנת למילה הראשונה בכותרת:
  // "ירושלמי מעשר שני" ב"תלמוד ירושלמי מעשר שני". אות בודדת היא מספר מיקום.
  if (query.needsTokenWiseRanking) {
    final queryTokens = query.tokens;
    for (int i = 1; i < queryTokens.length; i++) {
      final queryToken = queryTokens[i];
      if (queryToken.length == 1) continue;
      // התאמת תיקייה מספקת את המילה גם ללא כותרת; המפתח חייב להיות עצמאי
      // לכל תוצאה, אחרת שילוב עם התאמות TOC יוצר מעגל בהשוואה.
      final aHasMatch =
          a.categoryTokens.contains(queryToken) || a.titleWordMatches[i];
      final bHasMatch =
          b.categoryTokens.contains(queryToken) || b.titleWordMatches[i];
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
    // מספר בודד אחרי שם מסכת הוא לרוב דף, לכן בבלי (3) לפני משנה (2).
    if (query.preferBavli &&
        ((aTier == 2 && bTier == 3) || (aTier == 3 && bTier == 2))) {
      return bTier.compareTo(aTier);
    }
    return aTier.compareTo(bTier);
  }

  // "שמות רבה מה": הספר שנקרא בשמו לפני מפרשיו, שאינם ספרי יסוד כמוהו (#5741).
  if (aTier == null && a.namesBook != b.namesBook) {
    return a.namesBook ? -1 : 1;
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

  // ספר שתוכנו ענה על כל השאילתה קודם לספר שבו נשארה מילה ללא מענה.
  final aPartial = a.specificity >= _partialTocRankOffset;
  if (aPartial != (b.specificity >= _partialTocRankOffset)) {
    return aPartial ? 1 : -1;
  }
  return 0;
}

/// מקום המילה הראשונה של השאילתה בכותרת; 0 כשאינה בה (כינוי, ראשי-תיבות)
/// או כשהיא אות בודדת, שהייתה מתאימה לכל מילה שפותחת בה.
int _titleAnchor(List<String> titleTokens, String first) {
  if (first.length < 2) return 0;
  final at = titleTokens.indexWhere((t) => t.startsWith(first));
  return at < 0 ? 0 : at;
}

bool _titleTokenAt(List<String> titleTokens, int index, String prefix) =>
    index < titleTokens.length && titleTokens[index].startsWith(prefix);

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

/// כמה שורות ראשונות של ספר מועדף מוקדמות; שאר שורותיו נשארות במקומן.
const int findRefPersonalRowsPerBook = 2;

/// כמה שורות של ספרים מועדפים נוספות לכל היותר מעבר לחיתוך.
const int findRefPersonalMaxAdditions = 6;

/// סידור אישי **אחרי** הדירוג: מזיז שורות בתוך [kept] (אינדקסים ב-[sorted],
/// בסדר עולה) ומוסיף מעטות — לעולם אינו גורע. [cutoff] — אורך הרצף שנחתך.
List<int> personalizeFindRefOrder(
  List<FindRefRankKey<Object?>> sorted,
  List<int> kept,
  FindRefRankQuery query, {
  required int cutoff,
  required List<String?> books,
  required List<double> affinities,
}) {
  bool isPartial(int i) => sorted[i].specificity >= _partialTocRankOffset;

  // מועמדי ההקדמה: השורות הראשונות של כל ספר מועדף שענו על כל השאילתה.
  final candidates = <int>{};
  final rowsPerBook = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    final book = books[i];
    if (book == null || affinities[i] <= 0 || isPartial(i)) continue;
    final taken = rowsPerBook[book] ?? 0;
    if (taken >= findRefPersonalRowsPerBook) continue;
    rowsPerBook[book] = taken + 1;
    candidates.add(i);
  }
  if (candidates.isEmpty || kept.isEmpty) return kept;

  final included = kept.toSet();
  // אחרי [cutoff] נשארה רק מכסת הזנב של #839, שאינה גבול לתוספות.
  if (cutoff > 0 && cutoff < sorted.length) {
    final boundary = sorted[cutoff - 1];
    var additions = 0;
    for (final i in candidates) {
      if (additions >= findRefPersonalMaxAdditions) break;
      if (i < cutoff || included.contains(i)) continue;
      // רק שורה שמחלקת ההתאמה שלה אינה גרועה משל האחרונה שבחיתוך.
      if (compareFindRefMatchClass(sorted[i], boundary, query) > 0) continue;
      included.add(i);
      additions++;
    }
  }

  // התוספות נכנסות במקומן בסדר הדירוג; מכאן רק מועמדים זזים, שורה-שורה
  // כלפי מעלה, ונעצרים בחוסם הראשון — כך שאר השורות נשארות בסדרן.
  final order = included.toList()..sort();
  // מי שאינו מועמד נחשב חסר זיקה — גם שורה שלישית ואילך של ספר מועדף,
  // ולכן שתי הראשונות של כל ספר מועדף קודמות לשורות הנוספות של אחר.
  double boost(int i) => candidates.contains(i) ? affinities[i] : 0;
  for (final candidate in candidates) {
    var at = order.indexOf(candidate);
    if (at < 0) continue;
    while (at > 0) {
      final above = order[at - 1];
      // עוקפים רק שורה מאותה מחלקה, פחות מועדפת, ושאינה ספציפית יותר.
      if (compareFindRefMatchClass(sorted[above], sorted[candidate], query) !=
              0 ||
          boost(above) >= boost(candidate) ||
          sorted[above].specificity < sorted[candidate].specificity) {
        break;
      }
      order[at] = above;
      order[--at] = candidate;
    }
  }

  return order;
}
