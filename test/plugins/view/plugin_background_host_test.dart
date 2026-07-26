import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/view/plugin_background_host.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
    required bool allowOrderBeforeBuiltInsGranted,
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

// ── helpers ───────────────────────────────────────────────────────────────────

InstalledPlugin _plugin({
  String id = 'test.plugin',
  String version = '1.0.0',
  String installPath = '/install/path',
  String entrypointPath = 'index.html',
  String? devRootPath,
  List<String> permissions = const [],
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
    minAppVersion: '0.0.0',
    sdkVersion: '1.0.0',
    // ברירת מחדל: ללא app.run_on_startup, מונע קריאות SQLite
    // ב-_syncBackgroundPlugins
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Tab',
    toolTabOrder: 0,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2025),
  updatedAt: DateTime(2025),
  devRootPath: devRootPath,
);

/// מחשבת את ה-ValueKey שנבנה בפועל ב-PluginBackgroundHost עבור תוסף נתון.
/// חייבת להיות זהה לנוסחה ב-plugin_background_host.dart.
String backgroundKey(InstalledPlugin p) =>
    'background_${p.pluginId}'
    '_${p.version}'
    '_${p.installPath}'
    '_${p.entrypointPath}'
    '_${p.backgroundEntrypointPath}'
    '_${p.devRootPath ?? ""}';

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _TestableBloc bloc;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    bloc = _TestableBloc();
  });

  tearDown(() => bloc.close());

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

  // ── WebView2 Runtime gate ──────────────────────────────────────────────────
  // כש-WebView2 Runtime חסר, ה-host לא רשאי לבנות WebView מוסתר ברקע (זה
  // נכשל native). ה-gate מדלג על כל תוספי הרקע לפני כל גישה ל-DB/WebView.

  group('gate חוסר WebView2 Runtime', () {
    tearDown(
      () => WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null),
    );

    testWidgets(
      'override(false) — תוסף עם run_on_startup לא בונה WebView ברקע',
      (
        tester,
      ) async {
        WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
        bloc.testEmit(
          PluginSystemLoaded([
            _plugin(permissions: const [pluginRunOnStartupPermission]),
          ]),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<PluginSystemBloc>.value(
              value: bloc,
              child: const Scaffold(body: PluginBackgroundHost()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ה-gate חסם את כל המסלול לפני בניית WebView — אין InAppWebView,
        // וה-host נטען ללא קריסה.
        expect(find.byType(PluginBackgroundHost), findsOneWidget);
        expect(find.byType(InAppWebView), findsNothing);
      },
    );
  });

  // ── אתחול סביבת WebView2 — מתי הוא נקרא ────────────────────────────────────
  // ה-host קורא ל-initialize רק כשהוא באמת עומד להריץ תוסף רקע: האתחול מצמיח
  // 5-7 תהליכי Edge (~100MB). מנגד, בלי אתחול WebView2 כותב לתיקיית ברירת
  // מחדל ליד ה-EXE ונכשל בהתקנת Program Files.
  // ההרשאה נקראת מ-SQLite אמיתי, ולכן הקבוצה מרימה Settings + DB זמניים.

  group('אתחול סביבת WebView2', () {
    late Directory tempDir;
    late int initializeCalls;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-bg-host-');
      await Settings.init(cacheProvider: MemorySettingsCache());
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      await PluginSystemDatabase.instance.close();
      // פתיחת ה-DB כאן, מחוץ ל-FakeAsync של testWidgets: הפתיחה הראשונה עושה
      // IO אמיתי שלא מתקדם תחת השעון המזויף והבדיקה הייתה נתקעת.
      await PluginRegistryRepository().getPermission('warmup', 'warmup');

      initializeCalls = 0;
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(true);
      WebViewEnvironmentHolder.debugOverrideInitialize(() async {
        initializeCalls++;
      });
    });

    tearDown(() async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
      WebViewEnvironmentHolder.debugOverrideInitialize(null);
      await PluginSystemDatabase.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PluginSystemBloc>.value(
            value: bloc,
            child: const Scaffold(body: PluginBackgroundHost()),
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

    testWidgets('כשל באתחול — לא נבנה WebView ברקע', (tester) async {
      WebViewEnvironmentHolder.debugOverrideInitialize(() async {
        initializeCalls++;
        throw StateError('init failed');
      });
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

      // initializeCalls==1 מוכיח שהמסלול באמת חצה את קריאת ההרשאה מה-DB —
      // בלעדיו הבדיקות ה"שליליות" בקבוצה היו עוברות סתם כי הקוד נתקע.
      expect(initializeCalls, 1);
      expect(find.byType(InAppWebView), findsNothing);
    });
  });
}
