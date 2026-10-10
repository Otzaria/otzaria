import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

class _Files extends Fake implements FileSystemData {
  final started = Completer<void>();
  final next = Completer<Library>();
  @override
  String libraryPath = '.';
  @override
  Future<Library> getLibrary() {
    if (!started.isCompleted) started.complete();
    return next.future;
  }
}

class _Repository extends DataRepository {
  _Repository(FileSystemData files) : super(fileSystemData: files);

  int searches = 0;
  Completer<void>? searchGate;

  @override
  Future<({List<Book> books, List<Category> categories})>
  findBooksAndCategories(
    String query,
    Category? category, {
    List<String>? topics,
    bool includeOtzar = false,
    bool includeHebrewBooks = false,
    bool includeLocalHebrewBooks = true,
    List<Book> extraBooks = const [],
    bool sortByRatio = true,
  }) async {
    searches++;
    final found = await super.findBooksAndCategories(
      query,
      category,
      topics: topics,
      includeOtzar: includeOtzar,
      includeHebrewBooks: includeHebrewBooks,
      includeLocalHebrewBooks: includeLocalHebrewBooks,
      extraBooks: extraBooks,
      sortByRatio: sortByRatio,
    );
    await searchGate?.future;
    return found;
  }
}

class _ReadyIndex extends Fake implements TantivyDataProvider {
  @override
  Future<bool> reopenIndex({bool force = false}) async => true;
}

class _Store extends HiddenLibraryStore {
  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

Library _library() {
  final root = Library(categories: []);
  for (final name in ['מבחן א', 'מבחן ב']) {
    root.subCategories.add(
      Category(
        title: name,
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [TextBook(title: '$name ספר')],
        parent: root,
      ),
    );
  }
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryBloc bloc;
  late _Files files;
  late _Repository repo;
  late Library before;
  late TantivyDataProvider previous;
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    files = _Files();
    before = _library();
    previous = TantivyDataProvider.instance;
    TantivyDataProvider.instance = _ReadyIndex();
    repo = _Repository(files)
      ..library = Future.value(before)
      ..localHebrewBooks = Future.value(const []);
    bloc = LibraryBloc(repository: repo, hiddenStore: _Store());
    bloc.emit(LibraryState(library: before, currentCategory: before));
    final done = bloc.stream.firstWhere(
      (s) => s.searchResults != null && !s.isSearching,
    );
    bloc.add(const UpdateSearchQuery('מבחן'));
    bloc.add(const SearchBooks(showLocalHebrewBooks: false));
    await done;
  });
  tearDown(() async {
    final gate = repo.searchGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await bloc.close();
    TantivyDataProvider.instance = previous;
  });
  Future<void> navigate() async {
    final done = bloc.stream.firstWhere(
      (s) => identical(s.currentCategory, before.subCategories.last),
    );
    bloc.add(NavigateToCategory(before.subCategories.last));
    await done;
    expect(bloc.state.searchResults, isNull);
  }

  test(
    'ניווט בזמן רענון משאיר את תיקיית היעד בלי תוצאות איתור',
    () async {
      bloc.add(const RefreshLibrary(source: RefreshSource.customFoldersScan));
      await files.started.future;
      await navigate();
      final done = bloc.stream.firstWhere((s) => !s.isLoading);
      files.next.complete(_library());
      await done;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.currentCategory?.title, 'מבחן ב');
      expect(bloc.state.searchQuery, 'מבחן');
      expect(bloc.state.searchResults, isNull);
      expect(repo.searches, 1);
    },
  );
  test(
    'ניווט בזמן שינוי הסתרות משאיר את תיקיית היעד בלי תוצאות איתור',
    () async {
      repo.library = files.next.future;
      bloc.add(const HiddenBooksChanged());
      await Future<void>.delayed(Duration.zero);
      await navigate();
      final done = bloc.stream.firstWhere((s) => !identical(s.library, before));
      files.next.complete(_library());
      await done;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.currentCategory?.title, 'מבחן ב');
      expect(bloc.state.searchQuery, 'מבחן');
      expect(bloc.state.searchResults, isNull);
      expect(repo.searches, 1);
    },
  );
  test(
    'כשל ברענון אינו מריץ איתור שמוחק את השגיאה',
    () async {
      bloc.add(
        const RefreshLibrary(
          source: RefreshSource.customFoldersScan,
          requestIds: {7},
        ),
      );
      await files.started.future;
      final done = bloc.stream.firstWhere(
        (s) => s.failedRefreshRequestIds != null,
      );
      files.next.completeError(StateError('catalog failed'));
      expect((await done).error, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.error, isNotNull);
      expect(repo.searches, 1);
    },
  );

  for (final hidden in [false, true]) {
    final change = hidden ? 'שינוי הסתרות' : 'רענון';

    Future<void> startChange() async {
      if (hidden) {
        repo.library = files.next.future;
        bloc.add(const HiddenBooksChanged());
        await Future<void>.delayed(Duration.zero);
      } else {
        bloc.add(const RefreshLibrary(source: RefreshSource.customFoldersScan));
        await files.started.future;
      }
    }

    Future<void> finishChange() async {
      final done = bloc.stream.firstWhere((s) => !identical(s.library, before));
      files.next.complete(_library());
      await done;
    }

    test('$change בזמן איתור פעיל מעדכן את התוצאות', () async {
      await startChange();
      final searched = bloc.stream.firstWhere(
        (s) =>
            !identical(s.library, before) &&
            s.searchResults != null &&
            !s.isSearching,
      );
      final after = _library();
      after.subCategories.last.books.clear();
      files.next.complete(after);
      final state = await searched;
      expect(state.searchResults!.map((b) => b.title), ['מבחן א ספר']);
      expect(repo.searches, 2);
    });

    test('ניקוי האיתור בזמן $change אינו מחזיר תוצאות', () async {
      await startChange();
      final cleared = bloc.stream.firstWhere(
        (s) => s.searchResults == null && s.searchQuery == '' && !s.isSearching,
      );
      bloc.add(const UpdateSearchQuery(''));
      bloc.add(const SearchBooks());
      await cleared;
      await finishChange();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.searchQuery, isEmpty);
      expect(bloc.state.searchResults, isNull);
      expect(repo.searches, 1);
    });

    test('איתור חדש בזמן $change משתמש בשאילתה ובאפשרויות העדכניות', () async {
      await startChange();
      final updated = bloc.stream.firstWhere(
        (s) =>
            s.searchQuery == 'נוסף' &&
            !s.isSearching &&
            s.searchResults != null,
      );
      final pluginBook = TextBook(title: 'נוסף מתוסף');
      bloc.add(const UpdateSearchQuery('נוסף'));
      bloc.add(
        SearchBooks(showLocalHebrewBooks: false, extraBooks: [pluginBook]),
      );
      await updated;
      final searched = bloc.stream.firstWhere(
        (s) =>
            !identical(s.library, before) &&
            s.searchResults != null &&
            !s.isSearching,
      );
      await finishChange();
      final state = await searched;
      expect(state.searchQuery, 'נוסף');
      expect(state.searchResults, [pluginBook]);
      expect(repo.searches, 3);
    });

    for (final sameCategory in [false, true]) {
      test(
        'ניווט ${sameCategory ? "לאותה תיקייה" : "למעלה"} בזמן איתור ו$change מבטל את האיתור',
        () async {
          if (!sameCategory) {
            await navigate();
          }
          repo.searchGate = Completer<void>();
          final searching = bloc.stream.firstWhere((s) => s.isSearching);
          bloc.add(const SearchBooks(showLocalHebrewBooks: false));
          await searching;
          await startChange();
          bloc.add(sameCategory ? NavigateToCategory(before) : NavigateUp());
          await Future<void>.delayed(Duration.zero);
          expect(bloc.state.isSearching, isFalse);
          await finishChange();
          repo.searchGate!.complete();
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(bloc.state.currentCategory, same(bloc.state.library));
          expect(bloc.state.searchResults, isNull);
          expect(bloc.state.isSearching, isFalse);
          expect(repo.searches, 2);
        },
      );
    }
  }
}
