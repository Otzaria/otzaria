import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/view/plugin_background_host.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_headless_shell.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers/memory_settings_cache.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
  @override
  Future<InstalledPlugin?> getPlugin(String id) async => null;
  @override
  Future<bool?> getPermission(String id, String perm) async => false;
  @override
  Future<void> setPermission(String id, String perm, bool granted) async {}
  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];
}

class _FakeInstallerService extends PluginInstallerService {
  _FakeInstallerService() : super(repository: _FakeRepo());
  @override
  Future<void> cancelInstall(String path) async {}
  @override
  Future<void> finalizeInstall(
    String path,
    dynamic manifest, {
    required Map<String, bool> grantedPermissions,
    InstalledPlugin? expectedPlugin,
    Map<String, bool> expectedPermissions = const {},
  }) async {}
}

class _TestableBloc extends PluginSystemBloc {
  _TestableBloc()
    : super(
        repository: _FakeRepo(),
        installerService: _FakeInstallerService(),
      );
  void testEmit(PluginSystemState state) => emit(state);
}

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockLibraryBloc extends Mock implements LibraryBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockBookmarkBloc extends Mock implements BookmarkBloc {}

class _MockCustomFoldersBloc extends Mock implements CustomFoldersBloc {}

/// רושם בדיקות קיום של קבצים תחת [prefix]; כל קובץ אחר הוא קובץ אמיתי.
final class _EntryFileSpy extends IOOverrides {
  _EntryFileSpy(this.prefix);
  final String prefix;
  bool useRealFiles = false;
  Future<bool>? initialResult;
  final existsCalls = <String>[];
  final existsSyncCalls = <String>[];

  @override
  File createFile(String path) => path.replaceAll(r'\', '/').startsWith(prefix)
      ? _SpyFile(path, this, super.createFile(path))
      : super.createFile(path);
}

class _SpyFile implements File {
  _SpyFile(this.path, this._spy, this._file);
  @override
  final String path;
  final _EntryFileSpy _spy;
  final File _file;

  @override
  Future<bool> exists() {
    _spy.existsCalls.add(path.replaceAll(r'\', '/'));
    return _spy.useRealFiles
        ? _file.exists()
        : _spy.initialResult ?? Future.value(false);
  }

  @override
  bool existsSync() {
    _spy.existsSyncCalls.add(path);
    return _spy.useRealFiles && _file.existsSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BootPlatform extends InAppWebViewPlatform {
  final environment = _BootEnvironment();

  @override
  PlatformWebViewEnvironment createPlatformWebViewEnvironmentStatic() =>
      environment;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _BootWebView(params);
}

class _BootEnvironment extends PlatformWebViewEnvironment {
  _BootEnvironment()
    : super.implementation(const PlatformWebViewEnvironmentCreationParams());

  @override
  Future<PlatformWebViewEnvironment> create({
    WebViewEnvironmentSettings? settings,
  }) async => this;

  @override
  Future<void> dispose() async {}
}

class _BootWebView extends PlatformInAppWebViewWidget {
  _BootWebView(super.params) : super.implementation();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  void dispose() {}
}

class _BootController extends PlatformInAppWebViewController {
  _BootController(String id)
    : super.implementation(
        PlatformInAppWebViewControllerCreationParams(id: id),
      );

  final bootResults = <Completer<Object?>>[];
  Completer<void>? nextBootStarted;
  InAppWebViewSettings? nativeSettings;
  int settingsReads = 0;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (!source.contains('return window.Otzaria._boot(')) return null;
    final result = Completer<Object?>();
    bootResults.add(result);
    nextBootStarted?.complete();
    nextBootStarted = null;
    return result.future;
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required Function callback,
  }) {}

  @override
  Future<InAppWebViewSettings?> getSettings() async {
    settingsReads++;
    // Widget tests מדמים Android גם ב-Linux; העותק שומר enums של WebKit.
    return nativeSettings == null
        ? null
        : InAppWebViewSettings.fromMap(
            nativeSettings!.toMap(enumMethod: EnumMethod.value),
            enumMethod: EnumMethod.value,
          );
  }

  @override
  Future<void> setSettings({required InAppWebViewSettings settings}) async {
    nativeSettings = InAppWebViewSettings.fromMap(
      settings.toMap(enumMethod: EnumMethod.value),
      enumMethod: EnumMethod.value,
    )!;
  }

  @override
  dynamic getViewId() => params.id;
}

// ── helpers ───────────────────────────────────────────────────────────────────

InstalledPlugin _plugin({
  String id = 'test.plugin',
  String version = '1.0.0',
  String installPath = '/install/path',
  String entrypointPath = 'index.html',
  String? devRootPath,
  bool headless = false,
  List<String> permissions = const [],
  PluginStartupContributions? startup,
}) => InstalledPlugin(
  pluginId: id,
  name: 'Test Plugin',
  version: version,
  installPath: installPath,
  entrypointPath: entrypointPath,
  enabled: true,
  pinned: false,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: 'Test Plugin',
    version: version,
    description: '',
    author: '',
    homepage: '',
    entrypoint: entrypointPath,
    headless: headless,
    minAppVersion: '0.0.0',
    sdkVersion: '1.0.0',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Tab',
    toolTabOrder: 0,
    defaultPinned: false,
    publishedDataTypes: const [],
    startup: startup,
  ),
  installedAt: DateTime(2025),
  updatedAt: DateTime(2025),
  devRootPath: devRootPath,
);

/// מחשבת את ה-ValueKey שנבנה בפועל ב-PluginBackgroundHost עבור תוסף נתון.
/// חייבת להיות זהה לנוסחה ב-plugin_background_host.dart.
String backgroundKey(InstalledPlugin p, {int? generation}) =>
    'background_${p.pluginId}'
    '_${p.version}'
    '_${p.installPath}'
    '_${p.entrypointPath}'
    '_${p.backgroundEntrypointPath}'
    '_${p.devRootPath ?? ""}'
    '_$generation';

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _TestableBloc bloc;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    bloc = _TestableBloc();
  });

  tearDown(() => bloc.close());

  for (final replaceCallbacks in [false, true]) {
    testWidgets(
      replaceCallbacks
          ? 'dispose של host ישן משאיר את callbacks המחליף'
          : 'dispose של host מנתק את callbacks שהוא רשם',
      (tester) async {
        final lazy = PluginLazyActivationService.instance;
        bloc.testEmit(const PluginSystemLoaded([]));
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<PluginSystemBloc>.value(
              value: bloc,
              child: const Scaffold(body: PluginBackgroundHost()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(lazy.backgroundActivator, isNotNull);
        expect(lazy.backgroundDeactivator, isNotNull);
        Future<void> replacementActivator(String _) async {}
        void replacementDeactivator(String _) {}
        if (replaceCallbacks) {
          lazy.backgroundActivator = replacementActivator;
          lazy.backgroundDeactivator = replacementDeactivator;
        }
        try {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          expect(
            lazy.backgroundActivator,
            replaceCallbacks ? same(replacementActivator) : isNull,
          );
          expect(
            lazy.backgroundDeactivator,
            replaceCallbacks ? same(replacementDeactivator) : isNull,
          );
        } finally {
          lazy.backgroundActivator = null;
          lazy.backgroundDeactivator = null;
        }
      },
    );
  }

  // ── P1a: initState מסנכרן עם state קיים בעת mount ─────────────────────────

  testWidgets(
    'P1a — נטען ללא קריסה כשהבלוק כבר ב-PluginSystemLoaded לפני mount',
    (tester) async {
      // state מוגדר לפני שה-widget נבנה — BlocListener לבד לא יפעיל sync
      bloc.testEmit(const PluginSystemLoaded([]));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PluginSystemBloc>.value(
            value: bloc,
            child: const Scaffold(body: PluginBackgroundHost()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PluginBackgroundHost), findsOneWidget);
    },
  );

  testWidgets(
    'P1a — נטען ללא קריסה כשהבלוק ב-PluginSystemLoaded עם תוספים (ללא הרשאת startup)',
    (tester) async {
      final plugins = [_plugin(id: 'p1'), _plugin(id: 'p2')];
      bloc.testEmit(PluginSystemLoaded(plugins));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PluginSystemBloc>.value(
            value: bloc,
            child: const Scaffold(body: PluginBackgroundHost()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PluginBackgroundHost), findsOneWidget);
    },
  );

  testWidgets('BlocListener — מסנכרן כשמתקבל PluginSystemLoaded לאחר mount', (
    tester,
  ) async {
    // הבלוק מתחיל ב-initial state
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<PluginSystemBloc>.value(
          value: bloc,
          child: const Scaffold(body: PluginBackgroundHost()),
        ),
      ),
    );
    await tester.pump();

    // state משתנה לאחר mount — BlocListener מופעל
    bloc.testEmit(PluginSystemLoaded([_plugin()]));
    await tester.pumpAndSettle();

    expect(find.byType(PluginBackgroundHost), findsOneWidget);
  });

  // ── בידוד פוקוס ────────────────────────────────────────────────────────────

  testWidgets('ה-host עוטף את תוספי הרקע ב-ExcludeFocus', (tester) async {
    // ה-WebView של flutter_inappwebview_windows עוטף את עצמו ב-Focus עם
    // autofocus:true. Offstage לבדו אינו מונע פוקוס, ולכן מופע רקע שנטען
    // כשאין פוקוס באפליקציה היה חוטף אותו לחלון בלתי-נראה — ומאז שהחבילה
    // מגשרת פוקוס לנייטיב (MoveFocus) ההקלדה בתוסף הגלוי נשברה.
    bloc.testEmit(const PluginSystemLoaded([]));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<PluginSystemBloc>.value(
          value: bloc,
          child: const Scaffold(body: PluginBackgroundHost()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final excludeFocus = tester.widget<ExcludeFocus>(
      find.descendant(
        of: find.byType(PluginBackgroundHost),
        matching: find.byType(ExcludeFocus),
      ),
    );
    expect(excludeFocus.excluding, isTrue);

    // ה-ExcludeFocus חייב לעטוף את ה-Offstage, לא להיעטף בו — אחרת הוא לא
    // יחול על ה-WebViews שנבנים בתוכו.
    expect(
      find.descendant(
        of: find.byType(ExcludeFocus),
        matching: find.byType(Offstage),
      ),
      findsWidgets,
    );
  });

  // ── P2: ייחודיות ValueKey ──────────────────────────────────────────────────

  group('ValueKey — backgroundKey מזהה שינויים בכל שדות הזהות', () {
    final base = _plugin();

    test('key יציב לתוסף זהה', () {
      expect(backgroundKey(base), equals(backgroundKey(base)));
    });

    test('key משתנה כשגרסה משתנה', () {
      expect(
        backgroundKey(base),
        isNot(equals(backgroundKey(base.copyWith(version: '2.0.0')))),
      );
    });

    test('key משתנה כש-installPath משתנה', () {
      expect(
        backgroundKey(base),
        isNot(equals(backgroundKey(base.copyWith(installPath: '/other/path')))),
      );
    });

    test('key משתנה כש-entrypointPath משתנה', () {
      expect(
        backgroundKey(base),
        isNot(equals(backgroundKey(base.copyWith(entrypointPath: 'app.html')))),
      );
    });

    test('key משתנה כש-devRootPath עובר מ-null לערך', () {
      final withDev = base.copyWith(devRootPath: '/dev/root');
      expect(backgroundKey(base), isNot(equals(backgroundKey(withDev))));
    });

    test('key משתנה כש-devRootPath משנה ערך', () {
      final v1 = base.copyWith(devRootPath: '/dev/v1');
      final v2 = base.copyWith(devRootPath: '/dev/v2');
      expect(backgroundKey(v1), isNot(equals(backgroundKey(v2))));
    });

    test('key שונה בין שני תוספים שונים', () {
      final other = _plugin(id: 'other.plugin');
      expect(backgroundKey(base), isNot(equals(backgroundKey(other))));
    });

    test('key משתנה כש-backgroundEntrypoint משתנה (ללא שינוי גרסה/נתיב)', () {
      PluginManifest manifestWithBackground(String background) =>
          PluginManifest.fromJson({
            'schemaVersion': 1,
            'id': base.pluginId,
            'name': 'Test Plugin',
            'version': base.version,
            'entrypoint': base.entrypointPath,
            'contributes': {
              'background': {'entrypoint': background},
            },
          });

      final before = base.copyWith(
        manifest: manifestWithBackground('background.html'),
      );
      final after = base.copyWith(
        manifest: manifestWithBackground('worker.html'),
      );
      expect(backgroundKey(before), isNot(equals(backgroundKey(after))));
    });

    test('שינוי ב-devRootPath בלבד (ללא bump גרסה) מייצר key שונה', () {
      // מכסה את תרחיש ה-dev-plugin שציין ה-reviewer: שינוי נתיב ללא גרסה
      final before = base.copyWith(devRootPath: '/dev/old');
      final after = base.copyWith(devRootPath: '/dev/new');
      expect(backgroundKey(before), isNot(equals(backgroundKey(after))));
    });
  });

  // ── אתחול סביבת WebView2 — מתי הוא נקרא ────────────────────────────────────
  // מופע רקע קם רק לפי דרישה (contributes.startup), ולכן בעליית האפליקציה
  // ה-host לעולם אינו מאתחל את הסביבה: האתחול מצמיח 5-7 תהליכי Edge (~100MB).
  // ההרשאה נשמרת ב-SQLite אמיתי, ולכן הקבוצה מרימה Settings + DB זמניים.

  group('אתחול סביבת WebView2', () {
    late Directory tempDir;
    late int initializeCalls;

    setUp(() async {
      PackageInfo.setMockInitialValues(
        appName: 'Otzaria',
        packageName: 'org.otzaria',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      tempDir = await Directory.systemTemp.createTemp('otzaria-bg-host-');
      await Settings.init(cacheProvider: MemorySettingsCache());
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      await PluginSystemDatabase.instance.close();
      // פתיחת ה-DB כאן, מחוץ ל-FakeAsync של testWidgets: הפתיחה הראשונה עושה
      // IO אמיתי שלא מתקדם תחת השעון המזויף והבדיקה הייתה נתקעת.
      await PluginRegistryRepository().getPermission('warmup', 'warmup');
      await PluginFileServer.instance.ensurePort();

      initializeCalls = 0;
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(true);
      WebViewEnvironmentHolder.debugOverrideInitialize(() async {
        initializeCalls++;
      });
    });

    tearDown(() async {
      await PluginFileServer.instance.close();
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
      WebViewEnvironmentHolder.debugOverrideInitialize(null);
      await PluginSystemDatabase.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> pumpHost(WidgetTester tester) async {
      // ה-runner קורא בבלוקים האלה רק בבניית ה-bridge.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<HistoryBloc>.value(value: _MockHistoryBloc()),
            Provider<TabsBloc>.value(value: _MockTabsBloc()),
            Provider<NavigationBloc>.value(value: _MockNavigationBloc()),
            Provider<LibraryBloc>.value(value: _MockLibraryBloc()),
            Provider<CalendarCubit>.value(value: _MockCalendarCubit()),
            Provider<WorkspaceBloc>.value(value: _MockWorkspaceBloc()),
            Provider<BookmarkBloc>.value(value: _MockBookmarkBloc()),
            Provider<CustomFoldersBloc>.value(value: _MockCustomFoldersBloc()),
          ],
          child: MaterialApp(
            home: BlocProvider<PluginSystemBloc>.value(
              value: bloc,
              child: const Scaffold(body: PluginBackgroundHost()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('אין תוספים כלל — הסביבה לא מאותחלת', (tester) async {
      bloc.testEmit(const PluginSystemLoaded([]));
      await pumpHost(tester);

      expect(initializeCalls, 0);
    });

    testWidgets('תוסף ללא הצהרת run_on_startup — הסביבה לא מאותחלת', (
      tester,
    ) async {
      bloc.testEmit(PluginSystemLoaded([_plugin()]));
      await pumpHost(tester);

      expect(initializeCalls, 0);
    });

    testWidgets('הצהרה על run_on_startup בלי הרשאה מוענקת — לא מאותחלת', (
      tester,
    ) async {
      bloc.testEmit(
        PluginSystemLoaded([
          _plugin(permissions: const [pluginRunOnStartupPermission]),
        ]),
      );
      await pumpHost(tester);

      expect(initializeCalls, 0);
    });

    testWidgets('תוסף דקלרטיבי לא מאתחל WebView גם כשהרקע מאושר', (
      tester,
    ) async {
      final plugin = _plugin(
        permissions: const [pluginRunOnStartupPermission],
        startup: const PluginStartupContributions(
          activationEvents: ['app.startup'],
        ),
      );
      await PluginRegistryRepository().setPermission(
        plugin.pluginId,
        pluginRunOnStartupPermission,
        true,
      );

      bloc.testEmit(PluginSystemLoaded([plugin]));
      await pumpHost(tester);

      expect(initializeCalls, 0);
      expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
    });

    testWidgets(
      'run_on_startup מאושרת בלי contributes.startup — אין מופע רקע',
      (
        tester,
      ) async {
        final plugin = _plugin(
          permissions: const [pluginRunOnStartupPermission],
        );
        await PluginRegistryRepository().setPermission(
          plugin.pluginId,
          pluginRunOnStartupPermission,
          true,
        );

        bloc.testEmit(PluginSystemLoaded([plugin]));
        await pumpHost(tester);

        expect(initializeCalls, 0);
        expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
      },
    );
    testWidgets(
      'הערה עצלה מאתחלת את הסביבה בעצמה — כשל באתחול לא בונה WebView',
      (
        tester,
      ) async {
        WebViewEnvironmentHolder.debugOverrideInitialize(() async {
          initializeCalls++;
          throw StateError('init failed');
        });
        final plugin = _plugin(
          permissions: const [pluginRunOnStartupPermission],
          startup: const PluginStartupContributions(
            activationEvents: ['notes.changed'],
          ),
        );
        await PluginRegistryRepository().setPermission(
          plugin.pluginId,
          pluginRunOnStartupPermission,
          true,
        );
        final lazy = PluginLazyActivationService.instance;
        lazy.syncPlugin(
          plugin.pluginId,
          broadcastTopics: const {'notes.changed'},
          scheduleStartup: false,
        );
        addTearDown(() => lazy.removePlugin(plugin.pluginId));

        bloc.testEmit(PluginSystemLoaded([plugin]));
        await pumpHost(tester);
        expect(initializeCalls, 0);

        lazy.onBroadcast(
          'notes.changed',
          const {},
          hasUsableInstance: (_) => false,
        );
        await tester.pumpAndSettle();

        // initializeCalls==1 מוכיח שהמסלול העצל באמת הגיע לאתחול הסביבה —
        // בלעדיו הבדיקות ה"שליליות" בקבוצה היו עוברות סתם כי הקוד נתקע.
        expect(initializeCalls, 1);
        expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
      },
    );

    testWidgets(
      'מופע רקע בודק את קובץ הכניסה אסינכרונית — בלי existsSync ב-build (#3380)',
      (tester) async {
        final io = _EntryFileSpy('/install/');
        final plugin = _plugin(
          permissions: const [pluginRunOnStartupPermission],
          startup: const PluginStartupContributions(
            activationEvents: ['notes.changed'],
          ),
        );
        await PluginRegistryRepository().setPermission(
          plugin.pluginId,
          pluginRunOnStartupPermission,
          true,
        );
        final lazy = PluginLazyActivationService.instance;
        lazy.syncPlugin(
          plugin.pluginId,
          broadcastTopics: const {'notes.changed'},
          scheduleStartup: false,
        );
        addTearDown(() => lazy.removePlugin(plugin.pluginId));

        await IOOverrides.runWithIOOverrides(() async {
          bloc.testEmit(PluginSystemLoaded([plugin]));
          await pumpHost(tester);
          lazy.onBroadcast(
            'notes.changed',
            const {},
            hasUsableInstance: (_) => false,
          );
          await tester.pumpAndSettle();
          expect(initializeCalls, 1);
          expect(io.existsCalls, hasLength(1));

          // נתיב חדש → runner חדש שבודק את הנתיב החדש.
          bloc.testEmit(
            PluginSystemLoaded([plugin.copyWith(installPath: '/install/v2')]),
          );
          await tester.pumpAndSettle();
        }, io);

        expect(io.existsSyncCalls, isEmpty);
        expect(io.existsCalls, hasLength(2));
        expect(io.existsCalls.last, startsWith('/install/v2'));
        // קובץ כניסה חסר — עדיין לא נבנה WebView.
        expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
      },
    );

    testWidgets(
      'crash and retry in the same frame creates a new background runner',
      (tester) async {
        final io = _EntryFileSpy('/install/');
        final plugin = _plugin(
          permissions: const [pluginRunOnStartupPermission],
        );
        await tester.runAsync(
          () => PluginRegistryRepository().setPermission(
            plugin.pluginId,
            pluginRunOnStartupPermission,
            true,
          ),
        );
        final lazy = PluginLazyActivationService.instance;
        lazy.syncPlugin(
          plugin.pluginId,
          broadcastTopics: const {},
          scheduleStartup: false,
        );
        try {
          await IOOverrides.runWithIOOverrides(() async {
            bloc.testEmit(PluginSystemLoaded([plugin]));
            await pumpHost(tester);
            lazy.queueTargetedEvent(plugin.pluginId, 'click', {'n': 1});
            await tester.pumpAndSettle();
            expect(io.existsCalls, hasLength(1));
            final runnerFinder = find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_BackgroundPluginRunner',
              skipOffstage: false,
            );
            final oldRunner = tester.state(runnerFinder);
            lazy.onBackgroundProcessGone(
              plugin.pluginId,
              generation: lazy.activationGeneration(plugin.pluginId),
            );
            lazy.queueTargetedEvent(plugin.pluginId, 'click', {'n': 2});
            // Microtasks finish the new activation before Flutter rebuilds the old child.
            await tester.idle();
            await tester.pumpAndSettle();
            expect(io.existsCalls, hasLength(2));
            expect(oldRunner.mounted, isFalse);
            expect(identical(tester.state(runnerFinder), oldRunner), isFalse);
            expect(lazy.isBootPending(plugin.pluginId), isTrue);
          }, io);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          lazy.removePlugin(plugin.pluginId);
        }
      },
    );

    for (final initiallyCollecting in [false, true]) {
      testWidgets(
        'background keeps native policy current when log-only starts ${initiallyCollecting ? "before" : "after"} creation',
        (tester) async {
          final previousPlatform = InAppWebViewPlatform.instance;
          InAppWebViewPlatform.instance = _BootPlatform();
          final diagnostics = DeveloperDiagnostics.instance..resetForTesting();
          diagnostics.outputPath = '${tempDir.path}/diagnostics.jsonl';
          PluginWebViewHost.debugVerboseConsoleOverride = false;
          final plugin = _plugin(
            permissions: const [pluginRunOnStartupPermission],
          );
          final io = _EntryFileSpy('/install/')
            ..initialResult = Future.value(true);
          final lazy = PluginLazyActivationService.instance;
          final native = _BootController('console-policy');
          lazy.syncPlugin(
            plugin.pluginId,
            broadcastTopics: const {},
            scheduleStartup: false,
          );
          await tester.runAsync(
            () => PluginRegistryRepository().setPermission(
              plugin.pluginId,
              pluginRunOnStartupPermission,
              true,
            ),
          );
          try {
            if (Platform.isWindows) {
              WebViewEnvironmentHolder.debugOverrideInitialize(null);
              await tester.runAsync(
                () => WebViewEnvironmentHolder.initialize(
                  dataFolderChecked: true,
                ),
              );
            }
            if (initiallyCollecting) {
              await tester.runAsync(() async {
                diagnostics.initFromLaunch(const [
                  '--dev-diagnostics=log',
                ], environment: const {});
                await diagnostics.snapshot();
              });
            }
            await IOOverrides.runWithIOOverrides(() async {
              bloc.testEmit(PluginSystemLoaded([plugin]));
              await pumpHost(tester);
              lazy.queueTargetedEvent(plugin.pluginId, 'click', {'n': 1});
              await tester.pumpAndSettle();
              await tester.runAsync(PluginFileServer.instance.ensurePort);
              await tester.pumpAndSettle();
              final params = tester
                  .widget<InAppWebView>(
                    find.byType(InAppWebView, skipOffstage: false),
                  )
                  .platform
                  .params;
              final initial = params.initialSettings!;
              expect(
                initial.consoleMessageLevels,
                initiallyCollecting
                    ? isNull
                    : [ConsoleMessageLevel.WARNING, ConsoleMessageLevel.ERROR],
              );
              expect(
                initial.contentBlockers,
                pluginNetworkUsesContentBlockers ? isNotEmpty : isEmpty,
              );
              native.nativeSettings = initial;
              params.onWebViewCreated!(
                InAppWebViewController.fromPlatform(platform: native),
              );
              await tester.pump();
              if (!initiallyCollecting) {
                await tester.runAsync(() async {
                  diagnostics.initFromLaunch(const [
                    '--dev-diagnostics=log',
                  ], environment: const {});
                  await diagnostics.snapshot();
                });
                await tester.pump();
              }
              expect(diagnostics.panelVisible.value, isFalse);
              expect(native.nativeSettings!.consoleMessageLevels, isNull);
              await tester.runAsync(() async {
                diagnostics.toggle();
                await diagnostics.snapshot();
                final records = (await File(
                  diagnostics.outputPath,
                ).readAsLines()).map((line) => jsonDecode(line) as Map);
                final backend = records.singleWhere(
                  (record) => record['type'] == 'webview_backend',
                );
                expect(
                  backend['event'],
                  initiallyCollecting ? 'attached' : 'present',
                );
                expect(backend['pluginId'], plugin.pluginId);
                expect(backend['instanceId'], PluginInstanceIds.background);
                expect(backend['backend']['verified'], isFalse);
                expect(backend['backend']['observed'], isNull);
                expect(
                  backend['backend']['availability'],
                  Platform.isWindows ? 'unavailable' : 'unsupported',
                );
              });
              await tester.pump();
              expect(native.nativeSettings!.consoleMessageLevels, [
                ConsoleMessageLevel.WARNING,
                ConsoleMessageLevel.ERROR,
              ]);
              expect(
                native.nativeSettings!.contentBlockers!.map(
                  (rule) => rule.toMap(),
                ),
                initial.contentBlockers!.map((rule) => rule.toMap()),
              );
              expect(
                native.nativeSettings!.allowUniversalAccessFromFileURLs,
                isFalse,
              );
              await tester.pumpWidget(const SizedBox());
              await tester.pumpAndSettle();
              final readsAfterDisposal = native.settingsReads;
              await tester.runAsync(() async {
                diagnostics.initFromLaunch(const [
                  '--dev-diagnostics=log',
                ], environment: const {});
                await diagnostics.snapshot();
              });
              await tester.pump();
              expect(native.settingsReads, readsAfterDisposal);
              await tester.runAsync(() async {
                final records = (await File(
                  diagnostics.outputPath,
                ).readAsLines()).map((line) => jsonDecode(line) as Map);
                expect(
                  records.where((r) => r['type'] == 'webview_backend'),
                  hasLength(1),
                  reason:
                      'A disposed Offstage host cannot replay its old observation.',
                );
              });
            }, io);
          } finally {
            diagnostics.resetForTesting();
            PluginWebViewHost.debugVerboseConsoleOverride = null;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            lazy.removePlugin(plugin.pluginId);
            if (Platform.isWindows) {
              await tester.runAsync(
                WebViewEnvironmentHolder.disposeForAppRestart,
              );
            }
            if (previousPlatform != null) {
              InAppWebViewPlatform.instance = previousPlatform;
            }
          }
        },
      );
    }

    for (final crash in [false, true]) {
      testWidgets(
        'late background boot after ${crash ? "crash and retry" : "navigation"} cannot change options or flush events',
        (tester) async {
          final previousPlatform = InAppWebViewPlatform.instance;
          final platform = _BootPlatform();
          InAppWebViewPlatform.instance = platform;
          final plugin = _plugin(
            permissions: const [pluginRunOnStartupPermission],
          );
          final io = _EntryFileSpy('/install/')
            ..initialResult = Future.value(true);
          final lazy = PluginLazyActivationService.instance;
          final dispatcher = PluginRuntimeDispatcher.instance;
          final delivered = <int>[];
          final nativeControllers = <_BootController>[];
          final loads = <Future<void>>[];
          lazy.deliverOverride = (_, _, payload) async =>
              delivered.add(payload['n'] as int);
          lazy.syncPlugin(
            plugin.pluginId,
            broadcastTopics: const {},
            scheduleStartup: false,
          );
          await tester.runAsync(
            () => PluginRegistryRepository().setPermission(
              plugin.pluginId,
              pluginRunOnStartupPermission,
              true,
            ),
          );

          Future<void> startLoad(
            PlatformInAppWebViewWidgetCreationParams params,
            _BootController native,
            InAppWebViewController controller,
          ) async {
            await tester.runAsync(() async {
              final started = Completer<void>();
              native.nextBootStarted = started;
              final done =
                  Function.apply(params.onLoadStop!, [
                        controller,
                        WebUri('file:///install/path/index.html'),
                      ])
                      as Future<void>;
              loads.add(done);
              await started.future.timeout(const Duration(seconds: 5));
            });
          }

          Future<void> pumpWebView() async {
            await tester.pumpAndSettle();
            // ensurePort awaits a cached Future created by real-async setUp.
            await tester.runAsync(PluginFileServer.instance.ensurePort);
            await tester.pumpAndSettle();
          }

          try {
            if (Platform.isWindows) {
              WebViewEnvironmentHolder.debugOverrideInitialize(null);
              await tester.runAsync(
                () => WebViewEnvironmentHolder.initialize(
                  dataFolderChecked: true,
                ),
              );
            }
            await IOOverrides.runWithIOOverrides(() async {
              bloc.testEmit(PluginSystemLoaded([plugin]));
              await pumpHost(tester);
              lazy.queueTargetedEvent(plugin.pluginId, 'click', {'n': 1});
              await pumpWebView();
              final webViewFinder = find.byType(
                InAppWebView,
                skipOffstage: false,
              );
              expect(webViewFinder, findsOneWidget);
              final oldParams = tester
                  .widget<InAppWebView>(webViewFinder)
                  .platform
                  .params;
              final oldNative = _BootController('old');
              nativeControllers.add(oldNative);
              final oldController = InAppWebViewController.fromPlatform(
                platform: oldNative,
              );
              oldParams.onWebViewCreated!(oldController);
              expect(
                dispatcher.ownsController(
                  plugin.pluginId,
                  oldController,
                  instanceId: PluginInstanceIds.background,
                ),
                isTrue,
              );
              await startLoad(oldParams, oldNative, oldController);

              var currentParams = oldParams;
              var currentNative = oldNative;
              var currentController = oldController;
              if (crash) {
                oldParams.onRenderProcessGone!(
                  oldController,
                  RenderProcessGoneDetail(didCrash: true),
                );
                lazy.queueTargetedEvent(plugin.pluginId, 'click', {'n': 2});
                await tester.idle();
                await pumpWebView();
                currentParams = tester
                    .widget<InAppWebView>(webViewFinder)
                    .platform
                    .params;
                currentNative = _BootController('replacement');
                nativeControllers.add(currentNative);
                currentController = InAppWebViewController.fromPlatform(
                  platform: currentNative,
                );
                currentParams.onWebViewCreated!(currentController);
              } else {
                oldParams.onLoadStart?.call(
                  oldController,
                  WebUri('file:///install/path/next.html'),
                );
                lazy.queueTargetedEvent(plugin.pluginId, 'click', {'n': 2});
              }

              oldNative.bootResults.single.complete([
                {'topic': 'theme.changed', 'rawDivineNames': true},
              ]);
              await tester.runAsync(() => loads.first);
              await tester.pump();
              expect(
                dispatcher.rawDivineNamesTopicsOf(
                  plugin.pluginId,
                  instanceId: PluginInstanceIds.background,
                ),
                isEmpty,
              );
              expect(lazy.isBootPending(plugin.pluginId), isTrue);
              expect(delivered, isEmpty);

              await startLoad(currentParams, currentNative, currentController);
              currentNative.bootResults.last.complete([
                {'topic': 'theme.changed', 'rawDivineNames': true},
              ]);
              await tester.runAsync(() => loads.last);
              await tester.pump();
              expect(
                dispatcher.rawDivineNamesTopicsOf(
                  plugin.pluginId,
                  instanceId: PluginInstanceIds.background,
                ),
                {'theme.changed'},
              );
              expect(lazy.isBootPending(plugin.pluginId), isFalse);
              expect(delivered, crash ? [2] : [1, 2]);
            }, io);
          } finally {
            for (final controller in nativeControllers) {
              for (final result in controller.bootResults) {
                if (!result.isCompleted) result.complete(null);
              }
            }
            await tester.runAsync(() => Future.wait(loads));
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            lazy.deliverOverride = null;
            lazy.removePlugin(plugin.pluginId);
            if (Platform.isWindows) {
              await tester.runAsync(
                WebViewEnvironmentHolder.disposeForAppRestart,
              );
            }
            if (previousPlatform != null) {
              InAppWebViewPlatform.instance = previousPlatform;
            }
          }
        },
      );
    }

    for (final (headless, lateInitial) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      testWidgets(
        'קובץ ${headless ? "JS" : "HTML"} שנוצר אחרי ההפעלה נטען ברענון פיתוח'
        '${lateInitial ? " גם כשהבדיקה הראשונה מסתיימת באיחור" : ""}',
        (tester) async {
          final previousPlatform = InAppWebViewPlatform.instance;
          WindowsInAppWebViewPlatform.registerWith();
          const manager = MethodChannel(
            'com.pichillilorenzo/flutter_inappwebview_manager',
          );
          const view = MethodChannel(
            'com.pichillilorenzo/custom_platform_view_3',
          );
          const events = EventChannel(
            'com.pichillilorenzo/custom_platform_view_3_events',
          );
          const environmentManager = MethodChannel(
            'com.pichillilorenzo/flutter_webview_environment',
          );
          MethodChannel? environmentChannel;
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(manager, (call) async {
            return call.method == 'createInAppWebView' ? 3 : null;
          });
          messenger.setMockMethodCallHandler(view, (call) async => null);
          messenger.setMockMethodCallHandler(environmentManager, (call) async {
            if (call.method == 'create') {
              environmentChannel = MethodChannel(
                'com.pichillilorenzo/flutter_webview_environment_${call.arguments["id"]}',
              );
              messenger.setMockMethodCallHandler(
                environmentChannel!,
                (call) async => null,
              );
            }
            return null;
          });
          messenger.setMockStreamHandler(
            events,
            MockStreamHandler.inline(onListen: (arguments, events) {}),
          );
          addTearDown(() async {
            await WebViewEnvironmentHolder.disposeForAppRestart();
            messenger.setMockMethodCallHandler(environmentManager, null);
            if (environmentChannel case final channel?) {
              messenger.setMockMethodCallHandler(channel, null);
            }
            messenger.setMockMethodCallHandler(manager, null);
            messenger.setMockMethodCallHandler(view, null);
            messenger.setMockStreamHandler(events, null);
            if (previousPlatform case final platform?) {
              InAppWebViewPlatform.instance = platform;
            }
          });
          if (Platform.isWindows) {
            WebViewEnvironmentHolder.debugOverrideInitialize(null);
            await tester.runAsync(
              () =>
                  WebViewEnvironmentHolder.initialize(dataFolderChecked: true),
            );
          }

          final entrypoint = headless ? 'main.js' : 'index.html';
          final entryFile = File('${tempDir.path}/$entrypoint');
          expect(await tester.runAsync(entryFile.exists), isFalse);
          final plugin = _plugin(
            devRootPath: tempDir.path,
            entrypointPath: entrypoint,
            headless: headless,
            permissions: const [pluginRunOnStartupPermission],
            startup: const PluginStartupContributions(
              activationEvents: ['notes.changed'],
            ),
          ).copyWith(sourceType: 'development');
          await PluginRegistryRepository().setPermission(
            plugin.pluginId,
            pluginRunOnStartupPermission,
            true,
          );
          final lazy = PluginLazyActivationService.instance;
          lazy.syncPlugin(
            plugin.pluginId,
            broadcastTopics: const {'notes.changed'},
            scheduleStartup: false,
          );
          addTearDown(() => lazy.removePlugin(plugin.pluginId));
          final io = _EntryFileSpy(tempDir.path);
          final firstCheck = Completer<bool>();
          if (lateInitial) io.initialResult = firstCheck.future;
          await IOOverrides.runWithIOOverrides(() async {
            bloc.testEmit(PluginSystemLoaded([plugin]));
            await pumpHost(tester);
            lazy.onBroadcast(
              'notes.changed',
              const {},
              hasUsableInstance: (_) => false,
            );
            await tester.pumpAndSettle();
            expect(
              find.byType(InAppWebView, skipOffstage: false),
              findsNothing,
            );

            await tester.runAsync(
              () => entryFile.writeAsString(
                headless ? 'window.ready = true;' : '<html></html>',
              ),
            );
            io.useRealFiles = true;
            await tester.runAsync(
              () => PluginRuntimeDispatcher.instance.reloadPlugin(
                plugin.pluginId,
              ),
            );
            tester.element(find.byType(PluginBackgroundHost)).markNeedsBuild();
            await tester.pumpAndSettle();

            expect(
              find.byType(InAppWebView, skipOffstage: false),
              findsOneWidget,
            );
            final webview = tester.widget<InAppWebView>(
              find.byType(InAppWebView, skipOffstage: false),
            );
            expect(
              webview.platform.params.initialUrlRequest!.url!.path,
              endsWith(headless ? pluginHeadlessShellFileName : entrypoint),
            );
            if (lateInitial) {
              firstCheck.complete(false);
              await tester.pumpAndSettle();
              expect(
                find.byType(InAppWebView, skipOffstage: false),
                findsOneWidget,
              );
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          }, io);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets('WebView2 Runtime חסר — הערה עצלה נכשלת בלי לאתחל', (
      tester,
    ) async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      final plugin = _plugin(
        permissions: const [pluginRunOnStartupPermission],
        startup: const PluginStartupContributions(
          activationEvents: ['notes.changed'],
        ),
      );
      await PluginRegistryRepository().setPermission(
        plugin.pluginId,
        pluginRunOnStartupPermission,
        true,
      );
      final lazy = PluginLazyActivationService.instance;
      lazy.syncPlugin(
        plugin.pluginId,
        broadcastTopics: const {'notes.changed'},
        scheduleStartup: false,
      );
      addTearDown(() => lazy.removePlugin(plugin.pluginId));

      bloc.testEmit(PluginSystemLoaded([plugin]));
      await pumpHost(tester);
      lazy.onBroadcast(
        'notes.changed',
        const {},
        hasUsableInstance: (_) => false,
      );
      await tester.pumpAndSettle();

      expect(initializeCalls, 0);
      expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
    });
  });
}
