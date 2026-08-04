/// ניווט בין סמני-עוגן בשורות הספר באמצעות המקלדת.
///
/// הסמנים עצמם נבנים ב-[injectLinkAnchorMarkers] ומזוהים ב-URL בתור
/// `otzaria://anchor?ref=<line>_<i>`, כאשר `i` הוא המקום בתוך *רשימת
/// העוגנים של אותה שורה* — היא-היא הרשימה ש-`_anchorLinkFromUrl` בונה.
/// המודול הזה מספק את אותו מיפוי בכיוון ההפוך: מהמקום הנוכחי אל הסמן
/// הבא/הקודם, כדי שקיצור מקלדת יוכל לפתוח את אותה חלונית תצוגה מקדימה
/// שנפתחת בריחוף — בלי מיקום עכבר.
library;

import 'package:otzaria/models/links.dart';

/// מקומו של סמן-עוגן בספר: שורת מקור (0-based) והמקום בתוך עוגני השורה.
class AnchorCursor {
  final int line;
  final int index;

  const AnchorCursor(this.line, this.index);

  @override
  bool operator ==(Object other) =>
      other is AnchorCursor && other.line == line && other.index == index;

  @override
  int get hashCode => Object.hash(line, index);

  @override
  String toString() => 'AnchorCursor($line, $index)';
}

/// עוגני שורה [line0] (0-based) — בדיוק אותו סינון וסדר שבהם נבנו הסמנים
/// בשורה, כדי שהאינדקס יהיה זהה לזה שב-`otzaria://anchor?ref=`.
///
/// [linksByLine] ממופה במפתחות 1-based (כמו במסד ובקישורים).
List<Link> anchorLinksForLine(
  Map<int, List<Link>> linksByLine,
  int line0,
) {
  final links = linksByLine[line0 + 1];
  if (links == null || links.isEmpty) return const <Link>[];
  return links.where((link) => link.anchorStart != null).toList();
}

/// מספר העוגנים בשורה [line0].
int anchorCountForLine(Map<int, List<Link>> linksByLine, int line0) =>
    anchorLinksForLine(linksByLine, line0).length;

/// הסמן הבא אחרי [from] (או הראשון בספר כש-[from] הוא null), בסריקה קדימה
/// עד [lineCount]. `null` — אין עוד סמנים.
///
/// הסריקה היא על המפתחות שקיימים ב-[linksByLine] ולא על כל שורות הספר, כדי
/// שספר עם עשרות אלפי שורות ומעט עוגנים לא ייסרק שורה-שורה.
AnchorCursor? nextAnchor(
  Map<int, List<Link>> linksByLine,
  int lineCount, {
  AnchorCursor? from,
}) {
  if (from != null) {
    final inSameLine = anchorCountForLine(linksByLine, from.line);
    if (from.index + 1 < inSameLine) {
      return AnchorCursor(from.line, from.index + 1);
    }
  }
  final startLine = from == null ? 0 : from.line + 1;
  for (final line in _anchorLinesFrom(
    linksByLine,
    lineCount,
    startLine,
    forward: true,
  )) {
    return AnchorCursor(line, 0);
  }
  return null;
}

/// הסמן שלפני [from] (או האחרון בספר כש-[from] הוא null).
AnchorCursor? previousAnchor(
  Map<int, List<Link>> linksByLine,
  int lineCount, {
  AnchorCursor? from,
}) {
  if (from != null && from.index > 0) {
    return AnchorCursor(from.line, from.index - 1);
  }
  final startLine = from == null ? lineCount - 1 : from.line - 1;
  for (final line in _anchorLinesFrom(
    linksByLine,
    lineCount,
    startLine,
    forward: false,
  )) {
    return AnchorCursor(line, anchorCountForLine(linksByLine, line) - 1);
  }
  return null;
}

/// הסמן הראשון בשורה [line0] או אחריה; ואם אין כזה — האחרון שלפניה.
/// משמש לנקודת הפתיחה של מצב המקלדת, שמתחילה מהשורה הנבחרת/הנגללת.
AnchorCursor? anchorNearLine(
  Map<int, List<Link>> linksByLine,
  int lineCount,
  int line0,
) {
  final atLine = anchorCountForLine(linksByLine, line0);
  if (atLine > 0) return AnchorCursor(line0, 0);
  final ahead = nextAnchor(
    linksByLine,
    lineCount,
    from: AnchorCursor(line0, atLine),
  );
  if (ahead != null) return ahead;
  return previousAnchor(
    linksByLine,
    lineCount,
    from: AnchorCursor(line0, 0),
  );
}

/// שורות (0-based) שיש בהן עוגנים, מ-[startLine] והלאה/והחזרה, בסדר.
Iterable<int> _anchorLinesFrom(
  Map<int, List<Link>> linksByLine,
  int lineCount,
  int startLine, {
  required bool forward,
}) {
  final lines = linksByLine.keys
      .map((line1) => line1 - 1)
      .where(
        (line0) =>
            line0 >= 0 &&
            line0 < lineCount &&
            (forward ? line0 >= startLine : line0 <= startLine) &&
            anchorCountForLine(linksByLine, line0) > 0,
      )
      .toList();
  lines.sort(forward ? (a, b) => a.compareTo(b) : (a, b) => b.compareTo(a));
  return lines;
}

/// ה-URL של סמן — כדי שמסלול המקלדת ייכנס לאותו קוד טיפול כמו ריחוף/לחיצה
/// ולא ישכפל את פענוח הקישור.
String anchorUrlFor(AnchorCursor cursor) =>
    'otzaria://anchor?ref=${cursor.line}_${cursor.index}';
