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
  _Files(this.next);
  Library next;
  @override
  String libraryPath = '.';
  @override
  Future<Library> getLibrary() async => next;
}

class _ReadyIndex extends Fake implements TantivyDataProvider {
  @override
  Future<bool> reopenIndex({bool force = false}) async => true;
}

class _EmptyHiddenStore extends HiddenLibraryStore {
  const _EmptyHiddenStore();
  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

Library _library(List<String> titles) {
  final library = Library(categories: []);
  library.subCategories.add(
    Category(
      title: 'ספרים אישיים',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [for (final t in titles) TextBook(title: t)],
      parent: library,
    ),
  );
  return library;
}

Future<(LibraryBloc, _Files, Library)> _searchedBloc() async {
  await Settings.init(cacheProvider: MemorySettingsCache());
  final previousFiles = FileSystemData.instance;
  final previousIndex = TantivyDataProvider.instance;
  final before = _library(['מבחן ראשון', 'מבחן שני']);
  final files = _Files(before);
  FileSystemData.instance = files;
  TantivyDataProvider.instance = _ReadyIndex();
  final repository = DataRepository(fileSystemData: files)
    ..library = Future.value(before)
    ..localHebrewBooks = Future.value(const []);
  final bloc = LibraryBloc(
    hiddenStore: const _EmptyHiddenStore(),
    repository: repository,
  );
  addTearDown(() async {
    await bloc.close();
    FileSystemData.instance = previousFiles;
    TantivyDataProvider.instance = previousIndex;
  });
  bloc.emit(
    LibraryState(library: before, currentCategory: before, isLoading: false),
  );

  bloc.add(const UpdateSearchQuery('מבחן'));
  final searched = bloc.stream.firstWhere(
    (s) => !s.isSearching && s.searchResults != null,
  );
  bloc.add(const SearchBooks());
  expect((await searched).searchResults, hasLength(2));
  return (bloc, files, before);
}

Future<LibraryState> _refreshTo(LibraryBloc bloc, Library before) {
  final settled = bloc.stream
      .firstWhere(
        (s) => s.library != before && !s.isLoading && s.searchResults != null,
      )
      .timeout(const Duration(seconds: 5), onTimeout: () => bloc.state);
  bloc.add(RefreshLibrary());
  return settled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('רענון הספרייה מריץ שוב את האיתור הפעיל על העץ החדש', () async {
    final (bloc, files, before) = await _searchedBloc();

    // מחיקת ספר מתוך תוצאות האיתור שולחת RefreshLibrary.
    files.next = _library(['מבחן ראשון']);
    final after = await _refreshTo(bloc, before);

    expect(after.searchQuery, 'מבחן');
    expect(after.searchResults?.map((b) => b.title).toList(), ['מבחן ראשון']);
  });

  test('רענון בזמן עיון בתיקייה אינו מחזיר את תוצאות האיתור', () async {
    final (bloc, files, before) = await _searchedBloc();
    // מעבר לתיקייה מאפס את התוצאות, והטקסט נשאר בתיבה.
    bloc.add(NavigateToCategory(before.subCategories.single));
    await bloc.stream.firstWhere((s) => s.searchResults == null);

    files.next = _library(['מבחן ראשון']);
    final after = await _refreshTo(bloc, before);

    expect(after.searchQuery, 'מבחן');
    expect(after.searchResults, isNull);
  });
}
