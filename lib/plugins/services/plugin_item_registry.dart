import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_registry_item.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';

/// הבסיס המשותף לרישומי הפריטים של התוספים: רישום לפי מופע, עדכון, הסרה,
/// תצוגה מאוחדת וולידציה של השדות המשותפים.
abstract class PluginItemRegistry<T extends PluginRegistryItem>
    extends ChangeNotifier {
  static const int maxTopLevelItemsPerPlugin = 2;

  PluginItemRegistry({this.evaluator}) {
    evaluator?.addListener(notifyListeners);
  }

  @protected
  final Map<PluginInstanceKey, List<T>> items = {};
  @protected
  final PluginConditionEvaluator? evaluator;

  @protected
  Exception exception(String code, String message);
  @protected
  String get tooManyItemsMessage;
  @protected
  String get notFoundMessage;
  @protected
  T parseTopLevel(Map<String, dynamic> json);

  @protected
  Map<String, dynamic> mergePatch(T item, Map<String, dynamic> patch) => {
    ...item.toJson(),
    ...patch,
  };

  @override
  void dispose() {
    evaluator?.removeListener(notifyListeners);
    super.dispose();
  }

  PluginInstanceKey _key(String pluginId, String instanceId) =>
      (pluginId: pluginId, instanceId: instanceId);

  /// הרשימה של [instanceId] אם היא מכילה את [itemId]; אחרת הרשימה ברמת
  /// התוסף — כך JS של מופע יכול לעדכן/להסיר פריט שהוצהר במניפסט.
  List<T>? _listContaining(String pluginId, String instanceId, String itemId) {
    final own = items[_key(pluginId, instanceId)];
    if (own != null && own.any((item) => item.id == itemId)) return own;
    if (instanceId == PluginInstanceIds.pluginLevel) return null;
    final shared = items[_key(pluginId, PluginInstanceIds.pluginLevel)];
    if (shared != null && shared.any((item) => item.id == itemId)) {
      return shared;
    }
    return null;
  }

  void register(
    String pluginId,
    T item, {
    String instanceId = PluginInstanceIds.pluginLevel,
  }) {
    final list = items.putIfAbsent(_key(pluginId, instanceId), () => []);
    final index = list.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      list[index] = item;
    } else {
      if (list.length >= maxTopLevelItemsPerPlugin) {
        throw exception('error.invalid_params', tooManyItemsMessage);
      }
      list.add(item);
    }
    notifyListeners();
  }

  T registerPayload(
    String pluginId,
    Map<String, dynamic> payload, {
    String instanceId = PluginInstanceIds.pluginLevel,
  }) {
    final item = parseTopLevel(payload);
    register(pluginId, item, instanceId: instanceId);
    return item;
  }

  T update(
    String pluginId,
    String itemId,
    Map<String, dynamic> patch, {
    String instanceId = PluginInstanceIds.pluginLevel,
  }) {
    final list = _listContaining(pluginId, instanceId, itemId);
    final index = list?.indexWhere((item) => item.id == itemId) ?? -1;
    if (list == null || index < 0) {
      throw exception('error.not_found', notFoundMessage);
    }
    final updated = parseTopLevel({
      ...mergePatch(list[index], patch),
      'id': itemId,
    });
    list[index] = updated;
    notifyListeners();
    return updated;
  }

  void remove(
    String pluginId,
    String itemId, {
    String instanceId = PluginInstanceIds.pluginLevel,
  }) {
    final list = _listContaining(pluginId, instanceId, itemId);
    if (list == null) return;
    list.removeWhere((item) => item.id == itemId);
    items.removeWhere((_, items) => items.isEmpty);
    notifyListeners();
  }

  /// ניקוי מלא ברמת התוסף — כל המופעים והרישומים הדקלרטיביים.
  void removeAll(String pluginId) {
    final before = items.length;
    items.removeWhere((key, _) => key.pluginId == pluginId);
    if (items.length != before) notifyListeners();
  }

  /// מסיר רק את הרישומים של המופע [key] (סגירת טאב אחד של התוסף).
  void removeInstance(PluginInstanceKey key) {
    if (items.remove(key) != null) notifyListeners();
  }

  /// הפריטים המוצגים בפועל — פריט שתנאי ה-`when` שלו אינו מתקיים מסונן החוצה
  /// (ונשאר רשום, כך שהוא חוזר כשהתנאי מתקיים).
  ///
  /// תצוגה מאוחדת: פריט אחד לכל (pluginId, itemId) גם כשכמה מופעים רשמו
  /// אותו; רישום של מופע חי גובר על העותק הדקלרטיבי, המיקום לפי הראשון.
  List<(String pluginId, T item)> getAll() {
    final evaluator = this.evaluator;
    final deduped = <(String, String), (String, T)>{};
    for (final entry in items.entries) {
      final pluginId = entry.key.pluginId;
      for (final item in entry.value) {
        if (!(evaluator?.isVisible(pluginId, item.when) ?? true)) continue;
        final dedupeKey = (pluginId, item.id);
        if (!deduped.containsKey(dedupeKey) ||
            entry.key.instanceId != PluginInstanceIds.pluginLevel) {
          deduped[dedupeKey] = (pluginId, item);
        }
      }
    }
    return List.unmodifiable(deduped.values);
  }

  /// מזהי המופעים שרשמו את [itemId] (כולל בתוך פריטי ילדים), בסדר הרישום —
  /// הקלט לניתוב הלחיצה למופע הנכון.
  List<String> instanceIdsForItem(String pluginId, String itemId) => [
    for (final entry in items.entries)
      if (entry.key.pluginId == pluginId &&
          entry.value.any((item) => _treeContains(item, itemId)))
        entry.key.instanceId,
  ];

  bool _treeContains(PluginRegistryItem item, String itemId) =>
      item.id == itemId ||
      item.children.any((child) => _treeContains(child, itemId));

  /// contexts של פריט: ברירת מחדל מההורה או מ-[defaults], ופריט ילד מוגבל
  /// להקשרי ההורה.
  @protected
  List<String> parseContexts(
    Object? value, {
    required List<String>? inherited,
    required List<String> defaults,
    required Set<String> supported,
  }) {
    if (value != null &&
        (value is! List || value.any((context) => context is! String))) {
      throw exception(
        'error.invalid_params',
        'contexts must be an array of strings',
      );
    }
    final contexts = value == null
        ? inherited ?? defaults
        : List<String>.from(value as List);
    if (contexts.isEmpty ||
        contexts.toSet().length != contexts.length ||
        (value != null &&
            inherited != null &&
            contexts.any((context) => !inherited.contains(context))) ||
        contexts.any((context) => !supported.contains(context))) {
      throw exception(
        'error.unsupported_context',
        'contexts must be unique, supported, and within the parent contexts',
      );
    }
    return contexts;
  }

  @protected
  PluginWhenCondition? parseWhen(Object? value, {required bool nested}) {
    if (value == null) return null;
    if (nested) {
      throw exception(
        'error.invalid_params',
        'when is only allowed on top-level items',
      );
    }
    try {
      return PluginWhenCondition.fromJson(value);
    } on PluginWhenConditionException catch (error) {
      throw exception('error.invalid_params', '$error');
    }
  }

  @protected
  String safeText(
    Object? value, {
    required String field,
    required int maxLength,
  }) {
    final text = optionalSafeText(value, maxLength: maxLength);
    if (text == null || text.isEmpty) {
      throw exception('error.invalid_params', '$field is required');
    }
    return text;
  }

  @protected
  String? optionalSafeText(Object? value, {required int maxLength}) {
    if (value == null) return null;
    if (value is! String ||
        value.length > maxLength ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw exception(
        'error.invalid_params',
        'text field has an invalid type or content',
      );
    }
    return value;
  }

  @protected
  String? optionalEventName(Object? value) {
    final event = optionalSafeText(value, maxLength: 128);
    if (event != null && !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(event)) {
      throw exception(
        'error.invalid_params',
        'event name contains unsupported characters',
      );
    }
    return event;
  }
}
