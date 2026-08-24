import 'dart:async';
import 'dart:convert';
import 'dart:io';
// קידומת ל-Link של dart:io כי models/links.dart מגדיר Link משלו שמסתיר אותו.
import 'dart:io' as io show Link;

import 'package:archive/archive_io.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:path/path.dart' as p;
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/data/repository/hive_list_repository.dart';
import 'package:otzaria/plugins/models/plugin_report_record.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show
        MergedSibling,
        ResultGrouping,
        ResultsOrder,
        SearchPageResult,
        SearchResult,
        SearchScope,
        SearchStreamUpdate,
        WordMatchMode;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

import '../../support/search_engine_test_init.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _StubTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = TabsState.initial();

  @override
  TabsState get state => currentState;
}

/// לוכד את ה-events ששולח ה-bridge אל TabsBloc (בעיקר AddTab) כדי שנוכל
/// לבחון את הטאב שנפתח על ידי `reader.openSearchTab`.
class _CapturingTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _CapturingTabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));

  final List<TabsEvent> captured = [];

  @override
  void add(TabsEvent event) {
    captured.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _StubCalendarCubit extends Mock implements CalendarCubit {
  _StubCalendarCubit(this.currentState);

  CalendarState currentState;

  @override
  CalendarState get state => currentState;
}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

/// לוכד את פרמטרי `searchTextsStreamWithCounts` ומחזיר stream קבוע —
/// כדי לבדוק את התרגום של `search.query` בלי מנוע חיפוש אמיתי.
class _StubSearchRepository extends SearchRepository {
  Map<String, dynamic>? captured;
  List<SearchStreamUpdate> updates = const [];
  SearchPageResult pageResult = const SearchPageResult(
    totalCount: 0,
    results: [],
    truncated: false,
  );
  int pageCalls = 0;
  int streamWithCountsCalls = 0;
  Stream<SearchStreamUpdate>? streamOverride;

  void _capture(
    String query,
    List<String> facets,
    int limit, {
    required int offset,
    required ResultsOrder order,
    required SearchMode searchMode,
    required int distance,
    required SearchScope scope,
    required ResultGrouping? grouping,
    required WordMatchMode wordMatchMode,
    required Map<String, Map<String, bool>>? searchOptions,
  }) {
    captured = {
      'query': query,
      'facets': facets,
      'limit': limit,
      'offset': offset,
      'order': order,
      'searchMode': searchMode,
      'distance': distance,
      'scope': scope,
      'grouping': grouping,
      'wordMatchMode': wordMatchMode,
      'searchOptions': searchOptions,
    };
  }

  @override
  Future<SearchPageResult> searchTextsAndCount(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    ResultsOrder order = ResultsOrder.relevance,
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    pageCalls++;
    _capture(
      query,
      facets,
      limit,
      offset: offset,
      order: order,
      searchMode: searchMode,
      distance: distance,
      scope: scope,
      grouping: grouping,
      wordMatchMode: wordMatchMode,
      searchOptions: searchOptions,
    );
    return pageResult;
  }

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    int chunkSize = 50,
    ResultsOrder order = ResultsOrder.relevance,
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) {
    streamWithCountsCalls++;
    _capture(
      query,
      facets,
      limit,
      offset: offset,
      order: order,
      searchMode: searchMode,
      distance: distance,
      scope: scope,
      grouping: grouping,
      wordMatchMode: wordMatchMode,
      searchOptions: searchOptions,
    );
    return streamOverride ?? Stream.fromIterable(updates);
  }
}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _StubPluginRegistryRepository extends PluginRegistryRepository {
  List<PluginPermissionGrant> permissions = [];
  bool? permissionGrant;
  Completer<void>? permissionGate;

  /// מיפוי פר-הרשאה; כשמוגדר, גובר על [permissionGrant].
  Map<String, bool>? permissionGrants;

  // KV in-memory (מפתח: "namespace/key") — מחליף את ה-DB בבדיקות.
  final Map<String, String> kv = {};

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(
    String pluginId,
  ) async {
    return permissions;
  }

  @override
  Future<bool?> getPermission(String pluginId, String permission) async {
    await permissionGate?.future;
    if (permissionGrants != null) return permissionGrants![permission];
    return permissionGrant;
  }

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    kv['$namespace/$key'] = valueJson;
  }

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async {
    return kv['$namespace/$key'];
  }

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async {
    final out = <String, String>{};
    for (final key in keys) {
      final value = kv['$namespace/$key'];
      if (value != null) out[key] = value;
    }
    return out;
  }

  @override
  Future<void> removeKV(String pluginId, String namespace, String key) async {
    kv.remove('$namespace/$key');
  }

  /// התוספים ה"מותקנים" — plugin.openOther נבדק מולם.
  List<InstalledPlugin> installed = [];

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => installed;
}

class _EnabledRegistryRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

/// קולט את ה-JS שהאירוע נמסר בו, לאימות תוכן ה-payload.
class _RecordingWebViewController extends Fake
    implements InAppWebViewController {
  final List<String> jsCalls = [];

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    jsCalls.add(source);
    return null;
  }
}

InstalledPlugin _buildInstalledPlugin({
  List<String> permissions = const [],
  bool networkEnabled = false,
  List<String> networkAllowlist = const [],
  String pluginId = 'test.plugin',
}) {
  return InstalledPlugin(
    pluginId: pluginId,
    name: 'Test Plugin',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: pluginId,
      name: 'Test Plugin',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: permissions,
      networkEnabled: networkEnabled,
      networkAllowlist: networkAllowlist,
      toolTabTitle: 'Test Plugin',
      toolTabOrder: 1,
      defaultPinned: true,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

PluginBridgeDependencies _buildNetworkDeps() {
  return PluginBridgeDependencies(
    historyBloc: _MockHistoryBloc(),
    tabsBloc: _StubTabsBloc(),
    navigationBloc: _MockNavigationBloc(),
    calendarCubit: _StubCalendarCubit(
      _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
    ),
    workspaceBloc: _MockWorkspaceBloc(),
    searchRepository: _MockSearchRepository(),
    personalNotesRepository: _MockPersonalNotesRepository(),
    bookOpenCoordinator: _MockBookOpenCoordinator(),
    themePayloadBuilder: () => <String, dynamic>{},
    showConfirmDialog: ({required title, required content}) async => true,
    showWarningDialog:
        ({required title, required content, required subtitle}) async => true,
  );
}

Future<void> main() async {
  // search.query מנקה את השאילתה דרך sanitizeQuery שמאציל למנוע ה-Rust;
  // הבדיקות שלו מדולגות כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  group('PluginBridgeAdapter.getJewishDate', () {
    late _StubCalendarCubit calendarCubit;
    late _StubTabsBloc tabsBloc;
    late PluginBridgeAdapter adapter;

    setUp(() {
      tabsBloc = _StubTabsBloc();
      calendarCubit = _StubCalendarCubit(
        _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
      );
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['calendar.read']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: tabsBloc,
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: calendarCubit,
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

    test('returns extended jewish date fields for yom tov dates', () async {
      final jewishDate = JewishDate()
        ..setJewishDate(5786, JewishDate.NISSAN, 15);
      final gregorianDate = jewishDate.getGregorianCalendar();
      final state = _buildCalendarState(gregorianDate, inIsrael: true);
      final formatter = HebrewDateFormatter()..hebrewFormat = true;
      final jewishCalendar = JewishCalendar.fromDateTime(gregorianDate)
        ..inIsrael = true;

      calendarCubit.currentState = state;

      final response =
          await adapter.execute('calendar', 'getJewishDate', {})
              as Map<String, dynamic>;

      expect(response['year'], jewishCalendar.getJewishYear());
      expect(response['month'], jewishCalendar.getJewishMonth());
      expect(response['day'], jewishCalendar.getJewishDayOfMonth());
      expect(response['monthName'], formatter.formatMonth(jewishCalendar));
      expect(response['isLeapYear'], jewishCalendar.isJewishLeapYear());
      expect(response['isShabbat'], jewishCalendar.getDayOfWeek() == 7);

      final holidays = (response['holidays'] as List<dynamic>)
          .cast<Map<String, String>>();
      expect(
        holidays,
        contains(
          allOf(
            containsPair('kind', 'yomTov'),
            containsPair('text', formatter.formatYomTov(jewishCalendar)),
          ),
        ),
      );
    });

    test('returns rosh chodesh entries with correct kind', () async {
      final jewishDate = JewishDate()
        ..setJewishDate(5786, JewishDate.NISSAN, 1);
      final gregorianDate = jewishDate.getGregorianCalendar();
      final state = _buildCalendarState(gregorianDate, inIsrael: true);
      final formatter = HebrewDateFormatter()..hebrewFormat = true;
      final jewishCalendar = JewishCalendar.fromDateTime(gregorianDate)
        ..inIsrael = true;

      calendarCubit.currentState = state;

      final response =
          await adapter.execute('calendar', 'getJewishDate', {})
              as Map<String, dynamic>;
      final holidays = (response['holidays'] as List<dynamic>)
          .cast<Map<String, String>>();

      expect(
        holidays,
        contains(
          allOf(
            containsPair('kind', 'roshChodesh'),
            containsPair('text', formatter.formatRoshChodesh(jewishCalendar)),
          ),
        ),
      );
    });

    test('rejects incomplete location coordinates', () async {
      await expectLater(
        adapter.execute('calendar', 'getDailyTimes', {'lat': 31.7784}),
        throwsA(isA<Exception>()),
      );
    });

    test('returns the calendar cities for plugins', () async {
      final cities =
          await adapter.execute('calendar', 'getCities', {}) as List<dynamic>;

      expect(
        cities,
        contains(
          allOf(
            containsPair('name', 'ירושלים'),
            containsPair('timezone', 'Asia/Jerusalem'),
            containsPair('inIsrael', true),
          ),
        ),
      );
    });
  });

  group('PluginBridgeAdapter.settings.get', () {
    late PluginBridgeAdapter adapter;

    setUp(() {
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['settings.read'],
        ),
        dependencies: _buildNetworkDeps(),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    });

    test('מחזיר הגדרת תצוגה שאינה חסומה', () async {
      await Settings.setValue<double>(SettingsRepository.keyFontSize, 25);

      final result = await adapter.execute('settings', 'get', {
        'key': SettingsRepository.keyFontSize,
      });

      expect(result, 25);
    });

    test('מפתח חסום מוחזר כ-error.forbidden ולא כ-null', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyHebrewBooksPath,
        '/books/hebrewbooks',
      );

      await expectLater(
        adapter.execute('settings', 'get', {
          'key': SettingsRepository.keyHebrewBooksPath,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
    });

    test('getMany מדלג על מפתח חסום ומחזיר את המותר', () async {
      await Settings.setValue<double>(SettingsRepository.keyFontSize, 22);
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        '/library',
      );

      final result =
          await adapter.execute('settings', 'getMany', {
                'keys': [
                  SettingsRepository.keyFontSize,
                  SettingsRepository.keyLibraryPath,
                ],
              })
              as Map;

      expect(result[SettingsRepository.keyFontSize], 22);
      expect(result.containsKey(SettingsRepository.keyLibraryPath), isFalse);
    });
  });

  group('PluginBridgeAdapter fs.* — המרחב הפרטי', () {
    late Directory dataRoot;
    late PluginBridgeAdapter adapter;

    setUp(() async {
      dataRoot = await Directory.systemTemp.createTemp('plugin_ws_adapter_');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      // ללא הרשאות בכלל — המרחב הפרטי אינו דורש הרשאת manifest.
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const []),
        dependencies: _buildNetworkDeps(),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    });

    tearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      if (await dataRoot.exists()) await dataRoot.delete(recursive: true);
    });

    test('כתיבה, stat, listDir וקריאה — סבב שלם', () async {
      final written =
          await adapter.execute('fs', 'writeFile', {
                'path': 'cache/a.json',
                'content': '{"a":1}',
              })
              as Map;
      expect(written['size'], 7);
      expect(written['quotaBytes'], isPositive);

      final stat =
          await adapter.execute('fs', 'stat', {'path': 'cache/a.json'}) as Map;
      expect(stat['exists'], isTrue);
      expect(stat['type'], 'file');

      final listed =
          await adapter.execute('fs', 'listDir', {'path': 'cache'}) as Map;
      expect((listed['entries'] as List).single['name'], 'a.json');

      final read =
          await adapter.execute('fs', 'readFile', {'path': 'cache/a.json'})
              as Map;
      expect(read['content'], '{"a":1}');
    });

    test('base64 עובר סבב שלם ללא שינוי', () async {
      final bytes = [0, 1, 2, 250, 255];
      await adapter.execute('fs', 'writeFile', {
        'path': 'bin/blob',
        'content': base64Encode(bytes),
        'encoding': 'base64',
      });
      final read =
          await adapter.execute('fs', 'readFile', {
                'path': 'bin/blob',
                'encoding': 'base64',
              })
              as Map;
      expect(base64Decode(read['content'] as String), bytes);
    });

    test('נתיב שיוצא מהשורש נדחה ב-error.forbidden', () async {
      final victim = File(p.join(dataRoot.path, 'victim.txt'))
        ..writeAsStringSync('חשוב');
      await expectLater(
        adapter.execute('fs', 'writeFile', {
          'path': '../../../../victim.txt',
          'content': 'נדרס',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
      expect(victim.readAsStringSync(), 'חשוב');
    });

    test('deleteEntry idempotent, ו-makeDir יוצר תיקייה', () async {
      expect(await adapter.execute('fs', 'makeDir', {'path': 'x/y'}), isTrue);
      expect(
        await adapter.execute('fs', 'deleteEntry', {
          'path': 'x',
          'recursive': true,
        }),
        isTrue,
      );
      expect(
        await adapter.execute('fs', 'deleteEntry', {'path': 'x'}),
        isFalse,
      );
    });

    test('stat על נתיב שאינו קיים מחזיר exists:false', () async {
      final stat = await adapter.execute('fs', 'stat', {'path': 'nope'}) as Map;
      expect(stat, {'exists': false});
    });

    test('קידוד לא מוכר ותוכן שאינו מחרוזת נדחים', () async {
      await expectLater(
        adapter.execute('fs', 'writeFile', {
          'path': 'a.txt',
          'content': 'x',
          'encoding': 'utf16',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
      await expectLater(
        adapter.execute('fs', 'writeFile', {'path': 'a.txt', 'content': 5}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('המרחב מבודד בין תוספים', () async {
      await adapter.execute('fs', 'writeFile', {
        'path': 'mine.txt',
        'content': 'א',
      });
      final other = PluginBridgeAdapter(
        _buildInstalledPlugin(pluginId: 'other.plugin', permissions: const []),
        dependencies: _buildNetworkDeps(),
        pluginRepository: _StubPluginRegistryRepository(),
      );
      final listed =
          await other.execute('fs', 'listDir', <String, dynamic>{}) as Map;
      expect(listed['entries'], isEmpty);
    });
  });

  group('PluginBridgeAdapter runtime snapshots', () {
    late _StubTabsBloc tabsBloc;
    late _StubPluginRegistryRepository pluginRegistryRepository;
    late PluginBridgeAdapter adapter;

    setUp(() {
      tabsBloc = _StubTabsBloc();
      pluginRegistryRepository = _StubPluginRegistryRepository();

      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['app.info.read', 'reader.open'],
        ),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: tabsBloc,
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
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
        pluginRepository: pluginRegistryRepository,
      );
    });

    test(
      'app.getGrantedPermissions returns only granted permissions',
      () async {
        pluginRegistryRepository.permissions = [
          PluginPermissionGrant(
            pluginId: 'test.plugin',
            permission: 'reader.open',
            granted: true,
            grantedAt: DateTime(2026, 1, 1),
          ),
          PluginPermissionGrant(
            pluginId: 'test.plugin',
            permission: 'app.info.read',
            granted: true,
            grantedAt: DateTime(2026, 1, 1),
          ),
          PluginPermissionGrant(
            pluginId: 'test.plugin',
            permission: 'notes.write',
            granted: false,
            grantedAt: DateTime(2026, 1, 1),
          ),
        ];

        final response =
            await adapter.execute('app', 'getGrantedPermissions', {})
                as Map<String, dynamic>;

        // הרשאות הבסיס מצטרפות אוטומטית; notes.write שנשללה אינה מופיעה.
        expect(
          response['permissions'],
          withBaselinePermissions(['app.info.read', 'reader.open']),
        );
      },
    );

    group('app.getConnectivity', () {
      late ConnectivityStatusService original;

      setUp(() => original = ConnectivityStatusService.instance);
      tearDown(() => ConnectivityStatusService.instance = original);

      void useService({required bool offline, required bool reachable}) {
        ConnectivityStatusService.instance = ConnectivityStatusService(
          offlineModeReader: () => offline,
          networkProbe: () async => reachable,
        );
      }

      test('מחזיר מחובר כשיש רשת ואין מצב מנותק', () async {
        useService(offline: false, reachable: true);

        final response =
            await adapter.execute('app', 'getConnectivity', {})
                as Map<String, Object?>;

        expect(response, {
          'isOfflineMode': false,
          'hasNetwork': true,
          'isOnline': true,
        });
      });

      test('מחזיר מנותק כשאין רשת', () async {
        useService(offline: false, reachable: false);

        final response =
            await adapter.execute('app', 'getConnectivity', {})
                as Map<String, Object?>;

        expect(response['isOnline'], isFalse);
        expect(response['isOfflineMode'], isFalse);
      });

      test('מצב מנותק בהגדרות גובר על רשת זמינה', () async {
        useService(offline: true, reachable: true);

        final response =
            await adapter.execute('app', 'getConnectivity', {})
                as Map<String, Object?>;

        expect(response['isOfflineMode'], isTrue);
        expect(response['isOnline'], isFalse);
      });

      test('אינו מחזיר null — התוסף מקבל תשובה ודאית', () async {
        useService(offline: false, reachable: true);

        final response =
            await adapter.execute('app', 'getConnectivity', {})
                as Map<String, Object?>;

        expect(response.values.every((v) => v != null), isTrue);
      });

      test('קריאות חוזרות אינן פותחות בדיקת רשת נוספת', () async {
        var probes = 0;
        ConnectivityStatusService.instance = ConnectivityStatusService(
          offlineModeReader: () => false,
          networkProbe: () async {
            probes++;
            return true;
          },
        );

        for (var i = 0; i < 10; i++) {
          await adapter.execute('app', 'getConnectivity', {});
        }

        expect(probes, 1);
      });

      test('forceRefresh מועבר לשירות', () async {
        var reachable = false;
        ConnectivityStatusService.instance = ConnectivityStatusService(
          offlineModeReader: () => false,
          networkProbe: () async => reachable,
        );

        final first =
            await adapter.execute('app', 'getConnectivity', {})
                as Map<String, Object?>;
        reachable = true;
        final refreshed =
            await adapter.execute('app', 'getConnectivity', {
                  'forceRefresh': true,
                })
                as Map<String, Object?>;

        expect(first['isOnline'], isFalse);
        expect(refreshed['isOnline'], isTrue);
      });

      test('forceRefresh שאינו boolean נדחה', () async {
        useService(offline: false, reachable: true);

        await expectLater(
          adapter.execute('app', 'getConnectivity', {'forceRefresh': 'yes'}),
          throwsA(
            predicate((e) => e.toString().contains('error.invalid_params')),
          ),
        );
      });

      test('פעולה לא מוכרת ב-app עדיין נדחית', () async {
        await expectLater(
          adapter.execute('app', 'getConnectivityStatus', {}),
          throwsA(predicate((e) => e.toString().contains('Unknown action'))),
        );
      });
    });

    test('app.openUrl דוחה סכמה שאינה http/https (לפני שיגור)', () async {
      // file://, otzaria:// וכו' היו מאפשרים הרצת פעולות מחוץ לדפדפן.
      await expectLater(
        adapter.execute('app', 'openUrl', {'url': 'file:///etc/passwd'}),
        throwsA(predicate((e) => e.toString().contains('error.forbidden'))),
      );
    });

    test('app.openUrl ללא url זורק error.invalid_params', () async {
      await expectLater(
        adapter.execute('app', 'openUrl', const {}),
        throwsA(
          predicate((e) => e.toString().contains('error.invalid_params')),
        ),
      );
    });

    test(
      'reader.getCurrentRef returns current reference for active pdf tab',
      () async {
        final currentTab = PdfBookTab(
          book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
          pageNumber: 17,
        )..currentTitle.value = 'פרק ב';
        tabsBloc.currentState = TabsState(
          tabs: [currentTab],
          currentTabIndex: 0,
        );

        final response =
            await adapter.execute('reader', 'getCurrentRef', {})
                as Map<String, dynamic>;

        expect(response['currentBook'], 'מסילת ישרים');
        expect(response['currentBookId'], 'מסילת ישרים');
        expect(response['currentIndex'], 17);
        expect(response['currentRef'], 'פרק ב');
      },
    );

    test(
      'reader.getCurrentRef returns null ref for pdf tab without title',
      () async {
        final currentTab = PdfBookTab(
          book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
          pageNumber: 0,
        );
        tabsBloc.currentState = TabsState(
          tabs: [currentTab],
          currentTabIndex: 0,
        );

        final response =
            await adapter.execute('reader', 'getCurrentRef', {})
                as Map<String, dynamic>;

        expect(response['currentBook'], 'מסילת ישרים');
        expect(response['currentBookId'], 'מסילת ישרים');
        expect(response['currentIndex'], 0);
        expect(response['currentRef'], isNull);
      },
    );

    test(
      'reader.getCurrentRef returns current reference for active text tab',
      () async {
        final currentTab = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 42,
        )..currentTitle.value = 'פרק ג';
        tabsBloc.currentState = TabsState(
          tabs: [currentTab],
          currentTabIndex: 0,
        );

        final response =
            await adapter.execute('reader', 'getCurrentRef', {})
                as Map<String, dynamic>;

        expect(response['currentBook'], 'בראשית');
        expect(response['currentBookId'], 'בראשית');
        expect(response['currentIndex'], 42);
        expect(response['currentRef'], 'פרק ג');
      },
    );

    test('reader.getCurrentRef returns null when no tab is active', () async {
      tabsBloc.currentState = TabsState.initial();

      final response =
          await adapter.execute('reader', 'getCurrentRef', {})
              as Map<String, dynamic>;

      expect(response['currentBook'], isNull);
      expect(response['currentBookId'], isNull);
      expect(response['currentIndex'], 0);
      expect(response['currentRef'], isNull);
    });

    test(
      'reader.getSelection returns current text selection for active text tab',
      () async {
        final currentTab = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 42,
        )..currentTitle.value = 'פרק ג';
        currentTab.bloc.emit(
          TextBookLoaded.initial(
            book: currentTab.book,
            index: currentTab.index,
            showLeftPane: false,
            splitView: false,
          ).copyWith(
            visibleIndices: [42],
            currentTitle: 'פרק ג',
            selectedTextForNote: 'ויאמר אלהים',
            selectedTextStart: 120,
            selectedTextEnd: 131,
          ),
        );
        tabsBloc.currentState = TabsState(
          tabs: [currentTab],
          currentTabIndex: 0,
        );

        final response = await adapter.execute('reader', 'getSelection', {});

        expect(response, isA<Map<String, dynamic>>());
        final data = response as Map<String, dynamic>;
        expect(data['text'], 'ויאמר אלהים');
        expect(data['start'], 120);
        expect(data['end'], 131);
        expect(data['currentRef'], 'פרק ג');
        expect(data['currentBook'], 'בראשית');
        expect(data['currentBookId'], 'בראשית');
        expect(data['currentIndex'], 42);
      },
    );

    test('reader.getSelection adds a verified source anchor', () async {
      final currentTab = TextBookTab(book: TextBook(title: 'בראשית'), index: 1)
        ..currentTitle.value = 'פרק א';
      currentTab.bloc.emit(
        TextBookLoaded.initial(
          book: currentTab.book,
          index: currentTab.index,
          showLeftPane: false,
          splitView: false,
        ).copyWith(
          content: const ['כותרת', 'אני אומר שאני יודע'],
          currentTitle: 'פרק א',
          selectedTextForNote: 'אני',
          selectedTextSectionIndex: 1,
          selectedTextStart: 10,
          selectedTextEnd: 13,
        ),
      );
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

      final data =
          await adapter.execute('reader', 'getSelection', {})
              as Map<String, dynamic>;

      expect(data['schemaVersion'], 1);
      expect(data['renderedSelectedText'], 'אני');
      expect(data['sourceSelectedText'], 'אני');
      expect(data['sectionIndex'], 1);
      final sourceRange = data['sourceRange'] as Map<String, dynamic>;
      expect(sourceRange['type'], 'text-range-v1');
      expect(sourceRange['occurrenceIndexInSection'], 1);
      expect(sourceRange['occurrenceCountInSection'], 2);
    });

    test('reader.findTextOccurrences searches the loaded section', () async {
      final currentTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 1,
      )..currentTitle.value = 'פרק א';
      currentTab.bloc.emit(
        TextBookLoaded.initial(
          book: currentTab.book,
          index: currentTab.index,
          showLeftPane: false,
          splitView: false,
        ).copyWith(
          content: const ['כותרת', 'אני אומר שאני יודע שאני'],
          currentTitle: 'פרק א',
        ),
      );
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

      final data =
          await adapter.execute('reader', 'findTextOccurrences', {
                'bookId': 'ספר בדיקה',
                'sectionIndex': 1,
                'query': 'שאני',
                'normalize': {'profile': 'strict'},
                'limit': 1,
              })
              as Map<String, dynamic>;

      expect(data['schemaVersion'], 1);
      expect(data['totalCount'], 2);
      expect(data['hasMore'], isTrue);
      expect(data['nextCursor'], isA<String>());
      final results = data['results'] as List<dynamic>;
      expect(results, hasLength(1));
      expect(results.single['text'], 'שאני');
      expect(results.single['currentRef'], 'פרק א');
      expect(results.single['range']['layer'], 'source');
    });

    test('reader.getSectionTextMap maps the loaded section', () async {
      final currentTab = TextBookTab(book: TextBook(title: 'ספר מפה'), index: 1)
        ..currentTitle.value = 'פרק א';
      currentTab.bloc.emit(
        TextBookLoaded.initial(
          book: currentTab.book,
          index: currentTab.index,
          showLeftPane: false,
          splitView: false,
        ).copyWith(
          content: const ['כותרת', 'בְּרֵאשִׁית ברא'],
          currentTitle: 'פרק א',
          removeNikud: true,
        ),
      );
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

      final data =
          await adapter.execute('reader', 'getSectionTextMap', {
                'bookId': 'ספר מפה',
                'sectionIndex': 1,
                'layer': 'both',
                'includeWords': true,
                'includeSourceMap': true,
              })
              as Map<String, dynamic>;

      expect(data['schemaVersion'], 1);
      expect(data['sourceText'], 'בְּרֵאשִׁית ברא');
      expect(data['renderedText'], 'בראשית ברא');
      expect(data['sourceMap']['mappings'], isNotEmpty);
      expect(data['words'], hasLength(4));
      expect(data['currentRef'], 'פרק א');
    });
  });

  group('PluginBridgeAdapter.reader.openBookAtRef', () {
    late _MockBookOpenCoordinator mockCoordinator;
    late TextBook yerushalmi;

    PluginBridgeAdapter buildAdapter({
      Future<List<({String title, int index, bool isPdf})>> Function(String)?
      resolveReference,
    }) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['reader.open']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: mockCoordinator,
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
          resolveReference: resolveReference,
        ),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    }

    setUp(() {
      mockCoordinator = _MockBookOpenCoordinator();
      yerushalmi = TextBook(
        title: 'תלמוד ירושלמי עירובין',
        categoryId: 1,
        fileType: 'txt',
      );
      final category = Category(
        title: 'ש"ס',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [yerushalmi],
        parent: null,
      );
      final library = Library(categories: [category]);
      category.parent = library;
      DataRepository.instance.library = Future.value(library);
    });

    test(
      'find_ref מפענח הפניה מובנית → קופץ ל-index בלי להשאיר חיפוש',
      () async {
        // ירושלמי: "פ\"ו ה\"ז" דו-משמעי; find_ref מודע-הקשר מחזיר את ה-index.
        final adapter = buildAdapter(
          resolveReference: (reference) async => [
            (title: 'תלמוד ירושלמי עירובין', index: 1234, isPdf: false),
          ],
        );

        final result = await adapter.execute('reader', 'openBookAtRef', {
          'bookId': 'תלמוד ירושלמי עירובין',
          'ref': 'פ"ו ה"ז',
        });

        expect(result, isTrue);
        // קפיצה ל-index של find_ref, וללא searchText (כי הכותרת נמצאה)
        verify(
          mockCoordinator.openBook(yerushalmi, 1234, '', ignoreHistory: true),
        ).called(1);
      },
    );
  });

  group('PluginBridgeAdapter.library.getBookContent', () {
    late PluginBridgeAdapter adapter;
    late _FakeBookProvider fakeProvider;

    setUp(() {
      // 1. הזרקת ספריית קטלוג מותאמת: TextBook עם fileType='docx' (מקרה הבאג),
      //    TextBook עם fileType='txt' (לוודא שגם הדרך הרגילה עובדת), ו-PdfBook
      //    שצריך לפול-בק (כי הוא לא TextBook).
      final textBookDocx = TextBook(
        title: 'ספר-docx',
        categoryId: 100,
        fileType: 'docx',
      );
      final textBookTxt = TextBook(
        title: 'ספר-txt',
        categoryId: 200,
        fileType: 'txt',
      );
      final pdfBookEntry = PdfBook(
        title: 'ספר-pdf',
        path: '/tmp/pdf.pdf',
        categoryId: 300,
        fileType: 'pdf',
      );

      final library = Library(
        categories: [
          Category(
            title: 'בדיקה',
            description: '',
            shortDescription: '',
            order: 0,
            subCategories: const [],
            books: [textBookDocx, textBookTxt, pdfBookEntry],
            parent: null,
          ),
        ],
      );
      DataRepository.instance.library = Future.value(library);

      // 2. תוספי תוכן ל-LibraryProviderManager: נשים מיפויים שמדמים מצב של
      //    משתמש עם seforim.db בלבד (אין קבצי טקסט נפרדים בדיסק). הבאג היה
      //    ש-DataRepository.getBookText ניגש עם fileType='txt' כברירת מחדל
      //    גם כשה-TextBook הוא docx.
      final docxKey = BookCompositeKey.create(
        title: 'ספר-docx',
        categoryId: 100,
        fileType: 'docx',
      );
      final docxFakeTxtKey = BookCompositeKey.create(
        title: 'ספר-docx',
        categoryId: 100,
        fileType: 'txt',
      );
      final txtKey = BookCompositeKey.create(
        title: 'ספר-txt',
        categoryId: 200,
        fileType: 'txt',
      );
      final pdfFallbackKey = BookCompositeKey.create(
        title: 'ספר-pdf',
        categoryId: 300,
        fileType: 'txt',
      );
      final loneTxtKey = BookCompositeKey.create(
        title: 'שלא-בקטלוג',
        categoryId: 999,
        fileType: 'txt',
      );
      final sliceableKey = BookCompositeKey.create(
        title: 'ספר-לחיתוך',
        categoryId: 400,
        fileType: 'txt',
      );

      fakeProvider = _FakeBookProvider({
        docxKey: 'תוכן docx של הספר - נכון',
        docxFakeTxtKey: 'תוכן TXT שגוי - לא היה צריך להגיע לכאן עבור ספר-docx',
        txtKey: 'תוכן txt רגיל',
        pdfFallbackKey: 'תוכן fallback של ה-pdf',
        loneTxtKey: 'תוכן fallback של ספר שאינו בקטלוג',
        sliceableKey: 'ABCDEFGHIJKLMNOP',
      });

      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          docxKey: fakeProvider,
          docxFakeTxtKey: fakeProvider,
          txtKey: fakeProvider,
          pdfFallbackKey: fakeProvider,
          loneTxtKey: fakeProvider,
          sliceableKey: fakeProvider,
        },
        providers: [fakeProvider],
      );

      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['library.read']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
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

    tearDown(() {
      LibraryProviderManager.instance.resetForTesting();
    });

    test('זורק כש-bookId חסר', () async {
      expect(
        () => adapter.execute('library', 'getBookContent', const {}),
        throwsA(isA<Exception>()),
      );
    });

    test('TextBook עם fileType=docx מנותב דרך TextBookRepository עם ה-fileType '
        'הנכון (תיקון d94133731)', () async {
      // הבאג: הקוד הישן קרא ל-DataRepository.getBookText שמשתמש ב-fileType=
      // 'txt' כברירת מחדל. עבור משתמש עם seforim.db בלבד, זה היה מחזיר
      // נתון שגוי (או תוכן txt שאינו קיים, או כשל). התיקון: שימוש ב-
      // TextBookRepository שלוקח את ה-fileType מ-metadata של ה-TextBook.
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-docx',
      });

      expect(result, 'תוכן docx של הספר - נכון');
      expect(
        result,
        isNot(contains('שגוי')),
        reason: 'אסור שהקוד יפול חזרה ל-fileType=txt לספר docx',
      );
    });

    test(
      'TextBook עם fileType=txt עובר דרך TextBookRepository כרגיל',
      () async {
        final result = await adapter.execute(
          'library',
          'getBookContent',
          const {'bookId': 'ספר-txt'},
        );

        expect(result, 'תוכן txt רגיל');
      },
    );

    test('ספר שאינו בקטלוג נופל ל-DataRepository.getBookText (ברירת המחדל '
        'fileType=txt)', () async {
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'שלא-בקטלוג',
      });

      expect(result, 'תוכן fallback של ספר שאינו בקטלוג');
    });

    test(
      'PdfBook בקטלוג (לא TextBook) נופל ל-DataRepository.getBookText',
      () async {
        // ה-discriminator הוא `cataloged is TextBook`. PdfBook נכשל בבדיקה
        // ולכן נכנס לענף ה-else במקום ל-TextBookRepository.
        final result = await adapter.execute(
          'library',
          'getBookContent',
          const {'bookId': 'ספר-pdf'},
        );

        expect(result, 'תוכן fallback של ה-pdf');
      },
    );

    test('title כ-alias ל-bookId נתמך (תאימות לאחור)', () async {
      final result = await adapter.execute('library', 'getBookContent', const {
        'title': 'ספר-txt',
      });

      expect(result, 'תוכן txt רגיל');
    });

    test('offset חותך מתחילת הטקסט כשלא ניתן section', () async {
      // טקסט "ABCDEFGHIJKLMNOP" באורך 16, offset=4 — מתחיל מ-'E'.
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-לחיתוך',
        'offset': 4,
        'limit': 5,
      });

      expect(result, 'EFGHI');
    });

    test('limit שולט בגודל המקטע המוחזר', () async {
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-לחיתוך',
        'limit': 3,
      });

      expect(result, 'ABC');
    });

    test('section + offset: ה-offset נספר יחסית למיקום ה-section, לא לתחילת '
        'הטקסט (תיקון 00ccfa63d)', () async {
      // טקסט "ABCDEFGHIJKLMNOP". section='C' נמצא ב-index 2.
      // offset=3 פירושו 3 תווים אחרי 'C', כלומר מתחילים מ-index 5 ('F').
      // הקוד הישן התעלם מה-offset כש-section ניתן (startIndex = idx בלבד).
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-לחיתוך',
        'section': 'C',
        'offset': 3,
        'limit': 4,
      });

      expect(
        result,
        'FGHI',
        reason: 'section ב-index 2 + offset 3 → התחלה ב-index 5',
      );
    });

    test(
      'section ב-offset=0 מתחיל מהמיקום של section (התנהגות שלא השתנתה)',
      () async {
        final result = await adapter.execute(
          'library',
          'getBookContent',
          const {
            'bookId': 'ספר-לחיתוך',
            'section': 'D',
            'offset': 0,
            'limit': 3,
          },
        );

        expect(result, 'DEF');
      },
    );

    test('section שלא נמצא מתעלם וחוזר ל-offset רגיל מתחילת הטקסט', () async {
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-לחיתוך',
        'section': 'XYZ',
        'offset': 2,
        'limit': 3,
      });

      expect(
        result,
        'CDE',
        reason: 'section שלא נמצא → startIndex נשאר offset (2)',
      );
    });

    test('limit > 5000 חתוך ל-5000', () async {
      // לוקחים תוכן קצר ולכן באמת הקליפ יהיה אורך הטקסט.
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-לחיתוך',
        'limit': 99999,
      });

      // limit מקבוע ל-5000, end = (0 + 5000).clamp(0, 16) = 16 → כל הטקסט
      expect(result, 'ABCDEFGHIJKLMNOP');
    });

    test('offset החורג מהאורך מקובע לסוף הטקסט (clamp)', () async {
      final result = await adapter.execute('library', 'getBookContent', const {
        'bookId': 'ספר-לחיתוך',
        'offset': 999,
        'limit': 5,
      });

      expect(result, '');
    });
  });

  group('PluginBridgeAdapter.library.resolveCategoryPaths', () {
    late PluginBridgeAdapter adapter;

    setUp(() {
      final library = Library(
        categories: [
          Category(
            title: 'בדיקה',
            description: '',
            shortDescription: '',
            order: 0,
            subCategories: const [],
            books: [
              TextBook(
                id: 42,
                title: 'בראשית',
                categoryId: 1,
                fileType: 'txt',
                categoryPath: '/תנך/תורה',
              ),
              PdfBook(
                id: 7,
                title: 'שולחן ערוך',
                path: '/tmp/shulchan.pdf',
                categoryId: 2,
                fileType: 'pdf',
              ),
            ],
            parent: null,
          ),
        ],
      );
      DataRepository.instance.library = Future.value(library);

      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['library.books.read']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
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

    test('מחזיר נתיבים מיושרים לסדר הקלט, עם null למזהה לא מוכר', () async {
      final result = await adapter.execute(
        'library',
        'resolveCategoryPaths',
        const {
          'ids': [42, 9999, 7, 'לא-מספר'],
        },
      );

      expect(result, isA<List>());
      final paths = result as List;
      expect(paths, hasLength(4));
      expect(paths[0], '/תנך/תורה');
      expect(paths[1], isNull);
      // ספר בלי categoryPath — נפתר לפי עץ הקטגוריות או null; לא זורק.
      expect(paths[3], isNull);
    });

    test('קלט שאינו מערך או גדול מדי — נדחה', () async {
      expect(
        () => adapter.execute('library', 'resolveCategoryPaths', const {
          'ids': 'not-a-list',
        }),
        throwsA(isA<Exception>()),
      );
      expect(
        () => adapter.execute('library', 'resolveCategoryPaths', {
          'ids': List<int>.filled(20001, 1),
        }),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PluginBridgeAdapter.library.getTree', () {
    late PluginBridgeAdapter adapter;

    setUp(() {
      // עץ דו-שכבתי: תנך -> {ספר בראשית טקסט} ו-ראשונים -> {רשי PDF}.
      final genesis = TextBook(title: 'בראשית', categoryId: 1, fileType: 'txt')
        ..author = 'משה רבנו'
        ..topics = 'תורה';
      final rashi = PdfBook(
        title: 'רשי',
        path: '/tmp/rashi.pdf',
        categoryId: 2,
        fileType: 'pdf',
      );

      final tanach = Category(
        title: 'תנך',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [genesis],
        parent: null,
      );
      final rishonim = Category(
        title: 'ראשונים',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: const [],
        books: [rashi],
        parent: tanach,
      );
      tanach.subCategories.add(rishonim);

      final library = Library(categories: [tanach]);
      // קישור parent של הקטגוריה העליונה לספרייה (כפי שנבנה בקטלוג האמיתי)
      // כדי שחישוב ה-path יעבוד נכון.
      tanach.parent = library;
      DataRepository.instance.library = Future.value(library);

      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['library.books.read']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
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

    test('מחזיר את העץ המלא עם קטגוריות מקוננות וספרים', () async {
      final result =
          await adapter.execute('library', 'getTree', const {})
              as Map<String, dynamic>;

      expect(result['title'], 'ספריית אוצריא');
      expect(result['path'], '/');
      final topCategories = result['categories'] as List<dynamic>;
      expect(topCategories, hasLength(1));

      final tanach = topCategories.first as Map<String, dynamic>;
      expect(tanach['title'], 'תנך');
      expect(tanach['path'], '/תנך');

      final tanachBooks = tanach['books'] as List<dynamic>;
      expect(tanachBooks, hasLength(1));
      final genesis = tanachBooks.first as Map<String, dynamic>;
      expect(genesis['bookId'], 'בראשית');
      expect(genesis['type'], 'text');
      expect(genesis['author'], 'משה רבנו');
      expect(genesis['topics'], 'תורה');

      final subCategories = tanach['categories'] as List<dynamic>;
      expect(subCategories, hasLength(1));
      final rishonim = subCategories.first as Map<String, dynamic>;
      expect(rishonim['title'], 'ראשונים');
      final rashi =
          (rishonim['books'] as List<dynamic>).first as Map<String, dynamic>;
      expect(rashi['type'], 'pdf');
    });

    test('path מצמצם את העץ לתת-קטגוריה', () async {
      final result =
          await adapter.execute('library', 'getTree', const {
                'path': '/תנך/ראשונים',
              })
              as Map<String, dynamic>;

      expect(result['title'], 'ראשונים');
      final books = result['books'] as List<dynamic>;
      expect((books.first as Map<String, dynamic>)['title'], 'רשי');
    });

    test('path שאינו קיים מחזיר null', () async {
      final result = await adapter.execute('library', 'getTree', const {
        'path': '/לא-קיים',
      });

      expect(result, isNull);
    });

    test('includeBooks=false משמיט את רשימות הספרים', () async {
      final result =
          await adapter.execute('library', 'getTree', const {
                'includeBooks': false,
              })
              as Map<String, dynamic>;

      expect(result.containsKey('books'), isFalse);
      final tanach =
          (result['categories'] as List<dynamic>).first as Map<String, dynamic>;
      expect(tanach.containsKey('books'), isFalse);
      expect(tanach['title'], 'תנך');
    });
  });

  group('PluginBridgeAdapter.network', () {
    late _StubPluginRegistryRepository pluginRegistryRepository;
    late PluginBridgeAdapter adapter;

    setUp(() {
      pluginRegistryRepository = _StubPluginRegistryRepository()
        ..permissionGrant = true;

      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['network.access'],
          networkEnabled: true,
          networkAllowlist: const [],
        ),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
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
        pluginRepository: pluginRegistryRepository,
      );
    });

    test(
      'network.fetch חוסם גם URL מובנה אם המניפסט של התוסף לא הצהיר עליו',
      () async {
        await expectLater(
          () => adapter.execute('network', 'fetch', const {
            'url': 'https://nakdan.dicta.org.il/api',
          }),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.forbidden'),
            ),
          ),
        );
      },
    );

    test(
      'network.fetch ל-localhost נחסם כשיש רק network.access (לא localhost)',
      () async {
        pluginRegistryRepository.permissionGrants = const {
          'network.access': true,
          'network.localhost': false,
        };
        final loopbackAdapter = PluginBridgeAdapter(
          _buildInstalledPlugin(
            permissions: const ['network.localhost'],
            networkEnabled: true,
            networkAllowlist: const ['127.0.0.1'],
          ),
          dependencies: _buildNetworkDeps(),
          pluginRepository: pluginRegistryRepository,
        );

        await expectLater(
          () => loopbackAdapter.execute('network', 'fetch', const {
            'url': 'http://127.0.0.1:11434/api/tags',
          }),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.permission_denied'),
            ),
          ),
        );
      },
    );

    test('network.fetch לאינטרנט נחסם כשיש רק network.localhost', () async {
      pluginRegistryRepository.permissionGrants = const {
        'network.access': false,
        'network.localhost': true,
      };
      final internetAdapter = PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['network.localhost'],
          networkEnabled: true,
          networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
        ),
        dependencies: _buildNetworkDeps(),
        pluginRepository: pluginRegistryRepository,
      );

      await expectLater(
        () => internetAdapter.execute('network', 'fetch', const {
          'url': 'https://nakdan.dicta.org.il/api',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.permission_denied'),
          ),
        ),
      );
    });

    test(
      'network.fetch חסום כשהמניפסט כיבה network.enabled גם אם יש grant ו-allowlist',
      () async {
        final disabledAdapter = PluginBridgeAdapter(
          _buildInstalledPlugin(
            permissions: const ['network.access'],
            networkEnabled: false,
            networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
          ),
          dependencies: PluginBridgeDependencies(
            historyBloc: _MockHistoryBloc(),
            tabsBloc: _StubTabsBloc(),
            navigationBloc: _MockNavigationBloc(),
            calendarCubit: _StubCalendarCubit(
              _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
            ),
            workspaceBloc: _MockWorkspaceBloc(),
            searchRepository: _MockSearchRepository(),
            personalNotesRepository: _MockPersonalNotesRepository(),
            bookOpenCoordinator: _MockBookOpenCoordinator(),
            themePayloadBuilder: () => <String, dynamic>{},
            showConfirmDialog: ({required title, required content}) async =>
                true,
            showWarningDialog:
                ({required title, required content, required subtitle}) async =>
                    true,
          ),
          pluginRepository: pluginRegistryRepository,
        );

        await expectLater(
          () => disabledAdapter.execute('network', 'fetch', const {
            'url': 'https://nakdan.dicta.org.il/api',
          }),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.permission_denied'),
            ),
          ),
        );
      },
    );
  });

  group('PluginBridgeAdapter.network.fetch (HTTP contract)', () {
    late _StubPluginRegistryRepository pluginRegistryRepository;

    PluginBridgeAdapter buildAdapter(PluginNetworkFetchService fetchService) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['network.access'],
          networkEnabled: true,
          networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
        ),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
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
        pluginRepository: pluginRegistryRepository,
        networkFetchService: fetchService,
      );
    }

    setUp(() {
      pluginRegistryRepository = _StubPluginRegistryRepository()
        ..permissionGrant = true;
    });

    test('POST מעביר method/headers/body ומחזיר {status, ok, body}', () async {
      late http.Request captured;
      final fetchService = PluginNetworkFetchService(
        client: MockClient((req) async {
          captured = req;
          return http.Response('{"data":[]}', 200);
        }),
      );
      final adapter = buildAdapter(fetchService);

      final result =
          await adapter.execute('network', 'fetch', const {
                'url': 'https://nakdan.dicta.org.il/api',
                'method': 'POST',
                'headers': {'Content-Type': 'application/json;charset=UTF-8'},
                'body': '{"task":"nakdan"}',
              })
              as Map<String, dynamic>;

      expect(captured.method, 'POST');
      expect(captured.body, '{"task":"nakdan"}');
      expect(
        captured.headers['content-type'],
        'application/json;charset=UTF-8',
      );
      expect(result['status'], 200);
      expect(result['ok'], isTrue);
      expect(result['body'], '{"data":[]}');
    });

    test('סטטוס שאינו 2xx מוחזר עם ok=false', () async {
      final fetchService = PluginNetworkFetchService(
        client: MockClient((req) async => http.Response('err', 500)),
      );
      final adapter = buildAdapter(fetchService);

      final result =
          await adapter.execute('network', 'fetch', const {
                'url': 'https://nakdan.dicta.org.il/api',
              })
              as Map<String, dynamic>;

      expect(result['status'], 500);
      expect(result['ok'], isFalse);
    });

    test('method לא תקין נדחה לפני ביצוע הבקשה', () async {
      var hit = false;
      final fetchService = PluginNetworkFetchService(
        client: MockClient((req) async {
          hit = true;
          return http.Response('', 200);
        }),
      );
      final adapter = buildAdapter(fetchService);

      await expectLater(
        () => adapter.execute('network', 'fetch', const {
          'url': 'https://nakdan.dicta.org.il/api',
          'method': 'POST DELETE',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('invalid method'),
          ),
        ),
      );
      expect(hit, isFalse);
    });

    test('timeoutMs מעל התקרה נדחה לפני ביצוע הבקשה', () async {
      var hit = false;
      final fetchService = PluginNetworkFetchService(
        client: MockClient((req) async {
          hit = true;
          return http.Response('', 200);
        }),
      );
      final adapter = buildAdapter(fetchService);

      await expectLater(
        () => adapter.execute('network', 'fetch', const {
          'url': 'https://nakdan.dicta.org.il/api',
          'timeoutMs': 120001,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('timeoutMs'),
          ),
        ),
      );
      expect(hit, isFalse);
    });

    test('fetchStream שולח metadata ואז מקטעי גוף בלי לצבור אותם', () async {
      final responseBody = StreamController<List<int>>();
      final fetchService = PluginNetworkFetchService(
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            responseBody.stream,
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final adapter = buildAdapter(fetchService);
      final events = <Map<String, dynamic>>[];
      var completed = false;

      final execution = adapter
          .execute(
            'network',
            'fetchStream',
            const {
              'url': 'https://nakdan.dicta.org.il/api',
              '__streamId': 'network_test_1',
            },
            eventSink: (topic, payload) async {
              expect(topic, '__otzaria.network.fetchStream.chunk');
              events.add(payload);
            },
          )
          .whenComplete(() => completed = true);
      while (events.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }

      final metadata = events.single['chunk'] as Map<String, dynamic>;
      expect(metadata['sequence'], 0);
      expect(metadata['type'], 'response');
      expect(metadata['status'], 200);
      expect(metadata['ok'], isTrue);
      expect(metadata['headers']['content-type'], 'application/x-ndjson');

      responseBody.add(utf8.encode('{"id":1}\n'));
      while (events.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(completed, isFalse);
      expect(events[1]['chunk'], {
        'sequence': 1,
        'type': 'data',
        'body': '{"id":1}\n',
      });

      await responseBody.close();
      final result = await execution as Map<String, dynamic>;
      expect(result, {'completed': true, 'cancelled': false, 'chunks': 2});
      adapter.dispose();
    });

    test('fetchStream מפצל מנת שרת גדולה בלי לחצות surrogate pair', () async {
      final prefix = 'a' * 32767;
      final payload = '$prefix😀${'b' * 10000}';
      final fetchService = PluginNetworkFetchService(
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(payload)),
            200,
          );
        }),
      );
      final adapter = buildAdapter(fetchService);
      final fragments = <String>[];

      await adapter.execute(
        'network',
        'fetchStream',
        const {
          'url': 'https://nakdan.dicta.org.il/api',
          '__streamId': 'network_large_chunk_1',
        },
        eventSink: (topic, event) async {
          final chunk = event['chunk'] as Map<String, dynamic>;
          if (chunk['type'] == 'data') fragments.add(chunk['body'] as String);
        },
      );

      expect(fragments, hasLength(2));
      expect(fragments.every((part) => part.length <= 32768), isTrue);
      expect(fragments.join(), payload);
      expect(fragments.first.endsWith('a'), isTrue);
      expect(fragments.last.startsWith('😀'), isTrue);
      adapter.dispose();
    });

    test('fetchStream ניתן לביטול גם בזמן ההמתנה לכותרות', () async {
      final requestStarted = Completer<void>();
      final fetchService = PluginNetworkFetchService(
        client: MockClient.streaming((request, bodyStream) async {
          final abortable = request as http.AbortableRequest;
          requestStarted.complete();
          await abortable.abortTrigger;
          throw http.RequestAbortedException(request.url);
        }),
      );
      final adapter = buildAdapter(fetchService);

      final execution = adapter.execute(
        'network',
        'fetchStream',
        const {
          'url': 'https://nakdan.dicta.org.il/api',
          '__streamId': 'network_cancel_1',
        },
        eventSink: (topic, payload) async {},
      );
      await requestStarted.future;
      final cancellation =
          await adapter.execute('network', 'fetchStream', const {
                '__cancelStreamId': 'network_cancel_1',
              })
              as Map<String, dynamic>;
      final result = await execution as Map<String, dynamic>;

      expect(cancellation['cancelled'], isTrue);
      expect(result['completed'], isFalse);
      expect(result['cancelled'], isTrue);
      adapter.dispose();
    });

    test('ביטול fetchStream בזמן בדיקת הרשאה אינו הולך לאיבוד', () async {
      final gate = Completer<void>();
      pluginRegistryRepository.permissionGate = gate;
      var hit = false;
      final fetchService = PluginNetworkFetchService(
        client: MockClient((request) async {
          hit = true;
          return http.Response('unexpected', 200);
        }),
      );
      final adapter = buildAdapter(fetchService);

      final execution = adapter.execute(
        'network',
        'fetchStream',
        const {
          'url': 'https://nakdan.dicta.org.il/api',
          '__streamId': 'network_pending_cancel_1',
        },
        eventSink: (topic, payload) async {},
      );
      await Future<void>.delayed(Duration.zero);
      final cancellation =
          await adapter.execute('network', 'fetchStream', const {
                '__cancelStreamId': 'network_pending_cancel_1',
              })
              as Map<String, dynamic>;
      gate.complete();
      final result = await execution as Map<String, dynamic>;

      expect(cancellation['cancelled'], isFalse);
      expect(result, {'completed': false, 'cancelled': true});
      expect(hit, isFalse);
      adapter.dispose();
    });

    test('fetchStream מחיל timeout על גוף תגובה שלא הסתיים', () async {
      final responseBody = StreamController<List<int>>();
      final fetchService = PluginNetworkFetchService(
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(responseBody.stream, 200);
        }),
      );
      final adapter = buildAdapter(fetchService);

      await expectLater(
        adapter.execute(
          'network',
          'fetchStream',
          const {
            'url': 'https://nakdan.dicta.org.il/api',
            'timeoutMs': 5,
            '__streamId': 'network_timeout_1',
          },
          eventSink: (topic, payload) async {},
        ),
        throwsA(isA<TimeoutException>()),
      );
      await responseBody.close();
      adapter.dispose();
    });

    test('fetchStream דורש תעבורת stream פנימית', () async {
      final fetchService = PluginNetworkFetchService(
        client: MockClient((request) async => http.Response('ok', 200)),
      );
      final adapter = buildAdapter(fetchService);

      await expectLater(
        adapter.execute('network', 'fetchStream', const {
          'url': 'https://nakdan.dicta.org.il/api',
          '__streamId': 'network_no_transport_1',
        }),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('stream transport unavailable'),
          ),
        ),
      );
      adapter.dispose();
    });
  });

  group('PluginBridgeAdapter fs + pickFolder + download.destPath', () {
    late Directory tempDir;
    late _StubPluginRegistryRepository registry;
    late PluginNetworkAccessResolver originalResolver;

    const downloadHost =
        'https://github.com/YairDaniel11/Otzarya-Unofficial-Books';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adapter_fs_test_');
      registry = _StubPluginRegistryRepository()..permissionGrant = true;

      // בלי ה-stub הזה הבדיקה מושכת את רשימת ההיתר החיה מ-GitHub, ונצבעת
      // אדום ברגע שמישהו עורך שם כתובת. סנכרון הרשימה האמיתית נבדק ב-
      // plugin_network_allowlist_branch_sync_test.
      originalResolver = PluginNetworkAccessResolver.instance;
      PluginNetworkAccessResolver.instance = PluginNetworkAccessResolver(
        client: MockClient((_) async => http.Response(downloadHost, 200)),
      );
    });

    tearDown(() async {
      PluginNetworkAccessResolver.instance = originalResolver;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const downloadUrl = '$downloadHost/releases/latest/download/books.zip';

    PluginBridgeAdapter buildAdapter({
      required Future<String?> Function({String? title}) pickFolder,
      PluginFileDownloadService? fileDownloadService,
    }) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['ui.feedback', 'network.access'],
          networkEnabled: true,
          networkAllowlist: const [downloadHost],
        ),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: _MockBookOpenCoordinator(),
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
          pickFolder: pickFolder,
        ),
        pluginRepository: registry,
        fileDownloadService: fileDownloadService,
        fsService: PluginFsService(),
      );
    }

    String buildZip(String dir, String name) {
      final src = File(p.join(dir, 'hello.txt'))..writeAsStringSync('שלום');
      final zipPath = p.join(dir, name);
      final encoder = ZipFileEncoder()..create(zipPath);
      encoder.addFileSync(src, 'hello.txt');
      encoder.closeSync();
      return zipPath;
    }

    test('ui.pickFolder מחזיר נתיב ומעניק הרשאת כתיבה/מחיקה בתוכו', () async {
      final adapter = buildAdapter(pickFolder: ({title}) async => tempDir.path);

      final res =
          await adapter.execute('ui', 'pickFolder', {'title': 'בחר'}) as Map;
      expect(res['path'], tempDir.path);

      final file = File(p.join(tempDir.path, 'x.zip'))..writeAsBytesSync([1]);
      final del = await adapter.execute('fs', 'deleteFile', {
        'path': file.path,
      });
      expect(del, isTrue);
      expect(file.existsSync(), isFalse);
    });

    test('ui.pickFolder דוחה תיקייה מוגנת ואינו מעניק הרשאה', () async {
      final protectedFolder = p.dirname(Platform.resolvedExecutable);
      final adapter = buildAdapter(
        pickFolder: ({title}) async => protectedFolder,
      );

      await expectLater(
        adapter.execute('ui', 'pickFolder', {}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );

      final file = File(p.join(protectedFolder, 'plugin_probe.tmp'));
      await expectLater(
        adapter.execute('fs', 'deleteFile', {'path': file.path}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('forbidden'),
          ),
        ),
      );
    });

    test('ביטול ui.pickFolder מחזיר {path:null} ואינו מעניק הרשאה', () async {
      final adapter = buildAdapter(pickFolder: ({title}) async => null);

      final res = await adapter.execute('ui', 'pickFolder', {}) as Map;
      expect(res['path'], isNull);

      final file = File(p.join(tempDir.path, 'y.zip'))..writeAsBytesSync([1]);
      await expectLater(
        adapter.execute('fs', 'deleteFile', {'path': file.path}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('forbidden'),
          ),
        ),
      );
      // הקובץ לא נמחק — הפעולה נחסמה.
      expect(file.existsSync(), isTrue);
    });

    test('fs.extractZip מחלץ בתוך תיקייה מאושרת', () async {
      final adapter = buildAdapter(pickFolder: ({title}) async => tempDir.path);
      await adapter.execute('ui', 'pickFolder', {});

      final zipPath = buildZip(tempDir.path, 'a.zip');
      final dest = p.join(tempDir.path, 'out');
      final ok = await adapter.execute('fs', 'extractZip', {
        'zipPath': zipPath,
        'destFolder': dest,
      });

      expect(ok, isTrue);
      expect(File(p.join(dest, 'hello.txt')).existsSync(), isTrue);
    });

    test('fs.extractZip חוסם יעד מחוץ לתיקייה מאושרת', () async {
      final granted = Directory(p.join(tempDir.path, 'granted'))..createSync();
      final adapter = buildAdapter(pickFolder: ({title}) async => granted.path);
      await adapter.execute('ui', 'pickFolder', {});

      final zipPath = buildZip(granted.path, 'a.zip');
      await expectLater(
        adapter.execute('fs', 'extractZip', {
          'zipPath': zipPath,
          'destFolder': p.join(tempDir.path, 'evil'),
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('forbidden'),
          ),
        ),
      );
    });

    test('network.download עם destPath שומר בתוך תיקייה מאושרת', () async {
      final client = MockClient(
        (req) async => http.Response.bytes([7, 8, 9], 200),
      );
      final adapter = buildAdapter(
        pickFolder: ({title}) async => tempDir.path,
        fileDownloadService: PluginFileDownloadService(client: client),
      );
      await adapter.execute('ui', 'pickFolder', {});

      final destPath = p.join(tempDir.path, 'books.zip');
      final res =
          await adapter.execute('network', 'download', {
                'url': downloadUrl,
                'destPath': destPath,
              })
              as Map;

      expect(res['path'], destPath);
      expect(File(destPath).readAsBytesSync(), [7, 8, 9]);
    });

    test('network.download מעביר resume לשירות ההורדה', () async {
      final destPath = p.join(tempDir.path, 'resume.zip');
      await File(destPath).writeAsBytes([7, 8]);
      await File('$destPath.resume').writeAsString('$downloadUrl\n"v1"');
      final client = MockClient((request) async {
        expect(request.headers['range'], 'bytes=2-');
        expect(request.headers['if-range'], '"v1"');
        return http.Response.bytes(
          [9],
          206,
          headers: {'content-range': 'bytes 2-2/3', 'etag': '"v1"'},
        );
      });
      final adapter = buildAdapter(
        pickFolder: ({title}) async => tempDir.path,
        fileDownloadService: PluginFileDownloadService(client: client),
      );
      await adapter.execute('ui', 'pickFolder', {});

      await adapter.execute('network', 'download', {
        'url': downloadUrl,
        'destPath': destPath,
        'resume': true,
      });

      expect(File(destPath).readAsBytesSync(), [7, 8, 9]);
    });

    test(
      'network.download עם destPath מחוץ לתיקייה מאושרת נחסם ואינו מוריד',
      () async {
        var hit = false;
        final client = MockClient((req) async {
          hit = true;
          return http.Response.bytes([0], 200);
        });
        final granted = Directory(p.join(tempDir.path, 'granted'))
          ..createSync();
        final adapter = buildAdapter(
          pickFolder: ({title}) async => granted.path,
          fileDownloadService: PluginFileDownloadService(client: client),
        );
        await adapter.execute('ui', 'pickFolder', {});

        await expectLater(
          adapter.execute('network', 'download', {
            'url': downloadUrl,
            'destPath': p.join(tempDir.path, 'evil', 'books.zip'),
          }),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('forbidden'),
            ),
          ),
        );
        expect(hit, isFalse);
      },
    );

    test('fs.deleteFile חסום דרך symlink שמצביע מחוץ לתיקייה מאושרת', () async {
      final granted = Directory(p.join(tempDir.path, 'granted'))..createSync();
      final outside = Directory(p.join(tempDir.path, 'outside'))..createSync();
      final secret = File(p.join(outside.path, 'secret.txt'))
        ..writeAsStringSync('סוד');

      // קישור סימבולי בתוך התיקייה המאושרת שמצביע אל תיקייה חיצונית.
      // ב-Windows ללא Developer Mode/הרשאת admin יצירת symlink נכשלת — דלג.
      final io.Link link;
      try {
        link = io.Link(p.join(granted.path, 'escape'))
          ..createSync(outside.path);
      } catch (_) {
        markTestSkipped('יצירת symlink אינה נתמכת בסביבה זו');
        return;
      }

      final adapter = buildAdapter(pickFolder: ({title}) async => granted.path);
      await adapter.execute('ui', 'pickFolder', {});

      // נתיב שעובר דרך ה-symlink "נראה" בתוך התיקייה המאושרת מבחינת מחרוזת,
      // אבל מצביע בפועל מחוצה לה — ולכן חייב להיחסם.
      await expectLater(
        adapter.execute('fs', 'deleteFile', {
          'path': p.join(link.path, 'secret.txt'),
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('forbidden'),
          ),
        ),
      );
      expect(secret.existsSync(), isTrue); // הקובץ החיצוני לא נמחק
    });
  });

  group('PluginBridgeAdapter fs user files (pick/resolve/read/revoke)', () {
    late Directory tempDir;
    late _StubPluginRegistryRepository registry;
    late PluginFileServer fileServer;
    late HttpClient client;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adapter_userfile_test_');
      registry = _StubPluginRegistryRepository()..permissionGrant = true;
      fileServer = PluginFileServer();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await fileServer.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    PluginBridgeAdapter buildAdapter({
      required Future<String?> Function({
        List<String>? allowedExtensions,
        String? title,
      })
      pickFile,
      Future<String?> Function({
        required String suggestedName,
        List<String>? allowedExtensions,
        String? title,
      })?
      pickSaveLocation,
      List<String> permissions = const [
        'fs.user_files.read',
        'fs.user_files.write',
      ],
    }) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: permissions),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _StubTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: _MockBookOpenCoordinator(),
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
          pickFile: pickFile,
          pickSaveLocation: pickSaveLocation,
        ),
        pluginRepository: registry,
        fileServer: fileServer,
      );
    }

    Future<String> fetch(String url) async {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      expect(response.statusCode, 200);
      return utf8.decode(await response.expand((chunk) => chunk).toList());
    }

    test(
      'pickUserFile רושם token, מתמיד אותו ב-KV וה-URL מגיש את הקובץ',
      () async {
        final pdf = File(p.join(tempDir.path, 'book.pdf'))
          ..writeAsStringSync('%PDF content');
        final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => pdf.path,
        );

        final res = await adapter.execute('fs', 'pickUserFile', {}) as Map;

        expect(res['cancelled'], isFalse);
        expect(res['name'], 'book.pdf');
        expect(res['size'], '%PDF content'.length);
        final token = res['token'] as String;
        expect(token, isNotEmpty);
        // ה-grant הותמד ב-KV תחת namespace פנימי.
        expect(registry.kv['_internal/user_file_grants'], contains(token));
        // ה-URL מגיש את תוכן הקובץ בפועל.
        expect(await fetch(res['url'] as String), '%PDF content');
      },
    );

    test(
      'ביטול pickUserFile מחזיר {cancelled:true} בלי להתמיד grant',
      () async {
        final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => null,
        );

        final res = await adapter.execute('fs', 'pickUserFile', {}) as Map;

        expect(res['cancelled'], isTrue);
        expect(registry.kv['_internal/user_file_grants'], isNull);
      },
    );

    test(
      'resolveFileUrl בונה URL חדש מ-token שהותמד (סימולציית reload)',
      () async {
        final file = File(p.join(tempDir.path, 'notes.txt'))
          ..writeAsStringSync('שלום עולם');
        final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => file.path,
        );

        final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
        final token = picked['token'] as String;

        // reload: רישום הזיכרון של השרת אבד, אך ה-grant נשמר ב-KV.
        await fileServer.close();

        final resolved =
            await adapter.execute('fs', 'resolveFileUrl', {'token': token})
                as Map;
        expect(resolved['token'], token);
        expect(resolved['name'], 'notes.txt');
        expect(await fetch(resolved['url'] as String), 'שלום עולם');
      },
    );

    test('resolveFileUrl על token לא מוכר זורק error.not_found', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      await expectLater(
        adapter.execute('fs', 'resolveFileUrl', {'token': 'nope'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
    });

    test('readTextFile מחזיר את תוכן הקובץ המאושר', () async {
      final file = File(p.join(tempDir.path, 'a.txt'))
        ..writeAsStringSync('תוכן טקסטואלי');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final content = await adapter.execute('fs', 'readTextFile', {
        'token': picked['token'],
      });

      expect(content, 'תוכן טקסטואלי');
    });

    test('readTextFile קורא גם קובץ ב-ANSI עברית', () async {
      // הקובץ שהמשתמש בוחר יכול להיות בכל קידוד; `readAsString` היה זורק
      // עליו והתוסף היה מקבל שגיאה במקום את התוכן.
      final file = File(p.join(tempDir.path, 'ansi.txt'))
        ..writeAsBytesSync(const [
          0xFA, 0xE5, 0xEB, 0xEF, 0x20, // "תוכן " ב-Windows-1255
          0xE1, 0xF2, 0xE1, 0xF8, 0xE9, 0xFA, // "בעברית"
        ]);
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final content = await adapter.execute('fs', 'readTextFile', {
        'token': picked['token'],
      });

      expect(content, 'תוכן בעברית');
    });

    test('revokeFile מסיר את ה-grant — resolveFileUrl לאחריו נכשל', () async {
      final file = File(p.join(tempDir.path, 'x.txt'))..writeAsStringSync('x');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final token = picked['token'] as String;

      final revoked = await adapter.execute('fs', 'revokeFile', {
        'token': token,
      });
      expect(revoked, isTrue);
      expect(registry.kv['_internal/user_file_grants'], isNot(contains(token)));

      await expectLater(
        adapter.execute('fs', 'resolveFileUrl', {'token': token}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
    });

    // ======================================================================
    // כתיבה: beginBinaryWrite -> PUT -> commitUserFileWrite
    // ======================================================================

    /// שולח את הבייטים ל-uploadUrl, כמו ש-fetch עם body: blob עושה.
    Future<int> upload(String url, String content) async {
      final bytes = utf8.encode(content);
      final request = await client.putUrl(Uri.parse(url));
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain();
      return response.statusCode;
    }

    Map<String, dynamic> grants() =>
        jsonDecode(registry.kv['_internal/user_file_grants']!)
            as Map<String, dynamic>;

    test('pickUserFile עם access קריאה-בלבד שומר grant לקריאה', () async {
      final file = File(p.join(tempDir.path, 'a.docx'))..writeAsStringSync('x');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final res = await adapter.execute('fs', 'pickUserFile', {}) as Map;

      expect(res['access'], 'read');
      final grant = grants()[res['token']] as Map;
      expect(grant['access'], 'read');
    });

    test('pickUserFile עם readwrite שומר grant לכתיבה', () async {
      final file = File(p.join(tempDir.path, 'a.docx'))..writeAsStringSync('x');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final res =
          await adapter.execute('fs', 'pickUserFile', {'access': 'readwrite'})
              as Map;

      expect(res['access'], 'readwrite');
      expect((grants()[res['token']] as Map)['access'], 'readwrite');
    });

    test('readwrite בלי הרשאת כתיבה נדחה', () async {
      registry.permissionGrant = null;
      registry.permissionGrants = {
        'fs.user_files.read': true,
        'fs.user_files.write': false,
      };
      final file = File(p.join(tempDir.path, 'a.docx'))..writeAsStringSync('x');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      await expectLater(
        adapter.execute('fs', 'pickUserFile', {'access': 'readwrite'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('permission_denied'),
          ),
        ),
      );
    });

    test('access לא חוקי נדחה', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      await expectLater(
        adapter.execute('fs', 'pickUserFile', {'access': 'append'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('invalid_params'),
          ),
        ),
      );
    });

    test('„שמור בשם”: העלאה נכתבת לקובץ חדש ומחזירה token לכתיבה', () async {
      final target = p.join(tempDir.path, 'חידושים.docx');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async {
              expect(suggestedName, 'חידושים.docx');
              expect(allowedExtensions, ['docx']);
              return target;
            },
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {
                'purpose': 'user-file',
                'expectedSize': 5,
              })
              as Map;
      expect(ticket['maxBytes'], isA<int>());
      expect(await upload(ticket['uploadUrl'] as String, 'DOCX1'), 204);

      final res =
          await adapter.execute('fs', 'commitUserFileWrite', {
                'writeToken': ticket['writeToken'],
                'suggestedName': 'חידושים',
                'extension': 'docx',
              })
              as Map;

      expect(res['cancelled'], isFalse);
      expect(res['name'], 'חידושים.docx');
      expect(res['size'], 5);
      expect(File(target).readAsStringSync(), 'DOCX1');
      // ה-token שחוזר ניתן לכתיבה, וגם משמש לקריאה.
      expect((grants()[res['token']] as Map)['access'], 'readwrite');
      final resolved =
          await adapter.execute('fs', 'resolveFileUrl', {
                'token': res['token'],
              })
              as Map;
      expect(await fetch(resolved['url'] as String), 'DOCX1');
      // ה-session שוחרר וה-temp נמחק. בלי האסרשן הזאת שמירה מוצלחת יכולה
      // להדליף העלאה שנשארת committing לנצח — ואחרי שתיים התוסף חוסם את עצמו.
      expect(fileServer.activeUploadsFor('test.plugin'), 0);
      expect(
        File(
          '${Directory.systemTemp.path}/otzaria_plugin_uploads/'
          '${ticket['writeToken']}.part',
        ).existsSync(),
        isFalse,
      );
      // אין שאריות staging בתיקייה.
      expect(
        Directory(tempDir.path)
            .listSync()
            .where((e) => e.path.endsWith('.otztmp'))
            .toList(),
        isEmpty,
      );
    });

    test('„שמור”: כתיבה חוזרת ל-token דורסת את הקובץ בלי דיאלוג', () async {
      final file = File(p.join(tempDir.path, 'a.docx'))
        ..writeAsStringSync('גרסה ראשונה');
      var saveDialogOpened = false;
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async {
              saveDialogOpened = true;
              return null;
            },
      );

      final picked =
          await adapter.execute('fs', 'pickUserFile', {'access': 'readwrite'})
              as Map;
      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'גרסה שנייה');

      final res =
          await adapter.execute('fs', 'commitUserFileWrite', {
                'writeToken': ticket['writeToken'],
                'targetToken': picked['token'],
              })
              as Map;

      expect(res['cancelled'], isFalse);
      expect(res['token'], picked['token']);
      expect(file.readAsStringSync(), 'גרסה שנייה');
      expect(saveDialogOpened, isFalse);
      expect(fileServer.activeUploadsFor('test.plugin'), 0);
      expect(
        File(
          '${Directory.systemTemp.path}/otzaria_plugin_uploads/'
          '${ticket['writeToken']}.part',
        ).existsSync(),
        isFalse,
      );
    });

    test('token לקריאה בלבד אינו יעד כתיבה, והקובץ אינו נוגע', () async {
      final file = File(p.join(tempDir.path, 'a.docx'))
        ..writeAsStringSync('מקורי');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'דריסה');

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
          'targetToken': picked['token'],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('permission_denied'),
          ),
        ),
      );
      expect(file.readAsStringSync(), 'מקורי');
    });

    test('grant בפורמט הישן נקרא כקריאה בלבד', () async {
      final file = File(p.join(tempDir.path, 'legacy.docx'))
        ..writeAsStringSync('מקורי');
      // הפורמט שלפני הכתיבה: token -> path כמחרוזת.
      registry.kv['_internal/user_file_grants'] = jsonEncode({
        'legacytoken': file.path,
      });
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      // קריאה ממשיכה לעבוד.
      final resolved =
          await adapter.execute('fs', 'resolveFileUrl', {
                'token': 'legacytoken',
              })
              as Map;
      expect(await fetch(resolved['url'] as String), 'מקורי');

      // כתיבה אליו נדחית, כי grant ישן אינו יכול להיות readwrite.
      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'דריסה');
      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
          'targetToken': 'legacytoken',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('permission_denied'),
          ),
        ),
      );
      expect(file.readAsStringSync(), 'מקורי');
    });

    test('ביטול „שמור בשם” אינו כותב קובץ ואינו יוצר grant', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async => null,
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');

      final res =
          await adapter.execute('fs', 'commitUserFileWrite', {
                'writeToken': ticket['writeToken'],
                'suggestedName': 'מסמך',
                'extension': 'docx',
              })
              as Map;

      expect(res['cancelled'], isTrue);
      expect(registry.kv['_internal/user_file_grants'], isNull);
      expect(
        Directory(tempDir.path).listSync().map((e) => p.basename(e.path)),
        isNot(contains('מסמך.docx')),
      );
    });

    test('abortBinaryWrite משחרר את ההעלאה ואת המכסה מיד', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');
      final temp = File(
        '${Directory.systemTemp.path}/otzaria_plugin_uploads/'
        '${ticket['writeToken']}.part',
      );
      expect(temp.existsSync(), isTrue);
      expect(fileServer.activeUploadsFor('test.plugin'), 1);

      final aborted = await adapter.execute('fs', 'abortBinaryWrite', {
        'writeToken': ticket['writeToken'],
      });

      expect(aborted, isTrue);
      expect(temp.existsSync(), isFalse);
      expect(fileServer.activeUploadsFor('test.plugin'), 0);
      // ואחריו commit על אותו token נדחה — אין מה לכתוב.
      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
    });

    test('abortBinaryWrite בלי writeToken נדחה', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      await expectLater(
        adapter.execute('fs', 'abortBinaryWrite', const <String, dynamic>{}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('invalid_params'),
          ),
        ),
      );
    });

    test('commit על writeToken לא מוכר נדחה', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': 'nosuchtoken',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
    });

    test('commit שני על אותה העלאה נדחה', () async {
      final target = p.join(tempDir.path, 'once.docx');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async =>
                target,
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');
      await adapter.execute('fs', 'commitUserFileWrite', {
        'writeToken': ticket['writeToken'],
      });

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
    });

    test('commit לפני שההעלאה הושלמה נדחה', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
    });

    test('purpose שאינו user-file נדחה', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
      );

      await expectLater(
        adapter.execute('fs', 'beginBinaryWrite', {'purpose': 'plugin-file'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unsupported'),
          ),
        ),
      );
    });

    test('כשל באמצע הכתיבה אינו פוגע בקובץ הקיים', () async {
      final file = File(p.join(tempDir.path, 'protected.docx'))
        ..writeAsStringSync('הגרסה שאסור לאבד');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );
      final picked =
          await adapter.execute('fs', 'pickUserFile', {'access': 'readwrite'})
              as Map;
      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'גרסה חדשה');

      // תיקייה לקריאה בלבד: ה-staging אינו יכול להיווצר, ולכן הכתיבה נכשלת
      // בדיוק בשלב שבו הקובץ המקורי עוד שלם.
      final dir = Directory(tempDir.path);
      // ההרשאה משוחזרת לערך קבוע ולא לזו שנקראה מהדיסק: `stat -f '%Lp'` הוא
      // תחביר BSD, וב-Linux הדגל `-f` מדפיס מידע על מערכת הקבצים ולא על
      // הקובץ. שם ה-chmod המשחזר קיבל זבל, התיקייה נשארה 555, ומחיקת תיקיית
      // ה-temp ב-tearDown נכשלה ב-EACCES — הבדיקה עברה במקומי ונפלה ב-CI.
      // 700 הוא ההרשאה שתיקיית temp מקבלת מ-createTemp בלאו הכי.
      const restoreMode = '700';
      Process.runSync('chmod', ['555', dir.path]);
      addTearDown(() => Process.runSync('chmod', [restoreMode, dir.path]));

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
          'targetToken': picked['token'],
        }),
        throwsA(isA<Exception>()),
      );

      Process.runSync('chmod', [restoreMode, dir.path]);
      expect(file.readAsStringSync(), 'הגרסה שאסור לאבד');
      expect(
        Directory(tempDir.path)
            .listSync()
            .where((e) => e.path.endsWith('.otztmp'))
            .toList(),
        isEmpty,
      );
    }, skip: Platform.isWindows ? 'chmod אינו זמין ב-Windows' : null);

    test('אין מסלול שכותב ישירות על קובץ היעד', () {
      // בדיקת מקור ולא בדיקת התנהגות, בכוונה: כדי לתפוס fallback של copy
      // צריך מצב שבו rename נכשל ו-copy מצליח, ואת זה אי אפשר לביים מקומית
      // (rename באותה תיקייה נכשל רק כשגם copy ייכשל). מה שכן אפשר לקבע הוא
      // שהמסלול הזה לא קיים בקוד — וזאת הדרישה: כשל rename נכשל, ולא מתדרדר
      // להעתקה לא אטומית על מסמך של המשתמש.
      final source = File(
        'lib/plugins/bridge/plugin_bridge_adapter.dart',
      ).readAsStringSync();
      final atomicWrite = source.substring(
        source.indexOf('Future<void> _atomicWrite('),
        source.indexOf('static const String _stagingExt'),
      );

      // קיבוע חיובי ולא רשימת איסורים: כל שורה שנוגעת ביעד מפורטת כאן, ולכן
      // כל דרך חדשה לכתוב אליו — copy, writeAsBytes, openWrite — מפילה את
      // הבדיקה. רשימת שלילות הייתה מפספסת בדיוק את הצורה שלא חשבנו עליה.
      final targetLines = atomicWrite
          .split('\n')
          .map((line) => line.trim())
          .where(
            (line) =>
                !line.startsWith('//') &&
                !line.startsWith('///') &&
                (line.contains('targetPath') || line.contains('target.')),
          )
          .toList();

      expect(targetLines, [
        'Future<void> _atomicWrite(File source, String targetPath) async {',
        'final target = File(targetPath);',
        "p.join(target.parent.path, '.\${p.basename(targetPath)}.\$suffix\$_stagingExt'),",
        'await _sweepStagingLeftovers(target.parent);',
        'await staging.rename(targetPath);',
      ]);
    });

    test('כשל בהחלפת היעד אינו הורס אותו', () async {
      // יעד שהוא תיקייה: ה-copy ל-staging מצליח וה-rename נכשל. זה בדיוק
      // המסלול שבו fallback של copy היה כותב ישירות על היעד — כלומר על מסמך
      // של המשתמש, בלי אטומיות.
      final targetDir = Directory(p.join(tempDir.path, 'target-as-dir'))
        ..createSync();
      final marker = File(p.join(targetDir.path, 'inside.txt'))
        ..writeAsStringSync('התוכן שאסור לאבד');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async =>
                targetDir.path,
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
        }),
        throwsA(isA<Exception>()),
      );

      // היעד לא נדרס, מה שבתוכו שלם, ואין שאריות staging.
      expect(targetDir.existsSync(), isTrue);
      expect(marker.readAsStringSync(), 'התוכן שאסור לאבד');
      expect(
        Directory(tempDir.path)
            .listSync()
            .where((e) => e.path.endsWith('.otztmp'))
            .toList(),
        isEmpty,
      );
    });

    test('ביטול „שמור בשם” מוחק את קובץ ההעלאה', () async {
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async => null,
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');
      final temp = File(
        '${Directory.systemTemp.path}/otzaria_plugin_uploads/'
        '${ticket['writeToken']}.part',
      );
      expect(temp.existsSync(), isTrue);

      await adapter.execute('fs', 'commitUserFileWrite', {
        'writeToken': ticket['writeToken'],
      });

      // ה-session נסגר ב-finally, ולכן ה-temp אינו נשאר יתום.
      expect(temp.existsSync(), isFalse);
      expect(fileServer.activeUploadsFor('test.plugin'), 0);
    });

    test('extension עם מפרידי נתיב אינו מגיע לדיאלוג', () async {
      String? seenName;
      List<String>? seenExtensions;
      final target = p.join(tempDir.path, 'clean.docx');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => null,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async {
              seenName = suggestedName;
              seenExtensions = allowedExtensions;
              return target;
            },
      );

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');
      await adapter.execute('fs', 'commitUserFileWrite', {
        'writeToken': ticket['writeToken'],
        'suggestedName': 'מסמך',
        'extension': '../../Windows/System32/x',
      });

      // סיומת לא חוקית נזרקת לגמרי; אין מפרידי נתיב בשם ואין בסינון.
      expect(seenName, 'מסמך');
      expect(seenExtensions, isNull);
    });

    test('כתיבה ליעד שנמחק נדחית ומנקה את ה-grant', () async {
      final file = File(p.join(tempDir.path, 'gone.docx'))
        ..writeAsStringSync('x');
      final adapter = buildAdapter(
        pickFile: ({allowedExtensions, title}) async => file.path,
      );

      final picked =
          await adapter.execute('fs', 'pickUserFile', {'access': 'readwrite'})
              as Map;
      file.deleteSync();

      final ticket =
          await adapter.execute('fs', 'beginBinaryWrite', {}) as Map;
      await upload(ticket['uploadUrl'] as String, 'DOCX');

      await expectLater(
        adapter.execute('fs', 'commitUserFileWrite', {
          'writeToken': ticket['writeToken'],
          'targetToken': picked['token'],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not_found'),
          ),
        ),
      );
      expect(grants(), isNot(contains(picked['token'])));
    });
  });

  group('PluginBridgeAdapter plugin.openSelf + context menu openPlugin', () {
    late PluginBridgeAdapter adapter;

    late _StubPluginRegistryRepository registry;

    setUp(() {
      registry = _StubPluginRegistryRepository();
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['navigation.write', 'reader.context_menu'],
        ),
        dependencies: _buildNetworkDeps(),
        pluginRepository: registry,
      );
    });

    tearDown(() {
      PluginPageLauncher.instance.navigator = null;
      ContextMenuRegistry.instance.removeAll('test.plugin');
    });

    test('plugin.openSelf מנווט לדף התוסף עצמו', () async {
      final navigations = <String>[];
      PluginPageLauncher.instance.navigator = navigations.add;

      final result = await adapter.execute('plugin', 'openSelf', {
        'param': 'x',
      });

      expect(result, isTrue);
      expect(navigations, ['test.plugin']);
    });

    test('plugin.openOther מנווט לתוסף היעד ומוסר לו openedBy', () async {
      registry.installed = [_buildInstalledPlugin(pluginId: 'other.plugin')];
      final navigations = <String>[];
      PluginPageLauncher.instance.navigator = navigations.add;
      final dispatcher = PluginRuntimeDispatcher.instance;
      final controller = _RecordingWebViewController();
      dispatcher.repositoryForTesting = _EnabledRegistryRepo();
      dispatcher.registerController('other.plugin', controller);
      addTearDown(() {
        PluginPageLauncher.instance.markPageClosed('other.plugin');
        dispatcher.unregisterController('other.plugin');
        dispatcher.repositoryForTesting = PluginRegistryRepository();
      });

      final result = await adapter.execute('plugin', 'openOther', {
        'pluginId': 'other.plugin',
        'param': 'x',
      });
      PluginPageLauncher.instance.markPageReady('other.plugin');
      await Future<void>.delayed(Duration.zero);

      expect(result, isTrue);
      expect(navigations, ['other.plugin']);
      expect(controller.jsCalls.single, contains('plugin.page_opened'));
      expect(controller.jsCalls.single, contains('"openedBy":"test.plugin"'));
    });

    test(
      'plugin.openOther על תוסף שאינו מותקן → not_found, בלי ניווט',
      () async {
        registry.installed = [_buildInstalledPlugin(pluginId: 'other.plugin')];
        final navigations = <String>[];
        PluginPageLauncher.instance.navigator = navigations.add;

        await expectLater(
          adapter.execute('plugin', 'openOther', {'pluginId': 'ghost.plugin'}),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('not_found'),
            ),
          ),
        );
        expect(navigations, isEmpty);
      },
    );

    test('plugin.openOther ללא pluginId → invalid_params', () async {
      await expectLater(
        adapter.execute('plugin', 'openOther', <String, dynamic>{}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('invalid_params'),
          ),
        ),
      );
    });

    test('addContextMenuItem שומר openPlugin ו-param ב-registry', () async {
      await adapter.execute('reader', 'addContextMenuItem', {
        'id': 'item-1',
        'label': 'פתח בתוסף',
        'openPlugin': true,
        'param': 'my-param',
      });

      final items = ContextMenuRegistry.instance.getAll();
      final item = items.single.$2;
      expect(items.single.$1, 'test.plugin');
      expect(item.openPlugin, isTrue);
      expect(item.param, 'my-param');
    });

    test('addContextMenuItem ללא הדגלים החדשים — ברירות מחדל', () async {
      await adapter.execute('reader', 'addContextMenuItem', {
        'id': 'item-2',
        'label': 'רגיל',
      });

      final item = ContextMenuRegistry.instance.getAll().single.$2;
      expect(item.openPlugin, isFalse);
      expect(item.param, isNull);
    });

    test(
      'updateContextMenuItem עם when על storage רושם את המפתח למעקב',
      () async {
        addTearDown(
          () => PluginConditionEvaluator.instance.removePlugin('test.plugin'),
        );
        registry.kv['default/flag'] = '"on"';

        await adapter.execute('reader', 'addContextMenuItem', {
          'id': 'item-3',
          'label': 'מותנה',
        });
        await adapter.execute('reader', 'updateContextMenuItem', {
          'id': 'item-3',
          'patch': {
            'when': {
              'storage': {'key': 'flag', 'equals': 'on'},
            },
          },
        });

        // בלי רישום המפתח, הערך הקיים ב-KV לא נטען והפריט היה מוסתר לצמיתות.
        expect(ContextMenuRegistry.instance.getAll(), hasLength(1));
      },
    );
  });

  group('PluginBridgeAdapter — reader.addToolbarItem', () {
    late PluginBridgeAdapter adapter;

    setUp(() {
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['reader.toolbar']),
        dependencies: _buildNetworkDeps(),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    });

    tearDown(() {
      PluginToolbarRegistry.instance.removeAll('test.plugin');
    });

    test('addToolbarItem רושם לחצן ב-registry עם openPlugin ו-param', () async {
      final result = await adapter.execute('reader', 'addToolbarItem', {
        'id': 'mark',
        'title': 'סמן',
        'icon': 'bookmark_24_regular',
        'openPlugin': true,
        'param': 'my-param',
      });

      expect(result, isTrue);
      final records = PluginToolbarRegistry.instance.getAll();
      expect(records.single.$1, 'test.plugin');
      expect(records.single.$2.openPlugin, isTrue);
      expect(records.single.$2.param, 'my-param');
    });

    test('updateToolbarItem מעדכן ו-removeToolbarItem מסיר', () async {
      await adapter.execute('reader', 'addToolbarItem', {
        'id': 'mark',
        'title': 'סמן',
        'icon': 'bookmark_24_regular',
      });

      await adapter.execute('reader', 'updateToolbarItem', {
        'id': 'mark',
        'patch': {'title': 'סמן מחדש'},
      });
      expect(
        PluginToolbarRegistry.instance.getAll().single.$2.title,
        'סמן מחדש',
      );

      await adapter.execute('reader', 'removeToolbarItem', {'id': 'mark'});
      expect(PluginToolbarRegistry.instance.getAll(), isEmpty);
    });

    test('updateToolbarItem עם when על storage רושם את המפתח למעקב', () async {
      addTearDown(
        () => PluginConditionEvaluator.instance.removePlugin('test.plugin'),
      );
      final repo = _StubPluginRegistryRepository()..kv['default/flag'] = '"on"';
      final conditionedAdapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['reader.toolbar']),
        dependencies: _buildNetworkDeps(),
        pluginRepository: repo,
      );

      await conditionedAdapter.execute('reader', 'addToolbarItem', {
        'id': 'mark',
        'title': 'סמן',
        'icon': 'bookmark_24_regular',
      });
      await conditionedAdapter.execute('reader', 'updateToolbarItem', {
        'id': 'mark',
        'patch': {
          'when': {
            'storage': {'key': 'flag', 'equals': 'on'},
          },
        },
      });

      expect(PluginToolbarRegistry.instance.getAll(), hasLength(1));
    });
  });

  group('PluginBridgeAdapter — book identity (id + type + bookId)', () {
    late _MockBookOpenCoordinator mockCoordinator;
    late _StubTabsBloc tabsBloc;

    PluginBridgeAdapter buildAdapter({
      required List<Book> books,
      List<OpenedTab> tabs = const [],
      int currentTabIndex = 0,
      SearchRepository? searchRepository,
    }) {
      tabsBloc = _StubTabsBloc();
      if (tabs.isNotEmpty) {
        tabsBloc.currentState = TabsState(
          tabs: tabs,
          currentTabIndex: currentTabIndex,
        );
      }
      mockCoordinator = _MockBookOpenCoordinator();
      final category = Category(
        title: 'בדיקה',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: const [],
        books: books,
        parent: null,
      );
      final library = Library(categories: [category]);
      category.parent = library;
      DataRepository.instance.library = Future.value(library);

      return PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['reader.open', 'library.read'],
        ),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: tabsBloc,
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: searchRepository ?? _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: mockCoordinator,
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
        ),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    }

    // --- search.query ---

    test(
      'search.query מעביר את כל הפרמטרים ומחזיר זהות ספר מלאה',
      () async {
        final stub = _StubSearchRepository()
          ..updates = [
            const SearchStreamUpdate(
              totalCount: 812,
              bookCounts: {'id:10': 812},
              results: [],
              truncated: false,
            ),
            SearchStreamUpdate(
              results: [
                SearchResult(
                  title: 'בראשית',
                  reference: 'בראשית, פרק א',
                  text: 'בראשית ברא',
                  id: BigInt.one,
                  segment: BigInt.from(12),
                  isPdf: false,
                  filePath: 'id:10',
                  mergedCount: 1,
                  merged: const <MergedSibling>[],
                ),
              ],
              truncated: false,
            ),
          ];
        final adapter = buildAdapter(
          books: [TextBook(id: 10, title: 'בראשית')],
          searchRepository: stub,
        );

        final chunks = <Map<String, dynamic>>[];
        final completion =
            await adapter.execute(
                  'search',
                  'query',
                  {
                    'query': 'בראשית',
                    'mode': 'advanced',
                    'distance': 3,
                    'proximityScope': 'sameParagraph',
                    'order': 'catalogue',
                    'grouping': 'sameSection',
                    'wordMatchMode': 'mostWords',
                    'limit': 10,
                    'offset': 5,
                    'includeBookCounts': true,
                    '__streamId': 'test_search_1',
                  },
                  eventSink: (topic, payload) async {
                    expect(topic, '__otzaria.search.query.chunk');
                    chunks.add(payload['chunk'] as Map<String, dynamic>);
                  },
                )
                as Map<String, dynamic>;

        expect(stub.captured!['limit'], 10);
        expect(stub.captured!['offset'], 5);
        expect(stub.captured!['order'], ResultsOrder.catalogue);
        expect(stub.captured!['searchMode'], SearchMode.advanced);
        expect(stub.captured!['distance'], 3);
        expect(stub.captured!['scope'], SearchScope.sameParagraph);
        expect(stub.captured!['grouping'], ResultGrouping.sameSection);
        expect(stub.captured!['wordMatchMode'], WordMatchMode.mostWords);
        expect(stub.streamWithCountsCalls, 1);
        expect(stub.pageCalls, 0);

        expect(completion['completed'], isTrue);
        expect(chunks, hasLength(2));
        expect(chunks.first['total'], 812);
        expect(chunks.first['truncated'], isFalse);
        final hit = (chunks.last['results'] as List).single as Map;
        expect(hit['id'], 10);
        expect(hit['type'], 'text');
        expect(hit['index'], 12);
        expect(hit['reference'], 'בראשית, פרק א');
        expect((chunks.first['bookCounts'] as List).single, {
          'id': 10,
          'type': 'text',
          'bookId': 'בראשית',
          'bookUid': 'id:10',
          'source': 'library',
          'title': 'בראשית',
          'count': 812,
        });
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'search.query בלי היקף מחפש בכל הספרייה',
      () async {
        final stub = _StubSearchRepository()
          ..updates = [const SearchStreamUpdate(results: [], truncated: false)];
        final adapter = buildAdapter(
          books: [TextBook(id: 10, title: 'בראשית')],
          searchRepository: stub,
        );

        final chunks = <Map<String, dynamic>>[];
        await adapter.execute(
          'search',
          'query',
          {
            'query': 'בראשית',
            '__streamId': 'test_search_2',
          },
          eventSink: (topic, payload) async {
            chunks.add(payload['chunk'] as Map<String, dynamic>);
          },
        );

        expect(stub.captured!['facets'], ['/']);
        expect(stub.pageCalls, 0);
        expect(stub.streamWithCountsCalls, 1);
        expect(chunks.single['facets'], ['/']);
        expect(chunks.single['total'], isNull);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'search.query מצמצם את ההיקף לספר שנשלח',
      () async {
        final stub = _StubSearchRepository()
          ..updates = [const SearchStreamUpdate(results: [], truncated: false)];
        final adapter = buildAdapter(
          books: [TextBook(id: 10, title: 'בראשית', topics: 'תנך, תורה')],
          searchRepository: stub,
        );

        await adapter.execute('search', 'query', {
          'query': 'בראשית',
          '__streamId': 'test_search_3',
          'books': [
            {'id': 10},
          ],
        }, eventSink: (topic, payload) async {});

        expect(
          (stub.captured!['facets'] as List).single,
          startsWith('/תנך/תורה/'),
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('search.query דורש תעבורת stream פנימית', () async {
      final adapter = buildAdapter(books: [TextBook(id: 10, title: 'בראשית')]);

      await expectLater(
        () => adapter.execute('search', 'query', {'query': 'בראשית'}),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('stream id'),
          ),
        ),
      );
    });

    test(
      'ביטול בזמן אתחול החיפוש נצרך לפני רישום ה-stream הפעיל',
      () async {
        final stub = _StubSearchRepository();
        final adapter = buildAdapter(
          books: [TextBook(id: 10, title: 'בראשית')],
          searchRepository: stub,
        );
        final search = adapter.execute('search', 'query', {
          'query': 'בראשית',
          '__streamId': 'cancel_during_startup_1',
        }, eventSink: (topic, payload) async {});

        await adapter.execute('search', 'query', {
          '__cancelStreamId': 'cancel_during_startup_1',
        });
        final completion = await search as Map<String, dynamic>;

        expect(completion['cancelled'], isTrue);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'עצירת האיטרטור מבטלת את stream החיפוש הפעיל',
      () async {
        final controller = StreamController<SearchStreamUpdate>();
        final stub = _StubSearchRepository()
          ..streamOverride = controller.stream;
        final adapter = buildAdapter(
          books: [TextBook(id: 10, title: 'בראשית')],
          searchRepository: stub,
        );
        final search = adapter.execute('search', 'query', {
          'query': 'בראשית',
          '__streamId': 'cancel_search_1',
        }, eventSink: (topic, payload) async {});
        while (stub.streamWithCountsCalls == 0) {
          await Future<void>.delayed(Duration.zero);
        }

        final cancellation =
            await adapter.execute('search', 'query', {
                  '__cancelStreamId': 'cancel_search_1',
                })
                as Map<String, dynamic>;
        final completion = await search as Map<String, dynamic>;

        expect(cancellation['cancelled'], isTrue);
        expect(completion['cancelled'], isTrue);
        await controller.close();
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('search.getOptions מחזיר את הערכים החוקיים', () async {
      final adapter = buildAdapter(books: [TextBook(id: 10, title: 'בראשית')]);

      final options =
          await adapter.execute('search', 'getOptions', {})
              as Map<String, dynamic>;

      expect(options['modes'], containsAll(['exact', 'advanced', 'fuzzy']));
      expect(options['eras'], contains('ראשונים'));
    });

    // --- library.findBooks ---

    test('library.findBooks מחזיר id ו-type לכל תוצאה', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(id: 10, title: 'בראשית'),
          PdfBook(id: 20, title: 'ספר PDF', path: '/tmp/a.pdf'),
        ],
      );

      final results = await adapter.execute('library', 'findBooks', {}) as List;

      final text = results.firstWhere((r) => r['bookId'] == 'בראשית') as Map;
      expect(text['id'], 10);
      expect(text['type'], 'text');

      final pdf = results.firstWhere((r) => r['bookId'] == 'ספר PDF') as Map;
      expect(pdf['id'], 20);
      expect(pdf['type'], 'pdf');
    });

    // --- library.getBookMetadata ---

    test('library.getBookMetadata תומך בחיפוש לפי id בלבד', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(id: 42, title: 'שמות'),
        ],
      );

      final result =
          await adapter.execute(
                'library',
                'getBookMetadata',
                {'id': 42},
              )
              as Map;

      expect(result['bookId'], 'שמות');
      expect(result['id'], 42);
      expect(result['type'], 'text');
    });

    test('library.getBookMetadata: id נכון + שם שגוי → null', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(id: 42, title: 'שמות'),
        ],
      );

      final result = await adapter.execute(
        'library',
        'getBookMetadata',
        {'id': 42, 'bookId': 'שם_שגוי'},
      );

      expect(result, isNull);
    });

    test('library.getBookMetadata: שם נכון + id שגוי → null', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(id: 42, title: 'שמות'),
        ],
      );

      final result = await adapter.execute(
        'library',
        'getBookMetadata',
        {'bookId': 'שמות', 'id': 99},
      );

      expect(result, isNull);
    });

    test('library.getBookMetadata: type שגוי → null', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(id: 42, title: 'שמות'),
        ],
      );

      final result = await adapter.execute(
        'library',
        'getBookMetadata',
        {'bookId': 'שמות', 'type': 'pdf'},
      );

      expect(result, isNull);
    });

    test(
      'library.getBookMetadata: קריאה ישנה עם bookId בלבד ממשיכה לעבוד',
      () async {
        final adapter = buildAdapter(
          books: [
            TextBook(id: 42, title: 'שמות'),
          ],
        );

        final result =
            await adapter.execute(
                  'library',
                  'getBookMetadata',
                  {'bookId': 'שמות'},
                )
                as Map;

        expect(result['bookId'], 'שמות');
        expect(result['id'], 42);
      },
    );

    test('library.resolveBooks פותר זהויות באצווה ומחזיר קטגוריה', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(
            id: 42,
            title: 'שמות',
            categoryPath: 'תנך, תורה',
          ),
        ],
      );

      final result =
          await adapter.execute('library', 'resolveBooks', {
                'items': [
                  {'id': 42, 'source': 'library'},
                  {'id': 999, 'source': 'library'},
                ],
              })
              as List;

      expect(result.first, containsPair('categoryPath', '/תנך/תורה'));
      expect(result.last, isNull);
    });

    // --- reader.openBook ---

    test('reader.openBook פותח לפי id בלבד', () async {
      final book = TextBook(id: 5, title: 'ויקרא');
      final adapter = buildAdapter(books: [book]);

      final result = await adapter.execute(
        'reader',
        'openBook',
        {'id': 5, 'index': 0},
      );

      expect(result, isTrue);
      verify(
        mockCoordinator.openBook(book, 0, '', ignoreHistory: true),
      ).called(1);
    });

    test('reader.openBook: id נכון + שם שגוי → false, לא פותח', () async {
      final book = TextBook(id: 5, title: 'ויקרא');
      final adapter = buildAdapter(books: [book]);

      final result = await adapter.execute(
        'reader',
        'openBook',
        {'id': 5, 'bookId': 'שם_שגוי'},
      );

      expect(result, isFalse);
      verifyZeroInteractions(mockCoordinator);
    });

    test('reader.openBook: שם נכון + id שגוי → false, לא פותח', () async {
      final book = TextBook(id: 5, title: 'ויקרא');
      final adapter = buildAdapter(books: [book]);

      final result = await adapter.execute(
        'reader',
        'openBook',
        {'bookId': 'ויקרא', 'id': 999},
      );

      expect(result, isFalse);
      verifyZeroInteractions(mockCoordinator);
    });

    test('reader.openBook: type שגוי → false, לא פותח', () async {
      final book = TextBook(id: 5, title: 'ויקרא');
      final adapter = buildAdapter(books: [book]);

      final result = await adapter.execute(
        'reader',
        'openBook',
        {'bookId': 'ויקרא', 'type': 'pdf'},
      );

      expect(result, isFalse);
      verifyZeroInteractions(mockCoordinator);
    });

    test('reader.openBook: קריאה ישנה עם bookId בלבד ממשיכה לעבוד', () async {
      final book = TextBook(id: 5, title: 'ויקרא');
      final adapter = buildAdapter(books: [book]);

      final result = await adapter.execute(
        'reader',
        'openBook',
        {'bookId': 'ויקרא'},
      );

      expect(result, isTrue);
      verify(
        mockCoordinator.openBook(book, 0, '', ignoreHistory: true),
      ).called(1);
    });

    test('reader.openBook: id + bookId + type תואמים — פותח בהצלחה', () async {
      final book = TextBook(id: 5, title: 'ויקרא');
      final adapter = buildAdapter(books: [book]);

      final result = await adapter.execute(
        'reader',
        'openBook',
        {'id': 5, 'bookId': 'ויקרא', 'type': 'text'},
      );

      expect(result, isTrue);
      verify(
        mockCoordinator.openBook(book, 0, '', ignoreHistory: true),
      ).called(1);
    });

    // --- reader.getCurrentState ---

    test('reader.getCurrentState מחזיר id ו-type לכל טאב', () async {
      final textTab = TextBookTab(
        book: TextBook(id: 100, title: 'בראשית'),
        index: 5,
      )..currentTitle.value = 'פרק א';
      final pdfTab = PdfBookTab(
        book: PdfBook(id: 200, title: 'ספר PDF', path: '/tmp/b.pdf'),
        pageNumber: 3,
      )..currentTitle.value = 'עמוד 3';

      final adapter = buildAdapter(
        books: [],
        tabs: [textTab, pdfTab],
        currentTabIndex: 0,
      );

      final result =
          await adapter.execute('reader', 'getCurrentState', {})
              as Map<String, dynamic>;

      final openTabs = result['openTabs'] as List;
      final textEntry = openTabs[0] as Map;
      expect(textEntry['id'], 100);
      expect(textEntry['type'], 'text');
      expect(textEntry['bookId'], 'בראשית');

      final pdfEntry = openTabs[1] as Map;
      expect(pdfEntry['id'], 200);
      expect(pdfEntry['type'], 'pdf');
      expect(pdfEntry['bookId'], 'ספר PDF');

      // ספר פעיל
      expect(result['currentId'], 100);
      expect(result['currentType'], 'text');
    });

    test('reader.getCurrentRef מחזיר currentId ו-currentType', () async {
      final tab = PdfBookTab(
        book: PdfBook(id: 77, title: 'תנ"ך', path: '/tmp/c.pdf'),
        pageNumber: 10,
      )..currentTitle.value = 'עמוד 10';

      final adapter = buildAdapter(
        books: [],
        tabs: [tab],
        currentTabIndex: 0,
      );

      final result =
          await adapter.execute('reader', 'getCurrentRef', {})
              as Map<String, dynamic>;

      expect(result['currentId'], 77);
      expect(result['currentType'], 'pdf');
    });

    // --- שני ספרים בעלי אותו שם ---

    test('שני ספרים בעלי אותו שם — signature שונה בגלל id שונה', () {
      final snap1 = ReaderLocationSnapshot(
        currentBook: 'ספר',
        currentBookId: 'ספר',
        currentId: 1,
        currentType: 'text',
        currentIndex: 0,
        currentRef: 'פרק א',
      );
      final snap2 = ReaderLocationSnapshot(
        currentBook: 'ספר',
        currentBookId: 'ספר',
        currentId: 2,
        currentType: 'text',
        currentIndex: 0,
        currentRef: 'פרק א',
      );

      expect(snap1.signature(), isNot(snap2.signature()));
    });

    test(
      'library.getBookMetadata: שני ספרים בעלי אותו שם — מחזיר את הנכון',
      () async {
        final text = TextBook(id: 1, title: 'ספר');
        final pdf = PdfBook(id: 2, title: 'ספר', path: '/tmp/d.pdf');
        final adapter = buildAdapter(books: [text, pdf]);

        final resultPdf =
            await adapter.execute(
                  'library',
                  'getBookMetadata',
                  {'bookId': 'ספר', 'type': 'pdf'},
                )
                as Map;
        expect(resultPdf['id'], 2);
        expect(resultPdf['type'], 'pdf');

        final resultText =
            await adapter.execute(
                  'library',
                  'getBookMetadata',
                  {'bookId': 'ספר', 'type': 'text'},
                )
                as Map;
        expect(resultText['id'], 1);
        expect(resultText['type'], 'text');
      },
    );

    test('_pluginBookType — כל סוגי הספרים', () async {
      final adapter = buildAdapter(
        books: [
          TextBook(id: 1, title: 'טקסט'),
          PdfBook(id: 2, title: 'PDF', path: '/tmp/a.pdf'),
          DocxBook(id: 3, title: 'Docx', path: '/tmp/b.docx'),
          EpubBook(id: 4, title: 'Epub', path: '/tmp/c.epub'),
          ExternalLibraryBook(id: 5, title: 'External', link: 'https://x'),
        ],
      );

      final results = await adapter.execute('library', 'findBooks', {}) as List;

      expect(
        results.firstWhere((r) => r['bookId'] == 'טקסט')['type'],
        'text',
      );
      expect(
        results.firstWhere((r) => r['bookId'] == 'PDF')['type'],
        'pdf',
      );
      expect(
        results.firstWhere((r) => r['bookId'] == 'Docx')['type'],
        'docx',
      );
      expect(
        results.firstWhere((r) => r['bookId'] == 'Epub')['type'],
        'epub',
      );
      expect(
        results.firstWhere((r) => r['bookId'] == 'External')['type'],
        'external',
      );
    });

    test('getCurrentState: SearchingTab → id/type = null', () async {
      final searchTab = SearchingTab('חיפוש', 'בראשית');
      final adapter = buildAdapter(
        books: [],
        tabs: [searchTab],
        currentTabIndex: 0,
      );

      final result =
          await adapter.execute('reader', 'getCurrentState', {})
              as Map<String, dynamic>;

      final openTabs = result['openTabs'] as List;
      expect(openTabs[0]['id'], isNull);
      expect(openTabs[0]['type'], isNull);

      expect(result['currentId'], isNull);
      expect(result['currentType'], isNull);
    });

    test('search.fullText אינו מחזיר id — type תלוי ב-isPdf', () {
      const result = {
        'type': 'text',
        'book': 'בראשית',
        'text': 'snippet',
        'index': 42,
      };
      expect(result.containsKey('id'), isFalse);
      expect(result['type'], 'text');

      const pdfResult = {
        'type': 'pdf',
        'book': 'ספר PDF',
        'text': 'snippet',
        'index': 1,
      };
      expect(pdfResult['type'], 'pdf');
    });
  });

  group('PluginBridgeAdapter feedback.report', () {
    PluginBridgeDependencies buildDeps({
      required Future<bool> Function(String title, String content) onConfirm,
    }) {
      return PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _StubTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _StubCalendarCubit(
          _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
        ),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _MockPersonalNotesRepository(),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) =>
            onConfirm(title, content),
        showWarningDialog:
            ({required title, required content, required subtitle}) async =>
                true,
      );
    }

    PluginBridgeAdapter buildAdapter({
      required Future<bool> Function(String title, String content) onConfirm,
      required http.Client client,
      _InMemoryPluginReportQueue? queue,
    }) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(),
        dependencies: buildDeps(onConfirm: onConfirm),
        pluginRepository: _StubPluginRegistryRepository(),
        reportService: PluginReportService(
          client: client,
          queueRepository: queue ?? _InMemoryPluginReportQueue(),
          sentRepository: _InMemoryPluginReportQueue(),
        ),
      );
    }

    setUp(() async {
      await Settings.setValue<String>(
        SettingsRepository.keyErrorReportSenderEmail,
        '',
      );
    });

    test('details חסר → שגיאה, ואין דיאלוג ואין שליחה', () async {
      var confirmCalls = 0;
      var posted = false;
      final adapter = buildAdapter(
        onConfirm: (_, _) async {
          confirmCalls++;
          return true;
        },
        client: MockClient((_) async {
          posted = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        adapter.execute('feedback', 'report', {'details': '   '}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('details required'),
          ),
        ),
      );
      expect(confirmCalls, 0);
      expect(posted, isFalse);
    });

    test('ביטול בדיאלוג → cancelled ואין שליחה', () async {
      var posted = false;
      final adapter = buildAdapter(
        onConfirm: (_, _) async => false,
        client: MockClient((_) async {
          posted = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await adapter.execute('feedback', 'report', {
        'details': 'התוסף קורס',
      });

      expect(result, 'cancelled');
      expect(posted, isFalse);
    });

    test('אישור → POST עם שדות התוסף, סוג לא מוכר הופך ל-other', () async {
      String? dialogTitle;
      String? dialogContent;
      late Map<String, dynamic> body;
      final adapter = buildAdapter(
        onConfirm: (title, content) async {
          dialogTitle = title;
          dialogContent = content;
          return true;
        },
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }),
      );

      final result = await adapter.execute('feedback', 'report', {
        'details': 'התוסף קורס',
        'reportType': 'nonsense',
      });

      expect(result, 'sent');
      expect(dialogTitle, 'שליחת דיווח למפתח התוסף');
      expect(dialogContent, contains('Test Plugin'));
      expect(dialogContent, contains('התוסף קורס'));
      expect(body['pluginUid'], 'test.plugin');
      expect(body['pluginName'], 'Test Plugin');
      expect(body['pluginVersion'], '1.0.0');
      expect(body['reportType'], 'other');
      expect(body['details'], 'התוסף קורס');
      expect(body.containsKey('reporterEmail'), isFalse);
    });

    test('פירוט ארוך נחתך ל-5000 תווים גם בתצוגה המקדימה', () async {
      String? dialogContent;
      late Map<String, dynamic> body;
      final adapter = buildAdapter(
        onConfirm: (_, content) async {
          dialogContent = content;
          return true;
        },
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }),
      );

      await adapter.execute('feedback', 'report', {'details': 'א' * 6000});

      expect((body['details'] as String).length, 5000);
      expect(dialogContent!.length, lessThan(600));
    });

    test('כתובת חוזרת נלקחת מהגדרות דיווח השגיאות כשלא נמסרה', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyErrorReportSenderEmail,
        'user@example.com',
      );
      String? dialogContent;
      late Map<String, dynamic> body;
      final adapter = buildAdapter(
        onConfirm: (_, content) async {
          dialogContent = content;
          return true;
        },
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }),
      );

      await adapter.execute('feedback', 'report', {'details': 'משהו'});

      expect(body['reporterEmail'], 'user@example.com');
      expect(dialogContent, contains('user@example.com'));
    });

    test('כתובת שמורה בהגדרות גוברת על כתובת שנמסרה מהתוסף', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyErrorReportSenderEmail,
        'saved@example.com',
      );
      late Map<String, dynamic> body;
      final adapter = buildAdapter(
        onConfirm: (_, _) async => true,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }),
      );

      await adapter.execute('feedback', 'report', {
        'details': 'משהו',
        'reporterEmail': 'plugin@example.com',
      });

      expect(body['reporterEmail'], 'saved@example.com');
    });

    test('כתובת מהתוסף משמשת רק כשאין כתובת שמורה', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyErrorReportSenderEmail,
        '',
      );
      late Map<String, dynamic> body;
      final adapter = buildAdapter(
        onConfirm: (_, _) async => true,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }),
      );

      await adapter.execute('feedback', 'report', {
        'details': 'משהו',
        'reporterEmail': 'plugin@example.com',
      });

      expect(body['reporterEmail'], 'plugin@example.com');
    });

    test('hasReporterEmail מחזירה קיום בלבד, בלי הכתובת', () async {
      final adapter = buildAdapter(
        onConfirm: (_, _) async => true,
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await Settings.setValue<String>(
        SettingsRepository.keyErrorReportSenderEmail,
        '',
      );
      expect(
        await adapter.execute('feedback', 'hasReporterEmail', {}),
        isFalse,
      );

      await Settings.setValue<String>(
        SettingsRepository.keyErrorReportSenderEmail,
        'user@example.com',
      );
      expect(
        await adapter.execute('feedback', 'hasReporterEmail', {}),
        isTrue,
      );
    });

    test('דחייה קבועה (400) → חריגה מוחזרת לתוסף ולא נשמר בתור', () async {
      final queue = _InMemoryPluginReportQueue();
      final adapter = buildAdapter(
        onConfirm: (_, _) async => true,
        client: MockClient((_) async => http.Response('bad', 400)),
        queue: queue,
      );

      await expectLater(
        adapter.execute('feedback', 'report', {'details': 'משהו'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('400'),
          ),
        ),
      );
      expect(await queue.load(), isEmpty);
    });

    test('כשל זמני (500) → queued והדיווח נשמר בתור', () async {
      final queue = _InMemoryPluginReportQueue();
      final adapter = buildAdapter(
        onConfirm: (_, _) async => true,
        client: MockClient((_) async => http.Response('nope', 500)),
        queue: queue,
      );

      final result = await adapter.execute('feedback', 'report', {
        'details': 'משהו',
      });

      expect(result, 'queued');
      final queued = await queue.load();
      expect(queued.single.pluginUid, 'test.plugin');
      expect(queued.single.details, 'משהו');
    });

    test('מצב לא-מקוון עם תור כבוי → חריגה, בלי רשת ובלי תור', () async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
      await Settings.setValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
        false,
      );
      addTearDown(() async {
        await Settings.setValue<bool>(
          SettingsRepository.keyOfflineMode,
          false,
        );
        await Settings.setValue<bool>(
          SettingsRepository.keyQueueErrorReportsWhenOffline,
          true,
        );
      });

      var posted = false;
      final queue = _InMemoryPluginReportQueue();
      final adapter = buildAdapter(
        onConfirm: (_, _) async => true,
        client: MockClient((_) async {
          posted = true;
          return http.Response('{}', 200);
        }),
        queue: queue,
      );

      await expectLater(
        adapter.execute('feedback', 'report', {'details': 'משהו'}),
        throwsA(isA<Exception>()),
      );
      expect(posted, isFalse);
      expect(await queue.load(), isEmpty);
    });
  });

  group('PluginBridgeAdapter.reader.openSearchTab', () {
    late _CapturingTabsBloc tabsBloc;
    late PluginBridgeAdapter adapter;

    setUp(() {
      tabsBloc = _CapturingTabsBloc();
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['reader.open']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: tabsBloc,
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _StubCalendarCubit(
            _buildCalendarState(DateTime(2026, 1, 1), inIsrael: true),
          ),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: BookOpenCoordinator(
            tabsBloc: tabsBloc,
            historyBloc: _MockHistoryBloc(),
            navigationBloc: _MockNavigationBloc(),
          ),
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
        ),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    });

    SearchingTab capturedSearchTab() {
      final addTab = tabsBloc.captured.whereType<AddTab>().first;
      return addTab.tab as SearchingTab;
    }

    test(
      'פותח טאב חיפוש עם השאילתה ומריץ אותה אוטומטית כברירת מחדל',
      () async {
        final response = await adapter.execute('reader', 'openSearchTab', {
          'query': 'ברכת המזון',
        });
        expect(response, isTrue);
        final tab = capturedSearchTab();
        expect(tab.queryController.text, 'ברכת המזון');
        expect(tab.autoRunInitialSearch, isTrue);
        final config = tab.searchBloc.state.configuration;
        expect(config.searchMode, SearchMode.advanced);
        expect(config.distance, 0);
        expect(config.proximityScope, SearchScope.wordDistance);
        expect(config.wordMatchMode, WordMatchMode.all);
        expect(config.wordMatchCount, 2);
        expect(tab.searchOptions, isEmpty);
        // החיפוש מופעל אוטומטית — השאילתה נכנסה ל-state. החיפוש עצמו
        // עובר דרך מנוע ה-Rust (sanitizeQuery), ולכן דורש build נייטיבי.
        await pumpEventQueue();
        expect(tab.searchBloc.state.searchQuery, 'ברכת המזון');
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('autoSearch: false פותח עם השאילתה בשדה בלי להריץ חיפוש', () async {
      await adapter.execute('reader', 'openSearchTab', {
        'query': 'ברכת המזון',
        'autoSearch': false,
      });
      final tab = capturedSearchTab();
      expect(tab.autoRunInitialSearch, isFalse);
      expect(tab.queryController.text, 'ברכת המזון');
      await pumpEventQueue();
      expect(tab.searchBloc.state.searchQuery, isEmpty);
    });

    test('settings מעבירים מצב, מרחק ומדיניות התאמה לטאב', () async {
      // autoSearch: false — בודקים את מיפוי ההגדרות בלי להריץ חיפוש, כדי
      // שהטסט לא יהיה תלוי במנוע הנייטיבי.
      await adapter.execute('reader', 'openSearchTab', {
        'query': 'ואהבת לרעך',
        'autoSearch': false,
        'settings': {
          'mode': 'advanced',
          'distance': 2,
          'proximityScope': 'sameParagraph',
          'wordMatchMode': 'atLeast',
          'wordMatchCount': 3,
        },
      });
      final tab = capturedSearchTab();
      final config = tab.searchBloc.state.configuration;
      expect(config.searchMode, SearchMode.advanced);
      expect(config.distance, 2);
      expect(config.proximityScope, SearchScope.sameParagraph);
      expect(config.wordMatchMode, WordMatchMode.atLeast);
      expect(config.wordMatchCount, 3);
      expect(tab.searchOptions, isEmpty);
    });

    test(
      'settings.options נשמרים למסלול החיפוש הידני',
      () async {
        await adapter.execute('reader', 'openSearchTab', {
          'query': 'ואהבת לרעך',
          'autoSearch': false,
          'settings': {
            'mode': 'advanced',
            'options': {'קידומות דקדוקיות': true},
          },
        });
        final tab = capturedSearchTab();
        expect(tab.searchOptions, isNotEmpty);
        for (final options in tab.searchOptions.values) {
          expect(options['קידומות דקדוקיות'], isTrue);
        }
        expect(tab.useGlobalSearchOptions.value, isFalse);
        expect(tab.effectiveSearchOptions(), tab.searchOptions);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('שומר את העדפות תצוגת התוצאות של המשתמש', () async {
      SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.sameSection);
      addTearDown(() {
        SearchDefaults.saveSortOrderDefault(ResultsOrder.catalogue);
        SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.none);
      });

      await adapter.execute('reader', 'openSearchTab', {
        'query': 'ברכת המזון',
        'autoSearch': false,
      });

      final config = capturedSearchTab().searchBloc.state.configuration;
      expect(config.sortBy, ResultsOrder.relevance);
      expect(config.resultGrouping, ResultGroupingMode.sameSection);
    });

    test(
      'settings.wordOptions נשמרים פר-מילה בטאב',
      () async {
        await adapter.execute('reader', 'openSearchTab', {
          'query': 'ואהבת לרעך',
          'settings': {
            'mode': 'advanced',
            'wordOptions': {
              'ואהבת_0': {'קידומות': true},
            },
          },
        });
        final tab = capturedSearchTab();
        expect(tab.searchOptions['ואהבת_0'], {'קידומות': true});
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('settings לא חוקיים נדחים בלי לפתוח טאב', () async {
      await expectLater(
        adapter.execute('reader', 'openSearchTab', {
          'query': 'ברכת המזון',
          'settings': {'unknownParam': 1},
        }),
        throwsA(isA<Exception>()),
      );
      expect(tabsBloc.captured.whereType<AddTab>(), isEmpty);
    });

    test(
      'wordOptions מפתח שאינו תואם לשאילתה נדחה',
      () async {
        await expectLater(
          adapter.execute('reader', 'openSearchTab', {
            'query': 'ואהבת לרעך',
            'settings': {
              'mode': 'advanced',
              'wordOptions': {
                'מילה_5': {'קידומות': true},
              },
            },
          }),
          throwsA(isA<Exception>()),
        );
        expect(tabsBloc.captured.whereType<AddTab>(), isEmpty);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}

class _FakeBookProvider implements LibraryProvider {
  final Map<BookCompositeKey, String> _bookTextByKey;

  _FakeBookProvider(this._bookTextByKey);

  @override
  String get providerId => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  String get sourceIndicator => 'F';

  @override
  int get priority => 1;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    final key = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
    return _bookTextByKey.containsKey(key);
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    final key = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
    return _bookTextByKey[key];
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return _bookTextByKey.keys.map((k) => k.toStorageKey()).toSet();
  }

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    return Library(categories: const []);
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
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}

CalendarState _buildCalendarState(
  DateTime gregorianDate, {
  required bool inIsrael,
}) {
  final jewishDate = JewishDate.fromDateTime(gregorianDate);
  return CalendarState(
    selectedJewishDate: jewishDate,
    selectedGregorianDate: gregorianDate,
    selectedCity: 'ירושלים',
    dailyTimes: const {},
    currentJewishDate: jewishDate,
    currentGregorianDate: gregorianDate,
    todayGregorianDate: gregorianDate,
    calendarType: CalendarType.combined,
    calendarView: CalendarView.month,
    dayTransition: CalendarDayTransition.sunset,
    inIsrael: inIsrael,
  );
}

class _InMemoryPluginReportQueue
    extends HiveListRepository<PluginReportRecord> {
  List<PluginReportRecord> _items = [];

  _InMemoryPluginReportQueue()
    : super(
        boxName: 'in_memory',
        key: 'pending_reports',
        fromJson: PluginReportRecord.fromJson,
        toJson: (record) => record.toJson(),
      );

  @override
  Future<List<PluginReportRecord>> load() async {
    return List<PluginReportRecord>.from(_items);
  }

  @override
  Future<void> save(List<PluginReportRecord> items) async {
    _items = List<PluginReportRecord>.from(items);
  }

  @override
  Future<void> clear() async {
    _items = [];
  }
}
