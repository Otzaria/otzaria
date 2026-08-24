import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';

class _FakeRepo implements PluginRegistryRepository {
  final Map<String, Set<String>> grantedByPlugin = {};
  final List<PluginPublishedRecord> records = [];
  final Map<String, String> kv = {};
  int publishCalls = 0;

  String _kvKey(String pluginId, String namespace, String key) =>
      '$pluginId|$namespace|$key';

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async => [
    for (final permission in grantedByPlugin[id] ?? const <String>{})
      PluginPermissionGrant(
        pluginId: id,
        permission: permission,
        granted: true,
        grantedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async =>
      withBaselinePermissions(grantedByPlugin[id] ?? const <String>{});

  @override
  Future<void> publishRecord(
    String pluginId,
    String type,
    String scope,
    String recordKey,
    String payloadJson,
    String? expiresAt,
  ) async {
    publishCalls++;
    records.removeWhere(
      (r) =>
          r.pluginId == pluginId &&
          r.type == type &&
          r.scope == scope &&
          r.key == recordKey,
    );
    records.add(
      PluginPublishedRecord(
        pluginId: pluginId,
        type: type,
        scope: scope,
        key: recordKey,
        payloadJson: payloadJson,
        version: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  }

  @override
  Future<void> unpublishRecord(
    String pluginId,
    String type,
    String scope,
    String recordKey,
  ) async {
    records.removeWhere(
      (r) =>
          r.pluginId == pluginId &&
          r.type == type &&
          r.scope == scope &&
          r.key == recordKey,
    );
  }

  @override
  Future<List<PluginPublishedRecord>> getPluginPublishedRecords(
    String pluginId,
  ) async => records.where((r) => r.pluginId == pluginId).toList();

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv[_kvKey(pluginId, namespace, key)];

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async => {
    for (final key in keys)
      if (kv[_kvKey(pluginId, namespace, key)] != null)
        key: kv[_kvKey(pluginId, namespace, key)]!,
  };

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    kv[_kvKey(pluginId, namespace, key)] = valueJson;
  }

  @override
  Future<void> removeKV(String pluginId, String namespace, String key) async {
    kv.remove(_kvKey(pluginId, namespace, key));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

InstalledPlugin _plugin({
  String id = 'p1',
  bool enabled = true,
  Map<String, dynamic>? startup,
}) {
  final manifest = PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': 'Test',
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': const <String>[],
    'contributes': {'startup': ?startup},
  });
  return InstalledPlugin(
    pluginId: id,
    name: 'Test',
    version: '1.0.0',
    installPath: '/plugins/$id',
    entrypointPath: 'index.html',
    enabled: enabled,
    pinned: false,
    manifest: manifest,
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

Map<String, dynamic> _fullStartup() => {
  'toolbarItems': [
    {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
  ],
  'contextMenuItems': [
    {'id': 'm1', 'title': 'פריט'},
  ],
  'publishedData': [
    {
      'type': 'calendar.event',
      'key': 'k1',
      'payload': {'title': 'אירוע'},
    },
  ],
  'activationEvents': ['reader.sectionContentChanged'],
  'searchDialogItems': [
    {
      'id': 'include-external',
      'type': 'checkbox',
      'title': 'חפש גם במקור חיצוני',
      'visibleInModes': ['exact'],
    },
  ],
};

const _allPermissions = {
  'app.startup_contributions',
  'reader.toolbar',
  'reader.context_menu',
  'published_data.write',
  'search.dialog',
  'events.subscribe:reader.sectionContentChanged',
};

void main() {
  late PluginToolbarRegistry toolbar;
  late ContextMenuRegistry contextMenu;
  late PluginLazyActivationService activation;
  late PluginSearchDialogRegistry searchDialog;
  late PluginExternalEditionsRegistry externalEditions;
  late PluginStartupContributionsService service;
  late _FakeRepo repo;

  setUp(() {
    toolbar = PluginToolbarRegistry.forTesting();
    contextMenu = ContextMenuRegistry.forTesting();
    activation = PluginLazyActivationService.forTesting();
    searchDialog = PluginSearchDialogRegistry.forTesting();
    externalEditions = PluginExternalEditionsRegistry.detached();
    service = PluginStartupContributionsService.forTesting(
      toolbarRegistry: toolbar,
      contextMenuRegistry: contextMenu,
      activationService: activation,
      searchDialogRegistry: searchDialog,
      externalEditionsRegistry: externalEditions,
    );
    repo = _FakeRepo();
  });

  test('registers all contributions when permissions are granted', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};

    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(toolbar.getAll().single.$2.id, 'b1');
    expect(contextMenu.getAll().single.$2.id, 'm1');
    expect(searchDialog.getAll().single.$2.id, 'include-external');
    final record = repo.records.single;
    expect(record.key, 'manifest:k1');
    expect(jsonDecode(record.payloadJson), {'title': 'אירוע'});
    expect(
      activation.queueTargetedEvent('p1', 'click', {}),
      isFalse,
      reason: 'בלי app.run_on_startup אין הערה שקטה — לחיצה תפתח את הדף',
    );
  });

  group('externalEditions', () {
    InstalledPlugin editionsPlugin({List<String> permissions = const []}) {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'p1',
        'name': 'Test',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'permissions': permissions,
        'contributes': {
          'databaseSources': [
            {'id': 'mapping_source', 'label': 'מיפוי', 'required': true},
          ],
          'startup': {
            'externalEditions': [
              {
                'id': 'editions-1',
                'provider': 'extlib',
                'sourceId': 'mapping_source',
                'table': 'mapping',
                'externalIdColumn': 'ext_id',
                'otzariaIdColumn': 'otzaria_id',
              },
            ],
          },
        },
      });
      return InstalledPlugin(
        pluginId: 'p1',
        name: 'Test',
        version: '1.0.0',
        installPath: '/plugins/p1',
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: manifest,
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
    }

    const editionsPermissions = {
      'app.startup_contributions',
      'database.read',
      'library.books.read',
    };

    test('נרשם עם שתי ההרשאות ומוסר כשאחת נשללת', () async {
      repo.grantedByPlugin['p1'] = {...editionsPermissions};
      await service.sync([editionsPlugin()], repo);
      expect(externalEditions.configs, hasLength(1));
      final config = externalEditions.configs.single;
      expect(config.provider, 'extlib');
      expect(config.table, 'mapping');
      expect(config.plugin.pluginId, 'p1');

      // שלילת database.read מסירה את הרישום בסנכרון הבא.
      repo.grantedByPlugin['p1'] = {
        'app.startup_contributions',
        'library.books.read',
      };
      await service.sync([editionsPlugin()], repo);
      expect(externalEditions.configs, isEmpty);
    });

    test('הסרת התוסף מסירה את הרישום', () async {
      repo.grantedByPlugin['p1'] = {...editionsPermissions};
      await service.sync([editionsPlugin()], repo);
      expect(externalEditions.configs, hasLength(1));

      await service.sync(const [], repo);
      expect(externalEditions.configs, isEmpty);
    });
  });

  test('lazy activation requires the app.run_on_startup permission', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions, 'app.run_on_startup'};

    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(activation.queueTargetedEvent('p1', 'click', {}), isTrue);

    repo.grantedByPlugin['p1'] = {..._allPermissions};
    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(
      activation.queueTargetedEvent('p1', 'click', {}),
      isFalse,
      reason: 'שלילת ההרשאה מבטלת את יכולת ההערה',
    );
    expect(toolbar.getAll(), hasLength(1), reason: 'הרישומים נשארים');
  });

  test('without app.startup_contributions nothing is registered', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions}
      ..remove('app.startup_contributions');

    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(toolbar.getAll(), isEmpty);
    expect(contextMenu.getAll(), isEmpty);
    expect(searchDialog.getAll(), isEmpty);
    expect(repo.records, isEmpty);
    expect(activation.queueTargetedEvent('p1', 'click', {}), isFalse);
  });

  test('each category is gated by its domain permission', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions}..remove('reader.toolbar');

    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(toolbar.getAll(), isEmpty);
    expect(contextMenu.getAll(), hasLength(1));
    expect(repo.records, hasLength(1));
    expect(searchDialog.getAll(), hasLength(1));
  });

  test('revoking the permission on a later sync removes everything', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    final plugin = _plugin(startup: _fullStartup());
    await service.sync([plugin], repo);
    expect(toolbar.getAll(), hasLength(1));

    repo.grantedByPlugin['p1'] = {};
    await service.sync([plugin], repo);

    expect(toolbar.getAll(), isEmpty);
    expect(contextMenu.getAll(), isEmpty);
    expect(searchDialog.getAll(), isEmpty);
    expect(repo.records, isEmpty);
    expect(searchDialog.getAll(), isEmpty);
  });

  test('a disabled plugin contributes nothing', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};

    await service.sync([
      _plugin(startup: _fullStartup(), enabled: false),
    ], repo);

    expect(toolbar.getAll(), isEmpty);
    expect(repo.records, isEmpty);
    expect(searchDialog.getAll(), isEmpty);
  });

  test('an uninstalled plugin is cleaned up on the next sync', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    await service.sync([_plugin(startup: _fullStartup())], repo);
    expect(toolbar.getAll(), hasLength(1));

    await service.sync(const [], repo);

    expect(toolbar.getAll(), isEmpty);
    expect(repo.records, isEmpty);
  });

  test('a plugin update removes stale items and seeded records', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    await service.sync([_plugin(startup: _fullStartup())], repo);

    final updated = _plugin(
      startup: {
        'toolbarItems': [
          {'id': 'b2', 'title': 'חדש', 'icon': 'apps_24_regular'},
        ],
        'publishedData': [
          {
            'type': 'calendar.event',
            'key': 'k2',
            'payload': {'title': 'אחר'},
          },
        ],
      },
    );
    await service.sync([updated], repo);

    expect(toolbar.getAll().single.$2.id, 'b2');
    expect(contextMenu.getAll(), isEmpty);
    expect(searchDialog.getAll(), isEmpty);
    expect(repo.records.single.key, 'manifest:k2');
  });

  test('replacing both declarative items with new ids succeeds', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    Map<String, dynamic> pair(String a, String b) => {
      'toolbarItems': [
        {'id': a, 'title': a, 'icon': 'apps_24_regular'},
        {'id': b, 'title': b, 'icon': 'apps_24_regular'},
      ],
    };

    await service.sync([_plugin(startup: pair('a1', 'a2'))], repo);
    await service.sync([_plugin(startup: pair('b1', 'b2'))], repo);

    expect(
      toolbar.getAll().map((record) => record.$2.id).toSet(),
      {'b1', 'b2'},
    );
  });

  test('an unchanged publishedData seed is not rewritten', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    final plugin = _plugin(startup: _fullStartup());

    await service.sync([plugin], repo);
    expect(repo.publishCalls, 1);

    await service.sync([plugin], repo);
    await service.sync([plugin], repo);
    expect(repo.publishCalls, 1, reason: 'תוכן זהה — אסור לכתוב שוב');
  });

  test('corrupt ownership metadata does not abort contribution sync', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    repo.kv['p1|otzaria.startup|published-records'] = 'not-json';

    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(toolbar.getAll(), hasLength(1));
    expect(repo.records.single.key, 'manifest:k1');
    expect(repo.kv['p1|otzaria.startup|published-records'], isNot('not-json'));
  });

  test('runtime (non-seeded) published records are never touched', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    await repo.publishRecord(
      'p1',
      'calendar.event',
      'global',
      'runtime-key',
      '{}',
      null,
    );

    await service.sync([_plugin(startup: _fullStartup())], repo);
    repo.grantedByPlugin['p1'] = {};
    await service.sync([_plugin(startup: _fullStartup())], repo);

    expect(repo.records.single.key, 'runtime-key');
  });

  test(
    'a runtime record with the manifest prefix is not treated as owned',
    () async {
      repo.grantedByPlugin['p1'] = {..._allPermissions};
      await repo.publishRecord(
        'p1',
        'calendar.event',
        'global',
        'manifest:runtime-key',
        '{}',
        null,
      );

      await service.sync([_plugin(startup: _fullStartup())], repo);
      repo.grantedByPlugin['p1'] = {};
      await service.sync([_plugin(startup: _fullStartup())], repo);

      expect(repo.records.single.key, 'manifest:runtime-key');
    },
  );

  test(
    'keepAlive applies only when its independent grant is present',
    () async {
      activation.idleDelayOverride = const Duration(milliseconds: 30);
      final deactivations = <String>[];
      activation.backgroundDeactivator = deactivations.add;
      final startup = {
        'toolbarItems': [
          {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
        ],
        'keepAlive': true,
      };

      repo.grantedByPlugin['p1'] = {
        'app.startup_contributions',
        'app.run_on_startup',
        'reader.toolbar',
      };
      await service.sync([_plugin(startup: startup)], repo);
      activation.trackIdleTeardown('p1');
      await activation.onBackgroundInstanceReady('p1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
      activation.onBackgroundInstanceClosed('p1');

      repo.grantedByPlugin['p2'] = {
        'app.startup_contributions',
        'app.run_on_startup',
        'app.background_keep_alive',
        'reader.toolbar',
      };
      await service.sync([_plugin(id: 'p2', startup: startup)], repo);
      activation.trackIdleTeardown('p2');
      await activation.onBackgroundInstanceReady('p2');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
    },
  );

  test(
    'app.startup activation requires the app.run_on_startup permission',
    () async {
      var startupScheduled = false;
      activation.backgroundActivator = (_) async {
        startupScheduled = true;
      };
      activation.startupDelayOverride = Duration.zero;
      final startup = {
        'toolbarItems': [
          {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
        ],
        'activationEvents': ['app.startup'],
      };

      repo.grantedByPlugin['p1'] = {
        'app.startup_contributions',
        'reader.toolbar',
      }; // בכוונה בלי app.run_on_startup
      await service.sync([_plugin(startup: startup)], repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(startupScheduled, isFalse, reason: 'בלי ההרשאה הרגישה אין הערה');
      expect(toolbar.getAll(), hasLength(1), reason: 'הרישומים כן חלים');

      repo.grantedByPlugin['p2'] = {
        'app.startup_contributions',
        'app.run_on_startup',
      };
      await service.sync(
        [
          _plugin(
            id: 'p2',
            startup: {
              'activationEvents': ['app.startup'],
            },
          ),
        ],
        repo,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(startupScheduled, isTrue);
    },
  );

  test('an invalid item is skipped without breaking the rest', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    final startup = _fullStartup();
    (startup['toolbarItems'] as List).insert(0, {
      'id': 'bad',
    }); // חסר title+icon

    await service.sync([_plugin(startup: startup)], repo);

    expect(toolbar.getAll().single.$2.id, 'b1');
    expect(contextMenu.getAll(), hasLength(1));
  });

  test('פקד Host דקלרטיבי אינו נרשם במסלול ה-toolbar הישן', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};

    await service.sync([
      _plugin(
        startup: {
          'toolbarItems': [
            {
              'id': 'host-only',
              'title': 'Host',
              'icon': 'book_24_regular',
              'binding': {
                'program': 'links',
                'visibleOutput': 'book',
              },
              'action': {
                'type': 'reader.openBook',
                'args': {
                  'identity': {r'$output': 'book'},
                },
              },
            },
          ],
        },
      ),
    ], repo);

    expect(toolbar.getAll(), isEmpty);
  });

  test('revoking search.dialog removes only the static search row', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    final plugin = _plugin(startup: _fullStartup());
    await service.sync([plugin], repo);
    expect(searchDialog.getAll(), hasLength(1));

    repo.grantedByPlugin['p1'] = {..._allPermissions}..remove('search.dialog');
    await service.sync([plugin], repo);

    expect(searchDialog.getAll(), isEmpty);
    expect(toolbar.getAll(), hasLength(1));
    expect(contextMenu.getAll(), hasLength(1));
  });

  test('reapply restores declarative items after a registry wipe', () async {
    repo.grantedByPlugin['p1'] = {..._allPermissions};
    await service.sync([_plugin(startup: _fullStartup())], repo);

    toolbar.removeAll('p1');
    contextMenu.removeAll('p1');
    searchDialog.removeAll('p1');
    service.reapply('p1');

    expect(toolbar.getAll(), hasLength(1));
    expect(contextMenu.getAll(), hasLength(1));
    expect(searchDialog.getAll(), hasLength(1));
  });

  group('רישום מפתחות האחסון של תנאי when', () {
    late PluginConditionEvaluator evaluator;
    late PluginToolbarRegistry conditionalToolbar;
    late PluginStartupContributionsService conditionalService;

    Map<String, dynamic> startupWithWhen() => {
      'toolbarItems': [
        {
          'id': 'b1',
          'title': 'כפתור',
          'icon': 'apps_24_regular',
          'when': {
            'storage': {'key': 'showButton', 'equals': 'yes'},
          },
        },
      ],
    };

    setUp(() {
      evaluator = PluginConditionEvaluator.forTesting();
      conditionalToolbar = PluginToolbarRegistry.forTesting(
        evaluator: evaluator,
      );
      conditionalService = PluginStartupContributionsService.forTesting(
        toolbarRegistry: conditionalToolbar,
        contextMenuRegistry: ContextMenuRegistry.forTesting(
          evaluator: evaluator,
        ),
        activationService: PluginLazyActivationService.forTesting(),
        searchDialogRegistry: PluginSearchDialogRegistry.forTesting(
          evaluator: evaluator,
        ),
        externalEditionsRegistry: PluginExternalEditionsRegistry.detached(),
        conditionEvaluator: evaluator,
      );
    });

    test('הסנכרון טוען את ערך המפתח ומכריע את התצוגה', () async {
      repo.grantedByPlugin['p1'] = {..._allPermissions};
      repo.kv['p1|default|showButton'] = jsonEncode('yes');

      await conditionalService.sync([
        _plugin(startup: startupWithWhen()),
      ], repo);

      expect(conditionalToolbar.getAll(), hasLength(1));
    });

    test('מפתח חסר ב-KV מסתיר את הפריט', () async {
      repo.grantedByPlugin['p1'] = {..._allPermissions};

      await conditionalService.sync([
        _plugin(startup: startupWithWhen()),
      ], repo);

      expect(conditionalToolbar.getAll(), isEmpty);
      evaluator.onStorageValueChanged('p1', 'showButton', 'yes');
      expect(conditionalToolbar.getAll(), hasLength(1));
    });

    test('הסרת התוסף מנקה את הרישום ב-evaluator', () async {
      repo.grantedByPlugin['p1'] = {..._allPermissions};
      repo.kv['p1|default|showButton'] = jsonEncode('yes');
      await conditionalService.sync([
        _plugin(startup: startupWithWhen()),
      ], repo);

      await conditionalService.sync([], repo);

      evaluator.onStorageValueChanged('p1', 'showButton', 'yes');
      expect(
        evaluator.evaluate(
          'p1',
          PluginWhenCondition.fromJson({
            'storage': {'key': 'showButton', 'equals': 'yes'},
          }),
        ),
        isFalse,
      );
    });
  });

  group('תנאי when על activationEvents', () {
    late PluginConditionEvaluator evaluator;
    late PluginLazyActivationService conditionalActivation;
    late PluginStartupContributionsService conditionalService;

    Map<String, dynamic> startupWithGatedEvent() => {
      'toolbarItems': [
        {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
      ],
      'activationEvents': [
        {
          'topic': 'reader.sectionContentChanged',
          'when': {
            'storage': {'key': 'listen', 'equals': 'yes'},
          },
        },
      ],
    };

    setUp(() {
      evaluator = PluginConditionEvaluator.forTesting();
      conditionalActivation = PluginLazyActivationService.forTesting(
        conditionEvaluator: evaluator,
      );
      conditionalService = PluginStartupContributionsService.forTesting(
        toolbarRegistry: PluginToolbarRegistry.forTesting(
          evaluator: evaluator,
        ),
        contextMenuRegistry: ContextMenuRegistry.forTesting(
          evaluator: evaluator,
        ),
        activationService: conditionalActivation,
        searchDialogRegistry: PluginSearchDialogRegistry.forTesting(
          evaluator: evaluator,
        ),
        externalEditionsRegistry: PluginExternalEditionsRegistry.detached(),
        conditionEvaluator: evaluator,
      );
      repo.grantedByPlugin['p1'] = {..._allPermissions, 'app.run_on_startup'};
    });

    test('מפתח האחסון של האירוע נטען והתנאי חוסם הערה', () async {
      await conditionalService.sync([
        _plugin(startup: startupWithGatedEvent()),
      ], repo);

      expect(
        conditionalActivation.queueTargetedEvent(
          'p1',
          'reader.sectionContentChanged',
          {},
        ),
        isFalse,
      );

      // המפתח נרשם למעקב בסנכרון, ולכן עדכון חי מהגשר מהפך את התוצאה.
      evaluator.onStorageValueChanged('p1', 'listen', 'yes');
      expect(
        conditionalActivation.queueTargetedEvent(
          'p1',
          'reader.sectionContentChanged',
          {},
        ),
        isTrue,
      );
    });

    test('ערך קיים ב-KV מאפשר הערה מיד', () async {
      repo.kv['p1|default|listen'] = jsonEncode('yes');

      await conditionalService.sync([
        _plugin(startup: startupWithGatedEvent()),
      ], repo);

      expect(
        conditionalActivation.queueTargetedEvent(
          'p1',
          'reader.sectionContentChanged',
          {},
        ),
        isTrue,
      );
    });
  });
}
