/// כלים לטיפול בהערות שוליים inline שמקודדות בתוכן השורה כ-HTML:
///   <sup class="footnote-marker">marker</sup><i class="footnote">body</i>
///
/// בספרי המסד (סכמה 7) הגוף בטבלת `line_note` ([BookNotes]) ובשורה נשאר רק
/// ה-<sup>; כל פונקציה מאחדת את שני המקורות.
library;

import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

final RegExp _footnoteBodyRegExp = RegExp(
  r'<i\b[^>]*\bclass\s*=\s*"[^"]*\bfootnote\b[^"]*"[^>]*>(.*?)</i>',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _footnoteMarkerRegExp = RegExp(
  r'<sup\b[^>]*\bfootnote-marker\b[^>]*>.*?</sup>',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _footnoteBodyStartRegExp = RegExp(
  r'\s*<i\b[^>]*\bclass\s*=\s*"[^"]*\bfootnote\b',
  caseSensitive: false,
);

const String _supCloseTag = '</sup>';

/// סימוני ה-<sup> שגוף ההערה שלהם הוצא לטבלה — כל אחד בלי גוף צמוד אחריו.
/// לפי החוזה, ה-k-י מהם שייך להערה ה-k-ית שיש לה marker.
List<Match> _strippedMarkers(String html) => [
  for (final match in _footnoteMarkerRegExp.allMatches(html))
    if (_footnoteBodyStartRegExp.matchAsPrefix(html, match.end) == null) match,
];

/// הערות הטבלה של שורה, בסדר הקריאה.
List<BookNote> _dbNotesAt(BookNotes? dbNotes, int lineIndex) =>
    dbNotes == null || lineIndex < 0 ? const [] : dbNotes.notesAt(lineIndex);

String _previewAnchor(String marker, int lineIndex, int noteIndex) =>
    '<a class="book-note-marker" '
    'href="otzaria://book-note?line=$lineIndex&note=$noteIndex">'
    '$marker</a>';

/// הופך את סימוני ההערות המוטמעים לקישורי-ריחוף, בלי לשנות את הטקסט הגלוי.
/// [dbNotes] — הערות הטבלה; ה-href ממספר אותן אחרי הערות ה-inline של השורה.
String addInlineNotePreviewLinks(
  String html, {
  required int lineIndex,
  BookNotes? dbNotes,
}) {
  if (!html.contains('footnote')) return html;

  final replacements = <({int start, int end, String value})>[];
  var noteIndex = 0;
  for (final bodyMatch in _footnoteBodyRegExp.allMatches(html)) {
    final before = html.substring(0, bodyMatch.start);
    final closeIndex = before.lastIndexOf(_supCloseTag);
    if (closeIndex < 0 ||
        before.substring(closeIndex + _supCloseTag.length).trim().isNotEmpty) {
      noteIndex++;
      continue;
    }
    final openIndex = before.lastIndexOf('<sup', closeIndex);
    final contentStart = openIndex < 0 ? -1 : html.indexOf('>', openIndex) + 1;
    if (openIndex < 0 || contentStart <= openIndex) {
      noteIndex++;
      continue;
    }
    final marker = html.substring(contentStart, closeIndex);
    replacements.add((
      start: openIndex,
      end: closeIndex + _supCloseTag.length,
      value: _previewAnchor(marker, lineIndex, noteIndex),
    ));
    noteIndex++;
  }

  final lineNotes = _dbNotesAt(dbNotes, lineIndex);
  if (lineNotes.isNotEmpty) {
    final anchored = [
      for (var i = 0; i < lineNotes.length; i++)
        if (lineNotes[i].marker != null) i,
    ];
    final markers = _strippedMarkers(html);
    for (var k = 0; k < markers.length && k < anchored.length; k++) {
      final match = markers[k];
      final sup = match[0]!;
      final marker = sup.substring(
        sup.indexOf('>') + 1,
        sup.length - _supCloseTag.length,
      );
      replacements.add((
        start: match.start,
        end: match.end,
        value: _previewAnchor(marker, lineIndex, noteIndex + anchored[k]),
      ));
    }
    replacements.sort((a, b) => a.start.compareTo(b.start));
  }

  var result = html;
  for (final replacement in replacements.reversed) {
    result = result.replaceRange(
      replacement.start,
      replacement.end,
      replacement.value,
    );
  }
  return result;
}

/// מחזיר את תוכן ההערה שאליה מפנה [url] — מהשורה או מהטבלה ([dbNotes]).
String? inlineNoteFromPreviewUrl(
  List<String> content,
  String url, {
  BookNotes? dbNotes,
}) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'book-note') return null;
  final lineIndex = int.tryParse(uri!.queryParameters['line'] ?? '');
  final noteIndex = int.tryParse(uri.queryParameters['note'] ?? '');
  if (lineIndex == null || noteIndex == null || lineIndex < 0) return null;
  if (lineIndex >= content.length && _dbNotesAt(dbNotes, lineIndex).isEmpty) {
    return null;
  }
  final lineNotes = notesForLines(content, [lineIndex], dbNotes: dbNotes);
  if (noteIndex < 0 || noteIndex >= lineNotes.length) return null;
  return lineNotes[noteIndex];
}

/// מסיר את גוף ההערות (<i class="footnote">...</i>) משורה אחת.
/// משאיר את ה-<sup> במקומו כעוגן ויזואלי לאיפה הייתה ההערה.
String stripInlineNotes(String html) {
  if (!html.contains('footnote')) return html;
  return html.replaceAll(_footnoteBodyRegExp, '');
}

/// מסיר גם את אות ההפניה וגם את גוף ההערה — לחיפוש ולאינדוקס, שבהם תגי ה-HTML
/// נמחקים והשאריות היו נשארות כטקסט חשוף שמזהם את התוצאות.
String stripInlineNotesForSearch(String html) {
  if (!html.contains('footnote')) return html;
  return html
      .replaceAll(_footnoteMarkerRegExp, '')
      .replaceAll(_footnoteBodyRegExp, '');
}

/// בודק אם הספר מכיל לפחות שורה אחת עם הערה — בשורה או בטבלה ([dbNotes]).
bool hasInlineNotes(List<String> content, {BookNotes? dbNotes}) {
  if (dbNotes != null && !dbNotes.isEmpty) return true;
  for (final line in content) {
    if (line.contains('footnote') && _footnoteBodyRegExp.hasMatch(line)) {
      return true;
    }
  }
  return false;
}

/// ההערות של השורות [indexes]: ה-<sup> הצמוד (אם יש) ואחריו הגוף; הערות הטבלה
/// ([dbNotes]) באות אחרי הערות השורה.
List<String> notesForLines(
  List<String> content,
  Iterable<int> indexes, {
  BookNotes? dbNotes,
}) {
  final results = <String>[];
  for (final idx in indexes) {
    if (idx < 0) continue;
    if (idx < content.length && content[idx].contains('footnote')) {
      final line = content[idx];
      for (final iMatch in _footnoteBodyRegExp.allMatches(line)) {
        results.add(_inlineNoteHtml(line, iMatch));
      }
    }
    for (final note in _dbNotesAt(dbNotes, idx)) {
      results.add(
        BookNotes.toInlineHtml(
          note,
          body: bookNoteBodyWithDivineNames(dbNotes!, idx, note),
        ),
      );
    }
  }
  return results;
}

// lastIndexOf ולא regex עם $: אחרת נצמד רצף של <sup>-ים קודמים עם התוכן שביניהם.
String _inlineNoteHtml(String line, Match iMatch) {
  final body = iMatch.group(1) ?? '';
  final before = line.substring(0, iMatch.start);
  final closeIdx = before.lastIndexOf(_supCloseTag);
  if (closeIdx >= 0) {
    final tail = before.substring(closeIdx + _supCloseTag.length);
    if (tail.trim().isEmpty) {
      final openIdx = before.lastIndexOf('<sup', closeIdx);
      if (openIdx >= 0) {
        final supTag = before.substring(
          openIdx,
          closeIdx + _supCloseTag.length,
        );
        return '$supTag $body';
      }
    }
  }
  return body;
}

/// מחזיר לשורה את גופי ההערות מהטבלה, כל אחד באופסט `charPos` שלו (והערה בלי
/// מיקום — אחרי ה-<sup> שלה או בסוף). שורה שכבר יש בה גוף הערה לא משתנה.
/// [bodyOf] — גוף חלופי להערה, למשל עם סמני שמות הקודש.
String rehydrateInlineNotes(
  String line,
  List<BookNote> notes, {
  String Function(BookNote note)? bodyOf,
}) {
  if (notes.isEmpty || _footnoteBodyRegExp.hasMatch(line)) return line;
  final markers = _strippedMarkers(line);
  final inserts = <({int at, int order, String html})>[];
  var anchoredSeen = 0;
  for (var order = 0; order < notes.length; order++) {
    final note = notes[order];
    final int at;
    if (note.charPos >= 0) {
      at = _rawInsertionPoint(line, note.charPos);
    } else if (note.marker != null && anchoredSeen < markers.length) {
      at = markers[anchoredSeen].end;
    } else {
      at = line.length;
    }
    if (note.marker != null) anchoredSeen++;
    inserts.add((
      at: at,
      order: order,
      html: _footnoteHtml(bodyOf?.call(note) ?? note.body),
    ));
  }
  inserts.sort(
    (a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.order.compareTo(b.order),
  );
  final out = StringBuffer();
  var last = 0;
  for (final insert in inserts) {
    out
      ..write(line.substring(last, insert.at))
      ..write(insert.html);
    last = insert.at;
  }
  out.write(line.substring(last));
  return out.toString();
}

/// האינדקס הגולמי אחרי התו הגלוי ה-[visible] (ישות = תו אחד, כמו
/// `line.charCount`). תגי סגירה צמודים שייכים לתו שלפניהם, למשל `</sup>`.
int _rawInsertionPoint(String html, int visible) {
  var seen = 0;
  var i = 0;
  final len = html.length;
  while (i < len && seen < visible) {
    final unit = html.codeUnitAt(i);
    if (unit == 0x3C) {
      final close = html.indexOf('>', i);
      if (close < 0) return len;
      i = close + 1;
      continue;
    }
    if (unit == 0x26) {
      final end = html.indexOf(';', i + 1);
      i = end > 0 && end < i + 10 ? end + 1 : i + 1;
    } else {
      i++;
    }
    seen++;
  }
  if (seen < visible) return len;
  while (i < len && html.startsWith('</', i)) {
    final close = html.indexOf('>', i);
    if (close < 0) break;
    i = close + 1;
  }
  return i;
}

/// [rehydrateInlineNotes] על תוכן ספר שלם — שורה לכל `lineIndex`.
String rehydrateInlineNotesInText(String text, BookNotes notes) {
  if (notes.isEmpty) return text;
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    lines[i] = rehydrateInlineNotes(lines[i], notes.notesAt(i));
  }
  return lines.join('\n');
}

/// גוף ההערה [note] של שורה [lineIndex] עטוף בסמני שמות הקודש שבו — הרינדור
/// מחיל עליהם את צורת התצוגה, כמו בשורה עצמה.
String bookNoteBodyWithDivineNames(
  BookNotes notes,
  int lineIndex,
  BookNote note,
) {
  final spans = notes.bodyDivineNames(lineIndex, note.noteIndex);
  return spans.isEmpty ? note.body : wrapDivineNameSpans(note.body, spans);
}

/// שורה [lineIndex] השמורה עם שמות הקודש של השורה ושל גופי ההערות, וההערות
/// במקומן — למסלולי ההדפסה והייצוא. האופסטים נמדדים לפני כל שינוי גלוי.
String applyStoredLineData(
  String line,
  int lineIndex, {
  required DivineNameSpans names,
  required BookNotes notes,
  required bool substituteOtherNames,
  HolyNameStyle? holyNameStyle,
}) {
  final lineNotes = notes.notesAt(lineIndex);
  if (!substituteOtherNames && holyNameStyle == null) {
    return rehydrateInlineNotes(line, lineNotes);
  }
  final marked = rehydrateInlineNotes(
    injectDivineNameMarkers(line, names, lineIndex),
    lineNotes,
    bodyOf: (note) => bookNoteBodyWithDivineNames(notes, lineIndex, note),
  );
  if (identical(marked, line)) return line;
  return resolveDivineNameMarkers(
    marked,
    substituteOtherNames: substituteOtherNames,
    holyNameStyle: holyNameStyle,
  );
}

String _footnoteHtml(String body) => '<i class="footnote">$body</i>';
