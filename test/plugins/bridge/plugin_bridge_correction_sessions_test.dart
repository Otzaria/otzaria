import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _History extends Mock implements HistoryBloc {}

class _Navigation extends Mock implements NavigationBloc {}

class _Calendar extends Mock implements CalendarCubit {}

class _Workspace extends Mock implements WorkspaceBloc {}

class _Search extends Mock implements SearchRepository {}

class _Notes extends Mock implements PersonalNotesRepository {}

class _Coordinator extends Mock implements BookOpenCoordinator {}

class _Tabs extends Mock implements TabsBloc {
  late TabsState current;
  @override
  TabsState get state => current;
}

class _Grants extends PluginRegistryRepository {
  _Grants(this.permissions);
  final List<String> permissions;
  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      permissions.contains(permission);
  @override
  Future<List<String>> getGrantedPermissionNames(String pluginId) async =>
      permissions;
}

class _Reader extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _Reader(TextBook book)
    : super(
        TextBookLoaded.initial(
          book: book,
          index: 0,
          showLeftPane: false,
          splitView: false,
        ).copyWith(content: const ['בראשית א', 'שורה ב', 'שורה ג']),
      );
  void showCommentaryAtSide() =>
      emit((state as TextBookLoaded).copyWith(showSplitView: true));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin(String id, List<String> permissions) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: id,
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: id,
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _error(String code) => throwsA(
  isA<PluginCorrectionException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late String databasePath;
  late _Tabs tabs;
  late List<TextBookTab> readers;
  late PluginBridgeAdapter adapter;
  final events = <String>[];
  const permissions = ['reader.open', 'reader.local_edit'];

  PluginBridgeAdapter buildAdapter({
    String owner = 'owner',
    List<String> grants = permissions,
  }) => PluginBridgeAdapter(
    _plugin(owner, grants),
    dependencies: PluginBridgeDependencies(
      historyBloc: _History(),
      tabsBloc: tabs,
      navigationBloc: _Navigation(),
      calendarCubit: _Calendar(),
      workspaceBloc: _Workspace(),
      searchRepository: _Search(),
      personalNotesRepository: _Notes(),
      bookOpenCoordinator: _Coordinator(),
      themePayloadBuilder: () => {},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
      dispatchEventToPlugin: (pluginId, topic, payload, {instanceId}) async {
        events.add(topic);
      },
    ),
    pluginRepository: _Grants(grants),
  );

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> args, {
    PluginBridgeAdapter? target,
  }) async => Map<String, dynamic>.from(
    await (target ?? adapter).execute('reader', action, args) as Map,
  );

  Future<Map<String, dynamic>> begin([int index = 0]) =>
      call('beginCorrectionSession', {
        'tabId': PluginCorrectionSessionService.tabIdFor(readers[index]),
      });

  Map<String, dynamic> draft(
    Map<String, dynamic> session, {
    String proposed = 'תיקון 😀',
  }) => {
    'sessionId': session['sessionId'],
    'expectedRevision': session['revision'],
    'bookUid': session['bookUid'],
    'libraryVersion': session['libraryVersion'],
    'changes': [
      {
        'sectionIndex': 0,
        'originalSourceText': 'בראשית א',
        'originalText': 'בראשית א',
        'proposedText': proposed,
      },
    ],
  };

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('correction-bridge-');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(temporary.path, 'data'));
    databasePath = SeforimFixtureDb.create(
      temporary,
      SeforimFixtureVariant.full,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      temporary.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      databasePath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    tabs = _Tabs();
    final book = TextBook(id: 1, title: 'בראשית');
    readers = List.generate(
      2,
      (_) => TextBookTab(book: book, index: 0, blocOverride: _Reader(book)),
    );
    tabs.current = TabsState(tabs: readers, currentTabIndex: 0);
    events.clear();
    adapter = buildAdapter();
  });

  tearDown(() async {
    PluginCorrectionSessionService.instance.removeOwner('owner');
    PluginCorrectionSessionService.instance.removeOwner('foreign');
    for (final reader in readers) {
      await reader.bloc.close();
    }
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await temporary.delete(recursive: true);
  });

  test(
    'סבב API מלא מחיל טיוטה רק בלשונית שלה ומשאיר את המסד והבלוק מקוריים',
    () async {
      final before = await File(databasePath).readAsBytes();
      final initial = await begin();
      expect(await begin(), initial);
      final restored = await call('restoreCorrectionDraft', draft(initial));
      expect(restored['revision'], 1);
      await expectLater(
        call('getSelection', {}),
        _error('error.unsupported_context'),
      );
      for (final layer in ['rendered', 'both']) {
        await expectLater(
          call('getSectionTextMap', {
            'bookId': 'בראשית',
            'bookUid': restored['bookUid'],
            'sectionIndex': 0,
            'layer': layer,
          }),
          _error('error.unsupported_context'),
        );
      }
      final map = await call('getSectionTextMap', {
        'bookId': 'בראשית',
        'bookUid': restored['bookUid'],
        'sectionIndex': 0,
        'layer': 'source',
      });
      expect(map['sourceText'], 'בראשית א');
      expect(
        await call('getCorrectionSession', {'sessionId': initial['sessionId']}),
        restored,
      );
      expect(
        PluginCorrectionSessionService.instance.displayText(
          initial['tabId'],
          0,
          'בראשית א',
        ),
        'תיקון 😀',
      );
      final second = await begin(1);
      expect(second['sessionId'], isNot(initial['sessionId']));
      expect(second['changes'], isEmpty);
      expect(
        (readers.first.bloc.state as TextBookLoaded).content.first,
        'בראשית א',
      );
      final db = sqlite3.sqlite3.open(
        databasePath,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        expect(
          db
              .select(
                'SELECT content FROM line WHERE bookId = 1 AND lineIndex = 0',
              )
              .single['content'],
          'בראשית א',
        );
      } finally {
        db.close();
      }
      expect(await File(databasePath).readAsBytes(), before);
      final reset = await call('resetCorrection', {
        'sessionId': initial['sessionId'],
        'expectedRevision': 1,
        'sectionIndex': 0,
      });
      expect(reset['changes'], isEmpty);
      expect(reset['revision'], 2);
      final ended = await call('endCorrectionSession', {
        'sessionId': initial['sessionId'],
        'expectedRevision': 2,
      });
      expect(ended, reset);
      await expectLater(
        call('getCorrectionSession', {'sessionId': initial['sessionId']}),
        _error('error.not_found'),
      );
      expect(events, [
        'reader.correctionSessionChanged',
        'reader.correctionSessionChanged',
        'reader.correctionSessionEnded',
      ]);
    },
  );

  test('tabId יציב וייחודי גם לשתי לשוניות אותו ספר', () async {
    final first = await call('getCurrentState', {});
    final second = await call('getCurrentState', {});
    expect(second, first);
    final openTabs = first['openTabs'] as List;
    expect(openTabs[0]['tabId'], isNot(openTabs[1]['tabId']));
    expect(first['currentTabId'], openTabs[0]['tabId']);
    expect((await begin())['tabId'], openTabs[0]['tabId']);
    tabs.current = TabsState(tabs: readers, currentTabIndex: 1);
    final switched = await call('getCurrentState', {});
    expect(switched['currentTabId'], openTabs[1]['tabId']);
    tabs.current = TabsState(tabs: [readers[1]], currentTabIndex: 0);
    final remaining = await call('getCurrentState', {});
    expect(remaining['currentTabId'], openTabs[1]['tabId']);
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': openTabs[0]['tabId'],
      }),
      _error('error.not_found'),
    );
  });

  test('מצב הקורא חושף רק סשן קיים של בעליו גם למופע חדש', () async {
    final initial = await call('getCurrentState', {});
    expect(initial['currentCorrectionSessionId'], isNull);
    expect(
      (initial['openTabs'] as List).map((tab) => tab['correctionSessionId']),
      everyElement(isNull),
    );
    final session = await begin();
    final foreground = buildAdapter();
    final owned = await call('getCurrentState', {}, target: foreground);
    expect(owned['currentCorrectionSessionId'], session['sessionId']);
    expect(
      (owned['openTabs'] as List)[0]['correctionSessionId'],
      session['sessionId'],
    );
    expect((owned['openTabs'] as List)[1]['correctionSessionId'], isNull);
    expect(
      await call('getCorrectionSession', {
        'sessionId': owned['currentCorrectionSessionId'],
      }, target: foreground),
      session,
    );
    final foreign = buildAdapter(owner: 'foreign');
    final hidden = await call('getCurrentState', {}, target: foreign);
    expect(hidden['currentCorrectionSessionId'], isNull);
    expect(
      (hidden['openTabs'] as List).map((tab) => tab['correctionSessionId']),
      everyElement(isNull),
    );
    tabs.current = TabsState(tabs: readers, currentTabIndex: 1);
    expect(
      (await call('getCurrentState', {}))['currentCorrectionSessionId'],
      isNull,
    );
    await call('endCorrectionSession', {
      'sessionId': session['sessionId'],
      'expectedRevision': 0,
    });
    final ended = await call('getCurrentState', {});
    expect(
      (ended['openTabs'] as List).map((tab) => tab['correctionSessionId']),
      everyElement(isNull),
    );
    tabs.current = const TabsState(tabs: [], currentTabIndex: 0);
    expect(
      (await call('getCurrentState', {}))['currentCorrectionSessionId'],
      isNull,
    );
  });

  test('לשונית שנפתחה לפי כותרת משתמשת ב-id שנפתר ב-state של הקורא', () async {
    final titled = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      blocOverride: _Reader(TextBook(id: 1, title: 'בראשית')),
    );
    addTearDown(titled.bloc.close);
    tabs.current = TabsState(tabs: [titled], currentTabIndex: 0);
    final session = await call('beginCorrectionSession', {
      'tabId': PluginCorrectionSessionService.tabIdFor(titled),
    });
    expect(
      session['bookUid'],
      PluginBookIdentity.uidOf((titled.bloc.state as TextBookLoaded).book),
    );
    final restored = await call('restoreCorrectionDraft', draft(session));
    expect((restored['changes'] as List).single['proposedText'], 'תיקון 😀');
  });

  test('מפרשים בצד מאפשרים סשן ותיקון בטקסט הראשי בלבד', () async {
    (readers.first.bloc as _Reader).showCommentaryAtSide();
    final session = await begin();
    expect((session['capabilities'] as Map)['splitView'], isTrue);
    final restored = await call('restoreCorrectionDraft', draft(session));
    expect((restored['changes'] as List).single['proposedText'], 'תיקון 😀');
    expect(
      (readers.first.bloc.state as TextBookLoaded).content.first,
      'בראשית א',
    );
    expect(
      PluginCorrectionSessionService.instance.hasSessionForTab(
        PluginCorrectionSessionService.tabIdFor(readers[1]),
      ),
      isFalse,
    );
  });

  test('הרשאה חסרה ובעלות זרה אינן מאפשרות גישה לסשן', () async {
    final denied = buildAdapter(grants: const ['reader.open']);
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': PluginCorrectionSessionService.tabIdFor(readers.first),
      }, target: denied),
      _error('error.permission_denied'),
    );
    final session = await begin();
    await expectLater(
      call('getCorrectionSession', {
        'sessionId': session['sessionId'],
      }, target: denied),
      _error('error.permission_denied'),
    );
    final foreign = buildAdapter(owner: 'foreign');
    await expectLater(
      call('getCorrectionSession', {
        'sessionId': session['sessionId'],
      }, target: foreign),
      _error('error.not_found'),
    );
    await expectLater(
      call('restoreCorrectionDraft', draft(session), target: foreign),
      _error('error.not_found'),
    );
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': session['tabId'],
      }, target: foreign),
      _error('error.correction_busy'),
    );
  });

  test('פרמטרים פגומים וטיוטה ממקור אחר אינם משנים סשן', () async {
    for (final args in <Map<String, dynamic>>[
      {},
      {'tabId': 42},
      {'tabId': ''},
      {'tabId': 'missing', 'extra': true},
    ]) {
      await expectLater(
        call('beginCorrectionSession', args),
        _error('error.invalid_params'),
      );
    }
    await expectLater(
      call('beginCorrectionSession', {'tabId': 'missing'}),
      _error('error.not_found'),
    );
    final session = await begin();
    for (final args in <Map<String, dynamic>>[
      {...draft(session), 'expectedRevision': '0'},
      {...draft(session), 'expectedRevision': -1},
      {...draft(session), 'expectedRevision': 0.5},
      {...draft(session), 'changes': {}},
      {...draft(session), 'extra': true},
    ]) {
      await expectLater(
        call('restoreCorrectionDraft', args),
        _error('error.invalid_params'),
      );
    }
    await expectLater(
      call('restoreCorrectionDraft', {...draft(session), 'bookUid': 'id:999'}),
      _error('error.source_changed'),
    );
    await expectLater(
      call('restoreCorrectionDraft', draft(session, proposed: '<b>תיקון</b>')),
      _error('error.unsupported_context'),
    );
    expect(
      await call('getCorrectionSession', {'sessionId': session['sessionId']}),
      session,
    );
    expect(events, isEmpty);
  });

  test('גרסה לא ידועה אינה מאפשרת לפתוח סשן', () async {
    final db = sqlite3.sqlite3.open(databasePath);
    try {
      db.execute("DELETE FROM schema_meta WHERE key = 'db_version'");
    } finally {
      db.close();
    }
    await expectLater(begin(), _error('error.source_changed'));
  });

  test('גשר RPC אוכף גם הצהרה במניפסט וגם אישור להרשאה', () async {
    for (final declared in [false, true]) {
      final handler = PluginBridgeHandler(
        _plugin('owner', declared ? permissions : const ['reader.open']),
        adapter: adapter,
        registry: _Grants(declared ? const ['reader.open'] : permissions),
      );
      final response =
          await handler.handleRpcForTesting([
                {
                  'method': 'reader.beginCorrectionSession',
                  'payload': {
                    'tabId': PluginCorrectionSessionService.tabIdFor(
                      readers.first,
                    ),
                  },
                },
              ])
              as Map;
      expect(response['success'], isFalse);
      expect(response['error']['code'], 'permission_denied');
    }
    final handler = PluginBridgeHandler(
      _plugin('owner', permissions),
      adapter: adapter,
      registry: _Grants(permissions),
    );
    final response =
        await handler.handleRpcForTesting([
              {
                'method': 'reader.beginCorrectionSession',
                'payload': {
                  'tabId': PluginCorrectionSessionService.tabIdFor(
                    readers.first,
                  ),
                },
              },
            ])
            as Map;
    expect(response['success'], isTrue);
  });

  test('שינוי גרסה עם טקסט זהה דוחה גם ניקוי טיוטה אטומי', () async {
    final initial = await begin();
    final restored = await call('restoreCorrectionDraft', draft(initial));
    events.clear();
    final db = sqlite3.sqlite3.open(databasePath);
    try {
      db.execute("UPDATE schema_meta SET value = '2' WHERE key = 'db_version'");
    } finally {
      db.close();
    }
    await expectLater(
      call('restoreCorrectionDraft', draft(restored)),
      _error('error.source_changed'),
    );
    await expectLater(
      call('restoreCorrectionDraft', {...draft(restored), 'changes': []}),
      _error('error.source_changed'),
    );
    expect(
      await call('getCorrectionSession', {'sessionId': restored['sessionId']}),
      restored,
    );
    expect(events, isEmpty);
  });
}
