/// כלים לטיפול בהערות שוליים inline שמקודדות בתוכן השורה כ-HTML:
///   <sup class="footnote-marker">marker</sup><i class="footnote">body</i>
///
/// בספרי המסד (סכמה 7) הגוף בטבלת `line_note` ([BookNotes]) ובשורה נשאר רק
/// ה-<sup>; כל פונקציה מאחדת את שני המקורות.
library;

import 'package:otzaria/text_book/models/book_notes.dart';

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
      results.add(BookNotes.toInlineHtml(note));
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

/// מחזיר לשורה את גופי ההערות מהטבלה: הערה עם marker אחרי ה-<sup> שלה, והשאר
/// בסוף. שורה שכבר יש בה גוף הערה מוחזרת כמו שהיא, כך שהחלה כפולה בטוחה.
String rehydrateInlineNotes(String line, List<BookNote> notes) {
  if (notes.isEmpty || _footnoteBodyRegExp.hasMatch(line)) return line;
  final anchored = [
    for (final note in notes)
      if (note.marker != null) note,
  ];
  final markers = anchored.isEmpty ? const <Match>[] : _strippedMarkers(line);
  final out = StringBuffer();
  var last = 0;
  final used = <BookNote>{};
  for (var k = 0; k < markers.length && k < anchored.length; k++) {
    out
      ..write(line.substring(last, markers[k].end))
      ..write(_footnoteHtml(anchored[k].body));
    used.add(anchored[k]);
    last = markers[k].end;
  }
  out.write(line.substring(last));
  for (final note in notes) {
    if (!used.contains(note)) out.write(_footnoteHtml(note.body));
  }
  return out.toString();
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

String _footnoteHtml(String body) => '<i class="footnote">$body</i>';
