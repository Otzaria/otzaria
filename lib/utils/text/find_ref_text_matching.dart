import 'dart:typed_data';

String normalizeForFindRefMatch(String input) {
  // שלב 1: כמו removeVolwels — מקף, פסק ו-| לרווח; ניקוד וטעמים נמחקים.
  final units = Uint16List(input.length);
  var n = 0;
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x05BE || c == 0x05C0 || c == 0x7C) {
      units[n++] = 0x20;
    } else if (c < 0x0591 || c > 0x05C7) {
      units[n++] = c;
    }
  }

  // שלב 2: ציון עמוד, מחיקת גרשיים, החלפת תווים אסורים ואיחוד רווחים.
  final out = Uint16List(n + (n >> 1) + 1);
  var m = 0;
  var pendingSpace = false;
  void emit(int c) {
    if (_isFindRefQuote(c)) return;
    if (c >= 0x41 && c <= 0x5A) {
      c += 0x20;
    } else if (!((c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x0590 && c <= 0x05FF))) {
      pendingSpace = true;
      return;
    }
    if (pendingSpace) {
      if (m > 0) out[m++] = 0x20;
      pendingSpace = false;
    }
    out[m++] = c;
  }

  var i = 0;
  while (i < n) {
    final c = units[i];
    if (!_isHebrewLetter(c)) {
      emit(c);
      i++;
      continue;
    }
    // תמיד תחילת רצף אותיות: אות שקודמת לה אות כבר נצרכה בתוך הרצף.
    var end = i + 1;
    while (end < n && _isHebrewLetter(units[end])) {
      end++;
    }
    for (var k = i; k < end; k++) {
      emit(units[k]);
    }
    if (end - i <= 3 &&
        end < n &&
        (units[end] == 0x2E || units[end] == 0x3A) &&
        (end + 1 == n || _isRegExpWhitespace(units[end + 1])) &&
        (i == 0 || !_isFindRefQuote(units[i - 1]))) {
      pendingSpace = true;
      emit(units[end] == 0x2E ? 0x05D0 : 0x05D1);
      end++;
    }
    i = end;
  }
  return String.fromCharCodes(out, 0, m);
}

bool _isHebrewLetter(int c) => c >= 0x05D0 && c <= 0x05EA;

bool _isFindRefQuote(int c) =>
    c == 0x22 || c == 0x27 || c == 0x05F3 || c == 0x05F4;

/// התווים ש-`\s` תופס ב-RegExp של Dart (תקן JS), לא ה-White_Space של trim.
bool _isRegExpWhitespace(int c) {
  if (c <= 0x20) return c == 0x20 || (c >= 0x09 && c <= 0x0D);
  if (c < 0xA0) return false;
  return c == 0xA0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000 ||
      c == 0xFEFF;
}

/// מחזיר את [titleToken] בלי אות-חיבור פותחת שהמשתמש עשוי לא להקליד —
/// ה' הידיעה ("הטור" → "טור") או ו' החיבור ("וברכת" → "ברכת") — או null
/// אם אין כזו.
///
/// הדרישה לאורך >= 3 מותירה שארית באורך >= 2, כדי שטוקן מיקום של אות בודדת
/// ("עמוד א") לא ייבלע. [allowVav] כבוי בטוקן הפותח את הכותרת: שם ו' היא
/// חלק מהשם ("ויקרא", "וזה לשונו", "וביום השבת") ולא אות חיבור.
String? titleTokenWithoutConjunction(
  String titleToken, {
  required bool allowVav,
}) {
  if (titleToken.length < 3) return null;
  final first = titleToken[0];
  if (first == 'ה' || (allowVav && first == 'ו')) {
    return titleToken.substring(1);
  }
  return null;
}

/// טוקני [normalizedTitle] בתוספת הגרסאות בלי אות-חיבור פותחת — לשאלה "האם
/// המילה הזו היא מילה מכותרת הספר". ראו [titleTokenWithoutConjunction].
Set<String> titleMatchTokens(String normalizedTitle) =>
    titleMatchTokensOf(normalizedTitle.split(' '));

/// [titleMatchTokens] לכותרת שכבר פוצלה לטוקנים.
Set<String> titleMatchTokensOf(List<String> tokens) {
  final result = <String>{...tokens};
  for (var i = 0; i < tokens.length; i++) {
    final bare = titleTokenWithoutConjunction(tokens[i], allowVav: i > 0);
    if (bare != null) result.add(bare);
  }
  return result;
}

/// ציטוט דף מנותח: מספר הדף ועמוד אופציונלי ("א"/"ב").
typedef DafCitation = ({String number, String? amud});

/// בשו"ת היחידה שמצוטטת "סימן" נקראת בתוכן העניינים לעתים "שאלה"/"תשובה".
const List<String> responsaUnitWords = ['שאלה', 'תשובה'];

/// שמות שונים לאותה רמה ממוספרת ("כלל לה" מול "שער לה", ס"ק מול "סעיף").
/// "פרק", "משנה" ו"סימן" אינם כאן: בספרים רבים יש תחתם רמה ממוספרת נוספת.
const List<Set<String>> _structureWordGroups = [
  {'שער', 'כלל', 'מאמר'},
  {'סעיף', 'סק'},
  {'הלכה', 'דין', 'אות', 'פסקה'},
];

bool _isSiman(String token) => token == 'סימן' || token == 'סי';

/// מילת מבנה שיש לה שם חלופי בתוכן העניינים — ראו [matchesOtherStructureWord].
bool isStructureWord(String token) =>
    _isSiman(token) || _structureWordGroups.any((g) => g.contains(token));

/// האם כותרת הערך [ownTokens] נקראת בשם חלופי של מילת המבנה [token].
/// ל"סימן" החלופות הן [responsaUnitWords].
bool matchesOtherStructureWord(String token, List<String> ownTokens) {
  if (_isSiman(token)) return responsaUnitWords.any(ownTokens.contains);
  for (final group in _structureWordGroups) {
    if (group.contains(token)) {
      return ownTokens.any((t) => t != token && group.contains(t));
    }
  }
  return false;
}

/// מחזיר טוקן + גרסת טרנספוזיציה לאותיות עבריות דו-תווניות.
/// לדוגמה: "טל" → ["טל", "לט"] (שתי שיטות מניין עבריות ל-39).
List<String> hebrewTokenAlternatives(String token) {
  if (token == 'סי') return const ['סי', 'סימן'];
  // "סק" הפוך הוא "קס" (160) — מילת מבנה אינה מספר.
  if (isStructureWord(token)) return [token];
  if (token.length == 2) {
    final c0 = token.codeUnitAt(0);
    final c1 = token.codeUnitAt(1);
    // אותיות עבריות U+05D0–U+05EA
    if (c0 >= 0x05D0 &&
        c0 <= 0x05EA &&
        c1 >= 0x05D0 &&
        c1 <= 0x05EA &&
        c0 != c1) {
      return [token, '${token[1]}${token[0]}'];
    }
  }
  return [token];
}

/// האם [token] הוא ראשי-תיבות של [words] — כל מילה תורמת תחילית רצופה
/// והצירוף שווה בדיוק לטוקן ("יוד" ← "יורה דעה", "אהע" ← "אבן העזר").
/// הסף (3 תווים, שתי מילים לפחות) מונע מטוקן-מיקום קצר להיתפס ככותרת.
bool hebrewAbbreviationMatchesWords(String token, List<String> words) {
  if (token.length < 3 || words.length < 2) return false;

  bool walk(int wordIndex, int pos) {
    if (wordIndex == words.length) return pos == token.length;
    final word = words[wordIndex];
    final remaining = token.length - pos;
    if (remaining <= 0) return false;
    final maxLen = word.length < remaining ? word.length : remaining;
    for (var len = 1; len <= maxLen; len++) {
      if (word.codeUnitAt(len - 1) != token.codeUnitAt(pos + len - 1)) break;
      if (walk(wordIndex + 1, pos + len)) return true;
    }
    return false;
  }

  return walk(0, 0);
}

/// מנתח טוקני-מיקום כציטוט דף בפורמט "מספר ואחריו עמוד אופציונלי" (אחרי הפשטת
/// "דף"/"עמוד"). מחזיר null אם אינו ציטוט דף נקי — אז המתקשר משתמש בהתאמה
/// הרגילה. הבחנה זו מונעת ש-"ב" בודד (מספר דף) ייתפס ע"י סימון צד ע"ב
/// (הנקודתיים שבנרמול הופכות ל-"ב") של כל דף במסכת.
DafCitation? parseDafCitation(List<String> tokens) {
  final loc = tokens
      .where((t) => t != 'דף' && t != 'עמוד')
      .toList(growable: false);
  if (loc.isEmpty) return null;

  // מספר דף: 1–3 אותיות עבריות בלבד (כדי לא לתפוס מילות-הקשר כמו "ראשון").
  final number = loc.first;
  if (number.isEmpty ||
      number.length > 3 ||
      !number.codeUnits.every((c) => c >= 0x05D0 && c <= 0x05EA)) {
    return null;
  }

  String? amud;
  if (loc.length >= 2) {
    if (loc[1] == 'א' || loc[1] == 'ב') {
      amud = loc[1];
    } else {
      return null; // טוקן מיקום שני שאינו עמוד — אינו ציטוט דף פשוט
    }
  }
  if (loc.length > (amud != null ? 2 : 1)) return null;
  return (number: number, amud: amud);
}

/// ציטוט דף מהטוקן "דף" ואילך, גם כששם קודם לו ("מאימתי דף ב"), או null.
DafCitation? parseDafCitationFromDafToken(List<String> tokens) {
  final dafAt = tokens.indexOf('דף');
  return dafAt < 0 ? null : parseDafCitation(tokens.sublist(dafAt));
}

/// התאמה מיקומית של טוקני ערך בפורמט "דף מספר עמוד" לציטוט דף [cite].
/// מחזיר null אם הערך אינו בפורמט "דף ..." (אז המתקשר משתמש בהתאמה הרגילה),
/// אחרת bool האם המספר (וגם העמוד, אם צוין בשאילתה) תואמים.
///
/// [implicitDaf] מקבל גם כותרת בלי "דף" — "ב." או "תלמוד ב." — ומיועד רק
/// לשאילתה עם "דף" בספר שבנוי מדפים; אחרת "ב." הוא סעיף ממוספר.
bool? matchDafCitation(
  List<String> ownTokens,
  DafCitation cite, {
  bool implicitDaf = false,
}) {
  var heading = ownTokens;
  if (implicitDaf && _isBareDafHeading(heading)) {
    heading = ['דף', ...heading.sublist(heading.length - 2)];
  }
  if (heading.length < 2 || heading.first != 'דף') return null;
  if (!hebrewTokenAlternatives(cite.number).contains(heading[1])) {
    return false;
  }
  if (cite.amud != null) {
    // "דף מג עמוד א": העמוד אחרי המילה "עמוד".
    final amudAt = heading.length > 3 && heading[2] == 'עמוד' ? 3 : 2;
    final entryAmud = heading.length > amudAt
        ? _amudToken(heading[amudAt])
        : null;
    if (cite.amud != entryAmud) return false;
  }
  return true;
}

/// עמוד כטוקן מנורמל: "א"/"ב" (מ-"."/":" או "עמוד א") או "עא"/"עב" (ע"א/ע"ב).
String? _amudToken(String token) => switch (token) {
  'א' || 'עא' => 'א',
  'ב' || 'עב' => 'ב',
  _ => null,
};

/// "ב." / "תלמוד ב." אחרי נרמול: מספר דף ועמוד, בלי "דף".
bool _isBareDafHeading(List<String> tokens) {
  final start = tokens.length == 3 && tokens.first == 'תלמוד' ? 1 : 0;
  if (tokens.length - start != 2) return false;
  final number = tokens[start];
  return number.length <= 3 &&
      number.codeUnits.every((c) => c >= 0x05D0 && c <= 0x05EA) &&
      (tokens[start + 1] == 'א' || tokens[start + 1] == 'ב');
}

/// האם כותרת ה"דף" הקרובה בנתיב (הערך עצמו או האב הקרוב) תואמת ל-[cite].
/// "ב" של "דף יב" או של תת-כותרת תחתיו אינו דף ב.
bool nearestDafInPathMatches(List<String> pathTokens, DafCitation cite) {
  final dafAt = pathTokens.lastIndexOf('דף');
  return dafAt >= 0 &&
      matchDafCitation(pathTokens.sublist(dafAt), cite) == true;
}

/// בודק אם כותרת TOC תואמת להפניה חופשית של תוסף (למשל "ס\"ד ע\"ב" ↔ "דף סד:").
/// תחילה התאמה גולמית, ואז התאמת טוקנים מנורמלים — כדי לגשר על פערי
/// גרשיים, "דף"/"עמוד", וסימון העמוד ("ע\"א/ע\"ב" מול ".":/":") שבין התוסף ל-TOC.
bool tocTextMatchesRef(String tocText, String ref) {
  if (ref.isEmpty) return false;
  if (tocText.contains(ref)) return true;
  final refTokens = _refMatchTokens(ref);
  if (refTokens.isEmpty) return false;
  final tocTokens = _refMatchTokens(tocText);
  // תת-רצף מסודר — הסדר מבדיל בין מספר הדף לציון העמוד,
  // כך ש"ב ע\"א" (ב,א) לא יתאים ל"דף א:" (א,ב).
  var ti = 0;
  for (final token in refTokens) {
    while (ti < tocTokens.length && tocTokens[ti] != token) {
      ti++;
    }
    if (ti == tocTokens.length) return false;
    ti++;
  }
  return true;
}

List<String> _refMatchTokens(String s) => normalizeForFindRefMatch(s)
    .split(' ')
    .map((t) => t == 'עא' ? 'א' : (t == 'עב' ? 'ב' : t))
    .where((t) => t.isNotEmpty && t != 'דף' && t != 'עמוד')
    .toList();
