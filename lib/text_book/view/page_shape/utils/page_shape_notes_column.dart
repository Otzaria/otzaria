import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;

/// תוכן טור "הערות" בצורת הדף: שורה לכל הערה של הספר, וקישור מכל הערה לשורת
/// המקור שלה — כך שהסנכרון וההדגשה של טורי המפרשים חלים עליו כמו על ספר מפרש.
({List<String> content, List<Link> links}) buildPageShapeNotesColumn(
  List<String> content,
  BookNotes dbNotes,
) {
  final lineIndexes = <int>{
    ...dbNotes.lineIndexes,
    for (var i = 0; i < content.length; i++)
      if (content[i].contains('footnote')) i,
  }.toList()..sort();

  final rows = <String>[];
  final links = <Link>[];
  for (final lineIndex in lineIndexes) {
    for (final note in notes.notesForLines(content, [
      lineIndex,
    ], dbNotes: dbNotes)) {
      rows.add(note);
      links.add(
        Link(
          heRef: kNotesCommentatorTitle,
          index1: lineIndex + 1,
          path2: kNotesCommentatorTitle,
          index2: rows.length,
          connectionType: LinkTypes.commentary,
        ),
      );
    }
  }
  return (content: rows, links: links);
}
