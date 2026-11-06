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
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

String _colorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

/// מזריק קישורי inline לפי start/end — על הטקסט השמור, לפני כל הזרקה אחרת.
String injectInlineLinks(String rawLine, List<Link> inlineLinks) {
  if (rawLine.isEmpty || inlineLinks.isEmpty) return rawLine;
  if (rawLine.contains('otzaria://inline-link')) return rawLine;

  final ranges = <HtmlWrapRange>[];
  for (final link in inlineLinks) {
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
  }
  return wrapHtmlRanges(rawLine, ranges);
}

/// בונה את ה-HTML של השורה עם סימוני ההערות — ההזרקה האחרונה.
///
/// [rawLine] - HTML השורה אחרי שאר ההזרקות (כולל [injectInlineLinks]).
/// [sourceLine] - שורת המקור שבה נמדד [PersonalNote.anchorStart].
/// [notesForLine] - ההערות השייכות לשורה זו.
/// [lineIndex0] - אינדקס השורה (0-based), מוטמע ב-URL לטיפול בלחיצה.
/// [underlineColor] - צבע הקו התחתון של ההערה (בד"כ primary של ה-theme).
String buildAnnotatedLineHtml({
  required String rawLine,
  String? sourceLine,
  required List<PersonalNote> notesForLine,
  required int lineIndex0,
  required Color underlineColor,
  bool replaceHolyNames = false,
}) {
  if (rawLine.isEmpty || notesForLine.isEmpty) return rawLine;
  // כבר סומנה; `note?` ולא `note` — כדי לא לתפוס את otzaria://note-marker.
  if (rawLine.contains('otzaria://note?')) return rawLine;

  // ההערה מדלגת על כל <a> קיים — למניעת <a> מקונן.
  final linkSpans = _anchorElementSpans(rawLine);
  final hex = _colorToHex(underlineColor);
  final boundaries = <({int offset, String id, bool opening})>[];

  void addNoteSpan(int start, int end, String id) {
    for (final gap in _subtractSpans(start, end, linkSpans)) {
      boundaries.add((offset: gap[0], id: id, opening: true));
      boundaries.add((offset: gap[1], id: id, opening: false));
    }
  }

  for (final note in notesForLine) {
    if (note.pdfAnchor != null) continue;
    if (note.isWordAnchored) {
      final range = locateAnchor(
        rawLine: rawLine,
        anchorText: note.anchorText!,
        prefix: note.anchorPrefix,
        suffix: note.anchorSuffix,
        hintStart: note.anchorStart,
        hintSourceLine: sourceLine,
      );
      if (range != null) {
        final expanded = replaceHolyNames
            ? _expandToHolyName(rawLine, range)
            : range;
        addNoteSpan(expanded.start, expanded.end, note.id);
        continue;
      }
      // לא נמצא הביטוי — נופלים לסימון כל השורה.
    }
    // הערת-שורה-שלמה (או נפילה מאיתור כושל): סימון כל השורה.
    addNoteSpan(0, rawLine.length, note.id);
  }

  boundaries.sort((a, b) {
    final offsetOrder = a.offset.compareTo(b.offset);
    if (offsetOrder != 0) return offsetOrder;
    return (a.opening ? 1 : 0).compareTo(b.opening ? 1 : 0);
  });
  final ranges = <HtmlWrapRange>[];
  final activeIds = <String>{};
  var cursor = 0;
  for (final boundary in boundaries) {
    if (cursor < boundary.offset && activeIds.isNotEmpty) {
      final ids = activeIds
          .map((id) => '&id=${Uri.encodeComponent(id)}')
          .join();
      ranges.add(
        HtmlWrapRange(
          start: cursor,
          end: boundary.offset,
          // currentcolor שומר את צבע הטקסט; inherit אינו נתמך ברינדור ה-HTML.
          openTag:
              '<a href="otzaria://note?line=$lineIndex0$ids" '
              'style="text-decoration: underline; text-decoration-style: dotted; '
              'text-decoration-color: $hex; color: currentcolor;">',
          closeTag: '</a>',
        ),
      );
    }
    if (boundary.opening) {
      activeIds.add(boundary.id);
    } else {
      activeIds.remove(boundary.id);
    }
    cursor = boundary.offset;
  }
  return wrapHtmlRanges(rawLine, ranges);
}

/// מחזיר רק הערות של העוגן; קישור ישן בלי מזהים ממשיך להציג את הערות השורה.
List<PersonalNote> personalNotesForPreview(
  String url,
  Iterable<PersonalNote> notes,
) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'otzaria' || uri.host != 'note') return [];
  final line = int.tryParse(uri.queryParameters['line'] ?? '');
  if (line == null || line < 0) return [];
  final ids = uri.queryParametersAll['id']?.toSet();
  return notes
      .where(
        (note) =>
            note.pdfAnchor == null &&
            note.lineNumber == line + 1 &&
            (ids == null || ids.contains(note.id)),
      )
      .toList();
}

NoteAnchorRange _expandToHolyName(String rawLine, NoteAnchorRange range) {
  var start = range.start;
  var end = range.end;
  for (final name in text_utils.findReplaceableHolyNames(rawLine)) {
    if (name.start < end && name.end > start) {
      if (name.start < start) start = name.start;
      if (name.end > end) end = name.end;
    }
  }
  return NoteAnchorRange(start, end);
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

final RegExp _anchorTagRegExp = RegExp(r'<(/?)a\b[^>]*>', caseSensitive: false);

/// טווחי [start, end) של רכיבי `<a>…</a>` החיצוניים ב-[html], ממוינים.
List<List<int>> _anchorElementSpans(String html) {
  final spans = <List<int>>[];
  var depth = 0;
  var openStart = 0;
  for (final match in _anchorTagRegExp.allMatches(html)) {
    if (match.group(1)!.isEmpty) {
      if (depth == 0) openStart = match.start;
      depth++;
    } else if (depth > 0) {
      depth--;
      if (depth == 0) spans.add([openStart, match.end]);
    }
  }
  if (depth > 0) spans.add([openStart, html.length]);
  return spans;
}
