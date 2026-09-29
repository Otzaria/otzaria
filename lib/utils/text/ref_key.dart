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

/// ע"א/ע"ב בשאילתת איתור → "עמוד א"/"עמוד ב": מילת המיקום מסמנת את הטוקן
/// שלפניה כמספר דף גם כשהוא אות בודדת ("ברכות ב ע"א").
String expandQueryAmudMarks(String query) =>
    query.replaceAll(_amudA, 'עמוד א').replaceAll(_amudB, 'עמוד ב');

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

/// מסמן מפתח חלקי. טוקנים מנורמלים אינם מכילים אותו, ולכן מפתח חלקי לא
/// יתנגש במפתח מלא, ומסד ישן פשוט לא יחזיר עבורו כלום.
const String partialRefKeyMarker = '~';

/// המפתח החלקי של הפניה מוקלדת, שעשויה להשמיט את החלקים בעלי השם של ה-heRef.
String? buildPartialRefKey(String ref) {
  final key = buildRefKey(ref);
  return key == null ? null : '$partialRefKeyMarker $key';
}

/// מפתחות חלקיים של שורה שה-heRef שלה נפתח, אחרי הכותרת, בחלקים בעלי שם
/// ("טור, חושן משפט, שט, ג") — אחד לכל השמטה מבחוץ פנימה ("~ שט ג").
/// ריק אלא אם אחרי החלקים באים לפחות שני רכיבים מספריים.
List<String> partialLineRefKeys(String heRef, Iterable<String> titleAliases) {
  final suffix = _suffixAfterTitleAlias(heRef, titleAliases);
  if (suffix == null) return const [];
  final components = suffix
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  var named = components.indexWhere(_isNumeralComponent);
  if (named < 0) named = components.length;
  final numeric = components.sublist(named);
  if (named == 0 || numeric.length < 2 || !numeric.every(_isNumeralComponent)) {
    return const [];
  }
  final keys = <String>[];
  for (var omitted = 1; omitted <= named; omitted++) {
    final key = buildPartialRefKey(components.sublist(omitted).join(', '));
    if (key != null && !keys.contains(key)) keys.add(key);
  }
  return keys;
}

const Map<String, int> _numeralValues = {
  'א': 1,
  'ב': 2,
  'ג': 3,
  'ד': 4,
  'ה': 5,
  'ו': 6,
  'ז': 7,
  'ח': 8,
  'ט': 9,
  'י': 10,
  'כ': 20,
  'ל': 30,
  'מ': 40,
  'נ': 50,
  'ס': 60,
  'ע': 70,
  'פ': 80,
  'צ': 90,
  'ק': 100,
  'ר': 200,
  'ש': 300,
  'ת': 400,
};

/// רכיב heRef שהוא מספר מיקום ("שט", "סימן ז", "ב.") ולא שם.
bool _isNumeralComponent(String component) {
  final tokens = refKeyTokens(component);
  return tokens.isNotEmpty && tokens.every(_isNumeralToken);
}

/// ספרות, או אותיות בסדר ערך לא-עולה. שם שנקרא כמספר ("נח") רק מאבד את
/// המפתח החלקי שלו.
bool _isNumeralToken(String token) {
  if (RegExp(r'^\d+$').hasMatch(token)) return true;
  if (token.length > 6) return false;
  int? previous;
  for (final ch in token.split('')) {
    final value = _numeralValues[ch];
    if (value == null || (previous != null && value > previous)) return false;
    previous = value;
  }
  return true;
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
