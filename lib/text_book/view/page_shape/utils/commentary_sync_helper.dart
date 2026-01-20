import 'package:otzaria/links/links.dart';

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

  /// מציאת הקישור הטוב ביותר למפרש
  /// מחזיר null אם אין קישורים כלל
  static Link? findBestLink({
    required List<Link> linksForCommentary,
    required int logicalMainIndex,
  }) {
    if (linksForCommentary.isEmpty) {
      return null;
    }

    final mainLineNumber = logicalMainIndex + 1; // המרה ל-1-based

    // ניסיון למצוא קישור מדויק
    try {
      return linksForCommentary.firstWhere(
        (link) => link.index1 == mainLineNumber,
      );
    } catch (e) {
      // אין קישור מדויק - מחפשים את הקרוב ביותר
    }

    // חיפוש L_before (הקישור הקודם הכי קרוב)
    Link? lBefore;
    int minDistanceBefore = double.maxFinite.toInt();

    for (final link in linksForCommentary) {
      if (link.index1 < mainLineNumber) {
        final distance = mainLineNumber - link.index1;
        if (distance < minDistanceBefore) {
          minDistanceBefore = distance;
          lBefore = link;
        }
      }
    }

    // אם יש קישור קודם - תמיד מעדיפים אותו
    if (lBefore != null) {
      return lBefore;
    }

    // אין קישור קודם - מחפשים L_after (הקישור הבא הכי קרוב)
    Link? lAfter;
    int minDistanceAfter = double.maxFinite.toInt();

    for (final link in linksForCommentary) {
      if (link.index1 > mainLineNumber) {
        final distance = link.index1 - mainLineNumber;
        if (distance < minDistanceAfter) {
          minDistanceAfter = distance;
          lAfter = link;
        }
      }
    }

    return lAfter; // יכול להיות null אם אין גם קישור הבא
  }

  /// חישוב האינדקס היעד במפרש
  static int? getCommentaryTargetIndex(Link? link) {
    if (link == null) {
      return null;
    }
    return link.index2 - 1; // המרה ל-0-based
  }
}
