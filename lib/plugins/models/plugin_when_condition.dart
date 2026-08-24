/// סוג הצומת בעץ התנאי `when` של תרומה דקלרטיבית.
enum PluginWhenConditionKind { setting, storage, all, any, not }

/// האופרטור של עלה בתנאי — בדיוק אחד מהם מותר בכל עלה.
enum PluginWhenLeafOperator {
  equals,
  notEquals,
  exists,
  contains,
  greaterThan,
}

/// תנאי `when` מפורסר: עץ של עלים (`setting` / `storage`) וקומבינטורים
/// (`all` / `any` / `not`). הערכה מתבצעת ב-PluginConditionEvaluator.
class PluginWhenCondition {
  /// עומק מקסימלי של העץ (שורש = 1) — הגנת DoS על פרסינג והערכה.
  static const int maxDepth = 5;

  /// מספר עלים מקסימלי בעץ כולו.
  static const int maxLeaves = 20;

  static const int maxKeyLength = 128;

  /// אורך מקסימלי למחרוזת ההשוואה של `contains` — חיפוש תת-מחרוזת רץ על
  /// ערך שלם בכל הערכה, ולכן הוא חסום כמו רשימת המילים של showWhen.
  static const int maxContainsLength = 100;

  final PluginWhenConditionKind kind;

  /// מפתח ההגדרה או מפתח ה-KV — בעלים בלבד.
  final String? key;

  final PluginWhenLeafOperator? operator;

  /// ערך ההשוואה של האופרטור (ב-`exists` — bool).
  final Object? value;

  /// תתי-התנאים של קומבינטור (`not` מחזיק בדיוק אחד).
  final List<PluginWhenCondition> conditions;

  const PluginWhenCondition._({
    required this.kind,
    this.key,
    this.operator,
    this.value,
    this.conditions = const [],
  });

  bool get isLeaf =>
      kind == PluginWhenConditionKind.setting ||
      kind == PluginWhenConditionKind.storage;

  /// כל מפתחות ההגדרות שהתנאי קורא.
  Set<String> get settingKeys =>
      _collectKeys(PluginWhenConditionKind.setting, <String>{});

  /// כל מפתחות ה-KV של התוסף שהתנאי קורא.
  Set<String> get storageKeys =>
      _collectKeys(PluginWhenConditionKind.storage, <String>{});

  Map<String, dynamic> toJson() {
    switch (kind) {
      case PluginWhenConditionKind.setting:
      case PluginWhenConditionKind.storage:
        return {
          kind == PluginWhenConditionKind.setting ? 'setting' : 'storage': {
            'key': key,
            operator!.name: value,
          },
        };
      case PluginWhenConditionKind.all:
      case PluginWhenConditionKind.any:
        return {
          kind == PluginWhenConditionKind.all ? 'all' : 'any': [
            for (final child in conditions) child.toJson(),
          ],
        };
      case PluginWhenConditionKind.not:
        return {'not': conditions.single.toJson()};
    }
  }

  Set<String> _collectKeys(PluginWhenConditionKind target, Set<String> into) {
    if (kind == target && key != null) into.add(key!);
    for (final child in conditions) {
      child._collectKeys(target, into);
    }
    return into;
  }

  /// פרסינג של אובייקט `when` — זורק [PluginWhenConditionException] על כל
  /// חריגה מהסכימה או מהמגבלות.
  factory PluginWhenCondition.fromJson(Object? json) {
    final counter = _LeafCounter();
    return _parse(json, depth: 1, counter: counter);
  }

  static PluginWhenCondition _parse(
    Object? json, {
    required int depth,
    required _LeafCounter counter,
  }) {
    if (depth > maxDepth) {
      throw const PluginWhenConditionException('when is nested too deeply');
    }
    if (json is! Map) {
      throw const PluginWhenConditionException('when must be an object');
    }
    final map = Map<String, dynamic>.from(json);
    if (map.length != 1) {
      throw const PluginWhenConditionException(
        'when must declare exactly one of setting, storage, all, any, not',
      );
    }
    final entry = map.entries.single;
    switch (entry.key) {
      case 'setting':
        return _parseLeaf(
          entry.value,
          PluginWhenConditionKind.setting,
          counter,
        );
      case 'storage':
        return _parseLeaf(
          entry.value,
          PluginWhenConditionKind.storage,
          counter,
        );
      case 'all':
      case 'any':
        final kind = entry.key == 'all'
            ? PluginWhenConditionKind.all
            : PluginWhenConditionKind.any;
        final value = entry.value;
        if (value is! List || value.isEmpty || value.length > maxLeaves) {
          throw PluginWhenConditionException(
            '${entry.key} must be a non-empty array of conditions',
          );
        }
        return PluginWhenCondition._(
          kind: kind,
          conditions: List.unmodifiable([
            for (final child in value)
              _parse(child, depth: depth + 1, counter: counter),
          ]),
        );
      case 'not':
        return PluginWhenCondition._(
          kind: PluginWhenConditionKind.not,
          conditions: List.unmodifiable([
            _parse(entry.value, depth: depth + 1, counter: counter),
          ]),
        );
      default:
        throw PluginWhenConditionException(
          'unsupported when operator "${entry.key}"',
        );
    }
  }

  static PluginWhenCondition _parseLeaf(
    Object? raw,
    PluginWhenConditionKind kind,
    _LeafCounter counter,
  ) {
    counter.count++;
    if (counter.count > maxLeaves) {
      throw const PluginWhenConditionException('when has too many conditions');
    }
    if (raw is! Map) {
      throw const PluginWhenConditionException(
        'when leaf must be an object with a key',
      );
    }
    final leaf = Map<String, dynamic>.from(raw);
    final key = leaf['key'];
    if (key is! String || key.isEmpty || key.length > maxKeyLength) {
      throw const PluginWhenConditionException(
        'when leaf key must be a non-empty string of up to 128 characters',
      );
    }
    const operators = {
      'equals': PluginWhenLeafOperator.equals,
      'notEquals': PluginWhenLeafOperator.notEquals,
      'exists': PluginWhenLeafOperator.exists,
      'contains': PluginWhenLeafOperator.contains,
      'greaterThan': PluginWhenLeafOperator.greaterThan,
    };
    final unknown = leaf.keys.where(
      (field) => field != 'key' && !operators.containsKey(field),
    );
    if (unknown.isNotEmpty) {
      throw PluginWhenConditionException(
        'unsupported when field "${unknown.first}"',
      );
    }
    final declared = operators.keys.where(leaf.containsKey).toList();
    if (declared.length != 1) {
      throw const PluginWhenConditionException(
        'when leaf requires exactly one operator',
      );
    }
    final operator = operators[declared.single]!;
    final value = leaf[declared.single];
    if (operator == PluginWhenLeafOperator.exists) {
      if (value is! bool) {
        throw const PluginWhenConditionException('when exists must be a bool');
      }
    } else if (operator == PluginWhenLeafOperator.greaterThan) {
      if (value is! num) {
        throw const PluginWhenConditionException(
          'when greaterThan must be a number',
        );
      }
    } else if (operator == PluginWhenLeafOperator.contains) {
      if (value is! String && value is! num) {
        throw const PluginWhenConditionException(
          'when contains must be a string or a number',
        );
      }
      if (value is String &&
          (value.isEmpty || value.length > maxContainsLength)) {
        throw const PluginWhenConditionException(
          'when contains must be a non-empty string of up to 100 characters',
        );
      }
    } else if (value != null &&
        value is! String &&
        value is! num &&
        value is! bool) {
      throw const PluginWhenConditionException(
        'when comparison value must be a string, number or bool',
      );
    }
    return PluginWhenCondition._(
      kind: kind,
      key: key,
      operator: operator,
      value: value,
    );
  }
}

class _LeafCounter {
  int count = 0;
}

class PluginWhenConditionException implements Exception {
  final String message;

  const PluginWhenConditionException(this.message);

  @override
  String toString() => message;
}
