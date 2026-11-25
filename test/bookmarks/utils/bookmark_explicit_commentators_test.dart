import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/bookmarks/utils/section_bookmark.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

class _Book extends TextBook {
  _Book() : super(title: 'ספר בדיקה');

  @override
  Future<List<TocEntry>> get tableOfContents async => const [];
}

class _MemoryBookmarkRepository implements BookmarkRepository {
  List<Bookmark> _bookmarks = [];

  @override
  Future<List<Bookmark>> loadBookmarks() async => List.of(_bookmarks);

  @override
  Future<List<Bookmark>> mutateBookmarks(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => _bookmarks = List.of(apply(List.of(_bookmarks)));

  @override
  Future<List<BookmarkGroup>> loadGroups() async => const [];

  @override
  Stream<void> get remoteChanges => const Stream<void>.empty();

  @override
  Stream<void> get groupsRemoteChanges => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TextBookLoaded _loaded(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  hasExplicitCommentators: true,
  commentatorGroups: const [],
  availableCommentators: const ['רש"י'],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  removePunctuation: false,
  visibleIndices: const [0],
  continuousReadingMode: true,
  searchText: '',
);

/// שומר את [bookmark] כ-JSON ופותח ממנו טאב, כמו סימנייה או היסטוריה.
TextBookTab _reopen(Bookmark bookmark) {
  final tab = tabFromBookmark(Bookmark.fromJson(bookmark.toJson()));
  addTearDown(tab.dispose);
  return tab as TextBookTab;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  test('בחירה ריקה מפורשת בספר טעון נשמרת בסימנייה ונפתחת ריקה', () async {
    final book = _Book();
    final tab = TextBookTab(
      book: book,
      index: 0,
      blocOverride: StubTextBookBloc(_loaded(book)),
    );
    addTearDown(tab.dispose);

    final bookmark = (await bookmarkFromReadingTab(tab))!;

    expect(_reopen(bookmark).commentators, equals(const <String>[]));
  });

  test('בחירה ריקה מפורשת בטאב שלא נטען נשמרת בסימנייה', () async {
    final tab = TextBookTab(book: _Book(), index: 0, commentators: const []);
    addTearDown(tab.dispose);

    final bookmark = (await bookmarkFromReadingTab(
      tab,
      useStoredPositionFallback: true,
    ))!;

    expect(_reopen(bookmark).commentators, equals(const <String>[]));
  });

  testWidgets('סימנייה לקטע אחרי כיבוי כל המפרשים נפתחת בלי מפרשים', (
    tester,
  ) async {
    final repository = _MemoryBookmarkRepository();
    final bloc = BookmarkBloc(repository);
    addTearDown(bloc.close);
    late BuildContext context;
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    await addTextSectionBookmark(context, _loaded(_Book()), 0);
    await tester.pump();

    final saved = (await repository.loadBookmarks()).single;
    expect(_reopen(saved).commentators, equals(const <String>[]));
  });

  test('סימנייה ישנה עם רשימה ריקה ממשיכה לקבל את ברירת המחדל', () {
    final legacy = Bookmark.fromJson({
      'ref': 'ספר בדיקה',
      'index': 0,
      'book': TextBook(title: 'ספר בדיקה').toJson(),
      'commentatorsToShow': <String>[],
    });

    expect(_reopen(legacy).commentators, isNull);
  });
}
