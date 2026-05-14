import 'dart:async';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';

import '../test_helpers/memory_cache_provider.dart';

class _FakeProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 1;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'F';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    return Library(categories: []);
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType,
    {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType,
    {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return <String>{};
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return '';
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return false;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return <String, List<Book>>{};
  }
}

void main() {
  final providerManager = LibraryProviderManager.instance;
  final fileSystemProvider = FileSystemLibraryProvider.instance;
  late NavigationRepository navigationRepository;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    navigationRepository = NavigationRepository(reopenIndex: () async {});
    providerManager.resetForTesting();
    fileSystemProvider.resetForTesting();
    BooksCache.instance.clear();
  });

  tearDown(() {
    providerManager.resetForTesting();
    fileSystemProvider.resetForTesting();
    BooksCache.instance.clear();
  });

  test('refreshLibrary מאפס runtime state ומחליף את library future', () async {
    final tempDir = await Directory.systemTemp.createTemp('otzaria_nav_repo');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final newLibraryPath = tempDir.path;
    final oldFuture = Completer<Library>().future;
    DataRepository.instance.library = oldFuture;

    providerManager.seedMappingsForTesting(
      mapping: <BookCompositeKey, LibraryProvider>{},
      providers: <LibraryProvider>[_FakeProvider()],
    );

    fileSystemProvider.seedKeyToPathForTesting(
      keyToPath: <String, String>{'ישן|1|txt': 'C:/old/book.txt'},
      categoryIdToPath: <int, String>{1: 'ישן'},
      libraryPath: 'C:/old',
    );

    BooksCache.instance.clear();

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      newLibraryPath,
    );

    await navigationRepository.refreshLibrary();

    expect(BooksCache.instance.isLoaded, isFalse);
    expect(FileSystemData.instance.libraryPath, newLibraryPath);
    expect(DataRepository.instance.library, isNot(same(oldFuture)));

    final library = await DataRepository.instance.library;
    expect(library, isA<Library>());

    expect(providerManager.isInitialized, isTrue);
    expect(
      providerManager.providers.any((provider) => provider is _FakeProvider),
      isFalse,
    );
    expect(fileSystemProvider.isInitialized, isTrue);
    expect(
      await fileSystemProvider.hasBook('ישן', 1, 'txt'),
      isFalse,
    );
  });
}
