import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_item_registry.dart';

/// סוגי פקד שילדיהם הם פריטי תפריט.
const _typesWithChildren = {'menu', 'split'};

/// רישום פקדי שורת הפקדים שתוספים הוסיפו (reader.addToolbarItem).
class PluginToolbarRegistry extends PluginItemRegistry<PluginToolbarItem> {
  static const int maxTopLevelItemsPerPlugin =
      PluginItemRegistry.maxTopLevelItemsPerPlugin;
  static const int maxMenuChildren = 20;

  static final PluginToolbarRegistry instance = PluginToolbarRegistry._();
  PluginToolbarRegistry._()
    : super(evaluator: PluginConditionEvaluator.instance);

  @visibleForTesting
  PluginToolbarRegistry.forTesting({super.evaluator});

  /// מופע מנותק לפרסינג-יבש בוולידציה (אריזה/התקנה) — לא נוגע ב-UI.
  PluginToolbarRegistry.detached();

  @override
  Exception exception(String code, String message) =>
      PluginToolbarException(code, message);
  @override
  String get tooManyItemsMessage =>
      'a plugin can register at most 2 toolbar items';
  @override
  String get notFoundMessage => 'toolbar item was not found';
  @override
  PluginToolbarItem parseTopLevel(Map<String, dynamic> json) =>
      _parseItem(json, isChild: false);

  /// מחליף קבוצת פריטים מנוהלת בעדכון יחיד, בלי לגעת בפריטים אחרים.
  /// פריטים מנוהלים הם דקלרטיביים — חיים ברמת התוסף.
  void replaceManagedItems(
    String pluginId, {
    required Set<String> managedIds,
    required List<PluginToolbarItem> items,
  }) {
    if (items.any((item) => !managedIds.contains(item.id)) ||
        items.map((item) => item.id).toSet().length != items.length) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'managed toolbar items must have unique declared ids',
      );
    }
    final PluginInstanceKey key = (
      pluginId: pluginId,
      instanceId: PluginInstanceIds.pluginLevel,
    );
    final next = [
      for (final item in this.items[key] ?? const <PluginToolbarItem>[])
        if (!managedIds.contains(item.id)) item,
      ...items,
    ];
    if (next.length > maxTopLevelItemsPerPlugin ||
        next.map((item) => item.id).toSet().length != next.length) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'a plugin can register at most 2 unique toolbar items',
      );
    }
    if (next.isEmpty) {
      this.items.remove(key);
    } else {
      this.items[key] = next;
    }
    notifyListeners();
  }

  PluginToolbarItem _parseItem(
    Map<String, dynamic> json, {
    required bool isChild,
    List<String>? inheritedContexts,
  }) {
    final id = safeText(json['id'], field: 'id', maxLength: 128);
    final type = json['type'] as String? ?? 'button';
    final allowedTypes = isChild
        ? const {'button'}
        : const {'button', 'menu', 'split'};
    if (!allowedTypes.contains(type)) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'unsupported toolbar item type',
      );
    }
    final title = safeText(json['title'], field: 'title', maxLength: 100);
    final contexts = parseContexts(
      json['contexts'],
      inherited: inheritedContexts,
      defaults: const ['reader-text', 'reader-pdf'],
      supported: const {'reader-text', 'reader-pdf'},
    );

    final icon = optionalSafeText(json['icon'], maxLength: 100);
    if (!isChild && (icon == null || icon.isEmpty)) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'a toolbar item requires an icon',
      );
    }

    final children = <PluginToolbarItem>[];
    final childrenValue = json['children'];
    if (childrenValue != null) {
      if (!_typesWithChildren.contains(type)) {
        throw const PluginToolbarException(
          'error.invalid_params',
          'only menu or split items may declare children',
        );
      }
      if (childrenValue is! List || childrenValue.length > maxMenuChildren) {
        throw const PluginToolbarException(
          'error.invalid_params',
          'children must contain at most 20 items',
        );
      }
      for (final child in childrenValue) {
        if (child is! Map) {
          throw const PluginToolbarException(
            'error.invalid_params',
            'child must be an object',
          );
        }
        children.add(
          _parseItem(
            Map<String, dynamic>.from(child),
            isChild: true,
            inheritedContexts: contexts,
          ),
        );
      }
    }
    if (_typesWithChildren.contains(type) && children.isEmpty) {
      throw PluginToolbarException(
        'error.invalid_params',
        '$type requires children',
      );
    }
    if (children.map((child) => child.id).toSet().length != children.length) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'children ids must be unique',
      );
    }

    final placement = json['placement'] as String? ?? 'primary';
    if (isChild && json['placement'] != null) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'placement is only allowed on top-level items',
      );
    }
    if (!const {'primary', 'overflow'}.contains(placement)) {
      throw const PluginToolbarException(
        'error.invalid_params',
        'placement must be "primary" or "overflow"',
      );
    }

    final rawOrder = json['order'];
    if (rawOrder != null) {
      if (isChild) {
        throw const PluginToolbarException(
          'error.invalid_params',
          'order is only allowed on top-level items',
        );
      }
      if (placement != 'overflow') {
        throw const PluginToolbarException(
          'error.invalid_params',
          'order requires placement "overflow"',
        );
      }
      if (rawOrder is! int || rawOrder < 0 || rawOrder > 10000) {
        throw const PluginToolbarException(
          'error.invalid_params',
          'order must be an integer between 0 and 10000',
        );
      }
    }

    return PluginToolbarItem(
      id: id,
      type: type,
      title: title,
      icon: icon,
      contexts: contexts,
      onClickEvent: optionalEventName(json['onClickEvent']),
      children: children,
      openPlugin: json['openPlugin'] == true,
      param: json['param'],
      placement: placement,
      order: rawOrder as int? ?? PluginToolbarItem.defaultOrder,
      when: parseWhen(json['when'], nested: isChild),
    );
  }
}
