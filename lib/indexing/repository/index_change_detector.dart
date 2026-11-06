import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// שלב הבדיקה של ריצת אינדוקס: אילו ספרים מאונדקסים התיישנו מול מקורם.
abstract interface class IndexChangeDetector {
  /// ספרים שיש להחליף; null כשבוטל. [onMetadataOnlyChanged] מציין שינוי
  /// מטא־דאטה ללא שינוי תוכן ידוע.
  /// בין ספרים נקרא [waitWhilePaused]; [onProgress] מדווח (0, total) ואחריו כל ספר.
  Future<List<Book>?> detectChanged(
    List<Book> candidates, {
    required Library library,
    required bool Function() isCancelled,
    required Future<void> Function() waitWhilePaused,
    void Function(Book book)? onMetadataOnlyChanged,
    void Function(int processed, int total)? onProgress,
  });
}
