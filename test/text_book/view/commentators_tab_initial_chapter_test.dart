import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';

TextBookLoaded _loaded(TextBook book, {int? selectedIndex}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב', 'שורה ג'],
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
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: selectedIndex,
    searchText: '',
    currentTitle: 'סימן א',
    searchMode: SearchMode.exact,
  );
}

void main() {
  group('shouldNotifyCommentatorsTabListener', () {
    final book = TextBook(title: 'ספר בדיקה');

    test('פועל במעבר הראשון למצב טעון (רגרסיה: פתרון פרק התחלתי)', () {
      // TextBookLoading → TextBookLoaded — חייב להחזיר true גם כש-selectedIndex
      // נשאר null, אחרת הפרק ההתחלתי לעולם לא נפתר והמפרשים לא מוצגים.
      final loading = TextBookLoading(book, 5, false, const []);
      final loaded = _loaded(book, selectedIndex: null);
      expect(shouldNotifyCommentatorsTabListener(loading, loaded), isTrue);
    });

    test('פועל גם במעבר מ-TextBookInitial למצב טעון', () {
      final initial = TextBookInitial.named(book, 5, false, const []);
      final loaded = _loaded(book, selectedIndex: null);
      expect(shouldNotifyCommentatorsTabListener(initial, loaded), isTrue);
    });

    test('פועל כשמשתנה selectedIndex בין שני מצבים טעונים', () {
      final a = _loaded(book, selectedIndex: 3);
      final b = _loaded(book, selectedIndex: 7);
      expect(shouldNotifyCommentatorsTabListener(a, b), isTrue);
    });

    test('לא פועל כש-selectedIndex זהה בין שני מצבים טעונים', () {
      final a = _loaded(book, selectedIndex: 3);
      final b = _loaded(book, selectedIndex: 3);
      expect(shouldNotifyCommentatorsTabListener(a, b), isFalse);
    });

    test('לא פועל כשהמצב החדש אינו טעון', () {
      final loaded = _loaded(book, selectedIndex: 3);
      final loading = TextBookLoading(book, 5, false, const []);
      expect(shouldNotifyCommentatorsTabListener(loaded, loading), isFalse);
    });
  });
}
