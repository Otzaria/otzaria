import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

TextBookLoaded _state(BookProtection protection) => TextBookLoaded(
  book: TextBook(title: 'ספר'),
  protection: protection,
  showLeftPane: false,
  content: const ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  removePunctuation: false,
  visibleIndices: const [0],
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
  searchMode: SearchMode.exact,
);

const _copyLimit = BookProtection.copySegmentLimit;

List<String> _lines(int count) => [for (var i = 1; i <= count; i++) 'שורה $i'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ספירת שורות', () {
    test('countTextSegments סופר שורות לא ריקות, לפחות 1', () {
      expect(countTextSegments('א\n\nב\n  \nג'), 3);
      expect(countTextSegments(''), 1);
    });

    test('selectionSegmentCount מעדיף את טווח שורות המקור', () {
      expect(selectionSegmentCount(start: 3, end: 9, text: 'א'), 7);
      expect(selectionSegmentCount(start: 4, end: 4, text: 'א\nב\nג'), 1);
      expect(selectionSegmentCount(text: 'א\nב'), 2);
    });

    test('limitTextToCopySegments שומר רק את השורות המותרות', () {
      final text = _lines(_copyLimit + 2).join('\n');
      expect(
        limitTextToCopySegments(const BookProtection(level: 1), text),
        _lines(_copyLimit).join('\n'),
      );
      expect(limitTextToCopySegments(BookProtection.none, text), text);
    });

    test('ensureCopyAllowed חוסם מעל המגבלה בספר מוגן', () {
      const p = BookProtection(level: 1);
      expect(ensureCopyAllowed(p, _copyLimit), isTrue);
      expect(ensureCopyAllowed(p, _copyLimit + 1), isFalse);
      expect(ensureCopyAllowed(BookProtection.none, 600), isTrue);
    });
  });

  group('copySelectedTextForBook', () {
    late List<String> copied;

    setUp(() {
      copied = [];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
    });

    tearDown(() => debugSelectedTextCopyHandler = null);

    Future<void> copy(
      BookProtection stateProtection, {
      BookProtection? protection,
      int? segmentCount,
      String? text,
    }) => copySelectedTextForBook(
      plainText: text ?? _lines(_copyLimit + 1).join('\n'),
      selectedIndex: 0,
      sourceContent: _lines(_copyLimit + 2),
      textBookState: _state(stateProtection),
      settingsState: SettingsState.initial().copyWith(copyWithHeaders: 'none'),
      fontFamily: 'x',
      fontSize: 12,
      protection: protection,
      segmentCount: segmentCount,
    );

    test('ספר מוגן — שורה מעל המגבלה נחסמת והלוח לא נדרס', () async {
      await copy(const BookProtection(level: 1), segmentCount: _copyLimit + 1);
      expect(copied, isEmpty);
    });

    test('ספר מוגן — עד המגבלה מועתק', () async {
      await copy(
        const BookProtection(level: 2),
        segmentCount: _copyLimit,
        text: _lines(_copyLimit).join('\n'),
      );
      expect(copied, hasLength(1));
    });

    test('בלי טווח ידוע נספרות שורות הטקסט', () async {
      await copy(const BookProtection(level: 1));
      expect(copied, isEmpty);
    });

    test('ספר ללא הגבלה — בחירה ארוכה מועתקת', () async {
      await copy(BookProtection.none, segmentCount: 50);
      expect(copied, hasLength(1));
    });

    test('הגבלה מפורשת (מפרש) גוברת על הגבלת הספר הראשי', () async {
      await copy(
        BookProtection.none,
        protection: const BookProtection(level: 1),
        segmentCount: _copyLimit + 1,
      );
      expect(copied, isEmpty);
    });
  });
}
