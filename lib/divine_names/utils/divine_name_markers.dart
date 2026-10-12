import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

/// תחילת תג הסמן שעוטף מופע שם בשורה, עד ערך הסוג.
const String kDivineNameMarkerPrefix = '<span class="divine-name" data-k="';

/// תג הפתיחה של סמן לשם מסוג [kind].
String divineNameMarkerOpen(int kind) => '$kDivineNameMarkerPrefix$kind">';

/// מסיר את סמני השמות מ-[html] ומחיל עליהם את צורת התצוגה. רץ אחרי הדגשת
/// החיפוש, ולכן מדלג על תגי ההדגשה שבתוך הסמן.
///
/// [substituteOtherNames] — השמות שאינם שם הוי"ה מוצגים לפי [kDivineNameForms].
/// [holyNameStyle] — שם הוי"ה מוחלף בסגנון זה; null משאיר אותו ככתבו.
String resolveDivineNameMarkers(
  String html, {
  required bool substituteOtherNames,
  HolyNameStyle? holyNameStyle,
}) {
  var open = html.indexOf(kDivineNameMarkerPrefix);
  if (open < 0) return html;
  final out = StringBuffer();
  var copied = 0;
  while (open >= 0) {
    final kindStart = open + kDivineNameMarkerPrefix.length;
    final kindEnd = html.indexOf('"', kindStart);
    final tagEnd = kindEnd < 0 ? -1 : html.indexOf('>', kindEnd);
    final close = tagEnd < 0 ? -1 : _matchingSpanClose(html, tagEnd + 1);
    if (close < 0) break;
    final kind = int.tryParse(html.substring(kindStart, kindEnd)) ?? 0;
    final inner = html.substring(tagEnd + 1, close);
    final markerEnd = close + _spanClose.length;
    out
      ..write(html.substring(copied, open))
      ..write(
        divineNameHasWordBoundaries(html, open, markerEnd)
            ? _applyForm(
                inner,
                kind,
                substituteOtherNames: substituteOtherNames,
                holyNameStyle: holyNameStyle,
              )
            : inner,
      );
    copied = markerEnd;
    open = html.indexOf(kDivineNameMarkerPrefix, copied);
  }
  return (out..write(html.substring(copied))).toString();
}

const String _spanClose = '</span>';

/// אינדקס ה-`</span>` שסוגר span שתוכנו מתחיל ב-[from], או -1.
int _matchingSpanClose(String html, int from) {
  var depth = 1;
  var i = html.indexOf('<', from);
  while (i >= 0) {
    if (html.startsWith(_spanClose, i)) {
      if (--depth == 0) return i;
    } else if (html.startsWith('<span', i) &&
        i + 5 < html.length &&
        (html.codeUnitAt(i + 5) == 0x20 || html.codeUnitAt(i + 5) == 0x3E)) {
      depth++;
    }
    final gt = html.indexOf('>', i);
    if (gt < 0) return -1;
    i = html.indexOf('<', gt + 1);
  }
  return -1;
}

String _applyForm(
  String inner,
  int kind, {
  required bool substituteOtherNames,
  required HolyNameStyle? holyNameStyle,
}) {
  final isHvyh = kind == DivineNameKind.hvyh;
  if (isHvyh ? holyNameStyle == null : !substituteOtherNames) return inner;

  final letters = <int>[];
  var i = 0;
  while (i < inner.length) {
    final c = inner.codeUnitAt(i);
    if (c == 0x3C) {
      final gt = inner.indexOf('>', i);
      if (gt < 0) return inner;
      i = gt + 1;
      continue;
    }
    if (isHebrewLetter(c)) {
      letters.add(i);
    } else if (!isDivineNameMark(c)) {
      return inner;
    }
    i++;
  }
  final skeleton = String.fromCharCodes([
    for (final at in letters) inner.codeUnitAt(at),
  ]);
  // סמן שנחתך או תוכן שהשתנה — מוצג ככתבו.
  if (!divineNameSkeletonMatches(kind, skeleton)) return inner;

  if (isHvyh) {
    return holyNameStyle == HolyNameStyle.hehApostrophe
        ? _hehApostrophe(inner, letters.first)
        : _replaceAt(_replaceAt(inner, letters[3], 'ק'), letters[1], 'ק');
  }

  final form = kDivineNameForms[kind];
  if (form == null) return inner;
  final target = form.letter.codeUnitAt(0);
  for (var k = form.fromLetter; k < letters.length; k++) {
    final at = letters[k];
    if (inner.codeUnitAt(at) != target) continue;
    final insert = form.insertAfter;
    if (insert == null) return _replaceAt(inner, at, form.replacement!);
    var end = at + 1;
    while (end < inner.length && isDivineNameMark(inner.codeUnitAt(end))) {
      end++;
    }
    return inner.replaceRange(end, end, insert);
  }
  return inner;
}

String _replaceAt(String text, int at, String replacement) =>
    text.replaceRange(at, at + 1, replacement);

/// "ה'" במקום השם, בלי הניקוד והטעמים שלו — כמו `replaceHolyNames`.
String _hehApostrophe(String inner, int firstLetter) {
  final out = StringBuffer();
  var i = 0;
  while (i < inner.length) {
    final c = inner.codeUnitAt(i);
    if (c == 0x3C) {
      final gt = inner.indexOf('>', i);
      out.write(inner.substring(i, gt + 1));
      i = gt + 1;
      continue;
    }
    if (i == firstLetter) out.write("ה'");
    i++;
  }
  return out.toString();
}
