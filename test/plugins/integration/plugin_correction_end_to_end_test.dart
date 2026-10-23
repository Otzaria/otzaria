import 'dart:convert';
import 'dart:io';
import '../../test_helpers/activate_correction_paragraph.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_book_correction_service.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_session_banner.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// מסלול מקומי מלא של תיקון תוסף: adapter, שירות הסשנים עם worker אמיתי על
/// קובץ, הקורא, והדיווח. ההזרקה היחידה ברשת: ה-client מפנה ל-loopback.

const _pluginId = 'e2e.corrector';
const _pluginName = 'מתקן בדיקה';
const _productionEndpoint = 'https://otzaria.org/api/reportingerrors';
const _lines = ['בראשית א', 'שורה ב', 'שורה ג'];

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

class _NoLinks implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReaderBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _ReaderBloc(TextBook book)
    : super(
        TextBookLoaded.initial(
          book: book,
          index: 0,
          showLeftPane: false,
          splitView: false,
        ).copyWith(content: _lines),
      ) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _NoLinks();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _NotesBloc() : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealHttpOverrides extends HttpOverrides {}

/// שומר על הבקשה כפי שנבנתה (כתובת, כותרות, גוף) ומחליף רק את היעד.
class _LoopbackClient extends http.BaseClient {
  _LoopbackClient(this.target);

  final Uri target;
  // ה-binding של הבדיקות מחליף את HttpClient הגלובלי בתשובת 400 קבועה.
  final http.Client _inner = HttpOverrides.runWithHttpOverrides(
    () => IOClient(HttpClient()),
    _RealHttpOverrides(),
  );
  final List<Uri> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url);
    final original = request as http.Request;
    final redirected =
        http.Request(
            original.method,
            request.url.replace(
              scheme: target.scheme,
              host: target.host,
              port: target.port,
            ),
          )
          ..headers.addAll(original.headers)
          ..bodyBytes = original.bodyBytes;
    return _inner.send(redirected);
  }

  @override
  void close() => _inner.close();
}

typedef _Received = ({
  String method,
  String path,
  HttpHeaders headers,
  Map<String, dynamic> body,
});

InstalledPlugin _plugin(List<String> permissions) => InstalledPlugin(
  pluginId: _pluginId,
  name: _pluginName,
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: _pluginId,
    name: _pluginName,
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
    toolTabTitle: _pluginName,
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PluginCorrectionSessionService.instance;
  const permissions = [
    'reader.open',
    'reader.local_edit',
    'feedback.send_email',
  ];

  late Directory temporary;
  late String draftDbPath;
  late PluginCorrectionDraftRepository drafts;
  late HttpServer server;
  late _LoopbackClient client;
  late UserStateDatabase reportsDb;
  late DirectErrorReportService reports;
  late _Tabs tabs;
  late TextBook book;
  final received = <_Received>[];
  final events = <({String topic, Map<String, dynamic> payload})>[];
  final disposables = <Future<void> Function()>[];

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Otzaria',
      packageName: 'com.otzaria.app',
      version: '9.9.9',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('correction-e2e-');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(temporary.path, 'data'));
    final libraryDb = SeforimFixtureDb.create(
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
      libraryDb,
    );
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      'tester@example.com',
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();

    book = TextBook(id: SeforimFixtureIds.bereshitId, title: 'בראשית');
    final category = Category(
      title: 'תורה',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [book],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    DataRepository.instance.library = Future.value(library);
    tabs = _Tabs()..current = TabsState(tabs: const [], currentTabIndex: 0);

    draftDbPath = path.join(temporary.path, 'plugins_host.db');
    drafts = PluginCorrectionDraftRepository.isolate(
      dbPath: () async => draftDbPath,
    );
    service.draftRepository = drafts;

    received.clear();
    events.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      received.add((
        method: request.method,
        path: request.uri.path,
        headers: request.headers,
        body: jsonDecode(body) as Map<String, dynamic>,
      ));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': true, 'correction_supported': true}));
      await request.response.close();
    });
    client = _LoopbackClient(Uri.parse('http://127.0.0.1:${server.port}'));
    reportsDb = UserStateDatabase.openAt(
      path.join(temporary.path, 'user_state.db'),
    );
    reports = DirectErrorReportService(
      client: client,
      reportStore: PendingReportStore(database: reportsDb),
    );
  });

  tearDown(() async {
    for (final dispose in disposables.reversed) {
      await dispose();
    }
    disposables.clear();
    await service.purgeOwner(_pluginId);
    await drafts.dispose();
    client.close();
    await server.close(force: true);
    reportsDb.close();
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await temporary.delete(recursive: true);
  });

  PluginBridgeAdapter buildAdapter() {
    // אותו חיווט כמו ב-adapter עצמו; רק ה-client של השירות האמיתי הוחלף.
    final adapter = PluginBridgeAdapter(
      _plugin(permissions),
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
            ({required title, required content, required subtitle}) async =>
                true,
        // התוסף אינו צורך אירועים: הם נרשמים בלבד.
        dispatchEventToPlugin: (pluginId, topic, payload, {instanceId}) async =>
            events.add((
              topic: topic,
              payload: Map<String, dynamic>.from(payload),
            )),
      ),
      pluginRepository: _Grants(permissions),
      bookCorrectionService: PluginBookCorrectionService(
        senderEmail: () => reports.senderEmail,
        deliver: reports.submitReport,
      ),
    );
    disposables.add(() async => adapter.dispose());
    return adapter;
  }

  TextBookTab openTab() {
    final tab = TextBookTab(
      book: book,
      index: 0,
      blocOverride: _ReaderBloc(book),
    );
    tabs.current = TabsState(tabs: [tab], currentTabIndex: 0);
    return tab;
  }

  Map<String, Object?>? draftRow() {
    final db = sqlite3.sqlite3.open(
      draftDbPath,
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      final rows = db.select(
        'SELECT * FROM plugin_correction_draft WHERE plugin_id = ?',
        [_pluginId],
      );
      return rows.isEmpty ? null : Map<String, Object?>.of(rows.single);
    } finally {
      db.close();
    }
  }

  testWidgets(
    'עריכה בקורא נשמרת עמידה, משוחזרת אחרי "הפעלה מחדש", נשלחת כדיווח ומאושרת',
    (tester) async {
      Future<T> real<T>(Future<T> Function() body) async =>
          (await tester.runAsync(body)) as T;

      // הכתיבה מההקלדה רצה בשעון המדומה וה-worker בעולם האמיתי; מקדמים את שניהם.
      Future<void> pumpUntil(bool Function() done, String what) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await real(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(done(), isTrue, reason: what);
      }

      Future<Map<String, dynamic>> call(
        PluginBridgeAdapter adapter,
        String namespace,
        String action,
        Map<String, dynamic> args,
      ) async => Map<String, dynamic>.from(
        await real(() => adapter.execute(namespace, action, args)) as Map,
      );

      Future<void> mountReader(TextBookTab tab) async {
        final settings = _SettingsBloc();
        final notes = _NotesBloc();
        disposables.add(() async {
          await settings.close();
          await notes.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<TextBookBloc>.value(value: tab.bloc),
                  BlocProvider<SettingsBloc>.value(value: settings),
                  BlocProvider<PersonalNotesBloc>.value(value: notes),
                ],
                child: Column(
                  children: [
                    PluginCorrectionSessionBanner(
                      tabId: PluginCorrectionSessionService.tabIdFor(tab),
                    ),
                    Expanded(
                      child: CombinedView(
                        data: _lines,
                        tab: tab,
                        openBookCallback: (_) {},
                        openLeftPaneTab: (_, {searchText}) {},
                        textSize: 18,
                        showCommentaryAsExpansionTiles: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder editors() => find.byType(RtlTextField);
      String editorText() =>
          tester.widget<RtlTextField>(editors().first).controller!.text;

      // 1. התוסף פותח סשן; אין עדיין טיוטה.
      final tab = openTab();
      final tabId = PluginCorrectionSessionService.tabIdFor(tab);
      final adapter = buildAdapter();
      await mountReader(tab);
      expect(editors(), findsNothing);
      final begun = await call(adapter, 'reader', 'beginCorrectionSession', {
        'tabId': tabId,
      });
      expect(begun['recovery'], isNull);
      expect(begun['changes'], isEmpty);
      await tester.pumpAndSettle();
      expect(editors(), findsNothing);
      await activateCorrectionParagraph(
        tester,
        find.text(_lines.first, findRichText: true).first,
      );
      await tester.pumpAndSettle();
      expect(editors(), findsWidgets);
      expect(editorText(), _lines.first);
      expect(
        find.text(PluginCorrectionSessionBanner.modeText(_pluginName)),
        findsOneWidget,
      );

      // 2. המשתמש מקליד בשדה שבתוך הקורא.
      const proposed = 'בראשית א מתוקן';
      await tester.enterText(editors().first, proposed);
      await pumpUntil(
        () =>
            service.draftStatusForTab(tabId) ==
            PluginCorrectionDraftStatus.saved,
        'הטיוטה נשמרת דרך ה-worker',
      );
      final edited = await call(adapter, 'reader', 'getCorrectionSession', {
        'sessionId': begun['sessionId'],
      });
      expect(edited['revision'], 1);
      expect(edited['changes'], [
        {
          'sectionIndex': 0,
          'originalSourceText': _lines.first,
          'originalText': _lines.first,
          'proposedText': proposed,
        },
      ]);
      final editedDraft = Map<String, dynamic>.from(edited['draft'] as Map);
      expect(editedDraft['persisted'], isTrue);
      expect(editedDraft['version'], isA<int>());
      expect(
        find.text(PluginCorrectionSessionBanner.savedText),
        findsOneWidget,
      );

      // 3. הלשונית נסגרת והתוסף לא צרך אף אירוע; הטיוטה נשארת בקובץ.
      await tester.pumpWidget(const SizedBox.shrink());
      tab.dispose();
      await pumpUntil(
        () =>
            events.any(
              (event) => event.topic == 'reader.correctionSessionEnded',
            ) &&
            draftRow()?['holder'] == null,
        'הסשן הסתיים וה-lease שוחרר',
      );
      final ended = events.lastWhere(
        (event) => event.topic == 'reader.correctionSessionEnded',
      );
      expect(ended.payload['reason'], 'tab_closed');
      final row = draftRow()!;
      expect(row['version'], editedDraft['version']);
      expect(row['acknowledged_version'], isNull);
      expect(jsonDecode(row['changes_json'] as String), edited['changes']);

      // 4. "הפעלה מחדש": חיבור ו-worker חדשים לאותו קובץ, adapter ולשונית חדשים.
      // זו סימולציה של אתחול השירות והמסד, לא של קריסת תהליך.
      await real(drafts.dispose);
      drafts = PluginCorrectionDraftRepository.isolate(
        dbPath: () async => draftDbPath,
      );
      service.draftRepository = drafts;
      final reopenedTab = openTab();
      final reopenedTabId = PluginCorrectionSessionService.tabIdFor(
        reopenedTab,
      );
      disposables.add(() async => reopenedTab.dispose());
      final restartedAdapter = buildAdapter();
      await mountReader(reopenedTab);
      final reopened = await call(
        restartedAdapter,
        'reader',
        'beginCorrectionSession',
        {'tabId': reopenedTabId},
      );
      expect(reopened['recovery'], {
        'draftId': editedDraft['draftId'],
        'fromVersion': editedDraft['version'],
        'restoredSectionIndices': [0],
        'conflicts': isEmpty,
      });
      expect(reopened['changes'], edited['changes']);
      final reopenedDraft = Map<String, dynamic>.from(reopened['draft'] as Map);
      expect(reopenedDraft['persisted'], isTrue);
      expect(reopenedDraft['version'], greaterThan(editedDraft['version']));
      await tester.pumpAndSettle();
      expect(editorText(), proposed);
      expect(
        find.text(PluginCorrectionSessionBanner.modeText(_pluginName)),
        findsOneWidget,
      );
      final listed = await call(
        restartedAdapter,
        'reader',
        'listCorrectionDrafts',
        {},
      );
      expect((listed['drafts'] as List).single['changeCount'], 1);

      // שלילי: שינוי שאינו ניתן למיפוי מדויק אינו יוצא לרשת.
      // runAsync מדווח חריגה כשגיאת מבחן, ולכן היא נתפסת בתוכו.
      final rejection = await real<Object?>(() async {
        try {
          await restartedAdapter.execute('feedback', 'submitBookCorrection', {
            'bookId': 'בראשית',
            'bookUid': reopened['bookUid'],
            'reportId': 'e2e-span',
            'sectionIndex': 0,
            'endSectionIndex': 1,
            'original': '${_lines[0]}\n${_lines[1]}',
            'proposed': '$proposed\n${_lines[1]}',
            'snapshots': [
              {'index': 0, 'text': _lines[0]},
              {'index': 1, 'text': _lines[1]},
            ],
            'requireTextCorrection': true,
            'allowQueue': false,
          });
          return null;
        } catch (error) {
          return error;
        }
      });
      expect('$rejection', contains('error.text_correction_unavailable'));
      expect(received, isEmpty);
      expect(client.requestedUrls, isEmpty);

      // 5. התוסף שולח את התיקון שנגזר מה-snapshot.
      final change = Map<String, dynamic>.from(
        (reopened['changes'] as List).single as Map,
      );
      final sent = await call(
        restartedAdapter,
        'feedback',
        'submitBookCorrection',
        {
          'bookId': reopened['bookId'],
          'bookUid': reopened['bookUid'],
          'reportId': 'e2e-1',
          'sectionIndex': change['sectionIndex'],
          'original': change['originalText'],
          'proposed': change['proposedText'],
          'snapshots': [
            {'index': change['sectionIndex'], 'text': change['originalText']},
          ],
          'requireTextCorrection': true,
          'allowQueue': false,
        },
      );
      expect(sent['status'], 'sent');
      expect(sent['reportKind'], 'text_correction');
      expect(sent['correctionSupported'], isTrue);
      expect(sent['nativeReportId'], '$_pluginId:e2e-1');
      expect(client.requestedUrls, [Uri.parse(_productionEndpoint)]);
      expect(received, hasLength(1));
      final request = received.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/reportingerrors');
      expect(request.headers.contentType?.mimeType, 'application/json');
      final body = request.body;
      expect(body['report_id'], '$_pluginId:e2e-1');
      expect(body['report_kind'], 'text_correction');
      expect(body['sender_email'], 'tester@example.com');
      expect(body['book_title'], 'בראשית');
      expect(body['line_number'], 1);
      expect(body['correction'], {
        'original_line': _lines.first,
        'original_selection': anything,
        'selection_offset': anything,
        'proposed_text': proposed,
        'context_before': anything,
        'context_after': anything,
      });
      expect(body['error_details'], contains('תיקון מתוך תוסף $_pluginId'));
      expect(
        (body['location'] as Map)['book_id'],
        SeforimFixtureIds.bereshitId,
      );
      expect((body['client'] as Map)['app_version'], '9.9.9+1');
      expect(await real(reports.getPendingReportsCount), 0);

      // 6. התוסף מאשר את הגרסה המדויקת שקיבל; הטיוטה נמחקת ואינה חוזרת.
      final acked = await call(
        restartedAdapter,
        'reader',
        'acknowledgeCorrectionDraft',
        {
          'draftId': reopenedDraft['draftId'],
          'version': reopenedDraft['version'],
        },
      );
      expect(acked, {
        'draftId': reopenedDraft['draftId'],
        'version': reopenedDraft['version'],
        'acknowledged': true,
        'duplicate': false,
      });
      expect(
        (await call(
          restartedAdapter,
          'reader',
          'listCorrectionDrafts',
          {},
        ))['drafts'],
        isEmpty,
      );
      final endedAgain = await call(
        restartedAdapter,
        'reader',
        'endCorrectionSession',
        {
          'sessionId': reopened['sessionId'],
          'expectedRevision': reopened['revision'],
        },
      );
      expect(endedAgain['draft']['persisted'], isTrue);
      await pumpUntil(
        () => draftRow()?['holder'] == null,
        'ה-lease שוחרר אחרי סיום',
      );
      final fresh = await call(
        restartedAdapter,
        'reader',
        'beginCorrectionSession',
        {'tabId': reopenedTabId},
      );
      expect(fresh['recovery'], isNull);
      expect(fresh['changes'], isEmpty);
      await tester.pumpAndSettle();
      expect(editors(), findsNothing);
      await activateCorrectionParagraph(
        tester,
        find.text(_lines.first, findRichText: true).first,
      );
      await tester.pumpAndSettle();
      expect(editorText(), _lines.first);
      expect(received, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
