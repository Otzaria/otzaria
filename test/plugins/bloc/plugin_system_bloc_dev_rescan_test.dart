import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:path/path.dart' as path;

/// תוסף פיתוח שהגרסה הרשומה לו היא [version] והתיקייה שלו היא [devRootPath].
InstalledPlugin _devPlugin({
  required String devRootPath,
  String version = '1.0.0',
  String sourceType = 'development',
}) => InstalledPlugin(
  pluginId: 'org.test.dev',
  name: 'Dev',
  version: version,
  installPath: devRootPath,
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  sourceType: sourceType,
  devRootPath: devRootPath,
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': 'org.test.dev',
    'name': 'Dev',
    'version': version,
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {'title': 'Dev'},
    },
  }),
  installedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

class _FakeRepo implements PluginRegistryRepository {
  List<InstalledPlugin> plugins;

  _FakeRepo(this.plugins);

  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => List.of(plugins);

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async =>
      plugins.where((p) => p.isDevelopment).toList();

  @override
  Future<InstalledPlugin?> getPlugin(String id) async =>
      plugins.where((p) => p.pluginId == id).firstOrNull;

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  Future<bool?> getPermission(String id, String perm) async => null;

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// סופר טעינות-מחדש: זה מה שמעדכן את הגרסה הרשומה בפועל.
class _RecordingDevLoader implements PluginDevLoaderService {
  final List<String> loaded = [];

  @override
  Future<void> loadDevelopmentPlugin(
    String directoryPath, {
    PluginManifest? preValidatedManifest,
    Map<String, bool>? grantedPermissions,
  }) async {
    loaded.add(directoryPath);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory devRoot;

  setUp(() {
    devRoot = Directory.systemTemp.createTempSync('otzaria_dev_rescan');
  });

  tearDown(() {
    try {
      if (devRoot.existsSync()) devRoot.deleteSync(recursive: true);
    } on FileSystemException {
      // תיקיית temp — אם Windows עדיין מחזיק אותה, המערכת תנקה אותה בעצמה.
    }
  });

  void writeManifest(String version) {
    File(path.join(devRoot.path, 'manifest.json')).writeAsStringSync(
      '{"schemaVersion":1,"id":"org.test.dev","name":"Dev",'
      '"version":"$version","entrypoint":"index.html"}',
    );
  }

  /// [expectReload] — האם הבדיקה מצפה לטעינה מחדש. כשכן, ממתינים לה עד
  /// שנייה (קריאת הקובץ אסינכרונית); כשלא, נותנים לתור להתרוקן ואז מאמתים
  /// שדבר לא קרה.
  Future<_RecordingDevLoader> runRescan(
    InstalledPlugin plugin, {
    bool expectReload = false,
  }) async {
    final loader = _RecordingDevLoader();
    final bloc = PluginSystemBloc(
      repository: _FakeRepo([plugin]),
      devLoader: loader,
    );
    bloc.add(LoadPlugins());
    await bloc.stream.firstWhere((s) => s is PluginSystemLoaded);
    bloc.add(const RescanDevelopmentManifests());
    // הסריקה מוסיפה DevelopmentPluginManifestChanged — תור אירועים נוסף.
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (expectReload && loader.loaded.isNotEmpty) break;
      if (!expectReload &&
          DateTime.now().isAfter(
            deadline.subtract(
              const Duration(milliseconds: 700),
            ),
          )) {
        break;
      }
    }
    // סגירה לפני ה-tearDown: ה-watcher של תיקיית הפיתוח מחזיק handle,
    // ו-Windows אינו מרשה למחוק תיקייה שיש עליה handle פתוח.
    await bloc.close();
    return loader;
  }

  group('RescanDevelopmentManifests', () {
    // הרגרסיה: bump שנעשה כשהתוכנה סגורה נשאר תקוע ברשומה, ו-plugin.listInstalled
    // מדווח גרסה ישנה — ואז חנות התוספים מציעה "עדכון" לתוסף פיתוח.
    test('גרסה בקובץ גבוהה מהרשומה → התוסף נטען מחדש', () async {
      writeManifest('2.0.0');
      final loader = await runRescan(
        _devPlugin(devRootPath: devRoot.path),
        expectReload: true,
      );
      expect(loader.loaded, [devRoot.path]);
    });

    test('אותה גרסה בקובץ וברשומה → אין טעינה מחדש', () async {
      writeManifest('1.0.0');
      final loader = await runRescan(_devPlugin(devRootPath: devRoot.path));
      expect(loader.loaded, isEmpty);
    });

    test('אין manifest.json בתיקייה → נבלע בשקט', () async {
      final loader = await runRescan(_devPlugin(devRootPath: devRoot.path));
      expect(loader.loaded, isEmpty);
    });

    test('manifest שבור → נבלע בשקט', () async {
      File(
        path.join(devRoot.path, 'manifest.json'),
      ).writeAsStringSync('{ not json');
      final loader = await runRescan(_devPlugin(devRootPath: devRoot.path));
      expect(loader.loaded, isEmpty);
    });

    test('תוסף localhost_dev אינו נסרק — אין לו תיקייה', () async {
      writeManifest('2.0.0');
      final loader = await runRescan(
        _devPlugin(devRootPath: devRoot.path, sourceType: 'localhost_dev'),
      );
      expect(loader.loaded, isEmpty);
    });

    test('תוסף packaged אינו נסרק', () async {
      writeManifest('2.0.0');
      final loader = await runRescan(
        _devPlugin(devRootPath: devRoot.path, sourceType: 'packaged'),
      );
      expect(loader.loaded, isEmpty);
    });
  });
}
