/// בניית HTML של שורה עם סימון הערות אישיות inline (וקישורי inline קיימים).
///
/// הערה המעוגנת למילים ([PersonalNote.isWordAnchored]) מסומנת בקו תחתון מקווקו
/// סביב הביטוי; הערת-שורה-שלמה מסמנת את כל השורה. הסימון הוא `<a>` עם סכמת
/// `otzaria://note?line=...` ש-[SmartTextWidget] מטפל בה בלחיצה.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show isHeadingLine;

String _colorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

/// בונה את ה-HTML של השורה עם סימוני ההערות (וקישורי inline אם סופקו).
///
/// [rawLine] - טקסט השורה הגולמי (HTML+ניקוד).
/// [notesForLine] - ההערות השייכות לשורה זו.
/// [lineIndex0] - אינדקס השורה (0-based), מוטמע ב-URL לטיפול בלחיצה.
/// [inlineLinks] - קישורי inline (עם start/end) להזרקה יחד עם הסימונים.
/// [underlineColor] - צבע הקו התחתון של ההערה (בד"כ primary של ה-theme).
String buildAnnotatedLineHtml({
  required String rawLine,
  required List<PersonalNote> notesForLine,
  required int lineIndex0,
  required Color underlineColor,
  List<Link> inlineLinks = const [],
}) {
  if (rawLine.isEmpty) return rawLine;
  // אם כבר עברה עיבוד (מכילה את הסכמות שלנו) — מחזירים כמות שהיא.
  if (rawLine.contains('otzaria://note') ||
      rawLine.contains('otzaria://inline-link')) {
    return rawLine;
  }

  final ranges = <HtmlWrapRange>[];

  // 1) קישורי inline (אם יש) — נשמרים כפי שהיו ב-addInlineLinksToText.
  // כותרות משמשות לניווט, לכן קישורי Linker לא מוזרקים לתוכן שלהן.
  // נאסוף גם את טווחיהם כדי שסימוני ההערות לא יבלעו אותם.
  final linkSpans = <List<int>>[];
  final linksToRender = isHeadingLine(rawLine) ? const <Link>[] : inlineLinks;
  for (final link in linksToRender) {
    final start = link.start;
    final end = link.end;
    if (start == null || end == null) continue;
    if (start < 0 || end > rawLine.length || start >= end) continue;
    final url =
        'otzaria://inline-link?path=${Uri.encodeComponent(link.path2)}&index=${link.index2}&ref=${Uri.encodeComponent(link.heRef)}';
    ranges.add(
      HtmlWrapRange(
        start: start,
        end: end,
        openTag: '<a href="$url" style="text-decoration: underline;">',
        closeTag: '</a>',
      ),
    );
    linkSpans.add([start, end]);
  }
  linkSpans.sort((a, b) => a[0].compareTo(b[0]));

  // 2) סימוני הערות. טווח כל הערה מחוסר מטווחי הקישורים, כך שקישור inline
  // נשאר שלם וההדגשה ממלאת רק את המרווחים שסביבו.
  final hex = _colorToHex(underlineColor);
  // color: currentcolor (ולא inherit) — flutter_widget_from_html לא מפרש
  // inherit, וההצהרה הייתה נזרקת כך שטקסט ההערה נצבע בצבע ה-primary של
  // קישורים (ברירת המחדל של תגית <a>). currentcolor כן נתמך ומשאיר את
  // צבע הטקסט הרגיל — וכך הערה (קו מקווקו, צבע רגיל) נבדלת מקישור
  // (קו מלא, צבע primary).
  final openTag =
      '<a href="otzaria://note?line=$lineIndex0" '
      'style="text-decoration: underline; text-decoration-style: dotted; '
      'text-decoration-color: $hex; color: currentcolor;">';

  void addNoteSpan(int start, int end) {
    for (final gap in _subtractSpans(start, end, linkSpans)) {
      ranges.add(
        HtmlWrapRange(
          start: gap[0],
          end: gap[1],
          openTag: openTag,
          closeTag: '</a>',
        ),
      );
    }
  }

  for (final note in notesForLine) {
    if (note.isWordAnchored) {
      final range = locateAnchor(
        rawLine: rawLine,
        anchorText: note.anchorText!,
        prefix: note.anchorPrefix,
        suffix: note.anchorSuffix,
        hintStart: note.anchorStart,
      );
      if (range != null) {
        addNoteSpan(range.start, range.end);
        continue;
      }
      // לא נמצא הביטוי — נופלים לסימון כל השורה.
    }
    // הערת-שורה-שלמה (או נפילה מאיתור כושל): סימון כל השורה.
    addNoteSpan(0, rawLine.length);
  }

  return wrapHtmlRanges(rawLine, ranges);
}

/// מחזיר את המקטעים של [start, end) שאינם חופפים לאף אחד מ-[spans]
/// (רשימה ממוינת של [start, end] שאינם חופפים זה לזה).
List<List<int>> _subtractSpans(int start, int end, List<List<int>> spans) {
  final gaps = <List<int>>[];
  int cursor = start;
  for (final span in spans) {
    final s = span[0];
    final e = span[1];
    if (e <= cursor || s >= end) continue; // אין חפיפה עם מה שנותר.
    if (s > cursor) gaps.add([cursor, s]);
    if (e > cursor) cursor = e;
    if (cursor >= end) break;
  }
  if (cursor < end) gaps.add([cursor, end]);
  return gaps;
}
