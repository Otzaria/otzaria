import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// בהדגשת חיפוש במדיניות שאינה סטנדרטית רק שורה שהמנוע החזיר משתתפת;
/// searchResultLines שהוא null (אין תוצאות מנוע ידועות) חוסם כל שורה.
void main() {
  group('TextBookLoaded.lineParticipatesInSearchHighlight', () {
    test('null — אין תוצאות מנוע ידועות — חוסם כל שורה', () {
      final state = _loadedState(searchResultLines: null);
      expect(state.lineParticipatesInSearchHighlight(0), isFalse);
      expect(state.lineParticipatesInSearchHighlight(389), isFalse);
    });

    test('סט מוסמך: שורה שהמנוע החזיר משתתפת', () {
      final state = _loadedState(searchResultLines: {3, 7});
      expect(state.lineParticipatesInSearchHighlight(7), isTrue);
    });

    test('סט מוסמך: שורה שהמנוע לא החזיר אינה משתתפת', () {
      final state = _loadedState(searchResultLines: {3, 7});
      expect(state.lineParticipatesInSearchHighlight(5), isFalse);
    });

    test('סט ריק — חיפוש רץ ולא החזיר דבר — חוסם הכל', () {
      final state = _loadedState(searchResultLines: const {});
      expect(state.lineParticipatesInSearchHighlight(0), isFalse);
    });
  });
}

TextBookLoaded _loadedState({Set<int>? searchResultLines}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    contentVersion: 0,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    selectedLinkTypes: const {},
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndices: const {},
    pinLeftPane: false,
    searchText: 'אמר רבי',
    searchResultLines: searchResultLines,
  );
}
