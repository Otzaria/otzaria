import 'dart:async';
import 'dart:collection';

import 'package:otzaria/settings/engine/app_settings_store.dart';
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

class _ControlledFiles extends Fake implements FileSystemData {
  @override
  String libraryPath = '.';

  final Queue<Future<Library>> results = Queue<Future<Library>>();
  int calls = 0;

  @override
  Future<Library> getLibrary() {
    calls++;
    return results.removeFirst();
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileSystemData previousFiles;
  late TantivyDataProvider previousIndex;
  late _ControlledFiles files;
  late DataRepository repository;
  late LibraryBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    previousFiles = FileSystemData.instance;
    previousIndex = TantivyDataProvider.instance;
    files = _ControlledFiles();
    FileSystemData.instance = files;
    TantivyDataProvider.instance = _ReadyIndex();
    repository = DataRepository(fileSystemData: files);
    repository.library = Future.value(Library(categories: []));
    await repository.library;
    bloc = LibraryBloc(
      hiddenStore: const _EmptyHiddenStore(),
      repository: repository,
    );
  });

  tearDown(() async {
    await bloc.close();
    FileSystemData.instance = previousFiles;
    TantivyDataProvider.instance = previousIndex;
  });

  test('בקשה שבאה תוך רענון נשארת למיזוג ומדווחת רק בסיום השני', () async {
    final first = Completer<Library>();
    final second = Completer<Library>();
    files.results.addAll([first.future, second.future]);

    bloc.add(
      const RefreshLibrary(
        source: RefreshSource.customFoldersScan,
        requestIds: {3},
      ),
    );
    await bloc.stream.firstWhere((state) => state.isLoading);
    bloc.add(
      const RefreshLibrary(
        source: RefreshSource.customFoldersScan,
        requestIds: {7},
      ),
    );
    final firstDone = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(3) ?? false,
    );
    first.complete(Library(categories: []));
    expect((await firstDone).completedRefreshRequestIds, {3});

    final secondDone = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(7) ?? false,
    );
    second.complete(Library(categories: []));
    expect((await secondDone).completedRefreshRequestIds, {7});
  });

  test('כשל ברענון המאוחד מדווח מזהה כשל בלי מזהה הצלחה', () async {
    final first = Completer<Library>();
    final second = Completer<Library>();
    files.results.addAll([first.future, second.future]);

    bloc.add(
      const RefreshLibrary(
        source: RefreshSource.customFoldersScan,
        requestIds: {3},
      ),
    );
    await bloc.stream.firstWhere((state) => state.isLoading);
    bloc.add(
      const RefreshLibrary(
        source: RefreshSource.customFoldersScan,
        requestIds: {7},
      ),
    );
    final failed = bloc.stream.firstWhere(
      (state) => state.failedRefreshRequestIds?.contains(7) ?? false,
    );
    final firstDone = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(3) ?? false,
    );
    first.complete(Library(categories: []));
    await firstDone;
    while (files.calls < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    second.completeError(StateError('refresh failed'));
    final result = await failed;
    expect(result.failedRefreshRequestIds, {7});
    expect(result.completedRefreshRequestIds, isNull);
    expect(LibraryState.refreshRequestSettled(result, 7), isTrue);
  });

  test('רענון אחרי רענון שנכשל בונה קטלוג חדש ומחזיר את הספרייה', () async {
    final broken = Completer<Library>();
    final newBook = TextBook(title: 'ספר שנוסף בזמן הכשל');
    final refreshedLibrary = Library(
      categories: [
        Category(
          title: 'קטגוריה',
          description: '',
          shortDescription: '',
          order: 0,
          subCategories: [],
          books: [newBook],
          parent: null,
        ),
      ],
    );
    files.results.addAll([
      broken.future,
      Future.value(refreshedLibrary),
    ]);

    final failed = bloc.stream.firstWhere(
      (state) => state.failedRefreshRequestIds?.contains(1) ?? false,
    );
    bloc.add(const RefreshLibrary(requestIds: {1}));
    while (files.calls < 1) {
      await Future<void>.delayed(Duration.zero);
    }
    broken.completeError(StateError('catalog failed'));
    expect((await failed).error, isNotNull);

    final recovered = bloc.stream.firstWhere(
      (state) =>
          (state.completedRefreshRequestIds?.contains(2) ?? false) ||
          (state.failedRefreshRequestIds?.contains(2) ?? false),
    );
    bloc.add(const RefreshLibrary(requestIds: {2}));
    final result = await recovered;

    expect(files.calls, 2);
    expect(result.completedRefreshRequestIds, {2});
    expect(result.error, isNull);
    expect(result.newBooksToIndex, [newBook]);
  });

  // issue #4609 — טאבים פתוחים של ספרים אישיים נטענים מחדש לפי הדגל הזה.
  test('בנייה מחדש של נתוני המשתמש נמסרת גם ברענון המאוחד', () async {
    final first = Completer<Library>();
    final second = Completer<Library>();
    files.results.addAll([first.future, second.future]);

    bloc.add(const RefreshLibrary(requestIds: {3}));
    await bloc.stream.firstWhere((state) => state.isLoading);
    bloc.add(const RefreshLibrary(userContentChanged: true, requestIds: {7}));
    final firstDone = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(3) ?? false,
    );
    first.complete(Library(categories: []));
    expect((await firstDone).userContentChanged, isFalse);

    final secondDone = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(7) ?? false,
    );
    second.complete(Library(categories: []));
    final result = await secondDone;
    expect(result.userContentChanged, isTrue);
    expect(result.copyWith().userContentChanged, isFalse);
  });
}
