import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

/// תוסף ששלח רשימה חדשה מריץ שוב את החיפוש המוצג (`keepPreview`): הספר
/// שהמשתמש בחר נשאר בתצוגה המקדימה, אם הוא עדיין בתוצאות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LibraryBloc bloc;
  late TextBook libraryBook;
  late ExternalLibraryBook pluginBook;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    libraryBook = TextBook(id: 7, title: 'שו"ת אבני נזר');
    pluginBook = ExternalLibraryBook(
      title: 'אבני נזר',
      id: 7,
      link: '',
      externalLibraryId: 'mylib:7',
    );
    final library = Library(
      categories: [
        Category(
          title: 'שו"ת',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [libraryBook],
          parent: null,
        ),
      ],
    );
    final repository = DataRepository()
      ..library = Future.value(library)
      ..localHebrewBooks = Future.value(const []);
    bloc = LibraryBloc(repository: repository);
    bloc.emit(
      const LibraryState().copyWith(library: library, searchQuery: 'אבני נזר'),
    );
  });

  tearDown(() => bloc.close());

  Future<LibraryState> search(SearchBooks event) {
    final done = bloc.stream.firstWhere(
      (state) => !state.isSearching && state.searchResults != null,
    );
    bloc.add(event);
    return done;
  }

  test('חיפוש רגיל בוחר את ספר הטקסט הראשון', () async {
    final state = await search(SearchBooks(extraBooks: [pluginBook]));
    expect(state.previewBook, same(libraryBook));
  });

  test('keepPreview משאיר את הספר שנבחר כשהוא עדיין בתוצאות', () async {
    await search(SearchBooks(extraBooks: [pluginBook]));
    bloc.add(SelectBookForPreview(pluginBook));
    await Future<void>.delayed(Duration.zero);

    final kept = await search(
      SearchBooks(extraBooks: [pluginBook], keepPreview: true),
    );
    expect(kept.previewBook, same(pluginBook));

    final typed = await search(SearchBooks(extraBooks: [pluginBook]));
    expect(typed.previewBook, same(libraryBook));
  });

  test('keepPreview בוחר מחדש כשהספר שנבחר כבר אינו בתוצאות', () async {
    await search(SearchBooks(extraBooks: [pluginBook]));
    bloc.add(SelectBookForPreview(pluginBook));
    await Future<void>.delayed(Duration.zero);

    final state = await search(const SearchBooks(keepPreview: true));
    expect(state.previewBook, same(libraryBook));
  });

  Future<LibraryState> selectTopics(List<String> topics) {
    final selected = bloc.stream.firstWhere(
      (state) => identical(state.selectedTopics, topics),
    );
    bloc.add(SelectTopics(topics));
    return selected;
  }

  test('topic preview prefers the first matching text book', () async {
    final ignoredText = TextBook(title: 'Other topic', topics: 'אגדה');
    final matchingPdf = PdfBook(
      title: 'PDF',
      path: 'book.pdf',
      topics: 'מדרש, הלכה',
    );
    final matchingText = TextBook(
      title: 'Matching text',
      topics: 'אגדה, הלכה ',
    );
    bloc.emit(
      bloc.state.copyWith(
        searchResults: [ignoredText, matchingPdf, matchingText],
        previewBook: ignoredText,
      ),
    );

    final selected = await selectTopics(['הלכה']);
    expect(selected.previewBook, same(matchingText));
  });

  test('topic preview falls back to the first PDF when no text matches',
      () async {
    final ignored = PdfBook(title: 'Other', path: 'a.pdf', topics: 'אגדה');
    final matching = PdfBook(title: 'Match', path: 'b.pdf', topics: 'הלכה');
    bloc.emit(
      bloc.state.copyWith(
        searchResults: [ignored, matching],
        previewBook: ignored,
      ),
    );

    final selected = await selectTopics(['הלכה']);
    expect(selected.previewBook, same(matching));
  });

  test('no matching topic clears a stale search preview', () async {
    final existing = TextBook(title: 'Book', topics: 'אגדה');
    bloc.emit(
      bloc.state.copyWith(searchResults: [existing], previewBook: existing),
    );

    final selected = await selectTopics(['הלכה']);
    expect(selected.previewBook, isNull);
    expect(selected.selectedTopics, ['הלכה']);
  });
}
