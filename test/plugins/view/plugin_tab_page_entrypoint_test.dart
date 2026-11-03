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
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
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

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      controller;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    webViewsCreated++;
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

Widget _host(InstalledPlugin plugin, _SettingsBloc settings) => MultiProvider(
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
      body: PluginTabPage(plugin: plugin, instanceId: 'tab-1'),
    ),
  ),
);

Future<void> _run(
  WidgetTester tester,
  _EntryFileSpy io,
  Future<void> Function(_FakePlatform platform) body, {
  InstalledPlugin? plugin,
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
        await tester.pump();
      }
    }, io);
  } finally {
    await tester.runAsync(() => PluginFileServer.instance.close());
    await settings.close();
    InAppWebViewPlatform.instance = previousPlatform;
    PluginWebViewHost.cachedPackageInfo = previousPackageInfo;
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

  group('סימון הגנת הקריסות (#4008)', () {
    setUp(() {
      AppPaths.debugOverrideDataRootPath(_guardRoot);
      PluginCrashGuard.setInitialBlockedForTesting({});
    });
    tearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      PluginCrashGuard.resetForTesting();
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
      });
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
      });
    });
  });
}
