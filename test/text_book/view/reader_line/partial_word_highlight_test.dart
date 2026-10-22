import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

const _line = 'הארץ ה';

bool _partialHighlight(String searchText, {bool wholeWord = false}) {
  final state = TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const [_line],
    fontSize: 20,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: searchText,
    searchWholeWord: wholeWord,
  );
  final context = ReaderLineContext(
    state: state,
    lines: const [_line],
    profile: TextDisplayProfile.defaults,
    lineHtml: (_) => _line,
    fontSize: 20,
    lineHeight: 1.5,
  );
  return buildReaderLineSpec(0, context).settings.partialWordHighlight;
}

/// ההדגשה בגוף הספר חייבת לעקוב אחרי החיפוש: אות אחת נמצאת כמילה שלמה גם
/// במצב חלק ממילה, ולכן גם לא מודגשת בתוך מילים.
void main() {
  test('אות אחת — הדגשה במילים שלמות', () {
    expect(_partialHighlight('ה'), isFalse);
    expect(_partialHighlight(' ה '), isFalse);
  });

  test('שתי אותיות ומעלה — הדגשה בתוך מילים', () {
    expect(_partialHighlight('הא'), isTrue);
    expect(_partialHighlight('כם '), isTrue);
  });

  test('במילים שלמות אין שינוי', () {
    expect(_partialHighlight('הא', wholeWord: true), isFalse);
  });
}
