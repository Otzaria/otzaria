import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null));

  group('WebViewEnvironmentHolder.isRuntimeAvailable', () {
    test('איפוס override מחזיר את הבדיקה להתנהגות הרגילה', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
      // ללא override, על פלטפורמה שאינה Windows התוצאה היא true; ב-Windows
      // ללא platform channel הקריאה נכשלת ומוחזר false. בשני המקרים אסור
      // שהקריאה תזרוק חריגה.
      await expectLater(
        WebViewEnvironmentHolder.isRuntimeAvailable(),
        completes,
      );
    });
  });

  group('WebViewEnvironmentHolder.prewarm', () {
    late List<WebViewEnvironmentSettings> calls;
    late Directory dataRoot;
    late _FakeEnvironment fakeEnvironment;
    InAppWebViewPlatform? previousPlatform;
    Completer<WebViewEnvironmentPrewarmResult?>? pendingPrewarm;
    late Completer<void> prewarmStarted;

    setUp(() async {
      calls = [];
      pendingPrewarm = null;
      prewarmStarted = Completer<void>();
      dataRoot = await Directory.systemTemp.createTemp('otzaria_prewarm_');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      WebViewEnvironmentHolder.debugOverridePrewarm((settings) {
        calls.add(settings);
        if (!prewarmStarted.isCompleted) prewarmStarted.complete();
        return pendingPrewarm?.future ?? Future.value(_okResult);
      });
      WebViewEnvironmentHolder.debugIsWindowsOverride = true;
      WebViewEnvironmentHolder.debugOverrideUnwritableDataFolder(null);
      previousPlatform = InAppWebViewPlatform.instance;
      fakeEnvironment = _FakeEnvironment();
      InAppWebViewPlatform.instance = _FakePlatform(fakeEnvironment);
    });

    tearDown(() async {
      await WebViewEnvironmentHolder.disposeForAppRestart();
      final previous = previousPlatform;
      if (previous != null) InAppWebViewPlatform.instance = previous;
      WebViewEnvironmentHolder.debugIsWindowsOverride = null;
      WebViewEnvironmentHolder.debugClearUnwritableDataFolder();
      WebViewEnvironmentHolder.debugOverridePrewarm(null);
      WebViewEnvironmentHolder.prewarmWaitLimit = const Duration(seconds: 30);
      WebView2CreationDiagnostics.debugReset();
      AppPaths.debugOverrideDataRootPath(null);
      await dataRoot.delete(recursive: true);
    });

    test('skips the native call when no plugin is enabled', () async {
      final ran = await WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => false,
      );

      expect(ran, isFalse);
      expect(calls, isEmpty);
      expect(
        WebView2CreationDiagnostics.prewarmOutcome,
        startsWith('skipped: no enabled plugin'),
      );
    });

    test('uses the settings of the real environment', () async {
      final ran = await WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => true,
      );

      expect(ran, isTrue);
      expect(
        calls.single.toMap(),
        WebViewEnvironmentHolder.debugEnvironmentSettings(
          p.join(dataRoot.path, 'webview2'),
        ).toMap(),
      );
      expect(WebView2CreationDiagnostics.prewarmOutcome, startsWith('ok 12ms'));
    });

    test('skips when the environment already exists', () async {
      await WebViewEnvironmentHolder.initialize();
      expect(WebViewEnvironmentHolder.environment, isNotNull);

      var asked = false;
      final ran = await WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => asked = true,
      );

      expect(ran, isFalse);
      expect(asked, isFalse);
      expect(calls, isEmpty);
    });

    test('initialize waits for an in-flight prewarm', () async {
      pendingPrewarm = Completer();
      final prewarm = WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => true,
      );
      await prewarmStarted.future;
      expect(calls, hasLength(1));

      final waiting = Completer<void>();
      final initialize = runZoned(
        WebViewEnvironmentHolder.initialize,
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            // יצירת התיקייה חייבת להסתיים לפני שהמתנת החימום מתחילה.
            if (duration == WebViewEnvironmentHolder.prewarmWaitLimit &&
                !waiting.isCompleted) {
              waiting.complete();
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
      await waiting.future;
      expect(fakeEnvironment.creates, 0);

      pendingPrewarm!.complete(_okResult);
      await prewarm;
      await initialize;
      expect(fakeEnvironment.creates, 1);
      expect(
        WebView2CreationDiagnostics.prewarmOutcome,
        contains('initialize waited'),
      );
    });

    test('a prewarm that never answers delays only one initialize', () async {
      pendingPrewarm = Completer();
      WebViewEnvironmentHolder.prewarmWaitLimit = const Duration(
        milliseconds: 20,
      );
      final prewarm = WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => true,
      );
      await prewarmStarted.future;
      expect(calls, hasLength(1));

      await WebViewEnvironmentHolder.initialize();
      expect(fakeEnvironment.creates, 1);
      await WebViewEnvironmentHolder.disposeForAppRestart();

      WebViewEnvironmentHolder.prewarmWaitLimit = const Duration(seconds: 30);
      await WebViewEnvironmentHolder.initialize().timeout(
        const Duration(seconds: 5),
      );
      expect(fakeEnvironment.creates, 2);
      expect(
        'initialize waited'
            .allMatches(WebView2CreationDiagnostics.prewarmOutcome!)
            .length,
        1,
      );
      pendingPrewarm!.complete(_okResult);
      await prewarm;
    });
  });

  group('WebViewEnvironmentHolder environment settings', () {
    test('uses the requested user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.userDataFolder, r'C:\app-data\webview2');
    });

    test('requires exclusive access to the user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.exclusiveUserDataFolderAccess, isTrue);
    });

    test('registers the plugin asset scheme as a secure origin', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      final registration = settings.customSchemeRegistrations!.single;
      expect(registration.scheme, pluginAssetScheme);
      expect(registration.treatAsSecure, isTrue);
      expect(registration.hasAuthorityComponent, isTrue);
    });
  });
}

const _okResult = WebViewEnvironmentPrewarmResult(
  status: 'ok',
  duration: Duration(milliseconds: 12),
);

class _FakeEnvironment extends PlatformWebViewEnvironment {
  _FakeEnvironment()
    : super.implementation(const PlatformWebViewEnvironmentCreationParams());

  int creates = 0;

  @override
  Future<PlatformWebViewEnvironment> create({
    WebViewEnvironmentSettings? settings,
  }) async {
    creates++;
    return this;
  }

  @override
  Future<void> dispose() async {}
}

class _FakePlatform extends InAppWebViewPlatform {
  _FakePlatform(this.environment);

  final _FakeEnvironment environment;

  @override
  PlatformWebViewEnvironment createPlatformWebViewEnvironmentStatic() =>
      environment;
}
