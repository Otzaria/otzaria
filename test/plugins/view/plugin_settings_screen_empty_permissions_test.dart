import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

import '../../helpers/memory_settings_cache.dart';

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
}

InstalledPlugin _plugin(List<String> permissions) => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'תוסף בדיקה',
  version: '1.0.0',
  installPath: '/tmp/test.plugin',
  entrypointPath: '/tmp/test.plugin/index.html',
  enabled: true,
  pinned: false,
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'תוסף בדיקה',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.0.0',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: [],
    toolTabTitle: 'Tab',
    toolTabOrder: 0,
    defaultPinned: false,
    publishedDataTypes: [],
  ),
);

Future<void> _pumpDialog(WidgetTester tester, InstalledPlugin plugin) async {
  final repo = _FakeRepo();
  final bloc = PluginSystemBloc(
    repository: repo,
    installerService: PluginInstallerService(repository: repo),
  );
  addTearDown(bloc.close);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<PluginSystemBloc>.value(
        value: bloc,
        child: Scaffold(body: PluginSettingsScreen(plugin: plugin)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('דיאלוג ניהול הרשאות לתוסף ללא הרשאות (issue #1480)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-plugin-perms-');
      await Settings.init(cacheProvider: MemorySettingsCache());
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      await PluginSystemDatabase.instance.close();
      // פתיחת ה-DB מחוץ ל-FakeAsync של testWidgets, שבו ה-IO הראשון נתקע.
      await PluginRegistryRepository().getPermission('warmup', 'warmup');
    });

    tearDown(() async {
      await PluginSystemDatabase.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    testWidgets('תוסף בלי הרשאות מיוחדות מציג שאין הרשאות', (tester) async {
      await _pumpDialog(
        tester,
        _plugin(const ['app.info.read', 'ui.feedback']),
      );

      expect(find.text('אין הרשאות מיוחדות נדרשות'), findsOneWidget);
    });

    testWidgets('תוסף עם הרשאה מיוחדת מציג את כרטיס ההרשאות', (tester) async {
      await _pumpDialog(tester, _plugin(const ['app.open_url']));

      expect(find.text('הרשאות מבוקשות'), findsOneWidget);
      expect(find.text('אין הרשאות מיוחדות נדרשות'), findsNothing);
    });

    testWidgets('תוסף ניווט שלא ביקש את הכפתור אינו מקבל UI חדש', (
      tester,
    ) async {
      await _pumpDialog(tester, _plugin(const ['navigation.write']));
      expect(find.text('כפתור לשונית חדשה (+)'), findsNothing);
    });

    testWidgets('intent חסום מציג את הבעלים השמור גם לפני רישום runtime', (
      tester,
    ) async {
      final repo = PluginRegistryRepository();
      final requester = _plugin(const ['navigation.write']);
      final owner = requester.copyWith(pluginId: 'owner', name: 'בעל הכפתור');
      await repo.savePluginWithPermissions(owner, const {
        'navigation.write': true,
      });
      await repo.savePluginWithPermissions(requester, const {
        'navigation.write': true,
      });
      await repo.grantNewTabPage(
        owner.pluginId,
        allowPreviouslyDenied: true,
        expectedOwner: null,
        onGranted: () {},
      );
      await repo.setPermission(
        requester.pluginId,
        pluginNewTabPagePermission,
        false,
      );
      await _pumpDialog(tester, requester);
      expect(find.text('כפתור לשונית חדשה (+)'), findsOneWidget);
      expect(find.textContaining('בעל הכפתור כעת: בעל הכפתור'), findsOneWidget);
    });
  });
}
