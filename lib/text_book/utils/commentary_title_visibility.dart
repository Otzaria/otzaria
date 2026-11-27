import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';

/// הכרעה האם כותרת המקור של מקטע בלשונית הפרשנים מוסיפה מידע (issue #896).
/// הכותרת מוסתרת רק כשהיא חוזרת על מה שהמשתמש כבר יודע: כל מקטעי הקבוצה
/// באים מאותה שורת מקור, ויעד המקטע נמצא במקום שהוא קורא כעת.

/// האם כל קישורי הקבוצה שייכים לאותה שורת מקור. כשלא — הכותרות הן המבדיל
/// היחיד בין המקטעים (בחירה מרובה, "כל הפרק") וחובה להציגן.
bool groupSharesSingleSource(List<Link> links) {
  if (links.isEmpty) return false;
  final first = links.first.index1;
  return links.every((link) => link.index1 == first);
}

/// האם כותרת המקטע [displayTitle] מצביעה בדיוק על המקום הנקרא כעת:
/// שם ספר היעד [targetBookTitle] ואחריו כתובת זהה לכתובת שורת המקור
/// [sourceRef] בספר [sourceBookTitle]. כל אי-ודאות מוכרעת כ"לא תואם"
/// (הכותרת תוצג) — הסתרה שגויה מאבדת מידע, הצגה מיותרת לא.
bool commentaryTitleMatchesReadingLocation({
  required String displayTitle,
  required String targetBookTitle,
  required String sourceBookTitle,
  required String sourceRef,
}) {
  final titleTokens = referenceTokens(displayTitle);
  final targetTitleTokens = referenceTokens(targetBookTitle);
  if (targetTitleTokens.isEmpty ||
      !_isTokenPrefix(targetTitleTokens, titleTokens)) {
    return false;
  }
  final targetLocation = titleTokens.sublist(targetTitleTokens.length);

  var sourceTokens = referenceTokens(sourceRef);
  final sourceTitleTokens = referenceTokens(sourceBookTitle);
  if (_isTokenPrefix(sourceTitleTokens, sourceTokens)) {
    sourceTokens = sourceTokens.sublist(sourceTitleTokens.length);
  }

  return targetLocation.isNotEmpty && listEquals(targetLocation, sourceTokens);
}

/// כותרת המקטע [displayTitle] בלי שם הספר שכבר מופיע בכותרת הקבוצה
/// [groupBookTitle] (issue #3599): "רש"י על שופטים ו, ה" -> "ו, ה".
/// כשהכותרת אינה מתחילה בשם הספר, או שאחריו אין כתובת (שם הספר בלבד,
/// סיומת טווח "– ...") — מוחזרת הכותרת המלאה.
String commentaryTitleWithoutBook({
  required String displayTitle,
  required String groupBookTitle,
}) {
  final bookTokens = referenceTokens(groupBookTitle);
  final titleTokens = referenceTokens(displayTitle);
  if (bookTokens.length >= titleTokens.length ||
      !_isTokenPrefix(bookTokens, titleTokens)) {
    return displayTitle;
  }
  // חותכים במחרוזת המקורית, בגבול המילה הראשון שבו נגמר שם הספר.
  for (var i = 1; i < displayTitle.length; i++) {
    final c = displayTitle[i];
    if (c != ' ' && c != ',') continue;
    if (!listEquals(
      referenceTokens(displayTitle.substring(0, i)),
      bookTokens,
    )) {
      continue;
    }
    final location = displayTitle.substring(i).replaceFirst(_leadingGap, '');
    final startsWithWord =
        location.isNotEmpty &&
        listEquals(
          referenceTokens(location[0]),
          [location[0]],
        );
    return startsWithWord ? location : displayTitle;
  }
  return displayTitle;
}

final RegExp _leadingGap = RegExp(r'^[\s,]+');

final RegExp _nonspacingMarks = RegExp(r'\p{Mn}', unicode: true);

/// מפרק כתובת למילות השוואה: בלי ניקוד/טעמים, גרשיים ופיסוק מפריד.
/// נשמרות גם מילים בנות אות אחת — כתובות דף ("ג ב") בנויות מהן.
@visibleForTesting
List<String> referenceTokens(String reference) {
  // נקרא בכל בניית מקטע בלשונית הפרשנים, ולכן מעבר יחיד ולא שרשרת RegExp-ים.
  final text = _mayContainNonspacingMarks(reference)
      ? reference.replaceAll(_nonspacingMarks, '')
      : reference;
  final tokens = <String>[];
  final word = StringBuffer();
  void endWord() {
    if (word.isEmpty) return;
    tokens.add(word.toString());
    word.clear();
  }

  for (var i = 0; i < text.length; i++) {
    switch (text.codeUnitAt(i)) {
      // גרשיים נמחקים, והמילה שסביבם נשארת אחת.
      case 0x22 || 0x27 || 0x60 || 0x05F3 || 0x05F4 || 0x2019 || 0x201C:
      case 0x201D:
        break;
      // -–־,.(): ו-\s של RegExp מפרידים בין מילים.
      case 0x28 || 0x29 || 0x2C || 0x2D || 0x2E || 0x3A || 0x05BE || 0x2013:
      case 0x09 || 0x0A || 0x0B || 0x0C || 0x0D || 0x20 || 0xA0 || 0x1680:
      case 0x2028 || 0x2029 || 0x202F || 0x205F || 0x3000 || 0xFEFF:
      case >= 0x2000 && <= 0x200A:
        endWord();
      case final c:
        word.writeCharCode(c);
    }
  }
  endWord();
  return tokens;
}

/// סימני Mn מתחילים ב-U+0300, ואין כאלה באותיות העבריות ובפיסוק הכללי.
bool _mayContainNonspacingMarks(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0x300 &&
        !(c >= 0x5D0 && c <= 0x5FF) &&
        !(c >= 0x2000 && c <= 0x206F)) {
      return true;
    }
  }
  return false;
}

bool _isTokenPrefix(List<String> prefix, List<String> tokens) {
  if (prefix.isEmpty || prefix.length > tokens.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (prefix[i] != tokens[i]) return false;
  }
  return true;
}
