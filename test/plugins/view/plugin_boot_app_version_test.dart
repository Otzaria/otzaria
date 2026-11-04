import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/memory_settings_cache.dart';

class _NonceBridge extends Fake implements PluginBridgeHandler {
  @override
  String get bridgeNonce => 'nonce';
}

class _HostWidget extends StatefulWidget {
  const _HostWidget();

  @override
  State<_HostWidget> createState() => _Host();
}

class _Host extends State<_HostWidget> with PluginWebViewHost {
  @override
  final plugin = InstalledPlugin(
    pluginId: 'test.plugin',
    name: 'Test',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: '/index.html',
    enabled: true,
    pinned: false,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: 'test.plugin',
      name: 'Test',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '0.9.98',
      sdkVersion: '1.x',
      permissions: const [],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'Test',
      toolTabOrder: 1,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  String get instanceId => 'test';

  @override
  String get logTag => 'Plugin';

  @override
  BuildContext? get dialogContext => null;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  setUp(() {
    final original = ConnectivityStatusService.instance;
    ConnectivityStatusService.instance = ConnectivityStatusService(
      networkProbe: () async => true,
    );
    addTearDown(() => ConnectivityStatusService.instance = original);
  });

  testWidgets('plugin.boot reports the hotfix as the 4th version part', (
    tester,
  ) async {
    await tester.pumpWidget(const _HostWidget());
    final host = tester.state<_Host>(find.byType(_HostWidget))
      ..bridge = _NonceBridge();

    String bootFor(String buildNumber) => host.pluginBootScript(
      runMode: 'tab',
      packageInfo: PackageInfo(
        appName: 'Otzaria',
        packageName: 'otzaria',
        version: '0.9.98',
        buildNumber: buildNumber,
      ),
      permissions: const [],
      theme: const {},
    );

    expect(bootFor('99801'), contains('"app":{"version":"0.9.98.1"'));
    expect(bootFor('99800'), contains('"app":{"version":"0.9.98"'));
  });

  group('מדיניות רמות ה-console של תוסף (issue #4118)', () {
    final db = PluginSystemDatabase.instance;
    final printed = <String?>[];

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('plugin_console_');
      AppPaths.debugOverrideDataRootPath(dir.path);
      db.resetForTests();
      printed.clear();
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
      addTearDown(() async {
        debugPrint = original;
        db.resetForTests();
        AppPaths.debugOverrideDataRootPath(null);
        await dir.delete(recursive: true);
      });
    });

    /// 300 הודעות info/log/debug ואחריהן WARNING (מהרקע) ו-ERROR;
    /// מחזיר את מה שנכתב ליומן התוסף במסד.
    Future<List<String>> feed() async {
      final host = _Host();
      for (final level in [
        ConsoleMessageLevel.TIP,
        ConsoleMessageLevel.LOG,
        ConsoleMessageLevel.DEBUG,
      ]) {
        for (var i = 0; i < 100; i++) {
          host.logPluginConsole(
            ConsoleMessage(message: 'info $i', messageLevel: level),
          );
        }
      }
      host
        ..logPluginConsole(
          ConsoleMessage(
            message: 'w',
            messageLevel: ConsoleMessageLevel.WARNING,
          ),
          prefix: '[background] ',
        )
        ..logPluginConsole(
          ConsoleMessage(message: 'e', messageLevel: ConsoleMessageLevel.ERROR),
        );
      await db.close();
      final file = sqlite3.open(await AppPaths.resolvePluginsDbPath());
      addTearDown(file.close);
      return [
        for (final row in file.select(
          'SELECT level, message FROM plugin_runtime_log ORDER BY id',
        ))
          '${row['level']} ${row['message']}',
      ];
    }

    const kept = [
      'WARNING [background] w',
      'ERROR e',
    ];

    test('ב-release רגיל info/log/debug נזרקות לפני debugPrint', () async {
      PluginWebViewHost.debugVerboseConsoleOverride = false;
      addTearDown(() => PluginWebViewHost.debugVerboseConsoleOverride = null);
      expect(await feed(), kept);
      expect(printed, ['Plugin [test.plugin]: w', 'Plugin [test.plugin]: e']);
    });

    test('ב-debug כל ההודעות מודפסות, ולמסד רק WARNING/ERROR', () async {
      expect(await feed(), kept);
      expect(printed, hasLength(302));
      expect(printed.first, 'Plugin [test.plugin]: info 0');
    });
  });
}
