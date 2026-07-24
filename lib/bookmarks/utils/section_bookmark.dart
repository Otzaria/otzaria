import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// מספר המילים הראשונות של הקטע שנלכדות כתיאור ברירת המחדל של הסימניה.
const int _bookmarkLabelWords = 7;

/// מוסיף סימניה לקטע [index] בספר טקסט פתוח, עם תיאור ברירת מחדל הנגזר
/// מהמילים הראשונות של הקטע. מציג הודעת הצלחה/קיים.
Future<void> addTextSectionBookmark(
  BuildContext context,
  TextBookLoaded state,
  int index,
) async {
  final ref = addBookTitleToRef(
    await refFromIndex(index, state.book.tableOfContents),
    state.book.title,
  );
  if (!context.mounted) return;

  String? label;
  if (index >= 0 && index < state.content.length) {
    final extracted = extractDisplayTextFromLine(
      state.content[index],
      maxWords: _bookmarkLabelWords,
      excludeBookTitle: state.book.title,
    );
    if (extracted.isNotEmpty) label = extracted;
  }

  final added = context.read<BookmarkBloc>().addBookmark(
    ref: ref,
    book: state.book,
    index: index,
    commentatorsToShow: state.activeCommentators,
    label: label,
  );
  UiSnack.showQuick(
    added ? NotesMessages.bookmarkAdded : NotesMessages.bookmarkAlreadyExists,
  );
}
