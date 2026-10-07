import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פותר את תוכן הקישור (טקסט המפרש). ניתן להזרקה בבדיקות.
typedef CommentaryContentResolver = Future<String> Function(Link link);

/// בונה רשימת בלוקי הדפסה ([PrintBlock]) מתוך קבוצות המפרשים המוצגות
/// בכרטיסיית המפרשים (זהה גם לטקסט וגם ל-PDF).
///
/// לכל קבוצה ([LinkGroup]) נוצרת כותרת ([PrintBlockKind.commentaryGroupTitle])
/// ומתחתיה בלוק תוכן ([PrintBlockKind.commentary]) לכל קטע פירוש.
/// התוכן עובר ניקוי HTML בלבד — הסרת ניקוד/טעמים והחלפת שמות קודש מתבצעות
/// בשלב יצירת ה-PDF לפי בחירת המשתמש במסך ההדפסה.
///
/// [groups] - קבוצות המפרשים בסדר התצוגה.
/// [contentResolver] - פותר תוכן חלופי (לבדיקות); ברירת מחדל היא [Link.content].
///
/// מפרש עם הגבלת הדפסה של המו"ל נחתך למספר השורות המותר לו.
///
/// מחזירה [Future<List<PrintBlock>>] - בלוקים מוכנים להדפסה (ריק אם אין תוכן).
Future<List<PrintBlock>> buildCommentaryPrintBlocks(
  List<LinkGroup> groups, {
  CommentaryContentResolver? contentResolver,
  Future<BookProtection> Function(Link link)? protectionResolver,
}) async {
  final resolve = contentResolver ?? (Link link) => link.content;
  final protectionOf =
      protectionResolver ?? BookProtectionRepository.instance.forLink;
  final blocks = <PrintBlock>[];

  for (final group in groups) {
    final groupBlocks = <PrintBlock>[];
    final maxSegments = group.links.isEmpty
        ? null
        : (await protectionOf(group.links.first)).maxPrintSegments;
    var segments = 0;
    for (final link in group.links) {
      if (maxSegments != null) {
        segments += (link.index2End ?? link.index2) - link.index2 + 1;
        if (segments > maxSegments) break;
      }
      String text;
      try {
        text = stripHtmlIfNeeded(await resolve(link)).trim();
      } catch (e) {
        // הקטע יושמט מהפלט המודפס — לוג כדי שהחוסר יהיה ניתן לאבחון
        debugPrint(
          '[Print] commentary resolve failed for '
          '"${group.bookTitle}" (${link.path2}): $e',
        );
        continue;
      }
      if (text.isEmpty) continue;
      groupBlocks.add(PrintBlock(kind: PrintBlockKind.commentary, text: text));
    }

    if (groupBlocks.isEmpty) continue;
    blocks.add(
      PrintBlock(
        kind: PrintBlockKind.commentaryGroupTitle,
        text: group.bookTitle,
      ),
    );
    blocks.addAll(groupBlocks);
  }

  return blocks;
}
