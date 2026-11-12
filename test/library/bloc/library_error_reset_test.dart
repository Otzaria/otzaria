import 'dart:collection';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';

import '../../helpers/memory_settings_cache.dart';

class _ControlledFiles extends Fake implements FileSystemData {
  @override
  String libraryPath = '.';

  final Queue<Future<Library> Function()> results =
      Queue<Future<Library> Function()>();

  @override
  Future<Library> getLibrary() => results.removeFirst()();
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
  late Future<Library>? previousLibrary;
  late _ControlledFiles files;
  late DataRepository repository;
  late LibraryBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    previousFiles = FileSystemData.instance;
    previousIndex = TantivyDataProvider.instance;
    previousLibrary = DataRepository.instance.cachedLibraryFutureForTesting;
    files = _ControlledFiles();
    FileSystemData.instance = files;
    TantivyDataProvider.instance = _ReadyIndex();
    DataRepository.instance.library = Future.value(Library(categories: []));
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
    if (previousLibrary case final library?) {
      DataRepository.instance.library = library;
    } else {
      DataRepository.instance.invalidateLibraryCache();
    }
  });

  Future<LibraryState> refresh(int requestId) {
    final settled = bloc.stream.firstWhere(
      (s) => LibraryState.refreshRequestSettled(s, requestId),
    );
    bloc.add(
      RefreshLibrary(
        source: RefreshSource.customFoldersScan,
        requestIds: {requestId},
      ),
    );
    return settled;
  }

  group('שגיאה בספרייה מתאפסת בפעולה המוצלחת הבאה', () {
    test('רענון שמצליח אחרי החלפת מיקום שנכשלה מנקה את השגיאה', () async {
      final failed = bloc.stream.firstWhere(
        (s) => !s.isLoading && s.error != null,
      );
      bloc.add(const UpdateLibraryPath('/no/such/library/folder'));
      expect((await failed).error, 'התיקייה לא קיימת');

      files.results.add(() async => Library(categories: []));
      expect((await refresh(1)).error, isNull);
    });

    test('ניווט אחרי כשל מנקה את השגיאה', () async {
      files.results.add(() => Future.error(StateError('refresh failed')));
      expect((await refresh(1)).error, isNotNull);

      final library = bloc.state.library!;
      final navigated = bloc.stream.first;
      bloc.add(NavigateToCategory(library.subCategories.first));
      expect((await navigated).error, isNull);
    });
  });

  group('כשל בספרייה נרשם ב-errors.txt', () {
    Future<String> errorLog() async {
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
      final file = ErrorLogFile.resolveFile();
      return file.existsSync() ? file.readAsStringSync() : '';
    }

    test('טעינה ראשונית שנכשלה', () async {
      repository.invalidateLibraryCache();
      files.results.add(() => Future.error(StateError('logged load failure')));
      final failed = bloc.stream.firstWhere(
        (s) => !s.isLoading && s.error != null,
      );
      bloc.add(LoadLibrary());
      await failed;

      expect(await errorLog(), contains('כשל טעינת הספרייה'));
      expect(await errorLog(), contains('logged load failure'));
    });

    test('רענון שנכשל', () async {
      files.results.add(
        () => Future.error(StateError('logged refresh failure')),
      );
      expect((await refresh(1)).error, isNotNull);

      expect(await errorLog(), contains('כשל רענון הספרייה'));
      expect(await errorLog(), contains('logged refresh failure'));
    });
  });
}
