import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../helpers/memory_settings_cache.dart';

class _Store extends HiddenLibraryStore {
  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

class _Files extends Fake implements FileSystemData {
  _Files(this.library);
  final Library library;

  @override
  Future<Library> getLibrary({bool sharePendingReaderMetadata = false}) async =>
      library;
}

Library _library(String title) {
  final root = Library(categories: []);
  root.subCategories.add(
    Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [TextBook(title: '$title ספר')],
      parent: root,
    ),
  );
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DataRepository repo;
  late Library before;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    before = _library('לפני');
    repo = DataRepository()..library = Future.value(before);
  });

  LibraryBloc loaded() {
    final bloc = LibraryBloc(repository: repo, hiddenStore: _Store());
    bloc.emit(LibraryState(library: before, currentCategory: before));
    return bloc;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  for (final remove in [false, true]) {
    test(
      'שינוי נתיב היברובוקס מסנכרן את העץ בחלון האחר: remove=$remove',
      () async {
        final oldFiles = FileSystemData.instance;
        final oldLibrary =
            DataRepository.instance.cachedLibraryFutureForTesting;
        final folder = Directory.systemTemp.createTempSync('hebrew-books-path');
        addTearDown(() {
          FileSystemData.instance = oldFiles;
          if (oldLibrary != null) {
            DataRepository.instance.library = oldLibrary;
          } else {
            DataRepository.instance.invalidateLibraryCache();
          }
          folder.deleteSync();
        });
        repo = DataRepository.instance..library = Future.value(before);
        final after = _library('אחרי');
        FileSystemData.instance = _Files(after);
        final a = loaded();
        final b = loaded();
        addTearDown(a.close);
        addTearDown(b.close);
        final sourceUpdated = a.stream.firstWhere(
          (state) => identical(state.library, after) && !state.isLoading,
        );
        a.add(
          remove
              ? const RemoveHebrewBooksPath()
              : UpdateHebrewBooksPath(folder.path),
        );
        await sourceUpdated;
        await settle();

        expect(b.state.library!.subCategories.single.title, 'אחרי');
      },
    );
  }

  test('עץ שנבנה מחדש בחלון אחד נבנה מחדש גם בשני, בלי הד חוזר', () async {
    final a = loaded();
    final b = loaded();
    final aStates = <LibraryState>[];
    final sub = a.stream.listen(aStates.add);

    repo.library = Future.value(_library('אחרי'));
    a.add(const HiddenBooksChanged());
    await settle();

    expect(a.state.library!.subCategories.single.title, 'אחרי');
    expect(b.state.library!.subCategories.single.title, 'אחרי');
    // B אינו מודיע הלאה: A בנה את העץ פעם אחת בלבד.
    expect(aStates, hasLength(1));

    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('bloc שנסגר אינו מקבל עוד הודעות', () async {
    final a = loaded();
    final b = loaded();
    await b.close();

    repo.library = Future.value(_library('אחרי'));
    a.add(const HiddenBooksChanged());
    await settle();

    expect(b.state.library, same(before));
    await a.close();
  });
}
