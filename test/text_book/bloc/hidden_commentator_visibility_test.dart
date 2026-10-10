import 'dart:async';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/hidden/hidden_titles.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<({List<String> all, Set<String> rare})> getCommentatorsWithRarity(
    TextBook book,
  ) async => (all: ['מפרש מוסתר', 'מפרש גלוי'], rare: <String>{});

  @override
  Future<Map<String, BookSource>> getExternalCommentatorSources(
    TextBook book,
  ) async => const {};

  @override
  Future<String> getBookContent(TextBook book) async => 'תוכן';

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async => const BookContentRange(
    startLine: 0,
    endLine: 0,
    totalLines: 1,
    lines: ['תוכן'],
  );

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
}

Library _library() {
  final hiddenCategory = Category(
    title: 'מוסתרת',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [TextBook(title: 'מפרש מוסתר', categoryId: 1)],
    parent: null,
  );
  final visibleCategory = Category(
    title: 'גלויה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [TextBook(title: 'מפרש גלוי', categoryId: 2)],
    parent: null,
  );
  final library = Library(categories: [hiddenCategory, visibleCategory]);
  hiddenCategory.parent = library;
  visibleCategory.parent = library;
  return library;
}

TextBookLoaded _loaded(TextBook book) => TextBookLoaded(
  book: book,
  content: const ['תוכן'],
  fontSize: 20,
  showLeftPane: true,
  showSplitView: false,
  activeCommentators: const ['מפרש מוסתר', 'מפרש גלוי'],
  commentatorGroups: const [
    CommentatorGroup(
      title: 'מפרשים',
      commentators: ['מפרש מוסתר', 'מפרש גלוי'],
    ),
  ],
  availableCommentators: const ['מפרש מוסתר', 'מפרש גלוי'],
  links: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

Future<TextBookLoaded> _waitFor(
  TextBookBloc bloc,
  bool Function(TextBookLoaded) predicate,
) async {
  final current = bloc.state;
  if (current is TextBookLoaded && predicate(current)) return current;
  return await bloc.stream
      .where((state) => state is TextBookLoaded && predicate(state))
      .cast<TextBookLoaded>()
      .first
      .timeout(const Duration(seconds: 3));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = HiddenLibraryStore();
  late TextBookBloc bloc;
  late TextBook book;
  late Directory dataRoot;

  setUpAll(() async {
    dataRoot = await Directory.systemTemp.createTemp('hidden_commentators_');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  setUp(() async {
    await store.save(const HiddenLibrarySelection());
    DataRepository.instance.library = Future.value(_library());
    book = TextBook(title: 'ספר פתוח', source: BookSource.user);
    bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(book, 0, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() async {
    await bloc.close();
    DataRepository.instance.invalidateLibraryCache();
    await store.save(const HiddenLibrarySelection());
  });

  test('הסתרה חיה מסירה מפרש פעיל וגלוי אך שומרת את הספר הפתוח', () async {
    bloc.emit(_loaded(book));
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    final result = await _waitFor(
      bloc,
      (state) => !state.availableCommentators.contains('מפרש מוסתר'),
    );

    expect(result.book, same(book));
    expect(result.activeCommentators, ['מפרש גלוי']);
    expect(result.commentatorGroups.single.commentators, ['מפרש גלוי']);
  });

  test('בחירה שמורה או ידנית אינה מחזירה מפרש מוסתר לתצוגה', () async {
    bloc.emit(_loaded(book));
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await _waitFor(
      bloc,
      (state) => !state.availableCommentators.contains('מפרש מוסתר'),
    );

    bloc.add(
      const UpdateCommentators(
        ['מפרש מוסתר', 'מפרש גלוי'],
        isUserAction: false,
        isRestore: true,
      ),
    );
    final result = await _waitFor(
      bloc,
      (state) => bloc.userTouchedCommentatorsForTesting,
    );
    expect(result.activeCommentators, ['מפרש גלוי']);
  });

  test('מפרש מוסתר בבחירת פתיחה אינו מופיע בפריים הטעון הראשון', () async {
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await bloc.close();
    final initialBook = TextBook(title: 'ספר פתוח');
    bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(
        initialBook,
        0,
        true,
        const ['מפרש מוסתר', 'מפרש גלוי'],
      ),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );

    final firstLoaded = await _waitFor(bloc, (_) => true);
    expect(firstLoaded.book, same(initialBook));
    expect(firstLoaded.activeCommentators, ['מפרש גלוי']);
  });

  test('ספר מוסתר שנפתח ישירות נשאר פתוח ואינו מסונן כטאב', () async {
    final library = _library();
    DataRepository.instance.library = Future.value(library);
    final hiddenBook = library.subCategories.first.books.single as TextBook;
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await bloc.close();
    bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(hiddenBook, 0, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );

    final result = await _waitFor(bloc, (_) => true);
    expect(result.book, same(hiddenBook));
    expect(result.content, contains('תוכן'));
  });

  test('כשל טעינת הספרייה אינו חוסם פתיחת ספר ישירה', () async {
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await bloc.close();
    final libraryLoad = Completer<Library>();
    DataRepository.instance.library = libraryLoad.future;
    final hiddenTitles = currentHiddenBookTitles();
    final openedBook = TextBook(title: 'ספר פתוח');
    bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(openedBook, 0, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );

    libraryLoad.completeError(StateError('library unavailable'));
    expect(await hiddenTitles, isEmpty);

    final result = await _waitFor(bloc, (_) => true);
    expect(result.book, same(openedBook));
    expect(result.content, contains('תוכן'));
  });

  test('ביטול הסתרה מחזיר מפרש לרשימת הבחירה בלי לבחור אותו בכוח', () async {
    bloc.emit(_loaded(book));
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await _waitFor(
      bloc,
      (state) => !state.availableCommentators.contains('מפרש מוסתר'),
    );

    await store.save(const HiddenLibrarySelection());
    final result = await _waitFor(
      bloc,
      (state) => state.availableCommentators.contains('מפרש מוסתר'),
    );
    expect(result.activeCommentators, ['מפרש גלוי']);
  });

  test('איפוס הגדרות מרוחק מחזיר מפרש לטאב טקסט פתוח', () async {
    bloc.emit(_loaded(book));
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await _waitFor(
      bloc,
      (state) => !state.availableCommentators.contains('מפרש מוסתר'),
    );

    final sync = SettingsSync.instance;
    final previousClear = sync.clearLocally;
    sync.clearLocally = () async {
      await Settings.setValue<String>(HiddenLibraryStore.bookKeysSetting, '[]');
      await Settings.setValue<String>(
        HiddenLibraryStore.categoryPathsSetting,
        '[]',
      );
    };
    addTearDown(() => sync.clearLocally = previousClear);
    expect(
      await sync.handleRequest({'type': SettingsSync.requestReset}),
      isTrue,
    );

    final result = await _waitFor(
      bloc,
      (state) => state.availableCommentators.contains('מפרש מוסתר'),
    );
    expect(result.book, same(book));
  });
}
