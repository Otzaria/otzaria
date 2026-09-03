/// מפתח הפניה קנוני לרמת שורה — המקור היחיד לנרמול, משותף לבונה ה-DB
/// (`line_ref`), ל-FindRef, לתוספים ולבדיקות.
///
/// כל סטייה בין המימוש כאן למימוש ב-SeforimLibrary מייצרת החטאה שקטה
/// (hash שונה → אין מועמד), ולכן שני הצדדים נבדקים מול
/// `test/fixtures/ref_key_fixtures.json`.
library;

import 'dart:convert';

import 'package:otzaria/utils/text/text_manipulation.dart';

/// מילות מיקום שאינן חלק מערכי ההפניה ("פרק לג פסוק ה" ↔ "לג ה").
const Set<String> _locatorWords = {
  'פרק',
  'פסוק',
  'פסקה',
  'סעיף',
  'סימן',
  'הלכה',
  'משנה',
  'מאמר',
  'דף',
  'עמוד',
  'אות',
};

/// מרחיב סימון עמוד גמרא לטוקן עמוד מפורש: "ב." → "ב א", "ב:" → "ב ב".
///
/// בניגוד לנרמול הכללי הדפוס תופס גם סימן שאחריו פסיק ("ברכות ב., א") —
/// תבנית ה-heRef ב-DB, שבלעדיה מידע העמוד אובד.
String _expandDafMarks(String s) => s
    .replaceAllMapped(
      RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=[,\s]|$)'''),
      (m) => '${m[1]} א',
    )
    .replaceAllMapped(
      RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=[,\s]|$)'''),
      (m) => '${m[1]} ב',
    );

/// טווח בסוף ההפניה ("לב יא-יג", "ברכות ב.-ג.") — רק צורה זו נחתכת. חיתוך
/// במקף הראשון שנמצא בלע כל הפניה בספר שבכותרתו מקף ("מגדל־עז ...").
final RegExp _trailingRange = RegExp(
  '''(?:^|[\\s,.:])(?:\\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)[.:]?\\s*([-–־])\\s*'''
  '''(?:\\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)[.:]?\\s*\$''',
);

/// רק הצורות המגורשות מסמנות עמוד. "עא"/"עב" חשופים הם המספרים 71/72
/// ואסור שיתנגשו ב-א/ב.
final RegExp _amudA = RegExp('''(?<![א-ת])ע["'״׳]א(?![א-ת])''');
final RegExp _amudB = RegExp('''(?<![א-ת])ע["'״׳]ב(?![א-ת])''');

/// טוקני המפתח הקנוני של [ref], לפי הסדר: חיתוך טווח, הרחבת סימוני דף,
/// הסרת ניקוד/טעמים, מיפוי ע"א/ע"ב, הסרת גרשיים/פיסוק והסרת מילות מיקום.
List<String> refKeyTokens(String ref) {
  // חיתוך הטווח לפני הנרמול — המקף נהפך לרווח בהסרת הניקוד. תחילית ההתאמה
  // ורכיב המספר אינם מכילים מפריד, ולכן הראשון שאחרי תחילתה הוא מפריד הטווח.
  final range = _trailingRange.firstMatch(ref);
  final dash = range == null ? -1 : ref.indexOf(RegExp('[-–־]'), range.start);
  final head = dash > 0 ? ref.substring(0, dash) : ref;

  var cleaned = removeTeamim(removeVolwels(_expandDafMarks(head)));
  cleaned = cleaned.replaceAll(_amudA, 'א').replaceAll(_amudB, 'ב');
  cleaned = cleaned
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9֐-׿\s]'), ' ').toLowerCase();

  return cleaned
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_locatorWords.contains(t))
      .toList();
}

/// המפתח הקנוני של [ref], או `null` כשלא נותר ממנו דבר.
String? buildRefKey(String ref) {
  final tokens = refKeyTokens(ref);
  return tokens.isEmpty ? null : tokens.join(' ');
}

/// המפתח הקנוני של שורה: [heRef] לאחר קיצוץ הקידומת שהיא כותרת הספר.
///
/// [titleAliases] הן צורות הכותרת המוכרות; כשאף אחת אינה קידומת של ה-heRef
/// נשמר ה-heRef המלא, וזה מדווח כאי-התאמה בזמן הבנייה.
String? buildLineRefKey(String heRef, Iterable<String> titleAliases) {
  final suffix = _suffixAfterTitleAlias(heRef, titleAliases);
  if (suffix != null) return buildRefKey(suffix);

  final tokens = refKeyTokens(heRef);
  if (tokens.isEmpty) return null;

  List<String>? longestMatch;
  for (final alias in titleAliases) {
    final aliasTokens = refKeyTokens(alias);
    if (aliasTokens.isEmpty || aliasTokens.length > tokens.length) continue;
    var matches = true;
    for (var i = 0; i < aliasTokens.length; i++) {
      if (tokens[i] != aliasTokens[i]) {
        matches = false;
        break;
      }
    }
    if (matches && aliasTokens.length > (longestMatch?.length ?? 0)) {
      longestMatch = aliasTokens;
    }
  }
  if (longestMatch == null) return tokens.join(' ');
  // שורת כותרת — ה-heRef הוא שם הספר בלבד ואין בה הפניה תת-רמתית.
  if (longestMatch.length == tokens.length) return null;
  return tokens.sublist(longestMatch.length).join(' ');
}

/// החלק שאחרי כותרת מילולית ב-[heRef], לפי ה-alias הארוך ביותר שמתאים.
///
/// רץ בכוונה **לפני** זיהוי הטווח: מקף חוקי בתוך שם ספר, וחיתוך הטווח לפניו
/// היה מכווץ כל שורה בספר למפתח הכותרת.
String? _suffixAfterTitleAlias(String heRef, Iterable<String> titleAliases) {
  String? longestMatch;
  for (final alias in titleAliases) {
    if (alias.trim().isEmpty ||
        alias.length <= (longestMatch?.length ?? 0) ||
        !heRef.startsWith(alias)) {
      continue;
    }
    // ה-alias נבלע לתוך מילה ארוכה יותר ("ברכות" בתוך "ברכותיים").
    if (heRef.length > alias.length &&
        _isLetterOrDigit(heRef.codeUnitAt(alias.length))) {
      continue;
    }
    longestMatch = alias;
  }
  return longestMatch == null ? null : heRef.substring(longestMatch.length);
}

/// מקבילה ל-`Char.isLetterOrDigit` — אות (בכל כתב) או ספרה.
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{Nd}]', unicode: true);

bool _isLetterOrDigit(int codeUnit) =>
    _letterOrDigit.hasMatch(String.fromCharCode(codeUnit));

/// FNV-1a 64 ביט על ייצוג ה-UTF-8 של [refKey], כערך חתום — הצורה שנשמרת
/// ב-`line_ref.refKeyHash` ומחושבת זהה בבונה ה-DB.
int refKeyHash(String refKey) {
  // חשבון 64 ביט עם גלישה — זהה ל-Long בבונה ה-DB.
  var hash = -3750763034362895579; // 14695981039346656037 כערך חתום
  for (final byte in utf8.encode(refKey)) {
    hash = (hash ^ byte) * 1099511628211;
  }
  return hash;
}
