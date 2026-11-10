import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';

TextBookLoaded _state({Set<int> selected = const {}}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['א', 'ב', 'ג'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0, 1, 2],
  selectedIndices: selected,
  pinLeftPane: false,
  searchText: '',
);

void main() {
  // issue #4664 — שורה קשורה בטור מפרש מסומנת בסמן צד, כמו הבחירה בטקסט הראשי,
  // ולא ברקע.
  test('שורת מפרש קשורה: סמן צד בלי רקע', () {
    final marks = readerLineMarks(
      _state(),
      1,
      isMainText: false,
      isRelated: true,
    );
    expect(marks.isSelected, isTrue);
    expect(marks.background, ReaderLineBackground.none);
  });

  test('שורת מפרש שאינה קשורה: בלי סמן ובלי רקע', () {
    final marks = readerLineMarks(_state(), 1, isMainText: false);
    expect(marks.isSelected, isFalse);
    expect(marks.background, ReaderLineBackground.none);
  });

  test('בטקסט הראשי הבחירה נקבעת לפי השורות הנבחרות, ולא לפי isRelated', () {
    final state = _state(selected: {1});
    expect(readerLineMarks(state, 1, isRelated: true).isSelected, isTrue);
    expect(readerLineMarks(state, 0, isRelated: true).isSelected, isFalse);
  });
}
