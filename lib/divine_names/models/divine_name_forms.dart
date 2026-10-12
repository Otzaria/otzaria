import 'package:otzaria/divine_names/models/divine_name_spans.dart';

/// צורת התצוגה של שם: האות [letter] הראשונה מאות-השלד [fromLetter] ואילך
/// מוחלפת ב-[replacement], או — כש-[insertAfter] אינו null — נשארת, ואחריה
/// ואחרי סימני הניקוד שלה נוסף [insertAfter].
class DivineNameForm {
  const DivineNameForm.replace(
    this.letter, {
    this.fromLetter = 0,
    required String to,
  }) : replacement = to,
       insertAfter = null;

  const DivineNameForm.insertAfter(
    this.letter, {
    this.fromLetter = 0,
    required String text,
  }) : replacement = null,
       insertAfter = text;

  final String letter;
  final int fromLetter;
  final String? replacement;
  final String? insertAfter;
}

/// צורות התצוגה של השמות (חוץ משם הוי"ה, שצורתו לפי `HolyNameStyle`).
/// ממתין לאישור רבני — כל שינוי בצורות נעשה כאן בלבד.
const Map<int, DivineNameForm> kDivineNameForms = {
  DivineNameKind.elohim: DivineNameForm.replace('ה', fromLetter: 2, to: 'ק'),
  DivineNameKind.eloah: DivineNameForm.replace('ה', fromLetter: 2, to: 'ק'),
  DivineNameKind.el: DivineNameForm.replace('א', to: 'ק'),
  DivineNameKind.shaddai: DivineNameForm.replace('ד', to: 'ק'),
  DivineNameKind.tzevaot: DivineNameForm.replace('א', to: 'ק'),
  // מקף ASCII ולא מקף עברי: הסרת הטעמים הופכת מקף עברי לרווח.
  DivineNameKind.adnut: DivineNameForm.insertAfter('ד', text: '-'),
  DivineNameKind.ehyeh: DivineNameForm.replace('ה', to: 'ק'),
};

/// האם שלד האותיות [skeleton] (בלי ניקוד) תואם את סוג השם [kind]. הגנה מפני
/// אופסטים שזזו: מופע שאינו תואם אינו מוצג כשם.
bool divineNameSkeletonMatches(int kind, String skeleton) => switch (kind) {
  DivineNameKind.hvyh => skeleton == 'יהוה',
  DivineNameKind.adnut => skeleton == 'אדני',
  DivineNameKind.el => skeleton == 'אל' || skeleton == 'אלי',
  DivineNameKind.eloah => skeleton == 'אלוה' || skeleton == 'אלה',
  DivineNameKind.elohim =>
    skeleton.startsWith('אלה') || skeleton.startsWith('אלוה'),
  DivineNameKind.ehyeh => skeleton == 'אהיה',
  DivineNameKind.shaddai => skeleton == 'שדי',
  DivineNameKind.tzevaot => skeleton == 'צבאות',
  _ => false,
};

bool isHebrewLetter(int c) => c >= 0x05D0 && c <= 0x05EA;

/// סימן צירופי (ניקוד, טעם, CGJ) שנחשב חלק מהמילה. מקף, פסק, סוף-פסוק ונון
/// הפוכה הם סימני פיסוק — מופע שמכיל אותם אינו שם תקין.
bool isDivineNameMark(int c) {
  if (c >= 0x0300 && c <= 0x036F) return true;
  if (c < 0x0591 || c > 0x05C7) return false;
  return c != 0x05BE && c != 0x05C0 && c != 0x05C3 && c != 0x05C6;
}

/// שלד האותיות של [text] (אותיות וסימנים בלבד), או null כשיש בו תו אחר.
String? divineNameSkeleton(String text) {
  final letters = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (isHebrewLetter(c)) {
      letters.writeCharCode(c);
    } else if (!isDivineNameMark(c)) {
      return null;
    }
  }
  return letters.toString();
}

/// אותיות השימוש שמותר שיבואו לפני שם (ו ה ב כ ל מ ש), עד שלוש.
const String _prefixLetters = 'והבכלמש';
const int _maxPrefixLetters = 3;

/// האם המופע [start, end) ב-[html] עומד כמילה: אחריו אין אות עברית, ולפניו
/// עד שלוש אותיות שימוש ואז גבול מילה, כדי ש"אל" שבתוך "ישראל" לא יוצג כשם.
/// תגי עיצוב שקופים (`ל<b>אלהים</b>` תקין); sup, שבירה ובלוק הם גבול מילה.
bool divineNameHasWordBoundaries(String html, int start, int end) {
  var i = end;
  while (i < html.length) {
    final c = html.codeUnitAt(i);
    if (c == 0x3C) {
      final gt = html.indexOf('>', i);
      if (gt < 0 || _isBoundaryTag(html, i)) break;
      i = gt + 1;
    } else if (isDivineNameMark(c)) {
      i++;
    } else {
      if (isHebrewLetter(c)) return false;
      break;
    }
  }

  var prefixes = 0;
  i = start - 1;
  while (i >= 0) {
    final c = html.codeUnitAt(i);
    if (c == 0x3E) {
      final lt = html.lastIndexOf('<', i);
      if (lt < 0 || _isBoundaryTag(html, lt)) break;
      i = lt - 1;
    } else if (isDivineNameMark(c)) {
      i--;
    } else if (isHebrewLetter(c)) {
      if (!_prefixLetters.contains(html[i])) return false;
      if (++prefixes > _maxPrefixLetters) return false;
      i--;
    } else {
      break;
    }
  }
  return true;
}

const Set<String> _boundaryTags = {
  'sup', 'sub', 'br', 'hr', 'p', 'div', 'li', 'ul', 'ol', 'table', 'tr', //
  'td', 'th', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
};

/// האם התג שמתחיל ב-[lt] מפריד מילים (ולא רק מעצב אותן).
bool _isBoundaryTag(String html, int lt) {
  var i = lt + 1;
  if (i < html.length && html.codeUnitAt(i) == 0x2F) i++;
  final start = i;
  while (i < html.length) {
    final c = html.codeUnitAt(i) | 0x20;
    final isAlnum = (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39);
    if (!isAlnum) break;
    i++;
  }
  return _boundaryTags.contains(html.substring(start, i).toLowerCase());
}
