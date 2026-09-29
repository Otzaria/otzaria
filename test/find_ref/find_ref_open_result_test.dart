import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

class _FakeRepository implements FindRefRepository {
  _FakeRepository(this.results);

  final List<DbReferenceResult> results;

  @override
  bool get respectHiddenLibrary => false;

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async => results;

  @override
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) async => const [];

  @override
  Future<void> prewarmGlobalAltToc() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTabsRepository implements TabsRepository {
  @override
  List<OpenedTab> loadTabs() => [];
  @override
  Future<void> flushPendingWrites() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _CapturingTabsBloc extends TabsBloc {
  _CapturingTabsBloc() : super(repository: _FakeTabsRepository());

  final List<TabsEvent> events = [];

  @override
  void add(TabsEvent event) => events.add(event);

  OpenedTab get openedTab => events.whereType<OpenOrFocusTab>().single.tab;
}

class _FakeHistoryRepository extends HistoryRepository {
  _FakeHistoryRepository(this._items);

  final List<Bookmark> _items;

  @override
  Future<List<Bookmark>> load() async => _items;

  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => apply(const []);
}

class _FakeNavigationRepository implements NavigationRepository {
  @override
  bool checkLibraryIsEmpty() => false;
  @override
  Future<void> refreshLibrary() async {}
}

class _FakeNavigationBloc extends NavigationBloc {
  _FakeNavigationBloc()
    : super(
        repository: _FakeNavigationRepository(),
        tabsRepository: _FakeTabsRepository(),
      );

  @override
  void add(NavigationEvent event) {}
}

Library _libraryWith(List<Book> books) {
  final library = Library(categories: []);
  final category = Category(
    title: 'תנ"ך',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: library,
  );
  library.subCategories.add(category);
  category.books.addAll(books);
  return library;
}

/// פותח את הדיאלוג, מקליד ולוחץ על [reference]; מחזיר את הטאב שנפתח.
Future<OpenedTab> _openResult(
  WidgetTester tester, {
  required DbReferenceResult result,
  required Library library,
  List<Bookmark> history = const [],
}) async {
  final previousLibrary = DataRepository.instance.cachedLibraryFutureForTesting;
  DataRepository.instance.library = Future.value(library);
  addTearDown(() {
    if (previousLibrary == null) {
      DataRepository.instance.invalidateLibraryCache();
    } else {
      DataRepository.instance.library = previousLibrary;
    }
  });
  FocusRepository().findRefSearchController.clear();
  final bloc = FindRefBloc(findRefRepository: _FakeRepository([result]));
  final tabsBloc = _CapturingTabsBloc();
  final navigationBloc = _FakeNavigationBloc();
  late HistoryBloc historyBloc;
  await tester.runAsync(() async {
    historyBloc = HistoryBloc(_FakeHistoryRepository(history));
    await historyBloc.stream.firstWhere(
      (s) => s.history.length == history.length,
    );
  });
  addTearDown(bloc.close);
  addTearDown(tabsBloc.close);
  addTearDown(navigationBloc.close);
  addTearDown(historyBloc.close);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FocusRepository>.value(value: FocusRepository()),
        BlocProvider<FindRefBloc>.value(value: bloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<HistoryBloc>.value(value: historyBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
      ],
      child: MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const FindRefDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'שאילתה');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.tap(find.text(result.reference));
  await tester.pumpAndSettle();
  return tabsBloc.openedTab;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('תוצאת כותרת בשורה 0 נפתחת בה ולא במיקום מההיסטוריה', (
    tester,
  ) async {
    final book = TextBook(id: 1, title: 'בראשית');
    final tab = await _openResult(
      tester,
      library: _libraryWith([book]),
      history: [Bookmark(ref: 'בראשית', book: book, index: 40)],
      result: const DbReferenceResult(
        title: 'בראשית',
        reference: 'בראשית פרק א',
        segment: 0,
        bookId: 1,
      ),
    );

    expect((tab as TextBookTab).index, 0);
  });

  testWidgets('תוצאה בשורה 0 שומרת את המפרשים מההיסטוריה', (tester) async {
    final book = TextBook(id: 1, title: 'בראשית');
    final tab = await _openResult(
      tester,
      library: _libraryWith([book]),
      history: [
        Bookmark(
          ref: 'בראשית',
          book: book,
          index: 40,
          commentatorsToShow: const ['מפרש'],
        ),
      ],
      result: const DbReferenceResult(
        title: 'בראשית',
        reference: 'בראשית פרק א',
        segment: 0,
        bookId: 1,
      ),
    );

    expect((tab as TextBookTab).index, 0);
    expect(tab.commentators, ['מפרש']);
  });

  testWidgets('בבלי כ-PDF: טאב הטקסט החלופי בשורה 0 שומר את המפרשים', (
    tester,
  ) async {
    await Settings.setValue<String>(
      SettingsRepository.keyTalmudBavliOpenFormat,
      'pdf',
    );
    addTearDown(
      () => Settings.setValue<String>(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'text',
      ),
    );
    final library = Library(categories: []);
    final bavliRoot = Category(
      title: 'תלמוד בבלי',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: library,
    );
    library.subCategories.add(bavliRoot);
    final seder = Category(
      title: 'סדר זרעים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: bavliRoot,
    );
    bavliRoot.subCategories.add(seder);
    final text = TextBook(id: 3, title: 'ברכות', category: seder);
    seder.books.add(text);
    bavliRoot.books.add(
      PdfBook(
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
        category: bavliRoot,
      ),
    );

    final tab = await _openResult(
      tester,
      library: library,
      history: [
        Bookmark(
          ref: 'ברכות',
          book: text,
          index: 40,
          commentatorsToShow: const ['מפרש'],
        ),
      ],
      result: const DbReferenceResult(
        title: 'ברכות',
        reference: 'ברכות דף ב',
        segment: 0,
        bookId: 3,
      ),
    );

    final fallback = (tab as ResolvingTab).fallbackTab as TextBookTab;
    expect(fallback.index, 0);
    expect(fallback.commentators, ['מפרש']);
  });

  testWidgets('תוצאת ספר בלבד ממשיכה מהמיקום שבהיסטוריה', (tester) async {
    final book = TextBook(id: 1, title: 'בראשית');
    final tab = await _openResult(
      tester,
      library: _libraryWith([book]),
      history: [Bookmark(ref: 'בראשית', book: book, index: 40)],
      result: const DbReferenceResult(
        title: 'בראשית',
        reference: 'בראשית',
        segment: 0,
        bookId: 1,
      ),
    );

    expect((tab as TextBookTab).index, 40);
  });

  testWidgets('תוצאת PDF נפתחת עם הספר מהעץ ולא עם עותק לפי נתיב', (
    tester,
  ) async {
    final pdf = PdfBook(id: 5, title: 'ספר סרוק', path: r'C:\books\scan.pdf');
    final tab = await _openResult(
      tester,
      library: _libraryWith([pdf]),
      result: const DbReferenceResult(
        title: 'ספר סרוק',
        reference: 'ספר סרוק פרק ב',
        segment: 7,
        isPdf: true,
        filePath: r'C:\books\scan.pdf',
      ),
    );

    expect((tab as PdfBookTab).book, same(pdf));
    expect(tab.pageNumber, 7);
  });

  testWidgets('PDF שאינו בעץ נפתח לפי הנתיב', (tester) async {
    final tab = await _openResult(
      tester,
      library: _libraryWith([]),
      result: const DbReferenceResult(
        title: 'ספר סרוק',
        reference: 'ספר סרוק פרק ב',
        segment: 7,
        isPdf: true,
        filePath: r'C:\books\scan.pdf',
      ),
    );

    expect((tab as PdfBookTab).book.path, r'C:\books\scan.pdf');
    expect(tab.book.id, isNull);
  });
}
