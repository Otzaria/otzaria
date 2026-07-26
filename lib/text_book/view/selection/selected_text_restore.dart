import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// מעבד שורת מקור לטקסט הפשוט שהמשתמש רואה במסך. הרווחים מכווצים כמו
/// בתצוגת ה-HTML, אחרת רווח כפול שמותיר `removePunctuation` יכשיל את ההתאמה.
String renderSelectionLine({
  required String rawText,
  required RenderSettings settings,
}) {
  final processed = TextRendererService.processText(rawText, settings);
  // <br> מוצג כמעבר שורה (תו רווח) — המרה לרווח לפני הסרת התגים, אחרת
  // stripHtml מוחק אותו ומבנה הרווחים לא יתאם את הבחירה בבדיקת העקביות.
  final withBreakGaps = processed.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    ' ',
  );
  final stripped = TextRendererService.stripHtml(withBreakGaps);
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// שורות רצופות ומרונדרות לשחזור, כשהראשונה היא שורת המקור [baseIndex].
typedef SelectionWindow = ({int baseIndex, List<String> lines});

/// השורות הנראות + שוליים: הבחירה נמשכת גם מעבר למסך (גלילה תוך כדי סימון),
/// ובלעדיהם ההתאמה המדויקת נכשלת וההעתקה יוצאת שטוחה.
SelectionWindow buildSelectionWindow({
  required List<int> visibleIndices,
  required int totalLines,
  required int selectionLength,
  required String Function(int index) renderLine,
  int maxPadding = 100,
}) {
  if (visibleIndices.isEmpty || totalLines <= 0) {
    return (baseIndex: 0, lines: const <String>[]);
  }
  final first = visibleIndices.first.clamp(0, totalLines - 1);
  final last = visibleIndices.last.clamp(first, totalLines - 1);

  final leading = <String>[];
  var budget = selectionLength;
  for (
    var i = first - 1;
    i >= 0 && budget > 0 && leading.length < maxPadding;
    i--
  ) {
    final line = renderLine(i);
    leading.add(line);
    budget -= line.length;
  }

  final lines = leading.reversed.toList();
  for (var i = first; i <= last; i++) {
    lines.add(renderLine(i));
  }

  budget = selectionLength;
  var trailing = 0;
  for (
    var i = last + 1;
    i < totalLines && budget > 0 && trailing < maxPadding;
    i++
  ) {
    final line = renderLine(i);
    lines.add(line);
    budget -= line.length;
    trailing++;
  }

  return (baseIndex: first - leading.length, lines: lines);
}

/// הטקסט המשוחזר, ומיקומו ב-visibleLines כשההתאמה המדויקת הצליחה.
/// [ambiguous] — כמה מופעים תואמים; אסור אז ליפול לאינדקס ישן או לברירת מחדל.
typedef RestoredSelection = ({
  String text,
  int? startLine,
  int? endLine,
  int? startColumn,
  bool ambiguous,
});

/// מיקום ידוע → יחסית ל-[baseIndex]; עמימות → null (אינדקס ישן היה משייך
/// הערה/תפריט/plugin לשורה שגויה); אחרת [fallbackIndex].
({int? selectedIndex, int? lineStart, int? lineEnd, int? startColumn})
resolveSelectionLocation({
  required RestoredSelection restored,
  required int baseIndex,
  required int? fallbackIndex,
}) {
  if (restored.startLine != null) {
    final selectedIndex = baseIndex + restored.startLine!;
    return (
      selectedIndex: selectedIndex,
      lineStart: selectedIndex,
      lineEnd: baseIndex + restored.endLine!,
      startColumn: restored.startColumn,
    );
  }
  return (
    selectedIndex: restored.ambiguous ? null : fallbackIndex,
    lineStart: null,
    lineEnd: null,
    startColumn: null,
  );
}

/// האינדקס השמור תקף כרמז ו-fallback רק בסשן הבחירה הנוכחי: בלי טקסט שמור
/// הוא שייך לבחירה קודמת, ושיוך לפיו היה מפנה לשורה של הבחירה הישנה.
int? sessionSelectionIndex({
  required String? savedSelectedText,
  required int? savedSelectedIndex,
}) => savedSelectedText == null ? null : savedSelectedIndex;

/// משחזר מעברי שורה בבחירה השטוחה שפלאטר מחזיר: תחילה התאמה מדויקת, ואם
/// נכשלה — שחזור סלחני שעומד גם בשורת אמצע שרונדרה שונה או חסרה מהתצוגה.
String restoreSelectedTextLineBreaks({
  required String selectedText,
  required List<String> visibleLines,
}) {
  return restoreSelectedTextLineBreaksDetailed(
    selectedText: selectedText,
    visibleLines: visibleLines,
  ).text;
}

/// כמו [restoreSelectedTextLineBreaks] + מיקום ההתאמה — חייב להיחשב כאן, כי
/// indexOf נשבר על NBSP/רווח-דק שבבחירה ואינם בשורות המרונדרות.
/// [preferredLine] — השורה מהעדכון הקודם, מכריעה בין כמה מופעים תואמים.
RestoredSelection restoreSelectedTextLineBreaksDetailed({
  required String selectedText,
  required List<String> visibleLines,
  int? preferredLine,
}) {
  RestoredSelection withoutLocation(String text) => (
    text: text,
    startLine: null,
    endLine: null,
    startColumn: null,
    ambiguous: false,
  );

  if (selectedText.isEmpty || visibleLines.isEmpty) {
    return withoutLocation(selectedText);
  }

  final exact = _restoreExact(selectedText, visibleLines, preferredLine);
  if (exact != null) {
    return exact;
  }
  if (selectedText.contains('\n')) {
    return withoutLocation(selectedText);
  }
  return withoutLocation(_restoreGreedy(selectedText, visibleLines));
}

/// תואם את קבוצת `\s` של Dart RegExp (כולל NBSP ורווח-דק) — חייב להישאר
/// עקבי עם כיווץ הרווחים ב-[renderSelectionLine].
bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    (codeUnit >= 0x09 && codeUnit <= 0x0D) ||
    codeUnit == 0xA0 ||
    codeUnit == 0x1680 ||
    (codeUnit >= 0x2000 && codeUnit <= 0x200A) ||
    codeUnit == 0x2028 ||
    codeUnit == 0x2029 ||
    codeUnit == 0x202F ||
    codeUnit == 0x205F ||
    codeUnit == 0x3000 ||
    codeUnit == 0xFEFF;

/// התאמה מדויקת על התווים שאינם רווח בלבד — בבחירה יש NBSP/רווח-דק ו-\n
/// (מ-&nbsp;/<br>) שהשורות המרונדרות מכווצות לרווח רגיל.
RestoredSelection? _restoreExact(
  String selectedText,
  List<String> visibleLines,
  int? preferredLine,
) {
  // הבחירה ללא תווי רווח + מיפוי כל תו לאינדקסו במחרוזת המקורית.
  final selectedIndexMap = <int>[];
  final selectedBuffer = StringBuffer();
  for (var i = 0; i < selectedText.length; i++) {
    if (!_isWhitespace(selectedText.codeUnitAt(i))) {
      selectedBuffer.write(selectedText[i]);
      selectedIndexMap.add(i);
    }
  }
  final selectedCompact = selectedBuffer.toString();
  if (selectedCompact.isEmpty) {
    return (
      text: selectedText,
      startLine: null,
      endLine: null,
      startColumn: null,
      ambiguous: false,
    );
  }

  // איחוד השורות ללא תווי רווח + מספר השורה והעמודה של כל תו.
  final lineOfChar = <int>[];
  final columnOfChar = <int>[];
  final visibleBuffer = StringBuffer();
  for (var lineIndex = 0; lineIndex < visibleLines.length; lineIndex++) {
    final line = visibleLines[lineIndex];
    for (var i = 0; i < line.length; i++) {
      if (!_isWhitespace(line.codeUnitAt(i))) {
        visibleBuffer.write(line[i]);
        lineOfChar.add(lineIndex);
        columnOfChar.add(i);
      }
    }
  }
  final visibleCompact = visibleBuffer.toString();

  // מאמת שקיום רווח בין תווים סמוכים זהה בבחירה ובתצוגה, כדי לא לשייך למופע
  // עם פיזור רווחים אחר. גבול שורות הוא wildcard — שם הבחירה חסרת רווח בדין.
  bool selectedHasGap(int k) =>
      selectedIndexMap[k] > selectedIndexMap[k - 1] + 1;
  bool visibleHasGap(int pos) => columnOfChar[pos] > columnOfChar[pos - 1] + 1;

  bool isConsistentAt(int start) {
    for (var k = 1; k < selectedCompact.length; k++) {
      if (lineOfChar[start + k] != lineOfChar[start + k - 1]) continue;
      if (selectedHasGap(k) != visibleHasGap(start + k)) {
        return false;
      }
    }
    return true;
  }

  // הזרקת \n לפני התו הראשון של כל שורה חדשה בתוך ההתאמה — אלא אם רווחי
  // הגבול בבחירה כבר מכילים \n (למשל מ-<br>), כדי לא להכפיל מעבר קיים.
  String restoreAt(int start) {
    final result = StringBuffer();
    var writtenUpTo = 0;
    for (var k = 1; k < selectedCompact.length; k++) {
      if (lineOfChar[start + k] != lineOfChar[start + k - 1]) {
        final breakAt = selectedIndexMap[k];
        final boundaryGap = selectedText.substring(
          selectedIndexMap[k - 1] + 1,
          breakAt,
        );
        result.write(selectedText.substring(writtenUpTo, breakAt));
        if (!boundaryGap.contains('\n')) {
          result.write('\n');
        }
        writtenUpTo = breakAt;
      }
    }
    result.write(selectedText.substring(writtenUpTo));
    return result.toString();
  }

  final candidateStarts = <int>[];
  var found = -1;
  for (
    var from = 0;
    (found = visibleCompact.indexOf(selectedCompact, from)) >= 0;
    from = found + 1
  ) {
    if (isConsistentAt(found)) {
      candidateStarts.add(found);
    }
  }
  if (candidateStarts.isEmpty) {
    return null;
  }

  RestoredSelection resultAt(int start) => (
    text: restoreAt(start),
    startLine: lineOfChar[start],
    endLine: lineOfChar[start + selectedCompact.length - 1],
    startColumn: columnOfChar[start],
    ambiguous: false,
  );

  // מועמד יחיד — תוצאה מלאה כולל מיקום.
  if (candidateStarts.length == 1) {
    return resultAt(candidateStarts.first);
  }

  // כמה מועמדים: אם בדיוק אחד מהם מכיל את השורה הידועה מהעדכון הקודם —
  // הוא המופע שנבחר.
  if (preferredLine != null) {
    final preferred = candidateStarts
        .where(
          (start) =>
              lineOfChar[start] <= preferredLine &&
              preferredLine <= lineOfChar[start + selectedCompact.length - 1],
        )
        .toList();
    if (preferred.length == 1) {
      return resultAt(preferred.single);
    }
  }

  // עמימות: אם כל המופעים משחזרים אותו טקסט מחזירים אותו; אם השחזורים שונים
  // עדיף להחזיר את הבחירה כמות שהיא מאשר לנחש מעברים. בשני המצבים אין מיקום.
  final restoredText = restoreAt(candidateStarts.first);
  final allSameText = candidateStarts
      .skip(1)
      .every((start) => restoreAt(start) == restoredText);
  return (
    text: allSameText ? restoredText : selectedText,
    startLine: null,
    endLine: null,
    startColumn: null,
    ambiguous: true,
  );
}

/// שחזור סלחני: מזריק `\n` לתוך הבחירה השטוחה בלבד — לעולם אינו משנה תווים.
/// אם ההזרקה מייצרת טקסט שאינו זהה לבחירה המקורית (מלבד ה-`\n`), חוזר לבחירה.
String _restoreGreedy(String selectedText, List<String> visibleLines) {
  final start = _findSelectionStart(selectedText, visibleLines);
  if (start == null) {
    return selectedText;
  }

  final (startLine, startOffset) = start;
  final result = StringBuffer();

  // צריכת החלק שנבחר מהשורה הראשונה (הבחירה עשויה להתחיל באמצע שורה).
  final firstLine = visibleLines[startLine];
  final firstContribution = (firstLine.length - startOffset).clamp(
    0,
    selectedText.length,
  );
  result.write(selectedText.substring(0, firstContribution));
  var pos = firstContribution;

  var lineIndex = startLine + 1;
  while (pos < selectedText.length && lineIndex < visibleLines.length) {
    final line = visibleLines[lineIndex];
    lineIndex++;
    if (line.isEmpty) {
      continue;
    }
    final remaining = selectedText.substring(pos);
    if (remaining.startsWith(line)) {
      result.write('\n');
      result.write(line);
      pos += line.length;
    } else if (line.startsWith(remaining)) {
      // הבחירה מסתיימת באמצע השורה הנוכחית.
      result.write('\n');
      result.write(remaining);
      pos = selectedText.length;
    } else {
      final found = remaining.indexOf(line);
      if (found > 0) {
        // מקטע לא-תואם לפני השורה (שורה שנגללה/רונדרה שונה) — שורה נפרדת.
        result.write('\n');
        result.write(remaining.substring(0, found));
        result.write('\n');
        result.write(line);
        pos += found + line.length;
      }
      // אחרת: השורה אינה בבחירה כאן — מדלגים עליה בלי לצרוך תווים.
    }
  }

  if (pos < selectedText.length) {
    result.write(selectedText.substring(pos));
  }

  final restored = result.toString();
  if (restored.replaceAll('\n', '') != selectedText) {
    return selectedText;
  }
  return restored;
}

/// מאתר את השורה והעמודה שבהן מתחילה הבחירה בתוך השורות המרונדרות.
(int, int)? _findSelectionStart(
  String selectedText,
  List<String> visibleLines,
) {
  for (var lineIndex = 0; lineIndex < visibleLines.length; lineIndex++) {
    final line = visibleLines[lineIndex];
    if (line.isEmpty) {
      continue;
    }
    for (var offset = 0; offset < line.length; offset++) {
      if (selectedText.startsWith(line.substring(offset))) {
        return (lineIndex, offset);
      }
    }
    final inside = line.indexOf(selectedText);
    if (inside >= 0) {
      return (lineIndex, inside);
    }
  }
  return null;
}
