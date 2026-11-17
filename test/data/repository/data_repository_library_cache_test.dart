import 'dart:async';
import 'dart:collection';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';

import '../../helpers/memory_settings_cache.dart';

class _ControlledFiles extends Fake implements FileSystemData {
  final Queue<Future<Library>> results = Queue<Future<Library>>();
  int calls = 0;

  @override
  Future<Library> getLibrary({bool sharePendingReaderMetadata = false}) {
    calls++;
    return results.removeFirst();
  }
}

void main() {
  late DataRepository repository;
  late _ControlledFiles files;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    files = _ControlledFiles();
    repository = DataRepository(fileSystemData: files);
  });

  test('קוראים במקביל חולקים Future אחד, ובנייה שנכשלה אינה נשמרת', () async {
    final build = Completer<Library>();
    repository.library = build.future;

    final first = repository.library;
    final second = repository.library;
    expect(identical(first, second), isTrue);

    build.completeError(StateError('catalog failed'));
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(repository.cachedLibraryFutureForTesting, isNull);

    final recoveredLibrary = Library(categories: []);
    files.results.add(Future.value(recoveredLibrary));
    expect(await repository.library, same(recoveredLibrary));
    expect(files.calls, 1);
  });

  test('כשל של Future שהוחלף אינו מוחק את החדש', () async {
    final stale = Completer<Library>();
    repository.library = stale.future;
    final staleTracked = repository.library;
    final fresh = Future.value(Library(categories: []));
    repository.library = fresh;
    final freshTracked = repository.library;

    stale.completeError(StateError('stale failed'));
    await expectLater(staleTracked, throwsStateError);
    expect(
      identical(repository.cachedLibraryFutureForTesting, freshTracked),
      isTrue,
    );
  });

  test('פסילת המטמון מנקה גם את הקטלוג האחרון', () async {
    final library = Library(categories: []);
    repository.library = Future.value(library);
    await repository.library;

    repository.invalidateLibraryCache();

    expect(repository.lastSuccessfulLibrary, isNull);
  });

  test('צילום מצב ממתין לבנייה שכבר רצה במקום להתחיל בנייה נוספת', () async {
    final build = Completer<Library>();
    files.results.add(build.future);

    final current = repository.library;
    final snapshot = repository.librarySnapshotForRefresh();
    expect(files.calls, 1);

    final library = Library(categories: []);
    build.complete(library);

    expect(await current, same(library));
    expect(await snapshot, same(library));
    expect(files.calls, 1);
  });
}
