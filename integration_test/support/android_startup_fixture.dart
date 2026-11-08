import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'android_startup_protocol.dart';
import 'perf_fixture.dart';

const _fixtureVersion = 'android-startup-v2';
const androidStartupHtml =
    '''<!doctype html><html lang="he" dir="rtl">
<meta charset="utf-8"><title>Android startup fixture</title>
<style>body{font:20px sans-serif;background:#fff;color:#111}</style>
<h1>מדידת פתיחת תוסף</h1><p>קלט מקומי קבוע, ללא רשת.</p>
<script>
const state = window.androidStartupFixture = {
  schemaVersion: 1, boots: 0, pluginId: null, runMode: null,
  documentToken: Date.now().toString(36) + '-' + Math.random().toString(36),
  sdkBooted: false, twoAnimationFrames: false, eventCount: 0, eventRunId: null
};
Otzaria.on('plugin.boot', function (payload) {
  state.boots++;
  state.pluginId = payload.plugin.id;
  state.runMode = payload.app.runMode;
  state.sdkBooted = window.Otzaria._booted === true;
  if (state.runMode === 'foreground') {
    requestAnimationFrame(() => requestAnimationFrame(() => {
      state.twoAnimationFrames = true;
    }));
  }
});
Otzaria.on('$androidStartupProbeEvent', function (payload) {
  state.eventCount++;
  state.eventRunId = payload.runId;
});
</script></html>''';

class AndroidStartupFixture {
  AndroidStartupFixture(this.root, {required this.enabledPlugin})
    : library = PerfFixture(Directory(p.join(root.path, 'library-fixture')));

  final Directory root;
  final bool enabledPlugin;
  final PerfFixture library;
  String get pluginPath => p.join(root.path, 'startup-plugin');
  File get _marker => File(p.join(root.path, 'startup-fixture.json'));
  File get _launches => File(p.join(root.path, 'launch-count.json'));
  late String identity;

  Map<String, dynamic> get manifestJson => {
    'schemaVersion': 1,
    'id': androidStartupProbePlugin,
    'name': 'מדידת Android מקומית',
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': [
      pluginStartupContributionsPermission,
      pluginRunOnStartupPermission,
    ],
    'network': {'enabled': false},
    'contributes': {
      'background': {'entrypoint': 'index.html'},
      'startup': {
        'activationEvents': [androidStartupProbeEvent],
      },
    },
  };

  Future<void> prepare() async {
    await _guardRoot();
    if (await root.exists() && !await root.list().isEmpty) {
      throw StateError('Preparation requires a new, empty probe fixture.');
    }
    await root.create(recursive: true);
    await library.prepare(preparationOnly: true);
    await Directory(pluginPath).create();
    await File(
      p.join(pluginPath, 'index.html'),
    ).writeAsString(androidStartupHtml);
    await _accessRegistry(prepare: true);
    identity = _identity();
    await _marker.writeAsString(
      jsonEncode({
        'version': _fixtureVersion,
        'identity': identity,
        'enabledPlugin': enabledPlugin,
      }),
      flush: true,
    );
    await _launches.writeAsString('0', flush: true);
  }

  Future<int> openForMeasurement({required String fixtureState}) async {
    await _guardRoot();
    if (await root.exists()) {
      await for (final entry in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is Link) {
          throw StateError('Probe fixture paths must not be symlinks.');
        }
      }
    }
    if (!await _marker.exists() || !await _launches.exists()) {
      throw StateError('Refusing to measure an unprepared startup fixture.');
    }
    final marker = jsonDecode(await _marker.readAsString()) as Map;
    if (marker['version'] != _fixtureVersion ||
        marker['enabledPlugin'] != enabledPlugin ||
        await File(p.join(pluginPath, 'index.html')).readAsString() !=
            androidStartupHtml) {
      throw StateError('The prepared startup fixture changed.');
    }
    await library.prepare(preparationOnly: false);
    identity = _identity();
    if (marker['identity'] != identity) {
      throw StateError('The startup fixture identity does not match.');
    }
    final count = jsonDecode(await _launches.readAsString());
    if (count is! int ||
        count < 0 ||
        (fixtureState == 'prepared'
            ? count != 0
            : fixtureState != 'reused' || count == 0)) {
      throw StateError(
        'Fixture reuse label does not match its launch history.',
      );
    }
    await _accessRegistry(prepare: false);
    await _launches.writeAsString(jsonEncode(count + 1), flush: true);
    return count;
  }

  Future<void> _accessRegistry({required bool prepare}) async {
    final dataPath = library.appDataPath;
    final databasesPath = p.join(library.root.path, 'databases');
    final installPath = pluginPath;
    final enabled = enabledPlugin;
    final manifestData = manifestJson;
    // Registry paths require Settings. Keep that initialization out of the
    // app isolate, which must still run its actual settings startup later.
    await Isolate.run(() async {
      AppPaths.configureDataRootPathForProcess(dataPath);
      try {
        await Settings.init(cacheProvider: HiveCache());
        if (Settings.getValue<String>(SettingsRepository.keyDatabasesPath) !=
            databasesPath) {
          throw StateError(
            'Fixture database settings point outside the fixture.',
          );
        }
        final repository = PluginRegistryRepository();
        final plugins = await repository.getAllPlugins();
        final manifest = PluginManifest.fromJson(manifestData);
        if (prepare) {
          if (plugins.isNotEmpty) {
            throw StateError(
              'A new startup fixture already has installed plugins.',
            );
          }
          if (enabled) {
            await repository.savePluginWithPermissions(
              InstalledPlugin(
                pluginId: manifest.id,
                name: manifest.name,
                version: manifest.version,
                installPath: installPath,
                entrypointPath: manifest.entrypoint,
                enabled: true,
                pinned: false,
                manifest: manifest,
                installedAt: DateTime.utc(2020),
                updatedAt: DateTime.utc(2020),
              ),
              {
                pluginStartupContributionsPermission: true,
                pluginRunOnStartupPermission: true,
              },
            );
          }
        } else if (enabled) {
          if (plugins.length != 1 ||
              plugins.single.pluginId != androidStartupProbePlugin ||
              !plugins.single.enabled ||
              plugins.single.installPath != installPath ||
              jsonEncode(plugins.single.manifest.toJson()) !=
                  jsonEncode(manifest.toJson())) {
            throw StateError(
              'The real plugin registry does not match the fixture.',
            );
          }
          for (final permission in [
            pluginStartupContributionsPermission,
            pluginRunOnStartupPermission,
          ]) {
            if (await repository.getPermission(
                  androidStartupProbePlugin,
                  permission,
                ) !=
                true) {
              throw StateError('A fixture background permission changed.');
            }
          }
        } else if (plugins.isNotEmpty || await repository.hasEnabledPlugin()) {
          throw StateError('The no-enabled-plugin control is not empty.');
        }
        if (!prepare) {
          // A forced stop can leave sessions in the configured or fallback DB.
          // Reset only restorable slots after validation, before measurement.
          for (final path in {
            p.join(databasesPath, 'user_state.db'),
            p.join(dataPath, 'databases', 'user_state.db'),
          }) {
            // Keep first-launch schema creation inside the measured app.
            if (!await File(path).exists()) continue;
            final state = sqlite3.open(path, mode: OpenMode.readWrite);
            try {
              state.execute('DELETE FROM window_sessions WHERE slot > 0');
            } finally {
              state.close();
            }
          }
        }
      } finally {
        await PluginSystemDatabase.instance.close();
        await Hive.close();
      }
    });
  }

  String _identity() => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'version': _fixtureVersion,
            'library': library.id,
            'html': sha256.convert(utf8.encode(androidStartupHtml)).toString(),
            'manifest': manifestJson,
            'enabledPlugin': enabledPlugin,
          }),
        ),
      )
      .toString();

  Future<void> _guardRoot() async {
    if (!p.isAbsolute(root.path)) {
      throw ArgumentError('Fixture root must be absolute.');
    }
    var current = root.absolute.path;
    while (true) {
      if (await FileSystemEntity.isLink(current)) {
        throw StateError('Fixture root or ancestor is a symlink.');
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }
}
