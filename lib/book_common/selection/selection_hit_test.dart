import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';

/// המיקום של הטקסט המסומן בשורה מסוימת ביחס לטקסט המלא של הפסקה.
///
/// משמש כדי לאתר את טווח התווים הנבחר בתוך ה-RenderParagraph:
/// - [full] — כל השורה מסומנת (שורת ביניים בבחירה רב-שורתית).
/// - [prefix] — מסומן מתחילת השורה (שורת הסיום בבחירה רב-שורתית).
/// - [suffix] — מסומן עד סוף השורה (שורת ההתחלה בבחירה רב-שורתית).
/// - [substring] — מסומן קטע באמצע (בחירת שורה בודדת).
enum SelectionSegmentEdge { full, prefix, suffix, substring }

/// מאתר בחירה חד-שורתית לפי מיקום ה-pointer. נדרש במיוחד ללחיצה כפולה:
/// הטקסט הנבחר הוא לעיתים מילה נפוצה, וחיפוש גלובלי היה בוחר את המופע הראשון
/// באזור הנראה במקום את המילה שעליה המשתמש לחץ.
({int lineIndex, int column})? locateSingleLineSelectionAtPointer({
  required List<String> renderedLines,
  required List<int> sourceIndices,
  required String selectedText,
  required int? pointerLineIndex,
  required int? pointerColumn,
}) {
  if (selectedText.isEmpty || selectedText.contains('\n')) return null;
  if (pointerLineIndex == null || pointerColumn == null) return null;
  final linePosition = sourceIndices.indexOf(pointerLineIndex);
  if (linePosition < 0 || linePosition >= renderedLines.length) return null;
  final line = renderedLines[linePosition];
  final occurrences = <int>[];
  for (var from = 0; ;) {
    final found = line.indexOf(selectedText, from);
    if (found < 0) break;
    occurrences.add(found);
    from = found + 1;
  }
  if (occurrences.isEmpty) return null;
  final column = occurrences.reduce((a, b) {
    final aDistance =
        pointerColumn.clamp(a, a + selectedText.length) - pointerColumn;
    final bDistance =
        pointerColumn.clamp(b, b + selectedText.length) - pointerColumn;
    return aDistance.abs() <= bDistance.abs() ? a : b;
  });
  return (lineIndex: pointerLineIndex, column: column);
}

/// Returns the start offset of the occurrence under [globalPosition].
/// This disambiguates repeated selected text inside the same paragraph.
/// [lineRange] מצמצם את החיפוש לשורת מקור אחת בתוך פסקה ממוזגת, והתוצאה
/// יחסית לתחילתה.
int? renderedSelectionStartAtPosition({
  required RenderObject root,
  required Offset globalPosition,
  required String selectedSegment,
  TextRange? lineRange,
}) {
  if (selectedSegment.isEmpty) return null;
  final paragraph = _findParagraphContaining(root, globalPosition);
  if (paragraph == null) return null;
  final paragraphText = _paragraphText(paragraph, lineRange);
  if (paragraphText == null) return null;
  final (:text, :base, length: _) = paragraphText;
  final occurrences = <int>[];
  for (var from = 0; ;) {
    final found = text.indexOf(selectedSegment, from);
    if (found < 0) break;
    occurrences.add(found);
    from = found + 1;
  }
  if (occurrences.isEmpty) return null;

  final local = paragraph.globalToLocal(globalPosition);
  final clickedOffset = paragraph.getPositionForOffset(local).offset - base;
  for (final start in occurrences) {
    if (clickedOffset >= start &&
        clickedOffset <= start + selectedSegment.length) {
      return start;
    }
  }
  return occurrences.reduce(
    (a, b) => (a - clickedOffset).abs() <= (b - clickedOffset).abs() ? a : b,
  );
}

/// Returns the rendered text offset under a pointer before Flutter collapses
/// the selection into plain text. Used as a stable occurrence hint.
/// With [lineRange] the offset is relative to that source line's text.
int? renderedTextOffsetAtPosition({
  required RenderObject root,
  required Offset globalPosition,
  TextRange? lineRange,
}) {
  final paragraph = _findParagraphContaining(root, globalPosition);
  if (paragraph == null) return null;
  final offset = paragraph
      .getPositionForOffset(paragraph.globalToLocal(globalPosition))
      .offset;
  final paragraphText = _paragraphText(paragraph, lineRange);
  if (paragraphText == null) return null;
  final (:text, :base, length: _) = paragraphText;
  return (offset - base).clamp(0, text.length).toInt();
}

/// בודק אם נקודת הלחיצה [globalPosition] נופלת על הטקסט המסומן בפועל.
///
/// מאתר בתת-העץ של [root] את ה-RenderParagraph שמכיל את הנקודה, מחשב את טווח
/// התווים הנבחר בתוכו לפי [selectedSegment] ו-[edge], ובודק אם הנקודה בתוך תיבות
/// הבחירה. נעשה שימוש ב-`BoxHeightStyle.includeLineSpacingMiddle` כך שהרווח האנכי
/// שבין שורות-תצוגה של אותה שורת-מקור שנשברה (wrap) נחשב חלק מהבחירה.
///
/// [segmentStartHint] הוא רמז למיקום ההתחלה של הקטע המסומן בתוך טקסט הפסקה
/// (אופציונלי), ומשמש בעיקר במקרה [SelectionSegmentEdge.substring] כדי לבחור את
/// המופע הנכון כאשר אותו קטע חוזר כמה פעמים באותה פסקה — בוחרים את המופע הקרוב
/// ביותר לרמז. ללא רמז, מופע כפול נחשב דו-משמעי.
///
/// מחזיר:
/// - `true`  — הלחיצה על הטקסט המסומן.
/// - `false` — הלחיצה בתוך הפסקה אך מחוץ לטקסט המסומן (למשל חלק לא-מסומן בשורה).
/// - `null`  — לא ניתן להכריע (לא נמצאה פסקה מתאימה, הטקסט לא תאם וכו'). על
///   המתקשר לחזור לברירת מחדל סלחנית (לא לבטל את הבחירה).
bool? clickIsOnRenderedSelection({
  required RenderObject root,
  required Offset globalPosition,
  required String selectedSegment,
  required SelectionSegmentEdge edge,
  int? segmentStartHint,
  TextRange? lineRange,
}) {
  final paragraph = _findParagraphContaining(root, globalPosition);
  if (paragraph == null) return null;

  final paragraphText = _paragraphText(paragraph, lineRange);
  if (paragraphText == null) return null;
  final (text: pText, base: _, length: _) = paragraphText;
  if (pText.isEmpty) return null;

  final int selStart;
  final int selEnd;
  switch (edge) {
    case SelectionSegmentEdge.full:
      selStart = 0;
      selEnd = pText.length;
    case SelectionSegmentEdge.prefix:
      selStart = 0;
      selEnd = selectedSegment.length.clamp(0, pText.length);
    case SelectionSegmentEdge.suffix:
      selStart = (pText.length - selectedSegment.length).clamp(0, pText.length);
      selEnd = pText.length;
    case SelectionSegmentEdge.substring:
      if (selectedSegment.isEmpty) return null;
      // אוספים את כל המופעים של הקטע בפסקה.
      final occurrences = <int>[];
      for (var from = 0; ;) {
        final i = pText.indexOf(selectedSegment, from);
        if (i < 0) break;
        occurrences.add(i);
        from = i + 1;
      }
      if (occurrences.isEmpty) return null; // לא הצלחנו למפות — נחזור לסלחני
      final int chosen;
      if (occurrences.length == 1) {
        chosen = occurrences.first;
      } else if (segmentStartHint != null) {
        // מופע כפול — בוחרים את המופע הקרוב ביותר לרמז המיקום של הבחירה בפועל,
        // כך שלחיצה על המופע הלא-מסומן תיחשב מחוץ לבחירה (ותבטל).
        chosen = occurrences.reduce(
          (a, b) => (a - segmentStartHint).abs() <= (b - segmentStartHint).abs()
              ? a
              : b,
        );
      } else {
        return null; // מופע כפול וללא רמז — דו-משמעי, נחזור לסלחני
      }
      selStart = chosen;
      selEnd = (chosen + selectedSegment.length).clamp(0, pText.length);
  }
  if (selStart >= selEnd) return null;

  final selection = _selectionInParagraph(paragraphText, selStart, selEnd);
  // במקטע של שורה ארוכה הבחירה יכולה להיות כולה במקטע אחר.
  if (selection.isCollapsed) return false;
  final boxes = paragraph.getBoxesForSelection(
    selection,
    boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
  );
  if (boxes.isEmpty) return null;

  final local = paragraph.globalToLocal(globalPosition);
  for (final box in boxes) {
    if (box.toRect().contains(local)) return true;
  }
  return false;
}

/// בודק אם נקודת הלחיצה [globalPosition] נופלת על הטקסט המסומן, עבור תצוגות
/// שבהן הבחירה מנוהלת ע"י `SelectionArea` יחיד ואין מעקב פר-שורה (פאנל/כרטסיית
/// מפרשים — בטקסט וב-PDF). בניגוד ל-[clickIsOnRenderedSelection] שמקבל קטע ו-edge
/// ידועים מתוך מעקב פר-שורה, כאן הקטע הנבחר בתוך הפסקה מחושב ישירות מתוך כלל
/// הטקסט הנבחר [selectedText] (השטוח שמחזיר Flutter), ע"י איתור החפיפה בינו לבין
/// הטקסט המרונדר של הפסקה שעליה לחצו.
///
/// מחזיר:
/// - `true`  — הלחיצה על הטקסט המסומן.
/// - `false` — הלחיצה בתוך פסקה אך מחוץ לטקסט המסומן (או שאין בחירה).
/// - `null`  — לא ניתן להכריע (לא נמצאה פסקה / לא ניתן למפות חד-משמעית). על
///   המתקשר לחזור לברירת מחדל סלחנית (לא לבטל את הבחירה).
bool? clickIsOnSelectionWithinArea({
  required RenderObject root,
  required Offset globalPosition,
  required String selectedText,
}) {
  if (selectedText.isEmpty) return false;
  final paragraph = _findParagraphContaining(root, globalPosition);
  if (paragraph == null) return null;

  final pText = paragraph.text.toPlainText(includeSemanticsLabels: false);
  if (pText.isEmpty) return null;

  final range = _selectedRangeWithin(pText, selectedText);
  if (range == null) return null; // לא ניתן למפות — סלחני
  final (selStart, selEnd) = range;
  if (selStart >= selEnd) return null;

  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: selStart, extentOffset: selEnd),
    boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
  );
  if (boxes.isEmpty) return null;

  final local = paragraph.globalToLocal(globalPosition);
  for (final box in boxes) {
    if (box.toRect().contains(local)) return true;
  }
  return false;
}

/// בודק אם נקודת הלחיצה [globalPosition] נופלת על מופע של [text] בפסקה
/// שתחת הנקודה. משמש לזיהוי לחיצה על טקסט מודגש (ללא בחירה פעילה).
///
/// כשידוע איזה מופע מודגש ([occurrenceIndex] מתוך [occurrenceCount]) —
/// נבדק רק הוא, כדי שלחיצה על מופע זהה לא-מודגש לא תיחשב על ההדגשה.
/// כשמספר המופעים בפסקה שונה מהצפוי המיפוי דו-משמעי ונבדקים כל המופעים.
///
/// מחזיר `true` — הלחיצה על המופע; `false` — בפסקה אך מחוץ לו;
/// `null` — לא ניתן להכריע (אין פסקה / הטקסט לא נמצא בה).
bool? clickIsOnTextOccurrence({
  required RenderObject root,
  required Offset globalPosition,
  required String text,
  int? occurrenceIndex,
  int? occurrenceCount,
  TextRange? lineRange,
}) {
  if (text.isEmpty) return false;
  final paragraph = _findParagraphContaining(root, globalPosition);
  if (paragraph == null) return null;

  final paragraphText = _paragraphText(paragraph, lineRange);
  if (paragraphText == null) return null;
  final (text: pText, base: _, length: _) = paragraphText;
  if (pText.isEmpty) return null;

  // שבירת שורה (<br>) ורצף רווחים מוצגים אחרת מהטקסט שחושב להדגשה; מחפשים
  // ברצף שבו כל רווח הוא רווח אחד, וממפים כל מופע חזרה לטקסט הפסקה.
  final collapsed = _collapseWhitespace(pText);
  final needle = text.replaceAll(_whitespace, ' ');
  final starts = <int>[];
  final ends = <int>[];
  for (var from = 0; ;) {
    final start = collapsed.text.indexOf(needle, from);
    if (start < 0) break;
    starts.add(collapsed.origin[start]);
    ends.add(collapsed.origin[start + needle.length - 1] + 1);
    from = start + 1;
  }
  if (starts.isEmpty) return null;

  final onlyKnownOccurrence =
      occurrenceIndex != null &&
      occurrenceCount != null &&
      starts.length == occurrenceCount &&
      occurrenceIndex >= 0 &&
      occurrenceIndex < starts.length;
  final candidates = onlyKnownOccurrence
      ? [occurrenceIndex]
      : [for (var i = 0; i < starts.length; i++) i];

  final local = paragraph.globalToLocal(globalPosition);
  for (final i in candidates) {
    final boxes = paragraph.getBoxesForSelection(
      _selectionInParagraph(paragraphText, starts[i], ends[i]),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
    );
    for (final box in boxes) {
      if (box.toRect().contains(local)) return true;
    }
  }
  return false;
}

final RegExp _whitespace = RegExp(r'\s+');

/// [text] כשכל רצף רווחים (גם מעבר שורה) הוא רווח אחד; [origin] — המיקום
/// ב-[text] המקורי של כל תו ברצף המכווץ.
({String text, List<int> origin}) _collapseWhitespace(String text) {
  final buffer = StringBuffer();
  final origin = <int>[];
  var previousSpace = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    final space = char.trim().isEmpty;
    if (space && previousSpace) continue;
    previousSpace = space;
    buffer.write(space ? ' ' : char);
    origin.add(i);
  }
  return (text: buffer.toString(), origin: origin);
}

/// מחשב את טווח התווים המסומן בתוך טקסט הפסקה [pText], בהינתן כלל הטקסט הנבחר
/// [selectedText] (שטוח, רציף בסדר הקריאה). מטפל בארבעה מצבים: הפסקה כולה נמצאת
/// בתוך הבחירה, הבחירה כולה בתוך הפסקה, הבחירה מתחילה בפסקה (סיומת מסומנת), או
/// מסתיימת בה (תחילית מסומנת). מחזיר `null` כשלא ניתן למפות חד-משמעית.
(int, int)? _selectedRangeWithin(String pText, String selectedText) {
  // הפסקה כולה בתוך הבחירה (פסקת ביניים/פסקה שלמה שנבחרה).
  if (selectedText.contains(pText)) return (0, pText.length);

  // הבחירה כולה בתוך הפסקה (בחירת קטע בודד). דורש מופע יחיד למניעת אי-בהירות.
  final inside = pText.indexOf(selectedText);
  if (inside >= 0) {
    if (pText.indexOf(selectedText, inside + 1) >= 0) return null; // כפול
    return (inside, inside + selectedText.length);
  }

  // הפסקה בקצה הבחירה: סיומת של pText פותחת את selectedText (הבחירה מתחילה כאן),
  // או תחילית של pText סוגרת אותו (הבחירה מסתיימת כאן). בוחרים את החפיפה הארוכה.
  final suffix = _overlapLen(pText, selectedText, suffixOfFirst: true);
  final prefix = _overlapLen(pText, selectedText, suffixOfFirst: false);
  if (suffix == 0 && prefix == 0) return null;
  if (suffix >= prefix) return (pText.length - suffix, pText.length);
  return (0, prefix);
}

/// אורך החפיפה המרבי בין [a] ל-[b]: כש-[suffixOfFirst]=`true` — הסיומת הארוכה
/// ביותר של [a] שהיא תחילית של [b]; אחרת — התחילית הארוכה ביותר של [a] שהיא
/// סיומת של [b]. מחזיר `0` כשאין חפיפה.
int _overlapLen(String a, String b, {required bool suffixOfFirst}) {
  final maxK = a.length < b.length ? a.length : b.length;
  for (var k = maxK; k > 0; k--) {
    if (suffixOfFirst) {
      if (a.substring(a.length - k) == b.substring(0, k)) return k;
    } else {
      if (a.substring(0, k) == b.substring(b.length - k)) return k;
    }
  }
  return 0;
}

/// טקסט הפסקה או השורה [lineRange] שבה (null כשאינו תואם), ואופסט תחילתו.
/// במקטע של שורה ארוכה — השורה כולה, ו-base הוא מינוס תחילת המקטע.
({String text, int base, int length})? _paragraphText(
  RenderParagraph paragraph,
  TextRange? lineRange,
) {
  final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
  if (lineRange == null) {
    final chunk = longLineChunkOf(paragraph);
    if (chunk != null) {
      return (text: chunk.lineText, base: -chunk.start, length: text.length);
    }
    return (text: text, base: 0, length: text.length);
  }
  if (!lineRange.isValid ||
      !lineRange.isNormalized ||
      lineRange.end > text.length) {
    return null;
  }
  return (
    text: lineRange.textInside(text),
    base: lineRange.start,
    length: text.length,
  );
}

/// הטווח [start, end) של [paragraphText] באופסטים של הפסקה, חתוך לגבולותיה.
TextSelection _selectionInParagraph(
  ({String text, int base, int length}) paragraphText,
  int start,
  int end,
) {
  final (text: _, :base, :length) = paragraphText;
  return TextSelection(
    baseOffset: (base + start).clamp(0, length).toInt(),
    extentOffset: (base + end).clamp(0, length).toInt(),
  );
}

/// מאתר את ה-RenderParagraph העמוק ביותר בתת-העץ של [root] שתיבתו מכילה את
/// [globalPosition]. מחזיר `null` אם אין כזה.
RenderParagraph? _findParagraphContaining(
  RenderObject root,
  Offset globalPosition,
) {
  RenderParagraph? found;
  void visit(RenderObject object) {
    if (found != null) return;
    if (object is RenderParagraph && object.attached && object.hasSize) {
      final local = object.globalToLocal(globalPosition);
      if ((Offset.zero & object.size).contains(local)) {
        found = object;
        return;
      }
    }
    object.visitChildren(visit);
  }

  visit(root);
  return found;
}
