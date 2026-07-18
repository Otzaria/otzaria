import 'dart:convert';
import 'dart:io';
// קידומת ל-Link של dart:io כי models/links.dart מגדיר Link משלו שמסתיר אותו.
import 'dart:io' as io show Link;

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:path/path.dart' as p;
import 'package:mockito/mockito.dart';
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
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _StubTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = TabsState.initial();

  @override
  TabsState get state => currentState;
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

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _StubPluginRegistryRepository extends PluginRegistryRepository {
  List<PluginPermissionGrant> permissions = [];
  bool? permissionGrant;

  /// מיפוי פר-הרשאה; כשמוגדר, גובר על [permissionGrant].
  Map<String, bool>? permissionGrants;

  // KV in-memory (מפתח: "namespace/key") — מחליף את ה-DB בבדיקות.
  final Map<String, String> kv = {};

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(
      String pluginId) async {
    return permissions;
  }

  @override
  Future<bool?> getPermission(String pluginId, String permission) async {
    if (permissionGrants != null) return permissionGrants![permission];
    return permissionGrant;
  }

  @override
  Future<void> setKV(
      String pluginId, String namespace, String key, String valueJson) async {
    kv['$namespace/$key'] = valueJson;
  }

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async {
    return kv['$namespace/$key'];
  }

  @override
  Future<void> removeKV(String pluginId, String namespace, String key) async {
    kv.remove('$namespace/$key');
  }
}

InstalledPlugin _buildInstalledPlugin({
  List<String> permissions = const [],
  bool networkEnabled = false,
  List<String> networkAllowlist = const [],
}) {
  return InstalledPlugin(
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
    showWarningDialog: ({
      required title,
      required content,
      required subtitle,
    }) async =>
        true,
  );
}

void main() {
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
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

      final response = await adapter.execute('calendar', 'getJewishDate', {})
          as Map<String, dynamic>;

      expect(response['year'], jewishCalendar.getJewishYear());
      expect(response['month'], jewishCalendar.getJewishMonth());
      expect(response['day'], jewishCalendar.getJewishDayOfMonth());
      expect(response['monthName'], formatter.formatMonth(jewishCalendar));
      expect(response['isLeapYear'], jewishCalendar.isJewishLeapYear());
      expect(response['isShabbat'], jewishCalendar.getDayOfWeek() == 7);

      final holidays =
          (response['holidays'] as List<dynamic>).cast<Map<String, String>>();
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

      final response = await adapter.execute('calendar', 'getJewishDate', {})
          as Map<String, dynamic>;
      final holidays =
          (response['holidays'] as List<dynamic>).cast<Map<String, String>>();

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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
              true,
        ),
        pluginRepository: pluginRegistryRepository,
      );
    });

    test('app.getGrantedPermissions returns only granted permissions',
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

      final response = await adapter.execute('app', 'getGrantedPermissions', {})
          as Map<String, dynamic>;

      expect(response['permissions'], ['app.info.read', 'reader.open']);
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
            predicate((e) => e.toString().contains('error.invalid_params'))),
      );
    });

    test('reader.getCurrentRef returns current reference for active pdf tab',
        () async {
      final currentTab = PdfBookTab(
        book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
        pageNumber: 17,
      )..currentTitle.value = 'פרק ב';
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

      final response = await adapter.execute('reader', 'getCurrentRef', {})
          as Map<String, dynamic>;

      expect(response['currentBook'], 'מסילת ישרים');
      expect(response['currentBookId'], 'מסילת ישרים');
      expect(response['currentIndex'], 17);
      expect(response['currentRef'], 'פרק ב');
    });

    test('reader.getCurrentRef returns null ref for pdf tab without title',
        () async {
      final currentTab = PdfBookTab(
        book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
        pageNumber: 0,
      );
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

      final response = await adapter.execute('reader', 'getCurrentRef', {})
          as Map<String, dynamic>;

      expect(response['currentBook'], 'מסילת ישרים');
      expect(response['currentBookId'], 'מסילת ישרים');
      expect(response['currentIndex'], 0);
      expect(response['currentRef'], isNull);
    });

    test('reader.getCurrentRef returns current reference for active text tab',
        () async {
      final currentTab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 42,
      )..currentTitle.value = 'פרק ג';
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

      final response = await adapter.execute('reader', 'getCurrentRef', {})
          as Map<String, dynamic>;

      expect(response['currentBook'], 'בראשית');
      expect(response['currentBookId'], 'בראשית');
      expect(response['currentIndex'], 42);
      expect(response['currentRef'], 'פרק ג');
    });

    test('reader.getCurrentRef returns null when no tab is active', () async {
      tabsBloc.currentState = TabsState.initial();

      final response = await adapter.execute('reader', 'getCurrentRef', {})
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
      tabsBloc.currentState = TabsState(tabs: [currentTab], currentTabIndex: 0);

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
    });
  });

  group('PluginBridgeAdapter.reader.openBookAtRef', () {
    late _MockBookOpenCoordinator mockCoordinator;
    late TextBook yerushalmi;

    PluginBridgeAdapter buildAdapter({
      Future<List<({String title, int index, bool isPdf})>> Function(String)?
          resolveReference,
      Future<int?> Function(TextBook book, String ref)? resolveRefToLine,
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
              true,
          resolveReference: resolveReference,
          resolveRefToLine: resolveRefToLine,
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

    test('find_ref מפענח הפניה מובנית → קופץ ל-index בלי להשאיר חיפוש',
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
      verify(mockCoordinator.openBook(yerushalmi, 1234, '',
              ignoreHistory: true, markSection: false))
          .called(1);
    });

    test('רזולוציה לרמת שורה קודמת ל-find_ref ומכבדת highlight', () async {
      var findRefCalled = false;
      final adapter = buildAdapter(
        resolveReference: (reference) async {
          findRefCalled = true;
          return [(title: 'תלמוד ירושלמי עירובין', index: 1, isPdf: false)];
        },
        resolveRefToLine: (book, ref) async =>
            (book.title == 'תלמוד ירושלמי עירובין' && ref == 'לג:ה')
                ? 1194
                : null,
      );

      final result = await adapter.execute('reader', 'openBookAtRef', {
        'bookId': 'תלמוד ירושלמי עירובין',
        'ref': 'לג:ה',
        'highlight': true,
      });

      expect(result, isTrue);
      expect(findRefCalled, isFalse);
      verify(mockCoordinator.openBook(yerushalmi, 1194, '',
              ignoreHistory: true, markSection: true))
          .called(1);
    });

    test('כשאין התאמה ברמת שורה — נופלים ל-find_ref, בלי הדגשה כברירת מחדל',
        () async {
      final adapter = buildAdapter(
        resolveReference: (reference) async => [
          (title: 'תלמוד ירושלמי עירובין', index: 1234, isPdf: false),
        ],
        resolveRefToLine: (book, ref) async => null,
      );

      final result = await adapter.execute('reader', 'openBookAtRef', {
        'bookId': 'תלמוד ירושלמי עירובין',
        'ref': 'פ"ו ה"ז',
      });

      expect(result, isTrue);
      verify(mockCoordinator.openBook(yerushalmi, 1234, '',
              ignoreHistory: true, markSection: false))
          .called(1);
    });
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

      final library = Library(categories: [
        Category(
          title: 'בדיקה',
          description: '',
          shortDescription: '',
          order: 0,
          subCategories: const [],
          books: [textBookDocx, textBookTxt, pdfBookEntry],
          parent: null,
        ),
      ]);
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
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

    test(
        'TextBook עם fileType=docx מנותב דרך TextBookRepository עם ה-fileType '
        'הנכון (תיקון d94133731)', () async {
      // הבאג: הקוד הישן קרא ל-DataRepository.getBookText שמשתמש ב-fileType=
      // 'txt' כברירת מחדל. עבור משתמש עם seforim.db בלבד, זה היה מחזיר
      // נתון שגוי (או תוכן txt שאינו קיים, או כשל). התיקון: שימוש ב-
      // TextBookRepository שלוקח את ה-fileType מ-metadata של ה-TextBook.
      final result = await adapter
          .execute('library', 'getBookContent', const {'bookId': 'ספר-docx'});

      expect(result, 'תוכן docx של הספר - נכון');
      expect(result, isNot(contains('שגוי')),
          reason: 'אסור שהקוד יפול חזרה ל-fileType=txt לספר docx');
    });

    test('TextBook עם fileType=txt עובר דרך TextBookRepository כרגיל',
        () async {
      final result = await adapter
          .execute('library', 'getBookContent', const {'bookId': 'ספר-txt'});

      expect(result, 'תוכן txt רגיל');
    });

    test(
        'ספר שאינו בקטלוג נופל ל-DataRepository.getBookText (ברירת המחדל '
        'fileType=txt)', () async {
      final result = await adapter
          .execute('library', 'getBookContent', const {'bookId': 'שלא-בקטלוג'});

      expect(result, 'תוכן fallback של ספר שאינו בקטלוג');
    });

    test('PdfBook בקטלוג (לא TextBook) נופל ל-DataRepository.getBookText',
        () async {
      // ה-discriminator הוא `cataloged is TextBook`. PdfBook נכשל בבדיקה
      // ולכן נכנס לענף ה-else במקום ל-TextBookRepository.
      final result = await adapter
          .execute('library', 'getBookContent', const {'bookId': 'ספר-pdf'});

      expect(result, 'תוכן fallback של ה-pdf');
    });

    test('title כ-alias ל-bookId נתמך (תאימות לאחור)', () async {
      final result = await adapter
          .execute('library', 'getBookContent', const {'title': 'ספר-txt'});

      expect(result, 'תוכן txt רגיל');
    });

    test('offset חותך מתחילת הטקסט כשלא ניתן section', () async {
      // טקסט "ABCDEFGHIJKLMNOP" באורך 16, offset=4 — מתחיל מ-'E'.
      final result = await adapter.execute('library', 'getBookContent',
          const {'bookId': 'ספר-לחיתוך', 'offset': 4, 'limit': 5});

      expect(result, 'EFGHI');
    });

    test('limit שולט בגודל המקטע המוחזר', () async {
      final result = await adapter.execute('library', 'getBookContent',
          const {'bookId': 'ספר-לחיתוך', 'limit': 3});

      expect(result, 'ABC');
    });

    test(
        'section + offset: ה-offset נספר יחסית למיקום ה-section, לא לתחילת '
        'הטקסט (תיקון 00ccfa63d)', () async {
      // טקסט "ABCDEFGHIJKLMNOP". section='C' נמצא ב-index 2.
      // offset=3 פירושו 3 תווים אחרי 'C', כלומר מתחילים מ-index 5 ('F').
      // הקוד הישן התעלם מה-offset כש-section ניתן (startIndex = idx בלבד).
      final result = await adapter.execute(
        'library',
        'getBookContent',
        const {
          'bookId': 'ספר-לחיתוך',
          'section': 'C',
          'offset': 3,
          'limit': 4,
        },
      );

      expect(result, 'FGHI',
          reason: 'section ב-index 2 + offset 3 → התחלה ב-index 5');
    });

    test('section ב-offset=0 מתחיל מהמיקום של section (התנהגות שלא השתנתה)',
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
    });

    test('section שלא נמצא מתעלם וחוזר ל-offset רגיל מתחילת הטקסט', () async {
      final result = await adapter.execute(
        'library',
        'getBookContent',
        const {
          'bookId': 'ספר-לחיתוך',
          'section': 'XYZ',
          'offset': 2,
          'limit': 3,
        },
      );

      expect(result, 'CDE',
          reason: 'section שלא נמצא → startIndex נשאר offset (2)');
    });

    test('limit > 5000 חתוך ל-5000', () async {
      // לוקחים תוכן קצר ולכן באמת הקליפ יהיה אורך הטקסט.
      final result = await adapter.execute('library', 'getBookContent',
          const {'bookId': 'ספר-לחיתוך', 'limit': 99999});

      // limit מקבוע ל-5000, end = (0 + 5000).clamp(0, 16) = 16 → כל הטקסט
      expect(result, 'ABCDEFGHIJKLMNOP');
    });

    test('offset החורג מהאורך מקובע לסוף הטקסט (clamp)', () async {
      final result = await adapter.execute('library', 'getBookContent',
          const {'bookId': 'ספר-לחיתוך', 'offset': 999, 'limit': 5});

      expect(result, '');
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
              true,
        ),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    });

    test('מחזיר את העץ המלא עם קטגוריות מקוננות וספרים', () async {
      final result = await adapter.execute('library', 'getTree', const {})
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
      final result = await adapter
              .execute('library', 'getTree', const {'path': '/תנך/ראשונים'})
          as Map<String, dynamic>;

      expect(result['title'], 'ראשונים');
      final books = result['books'] as List<dynamic>;
      expect((books.first as Map<String, dynamic>)['title'], 'רשי');
    });

    test('path שאינו קיים מחזיר null', () async {
      final result = await adapter
          .execute('library', 'getTree', const {'path': '/לא-קיים'});

      expect(result, isNull);
    });

    test('includeBooks=false משמיט את רשימות הספרים', () async {
      final result = await adapter
              .execute('library', 'getTree', const {'includeBooks': false})
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
              true,
        ),
        pluginRepository: pluginRegistryRepository,
      );
    });

    test('network.fetch חוסם גם URL מובנה אם המניפסט של התוסף לא הצהיר עליו',
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
    });

    test('network.fetch ל-localhost נחסם כשיש רק network.access (לא localhost)',
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
    });

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
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
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
    });
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
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

      final result = await adapter.execute('network', 'fetch', const {
        'url': 'https://nakdan.dicta.org.il/api',
        'method': 'POST',
        'headers': {'Content-Type': 'application/json;charset=UTF-8'},
        'body': '{"task":"nakdan"}',
      }) as Map<String, dynamic>;

      expect(captured.method, 'POST');
      expect(captured.body, '{"task":"nakdan"}');
      expect(
          captured.headers['content-type'], 'application/json;charset=UTF-8');
      expect(result['status'], 200);
      expect(result['ok'], isTrue);
      expect(result['body'], '{"data":[]}');
    });

    test('סטטוס שאינו 2xx מוחזר עם ok=false', () async {
      final fetchService = PluginNetworkFetchService(
        client: MockClient((req) async => http.Response('err', 500)),
      );
      final adapter = buildAdapter(fetchService);

      final result = await adapter.execute('network', 'fetch', const {
        'url': 'https://nakdan.dicta.org.il/api',
      }) as Map<String, dynamic>;

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
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('invalid method'),
        )),
      );
      expect(hit, isFalse);
    });
  });

  group('PluginBridgeAdapter fs + pickFolder + download.destPath', () {
    late Directory tempDir;
    late _StubPluginRegistryRepository registry;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adapter_fs_test_');
      registry = _StubPluginRegistryRepository()..permissionGrant = true;
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const downloadUrl =
        'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download/books.zip';

    PluginBridgeAdapter buildAdapter({
      required Future<String?> Function({String? title}) pickFolder,
      PluginFileDownloadService? fileDownloadService,
    }) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(
          permissions: const ['ui.feedback', 'network.access'],
          networkEnabled: true,
          networkAllowlist: const [
            'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books'
          ],
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
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
      final del =
          await adapter.execute('fs', 'deleteFile', {'path': file.path});
      expect(del, isTrue);
      expect(file.existsSync(), isFalse);
    });

    test('ביטול ui.pickFolder מחזיר {path:null} ואינו מעניק הרשאה', () async {
      final adapter = buildAdapter(pickFolder: ({title}) async => null);

      final res = await adapter.execute('ui', 'pickFolder', {}) as Map;
      expect(res['path'], isNull);

      final file = File(p.join(tempDir.path, 'y.zip'))..writeAsBytesSync([1]);
      await expectLater(
        adapter.execute('fs', 'deleteFile', {'path': file.path}),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('forbidden'))),
      );
      // הקובץ לא נמחק — הפעולה נחסמה.
      expect(file.existsSync(), isTrue);
    });

    test('fs.extractZip מחלץ בתוך תיקייה מאושרת', () async {
      final adapter = buildAdapter(pickFolder: ({title}) async => tempDir.path);
      await adapter.execute('ui', 'pickFolder', {});

      final zipPath = buildZip(tempDir.path, 'a.zip');
      final dest = p.join(tempDir.path, 'out');
      final ok = await adapter.execute(
          'fs', 'extractZip', {'zipPath': zipPath, 'destFolder': dest});

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
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('forbidden'))),
      );
    });

    test('network.download עם destPath שומר בתוך תיקייה מאושרת', () async {
      final client =
          MockClient((req) async => http.Response.bytes([7, 8, 9], 200));
      final adapter = buildAdapter(
        pickFolder: ({title}) async => tempDir.path,
        fileDownloadService: PluginFileDownloadService(client: client),
      );
      await adapter.execute('ui', 'pickFolder', {});

      final destPath = p.join(tempDir.path, 'books.zip');
      final res = await adapter.execute('network', 'download', {
        'url': downloadUrl,
        'destPath': destPath,
      }) as Map;

      expect(res['path'], destPath);
      expect(File(destPath).readAsBytesSync(), [7, 8, 9]);
    });

    test('network.download עם destPath מחוץ לתיקייה מאושרת נחסם ואינו מוריד',
        () async {
      var hit = false;
      final client = MockClient((req) async {
        hit = true;
        return http.Response.bytes([0], 200);
      });
      final granted = Directory(p.join(tempDir.path, 'granted'))..createSync();
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
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('forbidden'))),
      );
      expect(hit, isFalse);
    });

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
        adapter.execute(
            'fs', 'deleteFile', {'path': p.join(link.path, 'secret.txt')}),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('forbidden'))),
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
      }) pickFile,
    }) {
      return PluginBridgeAdapter(
        _buildInstalledPlugin(permissions: const ['fs.user_files.read']),
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
          showWarningDialog: ({
            required title,
            required content,
            required subtitle,
          }) async =>
              true,
          pickFile: pickFile,
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

    test('pickUserFile רושם token, מתמיד אותו ב-KV וה-URL מגיש את הקובץ',
        () async {
      final pdf = File(p.join(tempDir.path, 'book.pdf'))
        ..writeAsStringSync('%PDF content');
      final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => pdf.path);

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
    });

    test('ביטול pickUserFile מחזיר {cancelled:true} בלי להתמיד grant',
        () async {
      final adapter =
          buildAdapter(pickFile: ({allowedExtensions, title}) async => null);

      final res = await adapter.execute('fs', 'pickUserFile', {}) as Map;

      expect(res['cancelled'], isTrue);
      expect(registry.kv['_internal/user_file_grants'], isNull);
    });

    test('resolveFileUrl בונה URL חדש מ-token שהותמד (סימולציית reload)',
        () async {
      final file = File(p.join(tempDir.path, 'notes.txt'))
        ..writeAsStringSync('שלום עולם');
      final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => file.path);

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final token = picked['token'] as String;

      // reload: רישום הזיכרון של השרת אבד, אך ה-grant נשמר ב-KV.
      await fileServer.close();

      final resolved = await adapter
          .execute('fs', 'resolveFileUrl', {'token': token}) as Map;
      expect(resolved['token'], token);
      expect(resolved['name'], 'notes.txt');
      expect(await fetch(resolved['url'] as String), 'שלום עולם');
    });

    test('resolveFileUrl על token לא מוכר זורק error.not_found', () async {
      final adapter =
          buildAdapter(pickFile: ({allowedExtensions, title}) async => null);

      await expectLater(
        adapter.execute('fs', 'resolveFileUrl', {'token': 'nope'}),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('not_found'))),
      );
    });

    test('readTextFile מחזיר את תוכן הקובץ המאושר', () async {
      final file = File(p.join(tempDir.path, 'a.txt'))
        ..writeAsStringSync('תוכן טקסטואלי');
      final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => file.path);

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final content = await adapter
          .execute('fs', 'readTextFile', {'token': picked['token']});

      expect(content, 'תוכן טקסטואלי');
    });

    test('revokeFile מסיר את ה-grant — resolveFileUrl לאחריו נכשל', () async {
      final file = File(p.join(tempDir.path, 'x.txt'))..writeAsStringSync('x');
      final adapter = buildAdapter(
          pickFile: ({allowedExtensions, title}) async => file.path);

      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      final token = picked['token'] as String;

      final revoked =
          await adapter.execute('fs', 'revokeFile', {'token': token});
      expect(revoked, isTrue);
      expect(registry.kv['_internal/user_file_grants'], isNot(contains(token)));

      await expectLater(
        adapter.execute('fs', 'resolveFileUrl', {'token': token}),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('not_found'))),
      );
    });
  });

  group('PluginBridgeAdapter plugin.openSelf + context menu openPlugin', () {
    late PluginBridgeAdapter adapter;

    setUp(() {
      adapter = PluginBridgeAdapter(
        _buildInstalledPlugin(
            permissions: const ['navigation.write', 'reader.context_menu']),
        dependencies: _buildNetworkDeps(),
        pluginRepository: _StubPluginRegistryRepository(),
      );
    });

    tearDown(() {
      PluginPageLauncher.instance.navigator = null;
      ContextMenuRegistry.instance.removeAll('test.plugin');
    });

    test('plugin.openSelf מנווט לדף התוסף עצמו', () async {
      final navigations = <String>[];
      PluginPageLauncher.instance.navigator = navigations.add;

      final result =
          await adapter.execute('plugin', 'openSelf', {'param': 'x'});

      expect(result, isTrue);
      expect(navigations, ['test.plugin']);
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
  });
}

/// Provider פיקטיבי שמחזיר טקסט לפי מפתחות מוגדרים מראש.
/// משמש לבדיקת ה-routing דרך LibraryProviderManager בלי לגשת ל-DB אמיתי.
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
      Map<String, Map<String, dynamic>> metadata) async {
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
      String title, int categoryId, String fileType) async {
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
