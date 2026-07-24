import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
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
    String fileType, {
    bool preferUserBooks = false,
  }) {
    return Future.value(null);
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) {
    return Future.value(null);
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async => <String>{};

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async => '';

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

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    providerManager.resetForTesting();
    fileSystemProvider.resetForTesting();
  });

  tearDown(() {
    providerManager.resetForTesting();
    fileSystemProvider.resetForTesting();
  });

  test(
    'resetRuntimeStateForAppRestart מאפס provider state ומעדכן נתיב ספריה',
    () async {
      const oldLibraryPath = 'C:/old-library';

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        oldLibraryPath,
      );

      providerManager.seedMappingsForTesting(
        mapping: <BookCompositeKey, LibraryProvider>{},
        providers: <LibraryProvider>[_FakeProvider()],
      );

      fileSystemProvider.seedKeyToPathForTesting(
        keyToPath: <String, String>{'ישן|1|txt': 'C:/old/book.txt'},
        categoryIdToPath: <int, String>{1: 'ישן'},
        libraryPath: oldLibraryPath,
      );
      FileSystemData.instance.libraryPath = oldLibraryPath;

      Settings.clearCache();
      await resetRuntimeStateForAppRestart();

      expect(providerManager.isInitialized, isFalse);
      expect(fileSystemProvider.isInitialized, isFalse);
      expect(FileSystemData.instance.libraryPath, isNot(oldLibraryPath));
      expect(
        FileSystemData.instance.libraryPath,
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
      );
    },
  );

  test('resetRuntimeStateAfterSettingsReset נשאר alias תקין', () async {
    const oldLibraryPath = 'C:/old-library';

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      oldLibraryPath,
    );

    FileSystemData.instance.libraryPath = oldLibraryPath;

    Settings.clearCache();
    await resetRuntimeStateAfterSettingsReset();

    expect(FileSystemData.instance.libraryPath, isNot(oldLibraryPath));
  });
}
