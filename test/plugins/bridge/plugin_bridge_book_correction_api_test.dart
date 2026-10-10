import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _StubTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = TabsState.initial();

  @override
  TabsState get state => currentState;
}

class _StubPluginRegistryRepository extends PluginRegistryRepository {
  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const ['library.books.read', 'tools.read'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _codedError(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

void main() {
  late PluginBridgeAdapter adapter;

  void installLibrary(List<Book> books) {
    final category = Category(
      title: 'הלכה',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: books,
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    DataRepository.instance.library = Future.value(library);
  }

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    adapter = PluginBridgeAdapter(
      _plugin(),
      dependencies: PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _StubTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _MockCalendarCubit(),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _MockPersonalNotesRepository(),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) async => true,
        showWarningDialog:
            ({required title, required content, required subtitle}) async =>
                true,
      ),
      pluginRepository: _StubPluginRegistryRepository(),
    );
  });

  Future<void> expectRejected(Map<String, dynamic> args, String code) =>
      expectLater(
        adapter.execute('feedback', 'submitBookCorrection', args),
        _codedError(code),
      );

  group('feedback.submitBookCorrection identity', () {
    for (final args in <Map<String, dynamic>>[
      {},
      {'bookId': null},
      {'bookId': 42},
      {'bookId': ''},
      {'bookId': '   '},
      {'bookId': 'ספר', 'bookUid': 42},
      {'bookId': 'ספר', 'bookUid': ''},
      {'bookId': 'ספר', 'bookUid': '   '},
    ]) {
      test('דוחה זהות פגומה $args לפני גישה למסד', () async {
        installLibrary([]);
        await expectRejected(args, 'error.invalid_params');
      });
    }

    test('דוחה UID לא מוכר גם כשהכותרת קיימת', () async {
      installLibrary([TextBook(id: 42, title: 'ספר')]);
      await expectRejected(
        {'bookId': 'ספר', 'bookUid': 'id:999999'},
        'error.not_found',
      );
    });

    test('דוחה כותרת לא מוכרת', () async {
      installLibrary([TextBook(id: 42, title: 'ספר')]);
      await expectRejected({'bookId': 'חסר'}, 'error.not_found');
    });

    test('דוחה כותרת עמומה ללא UID', () async {
      installLibrary([
        TextBook(id: 42, title: 'ספר', categoryId: 1),
        TextBook(id: 43, title: 'ספר', categoryId: 2),
      ]);
      await expectRejected({'bookId': 'ספר'}, 'error.not_found');
    });
  });

  group('feedback.submitBookCorrection supported sources', () {
    final unsupported = <String, Book>{
      'PDF': PdfBook(id: 42, title: 'ספר', path: '/book.pdf'),
      'אישי': TextBook(id: 42, title: 'ספר', source: BookSource.user),
      'מצורף': TextBook(
        id: 42,
        title: 'ספר',
        source: BookSource.attached('test-library'),
      ),
      'קטלוג חיצוני': TextBook(
        id: 42,
        title: 'ספר',
        externalLibraryId: 'remote:42',
      ),
      'קובץ ללא מזהה DB': TextBook(title: 'ספר', filePath: '/external.txt'),
      'מהדורה חלופית': TextBook(
        id: 42,
        title: 'ספר',
        versionTitle: 'alternate-version',
      ),
    };
    for (final entry in unsupported.entries) {
      test('דוחה ${entry.key} לפני גישה למסד', () async {
        installLibrary([entry.value]);
        await expectRejected({'bookId': 'ספר'}, 'error.unsupported_context');
      });
    }
  });
}
