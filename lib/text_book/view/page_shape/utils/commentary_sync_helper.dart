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
    while (logicalIndex < content.length &&
        isHeaderLine(content[logicalIndex])) {
      logicalIndex++;
    }

    // אם הגענו לסוף הטקסט, נחזור לאינדקס המקורי
    if (logicalIndex >= content.length) {
      return currentIndex;
    }

    return logicalIndex;
  }

  /// המרחק בפיקסלים שיש לגלול כדי ששורת היעד תשב על קו העוגן.
  ///
  /// [leadingEdge] - הקצה העליון של שורת היעד, כשבר מגובה החלון
  /// [viewportHeight] - גובה חלון המפרש בפיקסלים
  /// [alignment] - קו העוגן, כשבר מגובה החלון
  /// [epsilon] - סף בפיקסלים שמתחתיו היעד נחשב במקומו
  /// מחזיר null כשאין צורך לזוז — כך שתזוזה של שבר פיקסל לא תירה אנימציה
  /// חדשה שמבטלת את הקודמת.
  static double? glideDelta({
    required double leadingEdge,
    required double viewportHeight,
    required double alignment,
    required double epsilon,
  }) {
    final delta = (leadingEdge - alignment) * viewportHeight;
    if (!delta.isFinite || delta.abs() < epsilon) {
      return null;
    }
    return delta;
  }

  /// האם להזיז את המפרש אל [targetIndex], בהינתן הסנכרון האחרון.
  ///
  /// המפרש זז רק כשהיעד או השורה הנבחרת שממנה הוא נגזר השתנו. הבדיקה היא על
  /// *שינוי* השורה הנבחרת ולא על עצם קיומה: בחירת טקסט פולטת מצב בכל תזוזת
  /// עכבר, ואנימציית הגלילה שנורית מחדש בכל אחת מהן מרעידה את המפרש
  /// (issue #976).
  ///
  /// [targetIndex] - אינדקס היעד במפרש
  /// [selectedMainIndex] - השורה הנבחרת בטקסט הראשי, או null כשאין
  /// [lastSyncedIndex] / [lastSyncedMainIndex] - מה שסונכרן בפעם הקודמת
  static bool shouldMoveCommentary({
    required int targetIndex,
    required int? selectedMainIndex,
    required int? lastSyncedIndex,
    required int? lastSyncedMainIndex,
  }) {
    return targetIndex != lastSyncedIndex ||
        selectedMainIndex != lastSyncedMainIndex;
  }
}

/// אינדקס יעדי הסנכרון של טור מפרש אחד, לפי מספר שורת המקור.
class CommentarySyncIndex {
  const CommentarySyncIndex.empty() : _targets = const [];

  factory CommentarySyncIndex(Iterable<Link> links) {
    final targetBySource = <int, int>{};
    for (final link in links) {
      final current = targetBySource[link.index1];
      if (current == null || link.index2 < current) {
        targetBySource[link.index1] = link.index2;
      }
    }
    final targets = [
      for (final entry in targetBySource.entries)
        (sourceLine: entry.key, targetLine: entry.value),
    ]..sort((a, b) => a.sourceLine.compareTo(b.sourceLine));
    return CommentarySyncIndex._(targets);
  }

  const CommentarySyncIndex._(this._targets);

  final List<({int sourceLine, int targetLine})> _targets;

  /// מחזיר יעד מבוסס אפס לפי הקישור הקודם הקרוב או לפי הראשון כשאין קודם.
  int? targetIndexFor(int logicalMainIndex) {
    if (_targets.isEmpty) return null;

    final mainLine = logicalMainIndex + 1;
    var low = 0;
    var high = _targets.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (_targets[mid].sourceLine <= mainLine) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final target = _targets[low == 0 ? 0 : low - 1];
    return target.targetLine - 1;
  }
}
