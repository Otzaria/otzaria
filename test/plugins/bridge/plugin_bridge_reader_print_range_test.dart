import 'dart:async';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {
  TabsState current = TabsState.initial();
  @override
  TabsState get state => current;
}

class _PrintRepository extends Mock implements TextBookRepository {
  List<String> available = ['רש"י', 'אבן עזרא'];
  Object? error;
  Completer<List<String>>? pending;
  int lookups = 0;
  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    lookups++;
    if (error != null) throw error!;
    return pending?.future ?? available;
  }

  @override
  Future<String> getBookContent(TextBook book) async =>
      'content:${book.source.wireKey}';
}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockPluginRegistryRepository extends Mock
    implements PluginRegistryRepository {}

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
    minAppVersion: '0.9.99',
    sdkVersion: '1.x',
    permissions: const ['reader.open'],
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
  late List<({TextBook book, int startLine, int? endLine})> shown;
  late bool printResult;
  late bool userActivated;
  late PluginBridgeAdapter adapter;
  late _MockTabsBloc tabsBloc;
  late _PrintRepository repository;
  late List<String> selected;
  late List<String> available;

  void installLibrary(List<Book> books) {
    final category = Category(
      title: 'תנך',
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
    shown = [];
    tabsBloc = _MockTabsBloc();
    repository = _PrintRepository();
    selected = [];
    available = [];
    printResult = true;
    userActivated = true;
    installLibrary([
      TextBook(title: 'תהילים'),
      PdfBook(title: 'סריקה', path: '/tmp/scan.pdf'),
    ]);
    adapter = PluginBridgeAdapter(
      _plugin(),
      instanceId: 'tab-1',
      dependencies: PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: tabsBloc,
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
        hasUserActivation: (pluginId, instanceId) async => userActivated,
        textBookRepository: repository,
        printBookRange:
            (
              book, {
              required startLine,
              endLine,
              required activeCommentators,
              required availableCommentators,
            }) async {
              selected = List.of(activeCommentators);
              available = List.of(availableCommentators);
              shown.add((book: book, startLine: startLine, endLine: endLine));
              return printResult;
            },
      ),
      pluginRepository: _MockPluginRegistryRepository(),
    );
  });

  test('פותח את מסך ההדפסה על הטווח ומחזיר printed:true', () async {
    final result = await adapter.execute('reader', 'printRange', {
      'bookId': 'תהילים',
      'startIndex': 1,
      'endIndex': 120,
    });

    expect(result, {'printed': true});
    expect(shown, hasLength(1));
    expect(shown.single.book.title, 'תהילים');
    expect(shown.single.startLine, 1);
    expect(shown.single.endLine, 120);
  });

  test('בלי endIndex — רק שורת התחלה; אינדקס 3.0 מתקבל כשלם', () async {
    await adapter.execute('reader', 'printRange', {
      'bookId': 'תהילים',
      'startIndex': 3.0,
    });
    expect(shown.single.startLine, 3);
    expect(shown.single.endLine, isNull);
  });

  test('ביטול במסך ההדפסה מוחזר כ-printed:false', () async {
    printResult = false;
    expect(
      await adapter.execute('reader', 'printRange', {
        'bookId': 'תהילים',
        'startIndex': 0,
      }),
      {'printed': false},
    );
  });

  test('בלי מחוות משתמש — forbidden, והמסך לא נפתח', () async {
    userActivated = false;
    await expectLater(
      adapter.execute('reader', 'printRange', {
        'bookId': 'תהילים',
        'startIndex': 0,
      }),
      _codedError('error.forbidden'),
    );
    expect(shown, isEmpty);
    expect(repository.lookups, 0);
  });

  test('פרמטרים פסולים — invalid_params, לפני כל דיאלוג', () async {
    for (final args in <Map<String, dynamic>>[
      {'startIndex': 0},
      {'bookId': 'תהילים'},
      {'bookId': 'תהילים', 'startIndex': -1},
      {'bookId': 'תהילים', 'startIndex': 1.5},
      {'bookId': 'תהילים', 'startIndex': 5, 'endIndex': 5},
      {'bookId': 'תהילים', 'startIndex': 5, 'endIndex': 2},
      {'bookId': 'תהילים', 'startIndex': 0, 'endIndex': '9'},
    ]) {
      await expectLater(
        adapter.execute('reader', 'printRange', args),
        _codedError('error.invalid_params'),
        reason: '$args',
      );
    }
    expect(shown, isEmpty);
  });

  test('ספר שלא קיים — not_found; ספר PDF — unsupported', () async {
    await expectLater(
      adapter.execute('reader', 'printRange', {
        'bookId': 'אין כזה',
        'startIndex': 0,
      }),
      _codedError('error.not_found'),
    );
    await expectLater(
      adapter.execute('reader', 'printRange', {
        'bookId': 'סריקה',
        'type': 'pdf',
        'startIndex': 0,
      }),
      _codedError('error.unsupported'),
    );
    expect(shown, isEmpty);
  });
  test(
    'omitted commentators uses linked commentators; explicit [] remains empty',
    () async {
      await adapter.execute('reader', 'printRange', {
        'bookId': 'תהילים',
        'startIndex': 0,
      });
      expect(selected, ['רש"י', 'אבן עזרא']);
      expect(available, ['רש"י', 'אבן עזרא']);
      await adapter.execute('reader', 'printRange', {
        'bookId': 'תהילים',
        'startIndex': 0,
        'commentators': [],
      });
      expect(selected, isEmpty);
      await adapter.execute('reader', 'printRange', {
        'bookId': 'תהילים',
        'startIndex': 0,
        'commentators': [' רש"י ', 'רש"י'],
      });
      expect(selected, ['רש"י']);
    },
  );
  test(
    'commentators rejects invalid and unknown names before opening',
    () async {
      for (final names in [
        null,
        'רש"י',
        [3],
        [''],
        ['   '],
        List.filled(257, 'רש"י'),
      ]) {
        await expectLater(
          adapter.execute('reader', 'printRange', {
            'bookId': 'תהילים',
            'startIndex': 0,
            'commentators': names,
          }),
          _codedError('error.invalid_params'),
        );
      }
      await expectLater(
        adapter.execute('reader', 'printRange', {
          'bookId': 'תהילים',
          'startIndex': 0,
          'commentators': ['לא קיים'],
        }),
        _codedError('error.not_found'),
      );
      expect(shown, isEmpty);
    },
  );
  test(
    'active reader defaults only apply to the exact attached bookUid',
    () async {
      final a = TextBook(
        id: 5,
        title: 'תהילים',
        source: BookSource.attached('a'),
      );
      final b = TextBook(
        id: 5,
        title: 'תהילים',
        source: BookSource.attached('b'),
      );
      installLibrary([a, b]);
      final tab = TextBookTab(book: a, index: 0);
      tab.bloc.emit(
        TextBookLoaded.initial(
          book: a,
          index: 0,
          showLeftPane: false,
          splitView: false,
        ).copyWith(
          availableCommentators: repository.available,
          activeCommentators: ['רש"י'],
        ),
      );
      tabsBloc.current = TabsState(tabs: [tab], currentTabIndex: 0);
      await adapter.execute('reader', 'printRange', {
        'bookUid': 'db:a:5',
        'startIndex': 0,
      });
      expect(selected, ['רש"י']);
      await adapter.execute('reader', 'printRange', {
        'bookUid': 'db:b:5',
        'startIndex': 0,
      });
      expect(selected, repository.available);
      await adapter.execute('reader', 'printRange', {
        'bookUid': 'db:a:5',
        'startIndex': 0,
        'commentators': [],
      });
      expect(selected, isEmpty);
      await tab.bloc.close();
    },
  );
  test(
    'commentator lookup failure opens nothing and releases dialog guard',
    () async {
      repository.error = StateError('offline');
      await expectLater(
        adapter.execute('reader', 'printRange', {
          'bookId': 'תהילים',
          'startIndex': 0,
        }),
        throwsStateError,
      );
      expect(shown, isEmpty);
      repository.error = null;
      repository.available = [];
      expect(
        await adapter.execute('reader', 'printRange', {
          'bookId': 'תהילים',
          'startIndex': 0,
        }),
        {'printed': true},
      );
      expect(selected, isEmpty);
    },
  );
  test(
    'raw text cache isolates two attached sources with identical id and title',
    () async {
      installLibrary([
        TextBook(id: 5, title: 'זהה', source: BookSource.attached('a')),
        TextBook(id: 5, title: 'זהה', source: BookSource.attached('b')),
      ]);
      expect(
        await adapter.execute('library', 'getBookContent', {
          'bookUid': 'db:a:5',
        }),
        'content:d:a',
      );
      expect(
        await adapter.execute('library', 'getBookContent', {
          'bookUid': 'db:b:5',
        }),
        'content:d:b',
      );
      expect(
        await adapter.execute('library', 'getBookContent', {
          'bookUid': 'db:a:5',
        }),
        'content:d:a',
      );
    },
  );

  test(
    'loading linked commentators waits before dialog and blocks a second dialog',
    () async {
      repository.pending = Completer<List<String>>();
      final response = adapter.execute('reader', 'printRange', {
        'bookId': 'תהילים',
        'startIndex': 0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(shown, isEmpty);
      await expectLater(
        adapter.execute('reader', 'printRange', {
          'bookId': 'תהילים',
          'startIndex': 0,
        }),
        _codedError('error.forbidden'),
      );
      repository.pending!.complete(['רש"י']);
      expect(await response, {'printed': true});
      expect(selected, ['רש"י']);
    },
  );
}
