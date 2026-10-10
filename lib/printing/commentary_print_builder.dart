import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פותר את תוכן הקישור (טקסט המפרש). ניתן להזרקה בבדיקות.
typedef CommentaryContentResolver = Future<String> Function(Link link);

/// בונה בלוקי מפרשים להדפסה; [keepHtml] משמר את התגיות כדי להחיל את פרופיל
/// הייצוא לפני ניקוי HTML. ברירת המחדל מחזירה טקסט פשוט.
Future<List<PrintBlock>> buildCommentaryPrintBlocks(
  List<LinkGroup> groups, {
  CommentaryContentResolver? contentResolver,
  bool keepHtml = false,
}) async {
  final resolve = contentResolver ?? (Link link) => link.content;
  final blocks = <PrintBlock>[];

  for (final group in groups) {
    final groupBlocks = <PrintBlock>[];
    for (final link in group.links) {
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
