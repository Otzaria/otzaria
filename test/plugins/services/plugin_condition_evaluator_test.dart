import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

class _FakeRepo implements PluginRegistryRepository {
  final Map<String, String> kv = {};

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv['$pluginId|$namespace|$key'];

  int bulkCalls = 0;

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async {
    bulkCalls++;
    return {
      for (final key in keys)
        if (kv['$pluginId|$namespace|$key'] != null)
          key: kv['$pluginId|$namespace|$key']!,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PluginWhenCondition _when(Object json) => PluginWhenCondition.fromJson(json);

void main() {
  late Map<String, Object?> settings;
  late PluginConditionEvaluator evaluator;
  late _FakeRepo repo;
  late int notifications;

  setUp(() {
    settings = {};
    repo = _FakeRepo();
    evaluator = PluginConditionEvaluator.forTesting(
      settingReader: (key) => settings[key],
    );
    notifications = 0;
    evaluator.addListener(() => notifications++);
  });

  group('הגדרות תוכנה', () {
    test('מפתח ב-allowlist מוערך מול הערך בפועל', () {
      settings[SettingsRepository.keyDarkMode] = true;

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'setting': {'key': SettingsRepository.keyDarkMode, 'equals': true},
          }),
        ),
        isTrue,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'setting': {'key': SettingsRepository.keyDarkMode, 'equals': false},
          }),
        ),
        isFalse,
      );
    });

    test('מפתח שאינו ב-allowlist מוערך כ-false גם ב-notEquals', () {
      settings[SettingsRepository.keyLibraryPath] = 'C:/books';

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'setting': {
              'key': SettingsRepository.keyLibraryPath,
              'equals': 'C:/books',
            },
          }),
        ),
        isFalse,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'setting': {
              'key': SettingsRepository.keyLibraryPath,
              'notEquals': 'x',
            },
          }),
        ),
        isFalse,
      );
    });

    test('exists מבחין בין הגדרה קיימת לחסרה', () {
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'setting': {'key': SettingsRepository.keyFontSize, 'exists': false},
          }),
        ),
        isTrue,
      );
      settings[SettingsRepository.keyFontSize] = 25.0;
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'setting': {'key': SettingsRepository.keyFontSize, 'exists': true},
          }),
        ),
        isTrue,
      );
    });

    test('notifySettingsChanged מודיע למאזינים ומקדם את גרסת ההגדרות', () {
      evaluator.notifySettingsChanged();
      expect(notifications, 1);
      expect(evaluator.settingsRevision.value, 1);
    });

    test('greaterThan משווה מספרית בלבד', () {
      settings[SettingsRepository.keyFontSize] = 25.0;
      final condition = _when({
        'setting': {'key': SettingsRepository.keyFontSize, 'greaterThan': 20},
      });

      expect(evaluator.evaluate('p1', condition), isTrue);

      settings[SettingsRepository.keyFontSize] = 20;
      expect(
        evaluator.evaluate('p1', condition),
        isFalse,
        reason: 'שווה אינו גדול',
      );
      settings[SettingsRepository.keyFontSize] = 'ענק';
      expect(evaluator.evaluate('p1', condition), isFalse);
    });
  });

  group('contains', () {
    test('מחרוזת מוערכת כתת-מחרוזת', () async {
      repo.kv['p1|default|tags'] = jsonEncode('שבת ומועד');
      await evaluator.registerStorageKeys('p1', {'tags'}, repo);

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'tags', 'contains': 'מועד'},
          }),
        ),
        isTrue,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'tags', 'contains': 'חול'},
          }),
        ),
        isFalse,
      );
    });

    test('רשימה מוערכת לפי איבר', () async {
      repo.kv['p1|default|books'] = jsonEncode(['ברכות', 'שבת']);
      await evaluator.registerStorageKeys('p1', {'books'}, repo);

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'books', 'contains': 'שבת'},
          }),
        ),
        isTrue,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'books', 'contains': 'עירובין'},
          }),
        ),
        isFalse,
      );
    });

    test('מפתח חסר או ערך שאינו מכיל מוערך כ-false', () {
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'missing', 'contains': 'x'},
          }),
        ),
        isFalse,
      );
    });
  });

  group('snapshot של אחסון התוסף', () {
    test('registerStorageKeys טוען ערכים מפוענחים ומודיע', () async {
      repo.kv['p1|default|showButton'] = jsonEncode('yes');

      await evaluator.registerStorageKeys('p1', {'showButton'}, repo);

      expect(notifications, 1);
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'showButton', 'equals': 'yes'},
          }),
        ),
        isTrue,
      );
    });

    test('כל המפתחות נטענים בקריאה מרוכזת אחת', () async {
      for (var i = 0; i < 12; i++) {
        repo.kv['p1|default|k$i'] = jsonEncode(i);
      }

      await evaluator.registerStorageKeys(
        'p1',
        {for (var i = 0; i < 12; i++) 'k$i', 'missing'},
        repo,
      );

      expect(repo.bulkCalls, 1);
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'k11', 'equals': 11},
          }),
        ),
        isTrue,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'missing', 'exists': false},
          }),
        ),
        isTrue,
        reason: 'מפתח חסר מדולג ואינו נשמר כ-null קיים',
      );
    });

    test('ערך KV שאינו JSON תקין נשמר כמחרוזת גולמית', () async {
      repo.kv['p1|default|raw'] = 'לא JSON';

      await evaluator.registerStorageKeys('p1', {'raw'}, repo);

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'raw', 'equals': 'לא JSON'},
          }),
        ),
        isTrue,
      );
    });

    test('מפתח שלא נרשם למעקב אינו קיים בהערכה', () async {
      repo.kv['p1|default|other'] = jsonEncode('yes');
      await evaluator.registerStorageKeys('p1', {'showButton'}, repo);

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'other', 'exists': true},
          }),
        ),
        isFalse,
      );
    });

    test('הערכים מופרדים בין תוספים', () async {
      repo.kv['p1|default|flag'] = jsonEncode(1);
      await evaluator.registerStorageKeys('p1', {'flag'}, repo);
      await evaluator.registerStorageKeys('p2', {'flag'}, repo);

      final condition = _when({
        'storage': {'key': 'flag', 'equals': 1},
      });
      expect(evaluator.evaluate('p1', condition), isTrue);
      expect(evaluator.evaluate('p2', condition), isFalse);
    });

    test('onStorageValueChanged מעדכן ומודיע רק על מפתח במעקב', () async {
      await evaluator.registerStorageKeys('p1', {'showButton'}, repo);
      notifications = 0;

      evaluator.onStorageValueChanged('p1', 'untracked', 'x');
      expect(notifications, 0);

      evaluator.onStorageValueChanged('p1', 'showButton', 'yes');
      expect(notifications, 1);
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'showButton', 'equals': 'yes'},
          }),
        ),
        isTrue,
      );

      evaluator.onStorageValueChanged('p1', 'showButton', 'yes');
      expect(notifications, 1, reason: 'ערך זהה אינו מחולל הודעה');
    });

    test('onStorageRemoved מסיר מה-snapshot', () async {
      repo.kv['p1|default|showButton'] = jsonEncode('yes');
      await evaluator.registerStorageKeys('p1', {'showButton'}, repo);
      notifications = 0;

      evaluator.onStorageRemoved('p1', 'showButton');

      expect(notifications, 1);
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'showButton', 'exists': false},
          }),
        ),
        isTrue,
      );
    });

    test('trackStorageKeys מוסיף מפתח בלי למחוק קיימים', () async {
      repo.kv['p1|default|fromManifest'] = jsonEncode('a');
      repo.kv['p1|default|fromBridge'] = jsonEncode('b');
      await evaluator.registerStorageKeys('p1', {'fromManifest'}, repo);

      await evaluator.trackStorageKeys('p1', {'fromBridge'}, repo);

      for (final entry in {'fromManifest': 'a', 'fromBridge': 'b'}.entries) {
        expect(
          evaluator.evaluate(
            'p1',
            _when({
              'storage': {'key': entry.key, 'equals': entry.value},
            }),
          ),
          isTrue,
        );
      }
    });

    test('סנכרון מניפסט חוזר אינו מוחק מפתח שנרשם דרך הגשר', () async {
      await evaluator.trackStorageKeys('p1', {'fromBridge'}, repo);
      await evaluator.registerStorageKeys('p1', {'fromManifest'}, repo);
      notifications = 0;

      evaluator.onStorageValueChanged('p1', 'fromBridge', 'yes');

      expect(notifications, 1);
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'fromBridge', 'equals': 'yes'},
          }),
        ),
        isTrue,
      );
    });

    test('סנכרון בלי מפתחות מניפסט משמר מפתח מהגשר', () async {
      await evaluator.trackStorageKeys('p1', {'fromBridge'}, repo);

      await evaluator.registerStorageKeys('p1', const {}, repo);
      evaluator.onStorageValueChanged('p1', 'fromBridge', 'yes');

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'fromBridge', 'equals': 'yes'},
          }),
        ),
        isTrue,
      );
    });

    test('removePlugin מנקה את הרישום', () async {
      repo.kv['p1|default|flag'] = jsonEncode(true);
      await evaluator.registerStorageKeys('p1', {'flag'}, repo);

      evaluator.removePlugin('p1');

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'flag', 'equals': true},
          }),
        ),
        isFalse,
      );
      evaluator.onStorageValueChanged('p1', 'flag', true);
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'storage': {'key': 'flag', 'equals': true},
          }),
        ),
        isFalse,
        reason: 'עדכון חי אינו מחזיר מפתח שהרישום שלו הוסר',
      );
    });
  });

  group('קומבינטורים', () {
    test('all / any / not', () async {
      settings[SettingsRepository.keyDarkMode] = true;
      repo.kv['p1|default|flag'] = jsonEncode('on');
      await evaluator.registerStorageKeys('p1', {'flag'}, repo);

      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'all': [
              {
                'setting': {
                  'key': SettingsRepository.keyDarkMode,
                  'equals': true,
                },
              },
              {
                'storage': {'key': 'flag', 'equals': 'on'},
              },
            ],
          }),
        ),
        isTrue,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'any': [
              {
                'storage': {'key': 'flag', 'equals': 'off'},
              },
              {
                'setting': {
                  'key': SettingsRepository.keyDarkMode,
                  'equals': true,
                },
              },
            ],
          }),
        ),
        isTrue,
      );
      expect(
        evaluator.evaluate(
          'p1',
          _when({
            'not': {
              'storage': {'key': 'flag', 'equals': 'on'},
            },
          }),
        ),
        isFalse,
      );
    });

    test('isVisible מחזיר true לתנאי null', () {
      expect(evaluator.isVisible('p1', null), isTrue);
    });
  });
}
