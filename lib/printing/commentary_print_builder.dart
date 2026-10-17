import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/printing/commentary_print_limit.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פותר את תוכן הקישור (טקסט המפרש). ניתן להזרקה בבדיקות.
typedef CommentaryContentResolver = Future<String> Function(Link link);

/// תוכן הקישור עם הערות השוליים שהוצאו מהשורה למסד, בחזרה במקומן.
Future<String> contentWithBookNotes(Link link) async {
  final content = await link.content;
  // קטע שמשתרע על כמה שורות — ההערות ממופות לשורה אחת בלבד.
  if (link.index2End != null && link.index2End != link.index2) return content;
  final notes = await BookNotesRepository.instance.notesFor(
    getTitleFromPath(link.path2),
    categoryId: link.targetCategoryId,
    source: link.targetSource,
    fileType: link.targetFileType,
  );
  return rehydrateInlineNotes(content, notes.notesAt(link.index2 - 1));
}

/// בונה בלוקי מפרשים להדפסה; [keepHtml] משמר את התגיות כדי להחיל את פרופיל
/// הייצוא לפני ניקוי HTML. מפרש עם הגבלת הדפסה של המו"ל נחתך למספר השורות המותר.
Future<List<PrintBlock>> buildCommentaryPrintBlocks(
  List<LinkGroup> groups, {
  CommentaryContentResolver? contentResolver,
  Future<BookProtection> Function(Link link)? protectionResolver,
  bool keepHtml = false,
}) async {
  final resolve = contentResolver ?? contentWithBookNotes;
  final limit = CommentaryPrintLimit(protectionResolver: protectionResolver);
  final blocks = <PrintBlock>[];

  for (final group in groups) {
    final groupBlocks = <PrintBlock>[];
    for (final original in group.links) {
      final link = await limit.take(original);
      if (link == null) continue;
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
