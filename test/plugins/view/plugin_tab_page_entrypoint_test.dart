import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:provider/provider.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockPluginSystemBloc extends Mock implements PluginSystemBloc {}

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockLibraryBloc extends Mock implements LibraryBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockBookmarkBloc extends Mock implements BookmarkBloc {}

class _MockCustomFoldersBloc extends Mock implements CustomFoldersBloc {}

class _SettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// רושם בדיקות קיום של קבצים תחת [prefix]; כל קובץ אחר הוא קובץ אמיתי.
final class _EntryFileSpy extends IOOverrides {
  _EntryFileSpy(this.prefix);
  final String prefix;
  final entrypointResults = Queue<Future<bool>>();
  Future<bool> manifestExists = Future.value(true);
  final existsCalls = <String>[];
  final existsSyncCalls = <String>[];
  final guardWrites = <({String contents, Completer<void> done})>[];

  @override
  File createFile(String path) {
    final normalized = path.replaceAll(r'\', '/');
    if (normalized.startsWith(_guardRoot)) return _GuardFile(path, this);
    return normalized.startsWith(prefix)
        ? _SpyFile(path, this)
        : super.createFile(path);
  }

  @override
  Directory createDirectory(String path) =>
      path.replaceAll(r'\', '/').startsWith(_guardRoot)
      ? _GuardDirectory(path)
      : super.createDirectory(path);
}

const _guardRoot = '/guard';

/// קובץ הגנת הקריסות: כל כתיבה ממתינה עד שהבדיקה משחררת אותה.
class _GuardFile implements File {
  _GuardFile(this.path, this._spy);
  @override
  final String path;
  final _EntryFileSpy _spy;

  @override
  Directory get parent => _GuardDirectory(_guardRoot);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    final done = Completer<void>();
    _spy.guardWrites.add((contents: contents, done: done));
    return done.future.then((_) => this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GuardDirectory implements Directory {
  _GuardDirectory(this.path);
  @override
  final String path;

  @override
  Future<Directory> create({bool recursive = false}) async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyFile implements File {
  _SpyFile(this.path, this._spy);
  @override
  final String path;
  final _EntryFileSpy _spy;

  @override
  Future<bool> exists() async {
    _spy.existsCalls.add(path.replaceAll(r'\', '/'));
    if (path.endsWith('manifest.json')) return _spy.manifestExists;
    return _spy.entrypointResults.removeFirst();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      jsonEncode(_plugin().manifest.toJson());

  @override
  bool existsSync() {
    _spy.existsSyncCalls.add(path);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/install/path',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '0.0.0',
    sdkVersion: '1.0.0',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 0,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2025),
  updatedAt: DateTime(2025),
);

class _FakePlatform extends InAppWebViewPlatform {
  final controller = _FakeController();
  int webViewsCreated = 0;
  final views = <PlatformInAppWebViewWidgetCreationParams>[];

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      controller;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    webViewsCreated++;
    views.add(params);
    return _FakeWebView(params);
  }
}

class _FakeController extends PlatformInAppWebViewController {
  _FakeController()
    : super.implementation(
        PlatformInAppWebViewControllerCreationParams(id: 'entrypoint-test'),
      );

  int cacheClears = 0;
  int reloads = 0;
  final loadedUrls = <String>[];
  final fontLoads = <Completer<CallAsyncJavaScriptResult?>>[];
  final scripts = <String>[];
  Completer<dynamic>? bootGate;
  Completer<void>? fontStarted;
  Completer<void>? bootStarted;
  InAppWebViewSettings? nativeSettings;
  int settingsReads = 0;
  final settingsWrites = <InAppWebViewSettings>[];

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
    settingsWrites.add(nativeSettings!);
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required Function callback,
  }) {}

  @override
  dynamic getViewId() => params.id;

  List<String> get boots => scripts
      .where((source) => source.contains('return window.Otzaria._boot('))
      .toList();

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) {
    final gate = Completer<CallAsyncJavaScriptResult?>();
    fontLoads.add(gate);
    fontStarted?.complete();
    return gate.future;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    if (source.contains('return window.Otzaria._boot(')) {
      bootStarted?.complete();
      return bootGate?.future;
    }
    return null;
  }

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async {
    cacheClears++;
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    loadedUrls.add(urlRequest.url.toString());
  }

  @override
  Future<void> reload() async {
    reloads++;
  }
}

class _FakeWebView extends PlatformInAppWebViewWidget {
  _FakeWebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const Text('התוסף מוכן');

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(
  InstalledPlugin plugin,
  _SettingsBloc settings, {
  List<InstalledPlugin>? pages,
}) => MultiProvider(
  providers: [
    Provider<PluginSystemBloc>.value(value: _MockPluginSystemBloc()),
    Provider<HistoryBloc>.value(value: _MockHistoryBloc()),
    Provider<TabsBloc>.value(value: _MockTabsBloc()),
    Provider<NavigationBloc>.value(value: _MockNavigationBloc()),
    Provider<LibraryBloc>.value(value: _MockLibraryBloc()),
    Provider<CalendarCubit>.value(value: _MockCalendarCubit()),
    Provider<WorkspaceBloc>.value(value: _MockWorkspaceBloc()),
    Provider<BookmarkBloc>.value(value: _MockBookmarkBloc()),
    Provider<CustomFoldersBloc>.value(value: _MockCustomFoldersBloc()),
    BlocProvider<SettingsBloc>.value(value: settings),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          for (final page in pages ?? [plugin])
            PluginTabPage(
              key: ValueKey(page.updatedAt),
              plugin: page,
              instanceId: 'tab-1',
            ),
        ],
      ),
    ),
  ),
);

Future<void> _run(
  WidgetTester tester,
  _EntryFileSpy io,
  Future<void> Function(_FakePlatform platform) body, {
  InstalledPlugin? plugin,
  bool crashGuard = false,
}) async {
  final previousPlatform = InAppWebViewPlatform.instance ?? _FakePlatform();
  final previousPackageInfo = PluginWebViewHost.cachedPackageInfo;
  final platform = _FakePlatform();
  InAppWebViewPlatform.instance = platform;
  PluginWebViewHost.cachedPackageInfo = PackageInfo(
    appName: 'test',
    packageName: 'test',
    version: '1.0.0',
    buildNumber: '1',
  );
  final settings = _SettingsBloc();
  try {
    // HttpServer יוצר טיימר idle גם ללא בקשות; הוא שייך לשעון האמיתי.
    await tester.runAsync(() => PluginFileServer.instance.ensurePort());
    await IOOverrides.runWithIOOverrides(() async {
      if (crashGuard) {
        PluginCrashGuard.resetForTesting();
        PluginCrashGuard.setInitialBlockedForTesting({});
      }
      try {
        await tester.pumpWidget(_host(plugin ?? _plugin(), settings));
        await tester.pump();
        await tester.runAsync(() async {});
        await tester.pump();
        await tester.pump();
        final host =
            tester.state(find.byType(PluginTabPage)) as PluginWebViewHost;
        expect(host.pluginContentBlockers, isNotNull);
        await body(platform);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final font in platform.controller.fontLoads) {
          if (!font.isCompleted) font.complete(null);
        }
        final boot = platform.controller.bootGate;
        if (boot != null && !boot.isCompleted) boot.complete();
        await tester.pump();
        for (var i = 0; i < io.guardWrites.length; i++) {
          if (!io.guardWrites[i].done.isCompleted) {
            io.guardWrites[i].done.complete();
          }
          await tester.pump();
        }
      }
    }, io);
  } finally {
    await tester.runAsync(() => PluginFileServer.instance.close());
    await settings.close();
    InAppWebViewPlatform.instance = previousPlatform;
    PluginWebViewHost.cachedPackageInfo = previousPackageInfo;
  }
}

Future<({Future<void> done})> _startBoot(
  WidgetTester tester,
  PlatformInAppWebViewWidgetCreationParams view,
  _FakeController native,
  InAppWebViewController controller,
  WebUri url, {
  bool holdBoot = false,
}) async {
  late Future<void> done;
  await tester.runAsync(() async {
    native.fontStarted = Completer<void>();
    native.bootStarted = Completer<void>();
    native.bootGate = holdBoot ? Completer<dynamic>() : null;
    // ה-API מצהיר void; גוף ה-callback האסינכרוני מחזיר Future שניתן לנקז.
    done = Function.apply(view.onLoadStop!, [controller, url]) as Future<void>;
    await Future.any([native.fontStarted!.future, done]);
  });
  await tester.pump();
  return (done: done);
}

Future<void> _runBoot(
  WidgetTester tester,
  Future<void> Function(_FakePlatform platform) body,
) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('plugin_boot_generation_'),
  ))!;
  final previousFontSource = debugPluginFontsFromFileServer;
  PluginRuntimeDispatcher.instance.resetVisibilityForTesting();
  debugPluginFontsFromFileServer = true;
  PluginCrashGuard.resetForTesting();
  AppPaths.debugOverrideDataRootPath(root.path);
  final database = PluginSystemDatabase.instance;
  database.resetForTests();
  try {
    await tester.runAsync(() async {
      await Directory('${root.path}/databases').create();
      await database.database;
    });
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.add(Future.value(true));
    await _run(tester, io, body, plugin: _developmentPlugin());
  } finally {
    await tester.runAsync(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    AppPaths.debugOverrideDataRootPath(null);
    PluginRuntimeDispatcher.instance.resetVisibilityForTesting();
    debugPluginFontsFromFileServer = previousFontSource;
  }
}

InstalledPlugin _developmentPlugin() => _plugin().copyWith(
  sourceType: 'development',
  devRootPath: '/install/path',
);

Future<void> _reload() =>
    PluginRuntimeDispatcher.instance.reloadPlugin('test.plugin');

void main() {
  setUp(() => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets(
    'foreground applies log-only changes across creation and stops listening on disposal',
    (tester) async {
      final diagnostics = DeveloperDiagnostics.instance..resetForTesting();
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('foreground-console-'),
      ))!;
      diagnostics.outputPath = '${directory.path}/diagnostics.jsonl';
      PluginWebViewHost.debugVerboseConsoleOverride = false;
      late _FakeController native;
      try {
        final io = _EntryFileSpy('/install/')
          ..entrypointResults.add(Future.value(true));
        await _run(tester, io, (platform) async {
          final view = platform.views.last;
          final initial = view.initialSettings!;
          expect(initial.consoleMessageLevels, [
            ConsoleMessageLevel.WARNING,
            ConsoleMessageLevel.ERROR,
          ]);
          expect(
            initial.contentBlockers,
            pluginNetworkUsesContentBlockers ? isNotEmpty : isEmpty,
          );
          native = platform.controller..nativeSettings = initial;
          await tester.runAsync(() async {
            diagnostics.initFromLaunch(const [
              '--dev-diagnostics=log',
            ], environment: const {});
            await diagnostics.snapshot();
          });
          expect(diagnostics.panelVisible.value, isFalse);
          view.onWebViewCreated!(
            InAppWebViewController.fromPlatform(platform: native),
          );
          await tester.pump();
          expect(native.nativeSettings!.consoleMessageLevels, isNull);
          expect(
            native.nativeSettings!.contentBlockers!.map((rule) => rule.toMap()),
            initial.contentBlockers!.map((rule) => rule.toMap()),
          );
          expect(
            native.nativeSettings!.allowUniversalAccessFromFileURLs,
            isFalse,
          );
          await tester.runAsync(() async {
            diagnostics.toggle();
            await diagnostics.snapshot();
          });
          await tester.pump();
          expect(native.nativeSettings!.consoleMessageLevels, [
            ConsoleMessageLevel.WARNING,
            ConsoleMessageLevel.ERROR,
          ]);
        });
        final readsAfterDisposal = native.settingsReads;
        await tester.runAsync(() async {
          diagnostics.initFromLaunch(const [
            '--dev-diagnostics=log',
          ], environment: const {});
          await diagnostics.snapshot();
        });
        await tester.pump();
        expect(native.settingsReads, readsAfterDisposal);
      } finally {
        diagnostics.resetForTesting();
        PluginWebViewHost.debugVerboseConsoleOverride = null;
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );

  testWidgets('קובץ כניסה חסר נבדק פעם אחת ואסינכרונית (#3380)', (
    tester,
  ) async {
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.add(Future.value(false));
    await _run(tester, io, (_) async {
      expect(io.existsSyncCalls, isEmpty);
      expect(io.existsCalls, ['/install/path/index.html']);
      expect(find.byType(InAppWebView), findsNothing);
    });
  });

  testWidgets('קובץ כניסה קיים מציג WebView לאחר הבדיקה', (tester) async {
    final exists = Completer<bool>();
    final io = _EntryFileSpy('/install/')..entrypointResults.add(exists.future);
    await _run(tester, io, (_) async {
      expect(find.byType(InAppWebView), findsNothing);
      exists.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('התוסף מוכן'), findsOneWidget);
      expect(io.existsSyncCalls, isEmpty);
    });
  });

  testWidgets('יצירת קובץ חסר וריענון מאוחר בונים WebView', (tester) async {
    final exists = Completer<bool>();
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.addAll([Future.value(false), exists.future]);
    await _run(tester, io, (_) async {
      expect(find.byType(InAppWebView), findsNothing);
      final reload = _reload();
      await tester.pump();
      await tester.pump();
      expect(io.existsCalls, [
        '/install/path/index.html',
        '/install/path/manifest.json',
        '/install/path/index.html',
      ]);
      expect(find.byType(InAppWebView), findsNothing);
      exists.complete(true);
      await reload;
      await tester.pump();
      expect(find.text('התוסף מוכן'), findsOneWidget);
    }, plugin: _developmentPlugin());
  });

  testWidgets('ריענון עם controller חי טוען את נקודת הכניסה', (tester) async {
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.addAll([Future.value(true), Future.value(true)]);
    await _run(tester, io, (platform) async {
      final host =
          tester.state(find.byType(PluginTabPage)) as PluginWebViewHost;
      host.webViewController = InAppWebViewController.fromPlatform(
        platform: platform.controller,
      );
      await _reload();
      await tester.pump();
      expect(find.text('התוסף מוכן'), findsOneWidget);
      expect(platform.controller.cacheClears, 1);
      expect(platform.controller.loadedUrls.single, endsWith('/index.html'));
    }, plugin: _developmentPlugin());
  });

  testWidgets('ריענון משגיאה ממתין לקובץ ואז מציג WebView חדש', (tester) async {
    final exists = Completer<bool>();
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.addAll([
        Future.value(false),
        Future.value(false),
        exists.future,
      ]);
    await _run(tester, io, (_) async {
      await _reload();
      await tester.pump();
      expect(
        find.textContaining('קובץ נקודת הכניסה חסר בתיקייה'),
        findsOneWidget,
      );
      final reload = _reload();
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('קובץ נקודת הכניסה חסר בתיקייה'),
        findsOneWidget,
      );
      expect(find.byType(InAppWebView), findsNothing);
      exists.complete(true);
      await reload;
      await tester.pump();
      expect(find.text('התוסף מוכן'), findsOneWidget);
    }, plugin: _developmentPlugin());
  });

  testWidgets('בדיקה ראשונית מאוחרת אינה דורסת ריענון מוצלח', (tester) async {
    final initial = Completer<bool>();
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.addAll([initial.future, Future.value(true)]);
    await _run(tester, io, (_) async {
      await _reload();
      await tester.pump();
      expect(find.text('התוסף מוכן'), findsOneWidget);
      initial.complete(false);
      await tester.pump();
      expect(find.text('התוסף מוכן'), findsOneWidget);
    }, plugin: _developmentPlugin());
  });

  testWidgets('ריענון מציג שגיאה אם קובץ הכניסה עדיין חסר', (tester) async {
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.addAll([Future.value(false), Future.value(false)]);
    await _run(tester, io, (_) async {
      await _reload();
      await tester.pump();
      expect(
        find.textContaining('קובץ נקודת הכניסה חסר בתיקייה'),
        findsOneWidget,
      );
      expect(find.byType(InAppWebView), findsNothing);
    }, plugin: _developmentPlugin());
  });

  testWidgets('ריענון מציג שגיאה אם המניפסט חסר', (tester) async {
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.add(Future.value(false))
      ..manifestExists = Future.value(false);
    await _run(tester, io, (_) async {
      await _reload();
      await tester.pump();
      expect(find.text('קובץ manifest.json חסר בתיקייה.'), findsOneWidget);
      expect(find.byType(InAppWebView), findsNothing);
    }, plugin: _developmentPlugin());
  });

  testWidgets('סגירה לפני תשובת הבדיקה הראשונית אינה מעדכנת State', (
    tester,
  ) async {
    final exists = Completer<bool>();
    final io = _EntryFileSpy('/install/')..entrypointResults.add(exists.future);
    await _run(tester, io, (_) async {
      await tester.pumpWidget(const SizedBox());
      exists.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('סגירה בזמן בדיקת הקובץ בריענון אינה מעדכנת State', (
    tester,
  ) async {
    final exists = Completer<bool>();
    final io = _EntryFileSpy('/install/')
      ..entrypointResults.addAll([Future.value(false), exists.future]);
    await _run(tester, io, (_) async {
      final reload = _reload();
      await tester.pump();
      expect(io.existsCalls.last, '/install/path/index.html');
      await tester.pumpWidget(const SizedBox());
      exists.complete(false);
      await reload;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }, plugin: _developmentPlugin());
  });

  testWidgets('localhost מציג WebView ומרענן בלי לבדוק קובץ מקומי', (
    tester,
  ) async {
    final io = _EntryFileSpy('/install/');
    await _run(
      tester,
      io,
      (platform) async {
        expect(find.text('התוסף מוכן'), findsOneWidget);
        await _reload();
        expect(platform.controller.cacheClears, 1);
        expect(io.existsCalls, isEmpty);
        expect(io.existsSyncCalls, isEmpty);
      },
      plugin: _plugin().copyWith(
        sourceType: 'localhost_dev',
        devRootPath: 'http://localhost:5173/',
      ),
    );
  });

  testWidgets('מסלול גופנים מוטבעים בונה CSS פעם אחת לפני boot', (
    tester,
  ) async {
    const family = 'Embedded font test';
    await Settings.setValue(SettingsRepository.keyFontFamily, family);
    var lookups = 0;
    debugPluginSystemFaces = (name) {
      if (name == family) lookups++;
      return null;
    };
    addTearDown(() => debugPluginSystemFaces = null);

    await _runBoot(tester, (platform) async {
      debugPluginFontsFromFileServer = false;
      final native = platform.controller;
      final controller = InAppWebViewController.fromPlatform(platform: native);
      final boot = await _startBoot(
        tester,
        platform.views.last,
        native,
        controller,
        WebUri('file:///install/path/index.html'),
      );
      await tester.runAsync(() => boot.done);

      expect(lookups, 1);
      expect(native.fontLoads, isEmpty);
      expect(native.boots.single, contains('data:font/ttf;base64,'));
    });
  });

  for (final waitingAt in ['גופנים', 'boot']) {
    testWidgets(
      'ניווט חדש בזמן המתנה ל-$waitingAt מבטל את זרימת ה-boot הישנה',
      (
        tester,
      ) async {
        await _runBoot(tester, (platform) async {
          final view = platform.views.last;
          final native = platform.controller;
          final controller = InAppWebViewController.fromPlatform(
            platform: native,
          );
          final url = WebUri('file:///install/path/index.html');
          final first = await _startBoot(
            tester,
            view,
            native,
            controller,
            url,
            holdBoot: waitingAt == 'boot',
          );
          expect(native.fontLoads, hasLength(1));
          expect(native.boots, isEmpty);
          if (waitingAt == 'boot') {
            await tester.runAsync(() async {
              native.fontLoads.single.complete(
                CallAsyncJavaScriptResult(value: true),
              );
              await Future.any([native.bootStarted!.future, first.done]);
            });
            expect(native.boots, hasLength(1));
          }
          view.onLoadStart!(controller, url);
          await tester.runAsync(() async {
            if (waitingAt == 'גופנים') {
              native.fontLoads.single.complete(
                CallAsyncJavaScriptResult(value: true),
              );
            } else {
              native.bootGate!.complete();
            }
            await first.done;
          });
          await tester.pump();
          expect(native.boots, hasLength(waitingAt == 'גופנים' ? 0 : 1));
          expect(find.byType(LoadingIndicator), findsOneWidget);

          final second = await _startBoot(
            tester,
            view,
            native,
            controller,
            url,
          );
          expect(native.fontLoads, hasLength(2));
          await tester.runAsync(() async {
            native.fontLoads.last.complete(
              CallAsyncJavaScriptResult(value: true),
            );
            await second.done;
          });
          await tester.pump();
          expect(native.boots, hasLength(waitingAt == 'גופנים' ? 1 : 2));
          expect(find.byType(LoadingIndicator), findsNothing);
        });
      },
    );
  }

  testWidgets('boot שהושלם אחרי קריסה ולפני frame אינו מאבד אירוע ממתין', (
    tester,
  ) async {
    await _runBoot(tester, (platform) async {
      final view = platform.views.last;
      final native = platform.controller;
      final controller = InAppWebViewController.fromPlatform(platform: native);
      final host =
          tester.state(find.byType(PluginTabPage)) as PluginWebViewHost;
      final dispatcher = PluginRuntimeDispatcher.instance;
      host.webViewController = controller;
      dispatcher.setVisiblePluginInstances({
        (pluginId: 'test.plugin', instanceId: 'tab-1'),
      });
      dispatcher.setReaderScreenVisible(true);
      dispatcher.setWindowShown(true);
      dispatcher.registerController(
        'test.plugin',
        controller,
        instanceId: 'tab-1',
      );
      await tester.idle();
      final first = await _startBoot(
        tester,
        view,
        native,
        controller,
        WebUri('file:///install/path/index.html'),
        holdBoot: true,
      );
      await tester.runAsync(() async {
        native.fontLoads.single.complete(
          CallAsyncJavaScriptResult(value: true),
        );
        await native.bootStarted!.future;
        view.onRenderProcessGone!(
          controller,
          RenderProcessGoneDetail(didCrash: true),
        );
        await dispatcher.dispatchEventToPlugin(
          'test.plugin',
          'click',
          {'requestId': 'after-crash'},
          instanceId: 'tab-1',
        );
        // ניתוק renderer משלים eval ממתין ב-null, לפני ציור ה-WebView החדש.
        native.bootGate!.complete(null);
        await first.done;
      });
      await tester.idle();
      final replacement = _FakeController();
      final replacementController = InAppWebViewController.fromPlatform(
        platform: replacement,
      );
      dispatcher.registerController(
        'test.plugin',
        replacementController,
        instanceId: 'tab-1',
      );
      try {
        var readyDone = false;
        final ready = dispatcher
            .onForegroundInstanceReady('test.plugin', instanceId: 'tab-1')
            .then((_) => readyDone = true);
        for (var i = 0; i < 8 && !readyDone; i++) {
          await tester.idle();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        expect(readyDone, isTrue);
        await ready;
        expect(
          replacement.scripts.where(
            (s) => s.contains('"requestId":"after-crash"'),
          ),
          hasLength(1),
          reason: 'אירוע שממתין לשחזור נמסר פעם אחת, רק למופע החדש',
        );
      } finally {
        dispatcher.unregisterController('test.plugin', instanceId: 'tab-1');
      }
    });
  });

  testWidgets('onLoadStop שמתחיל אחרי קריסה ולפני frame אינו מאתחל מופע מת', (
    tester,
  ) async {
    await _runBoot(tester, (platform) async {
      final view = platform.views.last;
      final native = platform.controller;
      final controller = InAppWebViewController.fromPlatform(platform: native);
      final host =
          tester.state(find.byType(PluginTabPage)) as PluginWebViewHost;
      host.webViewController = controller;
      view.onRenderProcessGone!(
        controller,
        RenderProcessGoneDetail(didCrash: true),
      );
      late Future<void> done;
      await tester.runAsync(() async {
        native.fontStarted = Completer<void>();
        done =
            Function.apply(view.onLoadStop!, [
                  controller,
                  WebUri('file:///install/path/index.html'),
                ])
                as Future<void>;
        await Future.any([native.fontStarted!.future, done]);
      });
      expect(native.fontLoads, isEmpty);
      await tester.runAsync(() => done);
      expect(native.boots, isEmpty);
    });
  });

  testWidgets('onLoadStart של ניסיון קודם אינו מבטל boot של הניסיון הנוכחי', (
    tester,
  ) async {
    await _runBoot(tester, (platform) async {
      final previous = platform.views.last;
      final native = platform.controller;
      final controller = InAppWebViewController.fromPlatform(platform: native);
      final url = WebUri('file:///install/path/index.html');
      previous.onReceivedError!(
        controller,
        WebResourceRequest(url: url, isForMainFrame: true),
        WebResourceError(
          type: WebResourceErrorType.UNKNOWN,
          description: 'failed',
        ),
      );
      await tester.pump();
      await _reload();
      await tester.pump();
      final current = platform.views.last;
      final active = await _startBoot(tester, current, native, controller, url);
      expect(native.fontLoads, hasLength(1));
      previous.onLoadStart!(controller, url);
      previous.onLoadStop!(controller, url);
      await tester.pump();
      expect(native.fontLoads, hasLength(1));
      await tester.runAsync(() async {
        native.fontLoads.single.complete(
          CallAsyncJavaScriptResult(value: true),
        );
        await active.done;
      });
      await tester.pump();
      expect(native.boots, hasLength(1));
      expect(find.byType(LoadingIndicator), findsNothing);
    });
  });

  group('סימון הגנת הקריסות (#4008)', () {
    setUp(() => AppPaths.debugOverrideDataRootPath(_guardRoot));
    tearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      PluginCrashGuard.resetForTesting();
    });

    testWidgets('החלפת טאב עם אותו instanceId אינה מנקה את הסימון החדש', (
      tester,
    ) async {
      final plugin = _plugin().copyWith(
        sourceType: 'localhost_dev',
        devRootPath: 'http://localhost:5173/',
      );
      final io = _EntryFileSpy('/install/');
      await _run(
        tester,
        io,
        (platform) async {
          expect(io.guardWrites, hasLength(1));
          io.guardWrites.single.done.complete();
          await tester.pump();
          expect(platform.webViewsCreated, 1);
          final settings =
              tester.element(find.byType(PluginTabPage)).read<SettingsBloc>()
                  as _SettingsBloc;
          final replacement = plugin.copyWith(updatedAt: DateTime(2026));
          // ב-Windows החדש מסמן לפני dispose של הישן באותו פריים.
          // החפיפה משמרת סדר זה גם כשהכנת חוקי WebKit אסינכרונית.
          await tester.pumpWidget(
            _host(plugin, settings, pages: [plugin, replacement]),
          );
          await tester.runAsync(() async {});
          await tester.pump();
          expect(io.guardWrites, hasLength(2));
          io.guardWrites.last.done.complete();
          await tester.pump();
          expect(find.byType(InAppWebView), findsNWidgets(2));
          await tester.pumpWidget(_host(replacement, settings));
          for (var i = 2; i < io.guardWrites.length; i++) {
            io.guardWrites[i].done.complete();
            await tester.pump();
          }
          expect(
            (jsonDecode(io.guardWrites.last.contents) as Map)['blocked'],
            contains('test.plugin'),
          );
        },
        plugin: plugin,
        crashGuard: true,
      );
    });

    testWidgets('callback מניסיון קודם אינו מנקה סימון של ניסיון חדש', (
      tester,
    ) async {
      final io = _EntryFileSpy('/install/')
        ..entrypointResults.add(Future.value(true));
      await _run(
        tester,
        io,
        (platform) async {
          io.guardWrites.single.done.complete();
          await tester.pump();
          final previous = platform.views.last;
          final controller = InAppWebViewController.fromPlatform(
            platform: platform.controller,
          );
          final host =
              tester.state(find.byType(PluginTabPage)) as PluginWebViewHost;
          host.webViewController = controller;
          final request = WebResourceRequest(
            url: WebUri('file:///install/path/index.html'),
            isForMainFrame: true,
          );
          final error = WebResourceError(
            type: WebResourceErrorType.UNKNOWN,
            description: 'failed',
          );
          previous.onReceivedError!(controller, request, error);
          await tester.pump();
          io.guardWrites.last.done.complete();
          await tester.pump();
          await _reload();
          await tester.pump();
          previous.onWebContentProcessDidTerminate!(controller);
          await tester.pump();
          io.guardWrites.last.done.complete();
          await tester.pump();
          expect(find.byType(InAppWebView), findsOneWidget);
          previous.onReceivedError!(controller, request, error);
          await tester.pump();
          for (final write in io.guardWrites) {
            if (!write.done.isCompleted) write.done.complete();
          }
          await tester.pump();
          expect(
            (jsonDecode(io.guardWrites.last.contents) as Map)['blocked'],
            contains('test.plugin'),
          );
          expect(find.byType(InAppWebView), findsOneWidget);
        },
        plugin: _developmentPlugin(),
        crashGuard: true,
      );
    });

    testWidgets('ה-WebView נוצר רק אחרי שהסימון נשמר בדיסק', (tester) async {
      final io = _EntryFileSpy('/install/')
        ..entrypointResults.add(Future.value(true));
      await _run(tester, io, (platform) async {
        expect(platform.webViewsCreated, 0);
        expect(io.guardWrites.single.contents, contains('test.plugin'));
        io.guardWrites.single.done.complete();
        await tester.pump();
        await tester.pump();
        expect(platform.webViewsCreated, 1);
        expect(find.text('התוסף מוכן'), findsOneWidget);
      }, crashGuard: true);
    });

    testWidgets('סגירה בזמן השמירה: אין WebView והסימון מנוקה', (tester) async {
      final io = _EntryFileSpy('/install/')
        ..entrypointResults.add(Future.value(true));
      await _run(tester, io, (platform) async {
        await tester.pumpWidget(const SizedBox());
        io.guardWrites.single.done.complete();
        await tester.pump();
        expect(io.guardWrites, hasLength(2));
        expect(io.guardWrites.last.contents, isNot(contains('test.plugin')));
        io.guardWrites.last.done.complete();
        await tester.pump();
        expect(platform.webViewsCreated, 0);
        expect(tester.takeException(), isNull);
      }, crashGuard: true);
    });
  });
}
