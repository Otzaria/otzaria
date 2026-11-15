import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/toc_expansion_settings.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
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
    BookSource preferSource = BookSource.official,
  }) {
    return Future.value(null);
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
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

      await Settings.clearCache();
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

    await Settings.clearCache();
    await resetRuntimeStateAfterSettingsReset();

    expect(FileSystemData.instance.libraryPath, isNot(oldLibraryPath));
  });

  test('איפוס הגדרות טוען מחדש את ברירת המחדל של פתיחת הכותרות', () async {
    await TocExpansionSettings.saveAutoExpand(false);
    await TocExpansionSettings.saveLevel(2);
    await Settings.clearCache();
    await resetRuntimeStateAfterSettingsReset();
    expect(Settings.containsKey(TocExpansionSettings.autoExpandKey), isFalse);
    expect(TocExpansionSettings.autoExpand.value, isTrue);
    expect(TocExpansionSettings.loadLevel(), isNull);
  });

  for (final restored in [false, true]) {
    test('אתחול טוען את העדפת הכותרות ששוחזרה: $restored', () async {
      await TocExpansionSettings.saveAutoExpand(!restored);
      await Settings.setValue(TocExpansionSettings.autoExpandKey, restored);
      await resetRuntimeStateForAppRestart();
      expect(TocExpansionSettings.autoExpand.value, restored);
    });
  }

  group('התראות לוח השנה אחרי איפוס', () {
    test('הבעלים משדר את המצב השמור', () async {
      final revision = CalendarAlertsOwner.instance.revision;

      await resetRuntimeStateAfterSettingsReset();

      expect(CalendarAlertsOwner.instance.revision, revision + 1);
    });
  });

  test('restart מבטל עץ ספרייה ישן לאחר שינוי נתיב בגיבוי', () async {
    final oldLibrary = Library(categories: []);
    DataRepository.instance.library = Future.value(oldLibrary);
    expect(await DataRepository.instance.library, same(oldLibrary));
    expect(DataRepository.instance.lastSuccessfulLibrary, same(oldLibrary));

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      'C:/restored-library',
    );
    await resetRuntimeStateForAppRestart();

    expect(FileSystemData.instance.libraryPath, 'C:/restored-library');
    expect(DataRepository.instance.cachedLibraryFutureForTesting, isNull);
    expect(DataRepository.instance.lastSuccessfulLibrary, isNull);
  });

  test('איפוס אחרי העברת מסדים שומר את נעילת ההכנה הקיימת', () async {
    final corrections = PluginCorrectionSessionService.instance;
    const requestId = 'storage-move-reset-test';
    expect(corrections.beginProcessQuitPreparation(requestId), isTrue);
    addTearDown(() => corrections.cancelProcessQuitPreparation(requestId));

    await resetRuntimeStateForAppRestart(
      correctionStorageMoveRequestId: requestId,
    );

    expect(corrections.isProcessQuitPreparedFor(requestId), isTrue);
  });

  test('איפוס מנקה את תוצאות האיתור המוצגות', () async {
    final bloc = FindRefBloc(findRefRepository: FindRefRepository());
    addTearDown(bloc.close);
    bloc.emit(
      const FindRefSuccess([
        DbReferenceResult(title: 'בראשית', reference: 'בראשית', segment: 0),
      ], query: 'בראשית'),
    );

    await resetRuntimeStateForAppRestart();
    await pumpEventQueue();

    expect(bloc.state, isA<FindRefInitial>());
  });
}
