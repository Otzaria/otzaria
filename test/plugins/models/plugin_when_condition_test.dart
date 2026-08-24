import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';

void main() {
  group('PluginWhenCondition.fromJson', () {
    test('מפרסר עלה setting עם equals', () {
      final condition = PluginWhenCondition.fromJson({
        'setting': {'key': 'key-dark-mode', 'equals': true},
      });

      expect(condition.kind, PluginWhenConditionKind.setting);
      expect(condition.key, 'key-dark-mode');
      expect(condition.operator, PluginWhenLeafOperator.equals);
      expect(condition.value, isTrue);
      expect(condition.settingKeys, {'key-dark-mode'});
      expect(condition.storageKeys, isEmpty);
    });

    test('מפרסר contains ו-greaterThan, כולל round-trip', () {
      const raw = {
        'all': [
          {
            'storage': {'key': 'tags', 'contains': 'שבת'},
          },
          {
            'setting': {'key': 'key-font-size', 'greaterThan': 18},
          },
        ],
      };

      final condition = PluginWhenCondition.fromJson(raw);

      expect(
        condition.conditions.first.operator,
        PluginWhenLeafOperator.contains,
      );
      expect(
        condition.conditions.last.operator,
        PluginWhenLeafOperator.greaterThan,
      );
      expect(jsonEncode(condition.toJson()), jsonEncode(raw));
    });

    test('greaterThan שאינו מספר ו-contains פסול נדחים', () {
      for (final leaf in [
        {'key': 'k', 'greaterThan': 'big'},
        {'key': 'k', 'greaterThan': true},
        {'key': 'k', 'contains': true},
        {'key': 'k', 'contains': ''},
        {'key': 'k', 'contains': 'א' * 101},
      ]) {
        expect(
          () => PluginWhenCondition.fromJson({'storage': leaf}),
          throwsA(isA<PluginWhenConditionException>()),
          reason: '$leaf',
        );
      }
    });

    test('אוסף מפתחות משני סוגי העלים בעץ מקונן', () {
      final condition = PluginWhenCondition.fromJson({
        'all': [
          {
            'setting': {'key': 'key-dark-mode', 'equals': true},
          },
          {
            'not': {
              'storage': {'key': 'showButton', 'notEquals': 'no'},
            },
          },
          {
            'any': [
              {
                'storage': {'key': 'mode', 'exists': true},
              },
            ],
          },
        ],
      });

      expect(condition.settingKeys, {'key-dark-mode'});
      expect(condition.storageKeys, {'showButton', 'mode'});
    });

    test('toJson משחזר את המבנה ומאפשר round-trip', () {
      const raw = {
        'any': [
          {
            'setting': {'key': 'key-font-size', 'notEquals': 25},
          },
          {
            'storage': {'key': 'flag', 'exists': false},
          },
        ],
      };

      final condition = PluginWhenCondition.fromJson(raw);
      expect(jsonEncode(condition.toJson()), jsonEncode(raw));
    });

    test('דוחה אובייקט עם יותר ממפתח אחד', () {
      expect(
        () => PluginWhenCondition.fromJson({
          'setting': {'key': 'a', 'equals': 1},
          'storage': {'key': 'b', 'equals': 1},
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('דוחה אופרטור לא מוכר', () {
      expect(
        () => PluginWhenCondition.fromJson({'some': []}),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('דוחה עלה בלי key או עם key ארוך מדי', () {
      expect(
        () => PluginWhenCondition.fromJson({
          'setting': {'equals': 1},
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
      expect(
        () => PluginWhenCondition.fromJson({
          'setting': {'key': 'k' * 129, 'equals': 1},
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('דוחה עלה בלי אופרטור או עם שניים', () {
      expect(
        () => PluginWhenCondition.fromJson({
          'storage': {'key': 'k'},
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
      expect(
        () => PluginWhenCondition.fromJson({
          'storage': {'key': 'k', 'equals': 1, 'notEquals': 2},
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('דוחה exists שאינו bool וערך השוואה שאינו סקלרי', () {
      expect(
        () => PluginWhenCondition.fromJson({
          'storage': {'key': 'k', 'exists': 'yes'},
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
      expect(
        () => PluginWhenCondition.fromJson({
          'storage': {
            'key': 'k',
            'equals': ['a'],
          },
        }),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('דוחה all ריק', () {
      expect(
        () => PluginWhenCondition.fromJson({'all': []}),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('דוחה עומק מעל 5', () {
      Object nested = {
        'setting': {'key': 'k', 'equals': 1},
      };
      for (var i = 0; i < PluginWhenCondition.maxDepth; i++) {
        nested = {'not': nested};
      }

      expect(
        () => PluginWhenCondition.fromJson(nested),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });

    test('מקבל עומק 5 בדיוק', () {
      Object nested = {
        'setting': {'key': 'k', 'equals': 1},
      };
      for (var i = 0; i < PluginWhenCondition.maxDepth - 1; i++) {
        nested = {'not': nested};
      }

      expect(
        PluginWhenCondition.fromJson(nested).kind,
        PluginWhenConditionKind.not,
      );
    });

    test('דוחה יותר מ-20 עלים', () {
      final leaves = [
        for (var i = 0; i <= PluginWhenCondition.maxLeaves; i++)
          {
            'storage': {'key': 'k$i', 'exists': true},
          },
      ];

      expect(
        () => PluginWhenCondition.fromJson({'all': leaves}),
        throwsA(isA<PluginWhenConditionException>()),
      );
    });
  });
}
