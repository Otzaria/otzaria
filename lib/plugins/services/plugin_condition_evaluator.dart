import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';

/// קריאת הגדרת תוכנה — מוחלף בבדיקות.
typedef PluginSettingReader = Object? Function(String key);

/// Settings שטרם אותחל (בדיקות widget, עלייה מוקדמת) זורק — ואז אין ערך.
Object? _defaultSettingReader(String key) {
  try {
    return Settings.getValue(key);
  } catch (_) {
    return null;
  }
}

/// מעריך תנאי `when` של תרומות דקלרטיביות — סינכרונית ובלי מנוע JS.
/// מחזיק snapshot בזיכרון של מפתחות ה-KV שהתנאים קוראים ומודיע למאזינים.
class PluginConditionEvaluator extends ChangeNotifier {
  static final PluginConditionEvaluator instance = PluginConditionEvaluator._();
  PluginConditionEvaluator._() : _settingReader = _defaultSettingReader;

  @visibleForTesting
  PluginConditionEvaluator.forTesting({PluginSettingReader? settingReader})
    : _settingReader = settingReader ?? _defaultSettingReader;

  final PluginSettingReader _settingReader;

  /// pluginId → מפתח KV → ערך מפוענח. מפתח רשום שאינו במפה = לא קיים.
  final Map<String, Map<String, Object?>> _storage = {};

  /// pluginId → מפתחות ה-KV שנרשמו למעקב מתוך התנאים.
  final Map<String, Set<String>> _trackedKeys = {};

  /// מפתחות שנרשמו מרישום דינמי בגשר — סנכרון המניפסט לא מוחק אותם.
  final Map<String, Set<String>> _dynamicKeys = {};

  /// האם להציג פריט שהתנאי שלו הוא [condition] (null = תמיד להציג).
  bool isVisible(String pluginId, PluginWhenCondition? condition) =>
      condition == null || evaluate(pluginId, condition);

  bool evaluate(String pluginId, PluginWhenCondition condition) {
    switch (condition.kind) {
      case PluginWhenConditionKind.all:
        return condition.conditions.every((c) => evaluate(pluginId, c));
      case PluginWhenConditionKind.any:
        return condition.conditions.any((c) => evaluate(pluginId, c));
      case PluginWhenConditionKind.not:
        return !evaluate(pluginId, condition.conditions.single);
      case PluginWhenConditionKind.setting:
        final key = condition.key!;
        if (!PluginSettingsAccessPolicy.isReadable(key)) return false;
        return _evaluateLeaf(condition, _settingReader(key));
      case PluginWhenConditionKind.storage:
        final values = _storage[pluginId];
        final key = condition.key!;
        final exists = values != null && values.containsKey(key);
        return _evaluateLeaf(condition, exists ? values[key] : null);
    }
  }

  bool _evaluateLeaf(PluginWhenCondition condition, Object? actual) {
    switch (condition.operator!) {
      case PluginWhenLeafOperator.equals:
        return _valuesEqual(actual, condition.value);
      case PluginWhenLeafOperator.notEquals:
        return !_valuesEqual(actual, condition.value);
      case PluginWhenLeafOperator.exists:
        return (actual != null) == (condition.value == true);
      case PluginWhenLeafOperator.contains:
        return _valueContains(actual, condition.value);
      case PluginWhenLeafOperator.greaterThan:
        final expected = condition.value;
        final numeric = actual is num
            ? actual
            : (actual is String ? num.tryParse(actual) : null);
        if (numeric == null || expected is! num) return false;
        return numeric > expected;
    }
  }

  bool _valueContains(Object? actual, Object? expected) {
    if (actual is String) return actual.contains(expected.toString());
    if (actual is Iterable) {
      return actual.any((item) => _valuesEqual(item, expected));
    }
    return false;
  }

  bool _valuesEqual(Object? actual, Object? expected) => actual == expected;

  /// רושם למעקב את מפתחות ה-KV של [pluginId] מהמניפסט וטוען את ערכיהם.
  /// מפתחות שנרשמו דינמית דרך [trackStorageKeys] נשמרים.
  Future<void> registerStorageKeys(
    String pluginId,
    Set<String> keys,
    PluginRegistryRepository repository,
  ) async {
    final merged = {...keys, ...?_dynamicKeys[pluginId]};
    if (merged.isEmpty) {
      removePlugin(pluginId);
      return;
    }
    final values = await _loadValues(pluginId, merged, repository);
    final changed =
        !setEquals(_trackedKeys[pluginId], merged) ||
        !mapEquals(_storage[pluginId], values);
    _trackedKeys[pluginId] = merged;
    _storage[pluginId] = values;
    if (changed) notifyListeners();
  }

  /// רישום אדיטיבי של מפתחות KV — לפריטים שנרשמים בזמן ריצה דרך הגשר.
  Future<void> trackStorageKeys(
    String pluginId,
    Set<String> keys,
    PluginRegistryRepository repository,
  ) async {
    final missing = keys.difference(_trackedKeys[pluginId] ?? const {});
    _dynamicKeys.putIfAbsent(pluginId, () => {}).addAll(keys);
    if (missing.isEmpty) return;
    final values = await _loadValues(pluginId, missing, repository);
    _trackedKeys.putIfAbsent(pluginId, () => {}).addAll(keys);
    _storage.putIfAbsent(pluginId, () => {}).addAll(values);
    notifyListeners();
  }

  Future<Map<String, Object?>> _loadValues(
    String pluginId,
    Set<String> keys,
    PluginRegistryRepository repository,
  ) async {
    final raws = await repository.getKVMany(
      pluginId,
      kDefaultStorageNamespace,
      keys,
    );
    final values = <String, Object?>{};
    for (final entry in raws.entries) {
      try {
        values[entry.key] = jsonDecode(entry.value);
      } on FormatException {
        values[entry.key] = entry.value;
      }
    }
    return values;
  }

  void removePlugin(String pluginId) {
    final hadKeys = _trackedKeys.remove(pluginId) != null;
    _dynamicKeys.remove(pluginId);
    _storage.remove(pluginId);
    if (hadKeys) notifyListeners();
  }

  /// עדכון snapshot מ-`storage.set` בגשר — רק למפתח שנרשם למעקב.
  void onStorageValueChanged(String pluginId, String key, Object? value) {
    if (_trackedKeys[pluginId]?.contains(key) != true) return;
    final values = _storage.putIfAbsent(pluginId, () => {});
    if (values.containsKey(key) && _valuesEqual(values[key], value)) return;
    values[key] = value;
    notifyListeners();
  }

  /// עדכון snapshot מ-`storage.remove` בגשר.
  void onStorageRemoved(String pluginId, String key) {
    if (_trackedKeys[pluginId]?.contains(key) != true) return;
    final values = _storage[pluginId];
    if (values == null || !values.containsKey(key)) return;
    values.remove(key);
    notifyListeners();
  }

  final ValueNotifier<int> _settingsRevision = ValueNotifier(0);

  /// עולה בכל שינוי הגדרות. ערוץ נפרד מ-[notifyListeners] כדי שצרכן שמתעניין
  /// בהגדרות בלבד לא יתעורר גם משינויי אחסון.
  ValueListenable<int> get settingsRevision => _settingsRevision;

  /// הגדרת תוכנה השתנתה — הערכות שנשענות עליה עשויות להתהפך.
  void notifySettingsChanged() {
    _settingsRevision.value++;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _storage.clear();
    _trackedKeys.clear();
    _dynamicKeys.clear();
  }
}
