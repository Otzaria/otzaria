import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

class _FakeRepo implements PluginRegistryRepository {
  final Map<String, String> kv = {};

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv['$pluginId|$namespace|$key'];

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async => {
    for (final key in keys)
      if (kv['$pluginId|$namespace|$key'] != null)
        key: kv['$pluginId|$namespace|$key']!,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _darkModeWhen({bool equals = true}) => {
  'setting': {'key': SettingsRepository.keyDarkMode, 'equals': equals},
};

void main() {
  late Map<String, Object?> settings;
  late PluginConditionEvaluator evaluator;
  late _FakeRepo repo;

  setUp(() {
    settings = {};
    repo = _FakeRepo();
    evaluator = PluginConditionEvaluator.forTesting(
      settingReader: (key) => settings[key],
    );
  });

  group('PluginToolbarRegistry', () {
    late PluginToolbarRegistry registry;

    setUp(() {
      registry = PluginToolbarRegistry.forTesting(evaluator: evaluator);
      registry.registerPayload('p1', {
        'id': 'b1',
        'title': 'כפתור',
        'icon': 'apps_24_regular',
        'when': _darkModeWhen(),
      });
    });

    test('מסנן פריט שהתנאי שלו אינו מתקיים', () {
      expect(registry.getAll(), isEmpty);

      settings[SettingsRepository.keyDarkMode] = true;
      expect(registry.getAll().single.$2.id, 'b1');
    });

    test('שינוי הגדרה מעביר notifyListeners דרך ה-registry', () {
      var notifications = 0;
      registry.addListener(() => notifications++);

      settings[SettingsRepository.keyDarkMode] = true;
      evaluator.notifySettingsChanged();

      expect(notifications, 1);
      expect(registry.getAll(), hasLength(1));
    });

    test('update שומר את התנאי דרך toJson', () {
      final updated = registry.update('p1', 'b1', {'title': 'חדש'});

      expect(updated.when, isNotNull);
      expect(updated.when!.settingKeys, {SettingsRepository.keyDarkMode});
    });

    test('when על פריט-ילד נדחה', () {
      expect(
        () => registry.registerPayload('p1', {
          'id': 'm1',
          'title': 'תפריט',
          'icon': 'apps_24_regular',
          'type': 'menu',
          'children': [
            {'id': 'c1', 'title': 'ילד', 'when': _darkModeWhen()},
          ],
        }),
        throwsA(isA<PluginToolbarException>()),
      );
    });

    test('when לא תקין דוחה את הפריט כולו', () {
      expect(
        () => registry.registerPayload('p1', {
          'id': 'b2',
          'title': 'כפתור',
          'icon': 'apps_24_regular',
          'when': {'setting': 'לא אובייקט'},
        }),
        throwsA(isA<PluginToolbarException>()),
      );
    });
  });

  group('רישום דינמי בזמן ריצה (מסלול הגשר)', () {
    test(
      'פריט עם תנאי storage מגיב ל-storage.set אחרי trackStorageKeys',
      () async {
        final registry = PluginToolbarRegistry.forTesting(evaluator: evaluator);
        registry.registerPayload('p1', {
          'id': 'b1',
          'title': 'כפתור',
          'icon': 'apps_24_regular',
          'when': {
            'storage': {'key': 'showButton', 'equals': 'yes'},
          },
        });
        // הגשר רושם את מפתחות ה-when של הפריט הנרשם.
        await evaluator.trackStorageKeys('p1', {'showButton'}, repo);

        expect(registry.getAll(), isEmpty);

        evaluator.onStorageValueChanged('p1', 'showButton', 'yes');

        expect(registry.getAll().single.$2.id, 'b1');
      },
    );
  });

  group('ContextMenuRegistry', () {
    late ContextMenuRegistry registry;

    setUp(() {
      registry = ContextMenuRegistry.forTesting(evaluator: evaluator);
      registry.registerPayload('p1', {
        'id': 'm1',
        'title': 'פריט',
        'when': _darkModeWhen(),
        'showWhen': {
          'selectionContainsAny': ['רש"י'],
        },
      });
    });

    test('when מצטרף ל-showWhen ב-AND', () {
      expect(registry.getAll(), isEmpty);

      settings[SettingsRepository.keyDarkMode] = true;
      final entries = buildPluginContextMenuEntries(
        records: registry.getAll(),
        selection: const {'text': 'דברי רש"י כאן'},
      );
      expect(entries, hasLength(1));

      final withoutWord = buildPluginContextMenuEntries(
        records: registry.getAll(),
        selection: const {'text': 'טקסט אחר'},
      );
      expect(withoutWord, isEmpty);
    });

    test('when על פריט-ילד נדחה', () {
      expect(
        () => registry.registerPayload('p1', {
          'id': 'm2',
          'type': 'submenu',
          'title': 'תת-תפריט',
          'children': [
            {'id': 'c1', 'title': 'ילד', 'when': _darkModeWhen()},
          ],
        }),
        throwsA(isA<PluginContextMenuException>()),
      );
    });
  });

  group('PluginSearchDialogRegistry', () {
    late PluginSearchDialogRegistry registry;

    setUp(() {
      registry = PluginSearchDialogRegistry.forTesting(evaluator: evaluator);
      registry.registerPayload('p1', {
        'id': 'row',
        'type': 'checkbox',
        'title': 'שורה',
        'when': {
          'storage': {'key': 'showRow', 'equals': 'yes'},
        },
      });
    });

    test('שורה מסוננת עד שערך האחסון מתאים', () async {
      expect(registry.getAll(), isEmpty);

      repo.kv['p1|default|showRow'] = jsonEncode('yes');
      await evaluator.registerStorageKeys('p1', {'showRow'}, repo);

      expect(registry.getAll().single.$2.id, 'row');
    });

    test('עדכון חי של האחסון מעביר notifyListeners', () async {
      await evaluator.registerStorageKeys('p1', {'showRow'}, repo);
      var notifications = 0;
      registry.addListener(() => notifications++);

      evaluator.onStorageValueChanged('p1', 'showRow', 'yes');

      expect(notifications, 1);
      expect(registry.getAll(), hasLength(1));
    });

    test('when לא תקין דוחה את השורה', () {
      expect(
        () => registry.registerPayload('p1', {
          'id': 'bad',
          'type': 'checkbox',
          'title': 'שורה',
          'when': {'storage': {}},
        }),
        throwsA(isA<PluginSearchDialogItemException>()),
      );
    });
  });
}
