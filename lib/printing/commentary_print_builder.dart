import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פותר את תוכן הקישור (טקסט המפרש). ניתן להזרקה בבדיקות.
typedef CommentaryContentResolver = Future<String> Function(Link link);

/// בונה בלוקי מפרשים להדפסה; [keepHtml] משמר את התגיות כדי להחיל את פרופיל
/// הייצוא לפני ניקוי HTML. מפרש עם הגבלת הדפסה של המו"ל נחתך למספר השורות המותר.
Future<List<PrintBlock>> buildCommentaryPrintBlocks(
  List<LinkGroup> groups, {
  CommentaryContentResolver? contentResolver,
  Future<BookProtection> Function(Link link)? protectionResolver,
  bool keepHtml = false,
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
        segments += linkSegmentCount(link);
        if (segments > maxSegments) break;
      }
      String text;
      try {
        final content = await resolve(link);
        final plainText = stripHtmlIfNeeded(content).trim();
        if (plainText.isEmpty) continue;
        text = keepHtml ? content.trim() : plainText;
      } catch (e) {
        // הקטע יושמט מהפלט המודפס — לוג כדי שהחוסר יהיה ניתן לאבחון
        debugPrint(
          '[Print] commentary resolve failed for '
          '"${group.bookTitle}" (${link.path2}): $e',
        );
        continue;
      }
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
