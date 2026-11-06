import 'dart:async';
import 'dart:io';

import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_remote_file_cache.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdfrx/pdfrx.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

/// KV בזיכרון — מספיק ל-grants של `fs.pickUserFile`.
class _Registry extends PluginRegistryRepository {
  final Map<String, String> kv = {};

  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async => kv['$pluginId/$namespace/$key'] = valueJson;

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv['$pluginId/$namespace/$key'];
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'test.plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'test.plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'test.plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<Uint8List> _threePagePdf() {
  final doc = pw.Document();
  for (var i = 1; i <= 3; i++) {
    doc.addPage(pw.Page(build: (_) => pw.Text('page $i')));
  }
  return doc.save();
}

/// ה-worker של pdfrx פותח מסמכים בתוך ה-FakeAsync, ולכן תשובותיו מתקדמות רק
/// כשמריצים גם זמן אמיתי וגם pump.
Future<bool> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  return done();
}

void main() {
  late Directory tempDir;
  late File pdf;
  late Uint8List pdfBytes;
  late PluginFileServer fileServer;
  late PluginRemoteFileCache remoteCache;
  late PluginFileDownloadService cacheDownloader;
  late PluginBridgeAdapter adapter;
  late PluginBridgeDependencies dependencies;
  PluginBridgeWindowDependencies? requestWindow;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    tempDir = Directory.systemTemp.createTempSync('plugin_print_file_screen_');
    pdf = File(p.join(tempDir.path, 'mine.pdf'));
    // pdfrxFlutterInitialize מבקש את תיקיית ה-cache.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
  });

  tearDownAll(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    cacheDownloader = PluginFileDownloadService(
      client: MockClient((_) async => http.Response.bytes(pdfBytes, 200)),
    );
    remoteCache = PluginRemoteFileCache(
      root: Directory(p.join(tempDir.path, 'cache')),
      maxFiles: 1,
    );
    fileServer = PluginFileServer(remoteFileCache: remoteCache);
    requestWindow = null;
    dependencies = PluginBridgeDependencies(
      historyBloc: _MockHistoryBloc(),
      tabsBloc: _MockTabsBloc(),
      navigationBloc: _MockNavigationBloc(),
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: _MockWorkspaceBloc(),
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({
            required title,
            required content,
            required subtitle,
          }) async => true,
      pickFile: ({allowedExtensions, title}) async => pdf.path,
      hasUserActivation: (pluginId, instanceId) async => true,
      // בכוונה בלי printPluginFile: הבדיקה היא על ברירת המחדל האמיתית.
    );
    adapter = PluginBridgeAdapter(
      _plugin(),
      dependencies: dependencies,
      windowDependenciesResolver: () => requestWindow ?? dependencies.window,
      pluginRepository: _Registry(),
      fileServer: fileServer,
      remoteFileCache: remoteCache,
    );
  });

  tearDown(() async {
    cacheDownloader.dispose();
    await fileServer.close();
  });

  Future<PluginRemoteFile> fetchCachedPdf(String name) => remoteCache.fetch(
    'test.plugin',
    Uri.parse('https://example.org/$name.pdf'),
    downloader: cacheDownloader,
    isAllowed: (_) async => true,
  );

  /// מרכיב חלון עם navigatorKey של האפליקציה, אופציונלית עם PdfViewer חי
  /// מאחורי הדיאלוג (כמו טאב PDF פתוח).
  Future<String> mountWindow(
    WidgetTester tester, {
    bool withLivePdfViewer = false,
    bool fromRemoteCache = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    final token = await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      pdfBytes = await _threePagePdf();
      pdf = File(p.join(tempDir.path, 'mine.pdf'));
      if (fromRemoteCache) {
        pdf = File((await fetchCachedPdf('first')).path);
      } else {
        await pdf.writeAsBytes(pdfBytes);
      }
      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
      return picked['token'] as String;
    });
    await tester.pumpWidget(
      RepositoryProvider<SettingsRepository>.value(
        value: _FakeSettingsRepository(),
        child: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => MediaQuery(
              // גופן הבדיקה רחב מהאמיתי וגולש מפאנל ההגדרות הצר.
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
            home: Scaffold(
              body: withLivePdfViewer
                  ? PdfViewer.data(pdfBytes, sourceName: 'bg.pdf')
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    return token!;
  }

  bool previewDone() =>
      find.byType(Image).evaluate().isNotEmpty &&
      find.byType(CircularProgressIndicator).evaluate().isEmpty;

  Future<void> closeWithEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final fromRemoteCache in [false, true]) {
    testWidgets(
      'print snapshot survives ${fromRemoteCache ? 'remote cache eviction' : 'local file replacement'}',
      (tester) async {
        final token = await mountWindow(
          tester,
          fromRemoteCache: fromRemoteCache,
        );
        final result = adapter.execute('ui', 'printFile', {'token': token});
        expect(
          await _pumpUntil(
            tester,
            () => find.byType(PrintingScreen).evaluate().isNotEmpty,
          ),
          isTrue,
        );
        expect(await _pumpUntil(tester, previewDone), isTrue);
        final screen = tester.widget<PrintingScreen>(
          find.byType(PrintingScreen),
        );
        await tester.runAsync(() async {
          if (fromRemoteCache) {
            await fetchCachedPdf('second');
            expect(await pdf.exists(), isFalse);
          } else {
            await pdf.writeAsString('replaced while print dialog is open');
          }
          final output = screen.createPdfOverride != null
              ? await screen.createPdfOverride!(PdfPageFormat.a4)
              : await File(screen.pdfFilePath!).readAsBytes();
          expect(output, orderedEquals(pdfBytes));
        });
        await closeWithEscape(tester);
        expect(await result, {'printed': false});
      },
    );
  }

  testWidgets(
    'printing uses the request window when another window is active',
    (tester) async {
      final a = AppWindowKeys(id: const AppWindowId('a'));
      final b = AppWindowKeys(id: const AppWindowId('b'));
      addTearDown(AppWindowKeys.resetForTest);
      AppWindowKeys.activate(b);
      final token = await mountWindow(tester);
      final initial = dependencies.window;
      requestWindow = (
        context: b.navigator.currentContext,
        viewId: tester.view.viewId,
        windowKeys: b,
        tabsBloc: initial.tabsBloc,
        historyBloc: initial.historyBloc,
        navigationBloc: initial.navigationBloc,
        workspaceBloc: initial.workspaceBloc,
        bookOpenCoordinator: initial.bookOpenCoordinator,
        customFoldersBloc: initial.customFoldersBloc,
        waitForLibraryRefresh: initial.waitForLibraryRefresh,
      );
      AppWindowKeys.activate(a);
      final result = adapter.execute('ui', 'printFile', {'token': token});
      expect(
        await _pumpUntil(
          tester,
          () => find.byType(PrintingScreen).evaluate().isNotEmpty,
        ),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byKey(b.navigator),
          matching: find.byType(PrintingScreen),
        ),
        findsOneWidget,
      );
      await closeWithEscape(tester);
      expect(await result, {'printed': false});
    },
  );

  testWidgets(
    'ui.printFile פותח את מסך ההדפסה של אוצריא על הקובץ; סגירה: printed:false',
    (tester) async {
      final token = await mountWindow(tester);

      final result = adapter.execute('ui', 'printFile', {
        'token': token,
        'jobName': 'הגהה',
      });
      expect(
        await _pumpUntil(
          tester,
          () => find.byType(PrintingScreen).evaluate().isNotEmpty,
        ),
        isTrue,
      );
      final screen = tester.widget<PrintingScreen>(find.byType(PrintingScreen));
      expect(screen.bookId, 'הגהה');
      expect(screen.pdfFilePath, isNull);
      expect(
        await screen.createPdfOverride!(PdfPageFormat.a4),
        orderedEquals(pdfBytes),
      );
      expect(find.textContaining('הדפסה — הגהה'), findsOneWidget);
      // התצוגה המקדימה מרונדרת מצילום הבתים שנשמר לפתיחת הדיאלוג.
      expect(await _pumpUntil(tester, previewDone), isTrue);

      await closeWithEscape(tester);

      expect(find.byType(PrintingScreen), findsNothing);
      expect(await result, {'printed': false});
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'התצוגה המקדימה מסתיימת גם כשיש PdfViewer חי מאחורי המסך',
    (tester) async {
      final token = await mountWindow(tester, withLivePdfViewer: true);
      expect(await _pumpUntil(tester, () => true), isTrue);

      final result = adapter.execute('ui', 'printFile', {'token': token});

      expect(await _pumpUntil(tester, previewDone), isTrue);
      await closeWithEscape(tester);
      expect(await result, {'printed': false});
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('בלי חלון: error.unavailable', (tester) async {
    final token = await mountWindow(tester);
    // מנקים את ה-navigator: אין חלון להציג בו את המסך.
    await tester.pumpWidget(const SizedBox());
    expect(navigatorKey.currentContext, isNull);

    // בדיקת הקובץ קוראת מהדיסק, ולכן רצה בזמן אמיתי ולא ב-FakeAsync.
    await tester.runAsync(
      () => expectLater(
        adapter.execute('ui', 'printFile', {'token': token}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.unavailable'),
          ),
        ),
      ),
    );
  });
}
