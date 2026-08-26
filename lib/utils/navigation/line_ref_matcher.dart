/// ליבת ההתאמה של הפניה לרמת שורה דרך עמודת ה-heRef הפר-שורתית ב-DB.
///
/// ה-TOC מגיע רק עד רמת פרק/סימן, אבל לכל שורה (פסוק/סעיף) יש heRef מלא
/// כמו "במדבר לג, ה" — כך "לג ה" נפתר לשורת הפסוק עצמו ולא לתחילת הפרק.
///
/// הקוד חולץ מ-PluginRefLineResolver כדי לשמש גם את "איתור מקורות"
/// (issue #992 — איתור גם לפי פסוקים), כולל בתוך ה-DB isolate של האיתור.
library;

import 'package:otzaria/utils/text/text_manipulation.dart';

/// מילות-מיקום שאינן חלק מערכי ההפניה עצמם ("פרק לג פסוק ה" ↔ "לג ה").
const Set<String> lineRefLocatorWords = {
  'פרק',
  'פסוק',
  'פסקה',
  'סעיף',
  'סימן',
  'הלכה',
  'משנה',
  'דף',
  'עמוד',
  'אות',
};

/// טוקני ההפניה לאחר נרמול: טווח ("לג:ה-ז") נחתך לתחילתו, מילות-מיקום
/// מוסרות, ו-"ע\"א"/"ע\"ב" ממופים לטוקני העמוד של פורמט הגמרא.
List<String> lineRefQueryTokens(String ref) {
  final dashIndex = ref.indexOf(RegExp('[-–]'));
  final trimmed = dashIndex > 0 ? ref.substring(0, dashIndex) : ref;
  return filterLineRefLocators(tokenizeLineRef(trimmed));
}

List<String> tokenizeLineRef(String s) => normalizeForFindRefMatch(
  _expandDafMarks(s),
).split(' ').where((t) => t.isNotEmpty).toList();

/// מרחיב סימון עמוד גמרא ("ב." / "ב:") לטוקן עמוד מפורש — כמו הנרמול
/// הכללי, אבל גם כשאחרי הסימן בא פסיק ("ברכות ב., א"), תבנית ה-heRef ב-DB
/// שבה הנרמול הכללי מפספס ומידע העמוד אובד.
String _expandDafMarks(String s) => s
    .replaceAllMapped(
      RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=[,\s]|$)'''),
      (m) => '${m[1]} א',
    )
    .replaceAllMapped(
      RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=[,\s]|$)'''),
      (m) => '${m[1]} ב',
    );

List<String> filterLineRefLocators(List<String> tokens) => tokens
    .where((t) => !lineRefLocatorWords.contains(t))
    .map((t) => t == 'עא' ? 'א' : (t == 'עב' ? 'ב' : t))
    .toList();

/// מאתר ברשימת [heRefs] את השורה שההפניה [refTokens] מצביעה עליה בתוך
/// הספר [bookTitle], ומחזיר את האינדקס שלה ברשימה — או null אם אין התאמה.
///
/// ההתאמה דורשת שוויון-טוקנים מלא בין ההפניה לחלק שאחרי כותרת הספר ב-heRef,
/// כדי שהפניה דו-רכיבית לא תיתפס בטעות ע"י שורה ברמה אחרת. הקוראים
/// מחזיקים את שאר נתוני השורה (lineIndex, id) לצד ה-heRef לפי אותו אינדקס.
int? matchLineRefIndex({
  required List<String> heRefs,
  required String bookTitle,
  required List<String> refTokens,
}) {
  // רכיב יחיד ("לג") הוא ברמת TOC — אין מה לחפש ברמת שורה.
  if (refTokens.length < 2) return null;

  final titleTokens = tokenizeLineRef(bookTitle);
  for (var i = 0; i < heRefs.length; i++) {
    final heTokens = tokenizeLineRef(heRefs[i]);
    if (heTokens.length <= titleTokens.length) continue;

    var titleMatches = true;
    for (var t = 0; t < titleTokens.length; t++) {
      if (heTokens[t] != titleTokens[t]) {
        titleMatches = false;
        break;
      }
    }
    if (!titleMatches) continue;

    final remainder = filterLineRefLocators(
      heTokens.sublist(titleTokens.length),
    );
    if (remainder.length != refTokens.length) continue;
    var matches = true;
    for (var t = 0; t < refTokens.length; t++) {
      if (remainder[t] != refTokens[t]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return null;
}
