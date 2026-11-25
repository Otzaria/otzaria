/// מפתח הפניה קנוני לרמת שורה — המקור היחיד לנרמול, משותף לבונה ה-DB
/// (`line_ref`), ל-FindRef, לתוספים ולבדיקות.
///
/// כל סטייה בין המימוש כאן למימוש ב-SeforimLibrary מייצרת החטאה שקטה
/// (hash שונה → אין מועמד), ולכן שני הצדדים נבדקים מול
/// `test/fixtures/ref_key_fixtures.json`.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
    .replaceAllMapped(_dafA, (m) => '${m[1]} א')
    .replaceAllMapped(_dafB, (m) => '${m[1]} ב');

final RegExp _dafA = RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=[,\s]|$)''');
final RegExp _dafB = RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=[,\s]|$)''');

/// טווח בסוף ההפניה ("לב יא-יג", "ברכות ב.-ג.") — רק צורה זו נחתכת. חיתוך
/// במקף הראשון שנמצא בלע כל הפניה בספר שבכותרתו מקף ("מגדל־עז ...").
final RegExp _trailingRange = RegExp(
  '''(?:^|[\\s,.:])(?:\\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)[.:]?\\s*([-–־])\\s*'''
  '''(?:\\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)[.:]?\\s*\$''',
);
final RegExp _rangeDash = RegExp('[-–־]');

/// רק הצורות המגורשות מסמנות עמוד. "עא"/"עב" חשופים הם המספרים 71/72
/// ואסור שיתנגשו ב-א/ב.
final RegExp _amudA = RegExp('''(?<![א-ת])ע["'״׳]א(?![א-ת])''');
final RegExp _amudB = RegExp('''(?<![א-ת])ע["'״׳]ב(?![א-ת])''');

final RegExp _quoteMarks = RegExp('["\'״׳]');
final RegExp _amudAfterToken = RegExp(
  '''(?<!\\S)(\\S+)(\\s+)ע["'״׳]([אב])(?![א-ת])''',
);

/// ע"א/ע"ב בשאילתת איתור → "עמוד א"/"עמוד ב", רק אחרי מספר עברי ("ברכות ב ע"א",
/// גם "פרק ב ע"א"); אחרי מילה ("תהלים ע"א", "סימן ע"ב", "דף ע"א") הם המספרים 71/72.
String expandQueryAmudMarks(String query) =>
    query.replaceAllMapped(_amudAfterToken, (m) {
      final number = m[1]!.replaceAll(_quoteMarks, '');
      if (!isHebrewNumeral(number)) return m[0]!;
      return '${m[1]}${m[2]}עמוד ${m[3]}';
    });

/// ר"ת של מיקום בשאילתה: "פ"ב ה"ג" → "פרק ב הלכה ג", "פט"ז מ"ג" → "פרק טז משנה ג",
/// "ב ה"ג" → "ב הלכה ג". "פ"ב"/"מ"ג" לבדם הם גם המספרים 82/43 ("תהלים פ"ב").
String expandQueryLocatorAbbreviations(String query) {
  final words = query.split(' ');
  for (var i = 1; i < words.length; i++) {
    final second = _locatorAbbreviation(words[i]);
    if (second == null || second.prefix == 'פ') continue;
    final first = _locatorAbbreviation(words[i - 1]);
    if (first?.prefix == 'פ') {
      words[i - 1] = 'פרק ${first!.number}';
    } else if (second.prefix != 'ה' ||
        !isHebrewNumeral(words[i - 1].replaceAll(_quoteMarks, ''))) {
      continue;
    }
    words[i] = '${second.prefix == 'ה' ? 'הלכה' : 'משנה'} ${second.number}';
  }
  return words.join(' ');
}

final RegExp _locatorAbbreviationPattern = RegExp(
  '^([פהמ])([א-ת]{0,2})["״]([א-ת])\$',
);

({String prefix, String number})? _locatorAbbreviation(String word) {
  final m = _locatorAbbreviationPattern.firstMatch(word);
  if (m == null) return null;
  final number = '${m[2]}${m[3]}';
  return isHebrewNumeral(number) ? (prefix: m[1]!, number: number) : null;
}

/// האם [token] הוא מספר עברי של 1–3 אותיות (בלי סופיות): מאות, עשרות ואחדות
/// בסדר יורד, כולל ט"ו/ט"ז. "שבת" ו"פרק" אינם מספרים, "קכא" ו"ב" כן.
bool isHebrewNumeral(String token) {
  if (token.isEmpty || token.length > 3) return false;
  if (token == 'טו' || token == 'טז') return true;
  var place = 3; // 3 = מאות, 2 = עשרות, 1 = אחדות
  for (final c in token.codeUnits) {
    final int p;
    if (c >= 0x05D0 && c <= 0x05D8) {
      p = 1; // א-ט
    } else if (const [
      0x05D9,
      0x05DB,
      0x05DC,
      0x05DE,
      0x05E0,
      0x05E1,
      0x05E2,
      0x05E4,
      0x05E6,
    ].contains(c)) {
      p = 2; // י כ ל מ נ ס ע פ צ
    } else if (c >= 0x05E7 && c <= 0x05EA) {
      p = 3; // ק ר ש ת
    } else {
      return false;
    }
    if (p > place || (p == place && p != 3)) return false;
    place = p;
  }
  return true;
}

/// טווח וסימן דף דורשים מקף, נקודה או נקודתיים. רוב ה-heRef אינם מכילים
/// אותם, וסריקת שני הביטויים בכל אחד מהם היא רוב עלות הנרמול.
@visibleForTesting
bool mayHaveRangeOrDafMark(String ref) =>
    ref.contains('-') ||
    ref.contains('–') ||
    ref.contains('־') ||
    ref.contains('.') ||
    ref.contains(':');

/// טוקני המפתח הקנוני של [ref], לפי הסדר: חיתוך טווח, הרחבת סימוני דף,
/// הסרת ניקוד/טעמים, מיפוי ע"א/ע"ב, הסרת גרשיים/פיסוק והסרת מילות מיקום.
List<String> refKeyTokens(String ref) {
  // חיתוך הטווח לפני הנרמול — המקף נהפך לרווח בהסרת הניקוד. תחילית ההתאמה
  // ורכיב המספר אינם מכילים מפריד, ולכן הראשון שאחרי תחילתה הוא מפריד הטווח.
  final marked = mayHaveRangeOrDafMark(ref);
  final range = marked ? _trailingRange.firstMatch(ref) : null;
  final dash = range == null ? -1 : ref.indexOf(_rangeDash, range.start);
  final head = dash > 0 ? ref.substring(0, dash) : ref;

  var cleaned = removeVolwels(marked ? _expandDafMarks(head) : head);
  cleaned = cleaned.replaceAll(_amudA, 'א').replaceAll(_amudB, 'ב');
  cleaned = cleaned
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  // כל תו שאינו אות לטינית, ספרה או עברית מפריד בין טוקנים — כמו החלפתו
  // ברווח ופיצול לפי רווחים, בלי שני מעברי RegExp על כל הפניה.
  final tokens = <String>[];
  var start = -1;
  for (var i = 0; i <= cleaned.length; i++) {
    if (i < cleaned.length && isRefKeyChar(cleaned.codeUnitAt(i))) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      final token = cleaned.substring(start, i).toLowerCase();
      if (!_locatorWords.contains(token)) tokens.add(token);
      start = -1;
    }
  }
  return tokens;
}

/// אות לטינית, ספרה או תו מגוש העברית — מה שנשאר בתוך טוקן.
@visibleForTesting
bool isRefKeyChar(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    _isAsciiDigit(c) ||
    (c >= 0x0590 && c <= 0x05FF);

/// המפתח הקנוני של [ref], או `null` כשלא נותר ממנו דבר.
String? buildRefKey(String ref) {
  final tokens = refKeyTokens(ref);
  return tokens.isEmpty ? null : tokens.join(' ');
}

String? _lastTitle;
List<String> _lastTitleTokens = const [];

/// [refKeyTokens] של כותרת. כל שורות הספר נבדקות מול אותה כותרת, ולכן
/// הטוקנים של האחרונה נשמרים.
@visibleForTesting
List<String> titleTokens(String title) {
  if (title != _lastTitle) {
    _lastTitleTokens = List.unmodifiable(refKeyTokens(title));
    _lastTitle = title;
  }
  return _lastTitleTokens;
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
    final aliasTokens = titleTokens(alias);
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

/// האם [keyTokens] (לא ריקים) הם סיומת של [tokens].
bool endsWithRefKeyTokens(List<String> tokens, List<String> keyTokens) {
  if (keyTokens.isEmpty || keyTokens.length > tokens.length) return false;
  final offset = tokens.length - keyTokens.length;
  for (var i = 0; i < keyTokens.length; i++) {
    if (tokens[offset + i] != keyTokens[i]) return false;
  }
  return true;
}

/// האם השורה שה-heRef שלה [heRef] יושבת בתוך הציון [locationKey]
/// ([refKeyTokens] של "עט" או "עט ב") בספר [bookTitle].
bool heRefWithinLocation(
  String heRef,
  String bookTitle,
  List<String> locationKey,
) {
  final lineKey = buildLineRefKey(heRef, [bookTitle]);
  if (lineKey == null) return false;
  final lineTokens = lineKey.split(' ');
  if (lineTokens.length < locationKey.length) return false;
  for (var i = 0; i < locationKey.length; i++) {
    if (lineTokens[i] != locationKey[i]) return false;
  }
  return true;
}

/// ה-hash של המפתח המלא והמפתחות החלקיים של שורה; ריק לשורה בלי מפתח.
List<int> lineRefKeyHashes(String heRef, String bookTitle) => [
  if (buildLineRefKey(heRef, [bookTitle]) case final key?) ...[
    refKeyHash(key),
    for (final partial in partialLineRefKeys(heRef, [bookTitle]))
      refKeyHash(partial),
  ],
];

/// רשומות `line_ref` של ספר: (hash, lineIndex) לכל מפתח של כל שורה.
/// שורות תחת אותה כותרת חולקות heRef, ולכן [hashesOf] נקרא פעם אחת לכל heRef.
List<(int, int)> lineRefIndexEntries(
  Iterable<({int lineIndex, String heRef})> refs,
  List<int> Function(String heRef) hashesOf,
) {
  final hashesByHeRef = <String, List<int>>{};
  return [
    for (final ref in refs)
      for (final hash in hashesByHeRef[ref.heRef] ??= hashesOf(ref.heRef))
        (hash, ref.lineIndex),
  ];
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
  final named = components.indexWhere(_isNumeralComponent);
  if (named <= 0 || components.length - named < 2) return const [];
  for (var i = named + 1; i < components.length; i++) {
    if (!_isNumeralComponent(components[i])) return const [];
  }
  final keys = <String>[];
  for (var omitted = 1; omitted <= named; omitted++) {
    final key = buildPartialRefKey(components.sublist(omitted).join(', '));
    if (key != null && !keys.contains(key)) keys.add(key);
  }
  return keys;
}

const List<int> _numeralValues = [
  1, 2, 3, 4, 5, 6, 7, 8, 9, // א–ט
  10, 0, 20, 30, 0, 40, 0, 50, 60, 70, 0, 80, 0, 90, // י–צ, 0 לאות סופית
  100, 200, 300, 400, // ק–ת
];

/// רכיב heRef שהוא מספר מיקום ("שט", "סימן ז", "ב.") ולא שם.
bool _isNumeralComponent(String component) {
  final tokens = refKeyTokens(component);
  return tokens.isNotEmpty && tokens.every(_isNumeralToken);
}

/// ספרות, או אותיות בסדר ערך לא-עולה. שם שנקרא כמספר ("נח") רק מאבד את
/// המפתח החלקי שלו.
bool _isNumeralToken(String token) {
  if (token.isEmpty) return true;
  if (_isAsciiDigit(token.codeUnitAt(0))) {
    for (var i = 1; i < token.length; i++) {
      if (!_isAsciiDigit(token.codeUnitAt(i))) return false;
    }
    return true;
  }
  if (token.length > 6) return false;
  var previous = 400;
  for (var i = 0; i < token.length; i++) {
    final index = token.codeUnitAt(i) - 0x05D0;
    if (index < 0 || index >= _numeralValues.length) return false;
    final value = _numeralValues[index];
    if (value == 0 || value > previous) return false;
    previous = value;
  }
  return true;
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

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
