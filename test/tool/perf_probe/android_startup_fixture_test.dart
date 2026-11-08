import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../integration_test/support/android_startup_fixture.dart';
import '../../../integration_test/support/android_startup_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp(
      'android-startup-fixture-',
    ),
  );
  tearDown(() async {
    await PluginSystemDatabase.instance.close();
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    await temp.delete(recursive: true);
  });

  AndroidStartupFixture fixture(String name, {bool enabled = true}) =>
      AndroidStartupFixture(
        Directory(p.join(temp.path, name)),
        enabledPlugin: enabled,
      );

  List<String> userStatePaths(AndroidStartupFixture fixture) => [
    p.join(fixture.library.root.path, 'databases', 'user_state.db'),
    p.join(fixture.library.appDataPath, 'databases', 'user_state.db'),
  ];

  Future<void> withUserState(
    String path,
    Future<void> Function(UserStateDatabase database) body,
  ) async {
    await File(path).parent.create(recursive: true);
    final database = UserStateDatabase.openAt(path);
    try {
      await body(database);
    } finally {
      await database.flushWrites();
      database.close();
    }
  }

  test('first measured open does not create a user state database', () async {
    final prepared = fixture('first-launch');
    await prepared.prepare();
    for (final path in userStatePaths(prepared)) {
      expect(await File(path).exists(), isFalse);
    }
    expect(await prepared.openForMeasurement(fixtureState: 'prepared'), 0);
    for (final path in userStatePaths(prepared)) {
      expect(await File(path).exists(), isFalse);
    }
  });

  test(
    'reused fixture clears restorable windows but preserves other user data',
    () async {
      final prepared = fixture('reused-sessions');
      await prepared.prepare();
      final identity = prepared.identity;
      expect(await prepared.openForMeasurement(fixtureState: 'prepared'), 0);
      final tab = ToolTab(
        toolId: androidStartupProbePlugin,
        title: 'Restored fixture tool',
      );
      final tabsJson = jsonEncode([tab.toJson()]);
      tab.dispose();
      const history = [
        {'bookId': 42, 'line': 17},
      ];
      for (final path in userStatePaths(prepared)) {
        await withUserState(path, (database) async {
          final sessions = WindowSessionStore(database: database);
          for (final slot in [1, 8]) {
            await sessions.save(slot, tabsJson: tabsJson, currentIndex: 0);
          }
          await sessions.save(0, tabsJson: '[]', currentIndex: 7);
          final lists = UserStateListStore(database: database);
          try {
            await lists.write('history', 'books', history);
          } finally {
            lists.dispose();
          }
          expect((await sessions.loadAll()).map((s) => s.slot), [1, 8]);
        });
      }
      final cache = File(
        p.join(prepared.library.appDataPath, 'keep-cache.bin'),
      );
      await cache.writeAsBytes([2, 4, 8]);

      expect(await prepared.openForMeasurement(fixtureState: 'reused'), 1);
      expect(prepared.identity, identity);
      expect(await cache.readAsBytes(), [2, 4, 8]);
      expect(
        await File(
          p.join(prepared.root.path, 'launch-count.json'),
        ).readAsString(),
        '2',
      );
      for (final path in userStatePaths(prepared)) {
        await withUserState(path, (database) async {
          final sessions = WindowSessionStore(database: database);
          expect(await sessions.loadAll(), isEmpty, reason: path);
          final sentinel = await sessions.load(0);
          expect(sentinel!.tabsJson, '[]');
          expect(sentinel.currentIndex, 7);
          final lists = UserStateListStore(database: database);
          try {
            expect(await lists.read('history', 'books'), history);
          } finally {
            lists.dispose();
          }
        });
      }
      await Settings.init(cacheProvider: HiveCache());
      final repository = PluginRegistryRepository();
      final plugin = (await repository.getAllPlugins()).single;
      expect(plugin.pluginId, androidStartupProbePlugin);
      expect(plugin.enabled, isTrue);
      expect(plugin.installPath, prepared.pluginPath);
      for (final permission in [
        pluginStartupContributionsPermission,
        pluginRunOnStartupPermission,
      ]) {
        expect(
          await repository.getPermission(plugin.pluginId, permission),
          isTrue,
        );
      }
    },
  );

  test(
    'real registry is seeded before app startup and reopened without reseeding',
    () async {
      final prepared = fixture('enabled');
      final settingsBefore = Settings.isInitialized;
      await prepared.prepare();
      expect(Settings.isInitialized, settingsBefore);
      expect(PluginSystemDatabase.instance.openDatabase, isNull);
      final identity = prepared.identity;
      expect(await prepared.openForMeasurement(fixtureState: 'prepared'), 0);
      expect(Settings.isInitialized, settingsBefore);
      await Settings.init(cacheProvider: HiveCache());
      final repository = PluginRegistryRepository();
      expect(await repository.hasEnabledPlugin(), isTrue);
      final plugin = (await repository.getAllPlugins()).single;
      expect(plugin.pluginId, androidStartupProbePlugin);
      expect(plugin.installPath, prepared.pluginPath);
      expect(plugin.manifest.networkEnabled, isFalse);
      expect(plugin.manifest.startup!.activationEvents, [
        androidStartupProbeEvent,
      ]);
      expect(
        plugin.manifest.startup!.activationEvents,
        isNot(contains('app.startup')),
      );
      expect(
        await repository.getPermission(
          plugin.pluginId,
          pluginRunOnStartupPermission,
        ),
        isTrue,
      );
      expect(
        await repository.getPermission(
          plugin.pluginId,
          pluginStartupContributionsPermission,
        ),
        isTrue,
      );
      await PluginSystemDatabase.instance.close();
      await Hive.close();
      expect(PluginSystemDatabase.instance.openDatabase, isNull);
      expect(prepared.identity, identity);
      await expectLater(
        prepared.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      expect(await prepared.openForMeasurement(fixtureState: 'reused'), 1);
    },
  );

  test(
    'reused startup resets saved tabs while preserving fixture data',
    () async {
      final prepared = fixture('saved-session');
      await prepared.prepare();
      final identity = prepared.identity;
      final settingsBefore = Settings.isInitialized;
      expect(await prepared.openForMeasurement(fixtureState: 'prepared'), 0);
      final state = UserStateDatabase.openAt(
        p.join(prepared.library.root.path, 'databases', 'user_state.db'),
      );
      addTearDown(state.close);
      final sessions = WindowSessionStore(database: state);
      final savedTab = jsonEncode([
        {
          'type': 'ToolTab',
          'toolId': androidStartupProbePlugin,
          'title': 'Previous measured open',
          'instanceId': 'previous-measured-document',
          'isPinned': false,
          'allowMultipleInstances': false,
        },
      ]);
      await sessions.save(1, tabsJson: savedTab, currentIndex: 0);
      await sessions.save(2, tabsJson: savedTab, currentIndex: 0);
      expect((await sessions.load(1))!.tabsJson, savedTab);
      expect((await sessions.loadAll()).length, 2);
      final database = await state.database;
      database.execute(
        'INSERT INTO lists (box, key, payload_json, updated_at) VALUES (?, ?, ?, ?)',
        ['fixture-sentinel', 'preserved', '{"value":17}', 123],
      );
      state.close();
      final cache = File(p.join(prepared.library.appDataPath, 'cache', 'keep'));
      await cache.parent.create(recursive: true);
      await cache.writeAsString('retained fixture cache', flush: true);

      expect(await prepared.openForMeasurement(fixtureState: 'reused'), 1);
      expect(Settings.isInitialized, settingsBefore);
      expect(UserStateDatabase.instance.openDatabase, isNull);
      final reopened = await state.database;
      expect(await sessions.load(1), isNull);
      expect(await sessions.loadAll(), isEmpty);
      expect(
        reopened.select('SELECT * FROM lists').map((row) => Map.of(row)),
        [
          {
            'box': 'fixture-sentinel',
            'key': 'preserved',
            'payload_json': '{"value":17}',
            'updated_at': 123,
          },
        ],
      );
      expect(await cache.readAsString(), 'retained fixture cache');
      expect(prepared.identity, identity);
      expect(
        jsonDecode(
          await File(
            p.join(prepared.root.path, 'launch-count.json'),
          ).readAsString(),
        ),
        2,
      );
      await Settings.init(cacheProvider: HiveCache());
      final repository = PluginRegistryRepository();
      final plugin = (await repository.getAllPlugins()).single;
      expect(plugin.pluginId, androidStartupProbePlugin);
      expect(plugin.enabled, isTrue);
      expect(plugin.installPath, prepared.pluginPath);
      expect(
        plugin.manifest.toJson(),
        PluginManifest.fromJson(prepared.manifestJson).toJson(),
      );
      for (final permission in [
        pluginStartupContributionsPermission,
        pluginRunOnStartupPermission,
      ]) {
        expect(
          await repository.getPermission(plugin.pluginId, permission),
          isTrue,
        );
      }
    },
  );

  test('startup does not create a missing user-state database', () async {
    final prepared = fixture('missing-session');
    await prepared.prepare();
    final state = File(
      p.join(prepared.library.root.path, 'databases', 'user_state.db'),
    );
    expect(await state.exists(), isFalse);
    expect(await prepared.openForMeasurement(fixtureState: 'prepared'), 0);
    expect(await state.exists(), isFalse);
    expect(await prepared.openForMeasurement(fixtureState: 'reused'), 1);
    expect(await state.exists(), isFalse);
  });

  test('invalid saved state fails without advancing fixture history', () async {
    final prepared = fixture('invalid-session');
    await prepared.prepare();
    expect(await prepared.openForMeasurement(fixtureState: 'prepared'), 0);
    final state = File(
      p.join(prepared.library.root.path, 'databases', 'user_state.db'),
    );
    await state.writeAsString('invalid saved state', flush: true);
    await expectLater(
      prepared.openForMeasurement(fixtureState: 'reused'),
      throwsA(isA<SqliteException>()),
    );
    expect(await state.readAsString(), 'invalid saved state');
    expect(
      jsonDecode(
        await File(
          p.join(prepared.root.path, 'launch-count.json'),
        ).readAsString(),
      ),
      1,
    );
  });

  test(
    'no-enabled control has an empty actual registry and no permissions to wake',
    () async {
      final empty = fixture('empty-control', enabled: false);
      await empty.prepare();
      await Settings.init(cacheProvider: HiveCache());
      expect(await PluginRegistryRepository().hasEnabledPlugin(), isFalse);
      expect(await PluginRegistryRepository().getAllPlugins(), isEmpty);
      await PluginSystemDatabase.instance.close();
      await Hive.close();
      expect(await empty.openForMeasurement(fixtureState: 'prepared'), 0);
    },
  );

  test(
    'same fixture content has stable identity independent of paths',
    () async {
      final first = fixture('first-copy');
      final second = fixture('second-copy');
      await first.prepare();
      await second.prepare();
      expect(first.identity, second.identity);
      await expectLater(
        second.openForMeasurement(fixtureState: 'reused'),
        throwsStateError,
      );
      expect(await second.openForMeasurement(fixtureState: 'prepared'), 0);
    },
  );

  test(
    'unprepared or occupied directories are never seeded by a measured run',
    () async {
      final missing = fixture('missing');
      await expectLater(
        missing.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      expect(await missing.root.exists(), isFalse);
      final occupied = fixture('occupied');
      await occupied.root.create();
      final sentinel = File(p.join(occupied.root.path, 'keep.txt'));
      await sentinel.writeAsString('original');
      await expectLater(occupied.prepare(), throwsStateError);
      expect(await sentinel.readAsString(), 'original');
      expect(await occupied.root.list().length, 1);
    },
  );

  test(
    'changed plugin source and registry cannot masquerade as prepared input',
    () async {
      final changed = fixture('changed');
      await changed.prepare();
      final statePath = userStatePaths(changed).first;
      await withUserState(statePath, (database) async {
        await WindowSessionStore(
          database: database,
        ).save(1, tabsJson: '[]', currentIndex: 0);
      });
      final html = File(p.join(changed.pluginPath, 'index.html'));
      await html.writeAsString('changed');
      await expectLater(
        changed.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      expect(await html.readAsString(), 'changed');
      await html.writeAsString(androidStartupHtml);
      await Settings.init(cacheProvider: HiveCache());
      await PluginRegistryRepository().saveEnabledChoice(
        androidStartupProbePlugin,
        false,
      );
      await PluginSystemDatabase.instance.close();
      await Hive.close();
      await expectLater(
        changed.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      await withUserState(statePath, (database) async {
        expect(
          (await WindowSessionStore(database: database).loadAll()).map(
            (session) => session.slot,
          ),
          [1],
        );
      });
      expect(
        await File(
          p.join(changed.root.path, 'launch-count.json'),
        ).readAsString(),
        '0',
      );
    },
  );

  test(
    'old startup fixture version is rejected before session reset',
    () async {
      final prepared = fixture('old-version');
      await prepared.prepare();
      final statePath = userStatePaths(prepared).first;
      await withUserState(statePath, (database) async {
        await WindowSessionStore(
          database: database,
        ).save(1, tabsJson: '[]', currentIndex: 0);
      });
      final marker = File(p.join(prepared.root.path, 'startup-fixture.json'));
      final data = jsonDecode(await marker.readAsString()) as Map;
      data['version'] = 'android-startup-v1';
      await marker.writeAsString(jsonEncode(data));
      await expectLater(
        prepared.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      await withUserState(statePath, (database) async {
        expect(await WindowSessionStore(database: database).load(1), isNotNull);
      });
      expect(
        await File(
          p.join(prepared.root.path, 'launch-count.json'),
        ).readAsString(),
        '0',
      );
    },
  );

  test(
    'changed settings cannot redirect registry writes outside the fixture',
    () async {
      final prepared = fixture('changed-settings');
      await prepared.prepare();
      final outside = await Directory(
        p.join(temp.path, 'outside-databases'),
      ).create();
      await Settings.init(cacheProvider: HiveCache());
      await Settings.setValue(
        SettingsRepository.keyDatabasesPath,
        outside.path,
      );
      await Hive.close();
      await expectLater(
        prepared.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      expect(await outside.list().isEmpty, isTrue);
    },
  );

  test(
    'symlinked root and ancestor do not lead the fixture outside its path',
    () async {
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      final link = Link(p.join(temp.path, 'linked'));
      await link.create(outside.path);
      await expectLater(fixture('linked').prepare(), throwsStateError);
      final nested = AndroidStartupFixture(
        Directory(p.join(link.path, 'nested')),
        enabledPlugin: true,
      );
      await expectLater(nested.prepare(), throwsStateError);
      expect(await outside.list().isEmpty, isTrue);
    },
  );

  test(
    'nested symlinks are rejected before any fixture data is opened',
    () async {
      final prepared = fixture('nested-link');
      await prepared.prepare();
      final external = File(p.join(temp.path, 'external.html'));
      await external.writeAsString(androidStartupHtml);
      final html = File(p.join(prepared.pluginPath, 'index.html'));
      await html.delete();
      await Link(html.path).create(external.path);
      await expectLater(
        prepared.openForMeasurement(fixtureState: 'prepared'),
        throwsStateError,
      );
      expect(await external.readAsString(), androidStartupHtml);
      expect(PluginSystemDatabase.instance.openDatabase, isNull);
    },
  );

  test(
    'fixture readiness follows the real SDK boot and background event',
    () async {
      final script = RegExp(
        r'<script>([\s\S]*?)</script>',
      ).firstMatch(androidStartupHtml)!.group(1)!;
      final inputs = [
        for (final mode in ['foreground', 'background'])
          {
            'mode': mode,
            'stub': mode == 'background'
                ? pluginBackgroundSdkStubScript
                : pluginSdkStubScript,
            'fixture': script,
            'boot': buildPluginBootScript(
              nonceJson: jsonEncode('test-nonce'),
              payloadJson: jsonEncode({
                'plugin': {'id': androidStartupProbePlugin},
                'app': {'runMode': mode},
              }),
            ),
            'topic': androidStartupProbeEvent,
          },
      ];
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
for (const input of JSON.parse(process.argv[1])) {
  const listeners = new Map(), frames = [];
  const context = vm.createContext({console, setTimeout, clearTimeout});
  context.window = context;
  context.CustomEvent = class {constructor(type, options) {this.type = type; this.detail = options.detail;}};
  context.addEventListener = (type, callback) => {
    if (!listeners.has(type)) listeners.set(type, []);
    listeners.get(type).push(callback);
  };
  context.removeEventListener = () => {};
  context.dispatchEvent = event => (listeners.get(event.type) || []).forEach(callback => callback(event));
  context.requestAnimationFrame = callback => {
    assert.equal(input.mode, 'foreground');
    frames.push(callback);
  };
  vm.runInContext(input.stub, context);
  vm.runInContext(input.fixture, context);
  const state = context.androidStartupFixture;
  assert.equal(state.sdkBooted, false);
  assert.equal(state.boots, 0);
  assert.equal(state.twoAnimationFrames, false);
  vm.runInContext(input.boot, context);
  assert.equal(state.sdkBooted, true);
  assert.equal(state.boots, 1);
  assert.equal(state.runMode, input.mode);
  assert.equal(state.pluginId, 'org.otzaria.android-startup-fixture');
  if (input.mode === 'foreground') {
    assert.equal(state.twoAnimationFrames, false);
    frames.shift()();
    assert.equal(state.twoAnimationFrames, false);
    frames.shift()();
    assert.equal(state.twoAnimationFrames, true);
  } else {
    assert.equal(frames.length, 0);
    assert.equal(state.eventCount, 0);
    context.dispatchEvent(new context.CustomEvent(input.topic, {detail: {runId: 'own-run'}}));
    assert.equal(state.eventCount, 1);
    assert.equal(state.eventRunId, 'own-run');
  }
}
''',
        jsonEncode(inputs),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
