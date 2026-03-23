import 'package:otzaria/models/links.dart';

/// עוזר לסנכרון מפרשים - מוצא את הקישור הטוב ביותר
class CommentarySyncHelper {
  /// בדיקה אם שורה היא כותרת (H1, H2, H3, H4...)
  static bool isHeaderLine(String line) {
    final headerPattern = RegExp(r'^\s*<h[1-6]', caseSensitive: false);
    return headerPattern.hasMatch(line);
  }

  /// מציאת האינדקס הלוגי (עם טיפול בכותרות)
  /// אם השורה היא כותרת, מחזיר את השורה הבאה
  static int getLogicalIndex(int currentIndex, List<String> content) {
    if (currentIndex < 0 || currentIndex >= content.length) {
      return currentIndex;
    }

    // אם השורה הנוכחית היא כותרת, נדלג לשורה הבאה
    int logicalIndex = currentIndex;
    while (
        logicalIndex < content.length && isHeaderLine(content[logicalIndex])) {
      logicalIndex++;
    }

    // אם הגענו לסוף הטקסט, נחזור לאינדקס המקורי
    if (logicalIndex >= content.length) {
      return currentIndex;
    }

    return logicalIndex;
  }

  /// מיפוי יציב ודטרמיניסטי של הטקסט הראשי למפרש
  static int? calculateTargetIndex({
    required List<Link> linksForCommentary,
    required int logicalMainIndex,
  }) {
    if (linksForCommentary.isEmpty) return null;

    final targetLine1 = logicalMainIndex + 1;

    // מיון הלינקים לפי index1 ואחר כך לפי index2 כדי להבטיח סריקה יציבה
    final sortedLinks = List<Link>.from(linksForCommentary)
      ..sort((a, b) {
        final cmp = a.index1.compareTo(b.index1);
        if (cmp != 0) return cmp;
        return a.index2.compareTo(b.index2);
      });

    Link? exactLink;
    Link? prevLink;
    Link? nextLink;

    for (final link in sortedLinks) {
      if (link.index1 == targetLine1) {
        if (exactLink == null) {
          exactLink = link; // העוגן המדויק הראשון
        }
      } else if (link.index1 < targetLine1) {
        prevLink = link; // עדכון הדרגתי לעוגן האחרון לפני היעד
      } else if (link.index1 > targetLine1) {
        if (nextLink == null) {
          nextLink = link; // העוגן הראשון מיד אחרי היעד
          break; // אין צורך להמשיך לחפש
        }
      }
    }

    Link chosenLink;

    if (exactLink != null) {
      chosenLink = exactLink;
    } else if (prevLink != null) {
      // גם אם קיים nextLink וגם אם לא - הגישה הדטרמיניסטית היא להיצמד לעוגן הקודם
      chosenLink = prevLink;
    } else {
      // אין עוגן קודם, מצב של "תחילת ספר"
      chosenLink = nextLink ?? sortedLinks.first;
    }

    // משתמשים בפונקציה הקיימת להחזרת אינדקס היעד מהלינק הנבחר
    return getCommentaryTargetIndex(chosenLink);
  }

  /// חישוב האינדקס היעד במפרש
  static int? getCommentaryTargetIndex(Link? link) {
    if (link == null) {
      return null;
    }
    return link.index2 - 1; // המרה ל-0-based
  }
}
