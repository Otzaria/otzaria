/// כלים לטיפול בהערות שוליים inline שמקודדות בתוכן השורה כ-HTML:
///   <sup class="footnote-marker">marker</sup><i class="footnote">body</i>
///
/// הספרים האלה (כ-322 ב-DB) מקודדים את גוף ההערה בתוך השורה עצמה, ולא
/// בקובץ נלווה. אנו מציגים אותם כמפרש וירטואלי בצד, ומסירים אותם מגוף
/// הספר.
library;

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

const String _supCloseTag = '</sup>';

/// הופך את סימוני ההערות המוטמעים לקישורי-ריחוף, בלי לשנות את הטקסט הגלוי.
String addInlineNotePreviewLinks(String html, {required int lineIndex}) {
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
      value:
          '<a class="book-note-marker" '
          'href="otzaria://book-note?line=$lineIndex&note=$noteIndex">'
          '$marker</a>',
    ));
    noteIndex++;
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

/// מחזיר את תוכן ההערה המוטמעת שאליה מפנה [url].
String? inlineNoteFromPreviewUrl(List<String> content, String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'book-note') return null;
  final lineIndex = int.tryParse(uri!.queryParameters['line'] ?? '');
  final noteIndex = int.tryParse(uri.queryParameters['note'] ?? '');
  if (lineIndex == null ||
      noteIndex == null ||
      lineIndex < 0 ||
      lineIndex >= content.length) {
    return null;
  }
  final lineNotes = notesForLines(content, [lineIndex]);
  if (noteIndex < 0 || noteIndex >= lineNotes.length) return null;
  return lineNotes[noteIndex];
}

/// מסיר את גוף ההערות (<i class="footnote">...</i>) משורה אחת.
/// משאיר את ה-<sup> במקומו כעוגן ויזואלי לאיפה הייתה ההערה.
String stripInlineNotes(String html) {
  if (!html.contains('footnote')) return html;
  return html.replaceAll(_footnoteBodyRegExp, '');
}

/// מסיר את ההערות inline במלואן — גם אות ההפניה
/// (<sup class="footnote-marker">marker</sup>) וגם גוף ההערה
/// (<i class="footnote">body</i>).
///
/// בניגוד ל-[stripInlineNotes] שמשאיר את ה-<sup> כעוגן ויזואלי בקורא,
/// כאן מסירים גם אותו. נחוץ לטקסט שמיועד לחיפוש או לאינדוקס: שם תגי ה-HTML
/// נמחקים, ולכן אות ההפניה וגוף ההערה היו נשארים כטקסט חשוף ומזהמים את
/// תוצאות החיפוש.
String stripInlineNotesForSearch(String html) {
  if (!html.contains('footnote')) return html;
  return html
      .replaceAll(_footnoteMarkerRegExp, '')
      .replaceAll(_footnoteBodyRegExp, '');
}

/// בודק אם הספר מכיל לפחות שורה אחת עם הערה inline.
bool hasInlineNotes(List<String> content) {
  for (final line in content) {
    if (line.contains('footnote') && _footnoteBodyRegExp.hasMatch(line)) {
      return true;
    }
  }
  return false;
}

/// מחלץ את ההערות מסט שורות (לפי האינדקסים שניתנו).
///
/// כל ערך ברשימה הוא מחרוזת HTML שמכילה את ה-<sup>marker</sup> שצמוד
/// לפני ההערה (אם יש) ואחריו את גוף ההערה. אם אין <sup> צמוד - מוחזר
/// רק גוף ההערה.
///
/// משתמש ב-lastIndexOf במקום regex עם $-anchor כדי להבטיח שלכל הערה
/// מצמידים אך ורק את ה-<sup> שמופיע מיד לפניה (ולא רצף של <sup>-ים
/// קודמים יחד עם תוכן ביניהם).
List<String> notesForLines(
  List<String> content,
  Iterable<int> indexes,
) {
  final results = <String>[];
  for (final idx in indexes) {
    if (idx < 0 || idx >= content.length) continue;
    final line = content[idx];
    if (!line.contains('footnote')) continue;

    for (final iMatch in _footnoteBodyRegExp.allMatches(line)) {
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
            results.add('$supTag $body');
            continue;
          }
        }
      }
      results.add(body);
    }
  }
  return results;
}
