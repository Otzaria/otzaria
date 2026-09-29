/// מפתחות הדירוג של האיתור שתלויים רק בתוצאה עצמה, ולכן מבדילים בין תוצאות
/// של אותו ספר. משותפים לדירוג ב-main ולצמצום ב-worker (isolate-safe).
library;

/// תקרת-ביטחון מוחלטת על מספר תוצאות האיתור.
const int findRefMaxResultCap = 100;

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

/// סדר הספציפיות בתוך אותו ספר: שורת מקור מדויקת < TOC L1 < TOC L2 <
/// AltToc < TOC L3+.
int findRefSpecificityRank({
  required bool isSourceLine,
  required bool isAltToc,
  required int tocLevel,
}) {
  if (isSourceLine) return 0;
  if (isAltToc) return 4;
  return tocLevel <= 2 ? tocLevel + 1 : tocLevel + 2;
}

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

typedef FindRefInBookKey = ({
  String reference,
  num segment,
  bool isSourceLine,
  bool isAltToc,
  int tocLevel,
});

/// סדר הדירוג בין שתי תוצאות של אותו ספר רשמי ששתיהן התאמה ישירה: שאר
/// המפתחות תלויים בספר בלבד ושווים ביניהן.
int compareWithinBook(
  FindRefInBookKey a,
  FindRefInBookKey b, {
  required bool isDafCitation,
}) {
  final aCitation = findRefCitationMatch(isDafCitation, a.reference);
  if (aCitation != findRefCitationMatch(isDafCitation, b.reference)) {
    return aCitation ? -1 : 1;
  }
  final rankCmp =
      findRefSpecificityRank(
        isSourceLine: a.isSourceLine,
        isAltToc: a.isAltToc,
        tocLevel: a.tocLevel,
      ).compareTo(
        findRefSpecificityRank(
          isSourceLine: b.isSourceLine,
          isAltToc: b.isAltToc,
          tocLevel: b.tocLevel,
        ),
      );
  if (rankCmp != 0) return rankCmp;
  return compareFindRefDisplayOrder(
    a.reference,
    a.segment,
    b.reference,
    b.segment,
  );
}
