import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_selection_action.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_item_registry.dart';

class ContextMenuRegistry extends PluginItemRegistry<PluginContextMenuItem> {
  static final ContextMenuRegistry instance = ContextMenuRegistry._();
  ContextMenuRegistry._() : super(evaluator: PluginConditionEvaluator.instance);

  @visibleForTesting
  ContextMenuRegistry.forTesting({super.evaluator});

  /// מופע מנותק לפרסינג-יבש בוולידציה (אריזה/התקנה) — לא נוגע ב-UI.
  ContextMenuRegistry.detached();

  @override
  Exception exception(String code, String message) =>
      PluginContextMenuException(code, message);
  @override
  String get tooManyItemsMessage =>
      'a plugin can register at most 2 top-level context menu items';
  @override
  String get notFoundMessage => 'context menu item was not found';
  @override
  PluginContextMenuItem parseTopLevel(Map<String, dynamic> json) =>
      _parseItem(json, depth: 0);

  // toJson פולט תמיד title, ולכן patch עם label בלבד היה נבלע בשקט.
  @override
  Map<String, dynamic> mergePatch(
    PluginContextMenuItem item,
    Map<String, dynamic> patch,
  ) => {
    ...super.mergePatch(item, patch),
    if (patch.containsKey('label') && !patch.containsKey('title'))
      'title': patch['label'],
  };

  /// מחזיר פריט לפי [itemId], כולל פריטי משנה בתוך תת-תפריט.
  PluginContextMenuItem? findItem(String pluginId, String itemId) {
    for (final entry in items.entries) {
      if (entry.key.pluginId != pluginId) continue;
      for (final item in entry.value) {
        final found = _findInTree(item, itemId);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool isItemVisible(String pluginId, String itemId) {
    for (final entry in items.entries) {
      if (entry.key.pluginId != pluginId) continue;
      for (final item in entry.value) {
        if (_isVisibleInTree(pluginId, item, itemId)) return true;
      }
    }
    return false;
  }

  PluginContextMenuItem? _findInTree(
    PluginContextMenuItem item,
    String itemId,
  ) {
    if (item.id == itemId) return item;
    for (final child in item.children) {
      final found = _findInTree(child, itemId);
      if (found != null) return found;
    }
    return null;
  }

  bool _isVisibleInTree(
    String pluginId,
    PluginContextMenuItem item,
    String itemId,
  ) {
    if (!(evaluator?.isVisible(pluginId, item.when) ?? true)) return false;
    if (item.id == itemId) return true;
    return item.children.any(
      (child) => _isVisibleInTree(pluginId, child, itemId),
    );
  }

  PluginContextMenuItem _parseItem(
    Map<String, dynamic> json, {
    required int depth,
    List<String>? inheritedContexts,
  }) {
    if (depth > 2) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'context menu nesting is too deep',
      );
    }
    // אין הגבלת תווים על id — תוספי legacy נרשמו עם ids חופשיים.
    final id = safeText(json['id'], field: 'id', maxLength: 128);
    final type = json['type'] as String? ?? 'item';
    const types = {'item', 'submenu', 'color-row', 'separator'};
    if (!types.contains(type)) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'unsupported context menu item type',
      );
    }
    final titleValue = json['title'] ?? json['label'];
    final title = type == 'separator'
        ? null
        : safeText(titleValue, field: 'title', maxLength: 100);
    // ברירת מחדל: שני ההקשרים — פריטי legacy (בלי contexts) הופיעו מאז ומעולם
    // גם בתפריט של צורת הדף.
    final contexts = parseContexts(
      json['contexts'],
      inherited: inheritedContexts,
      defaults: const ['reader-selection', 'reader-page-shape-selection'],
      supported: const {
        'reader-book',
        'reader-selection',
        'reader-page-shape-selection',
        'reader-highlight',
      },
    );

    final children = <PluginContextMenuItem>[];
    final childrenValue = json['children'];
    if (childrenValue != null) {
      if (childrenValue is! List || childrenValue.length > 30) {
        throw const PluginContextMenuException(
          'error.invalid_params',
          'children must contain at most 30 items',
        );
      }
      for (final child in childrenValue) {
        if (child is! Map) {
          throw const PluginContextMenuException(
            'error.invalid_params',
            'child must be an object',
          );
        }
        children.add(
          _parseItem(
            Map<String, dynamic>.from(child),
            depth: depth + 1,
            inheritedContexts: contexts,
          ),
        );
      }
    }

    final colors = <PluginContextMenuColor>[];
    final colorsValue = json['colors'];
    if (colorsValue != null) {
      if (colorsValue is! List ||
          colorsValue.isEmpty ||
          colorsValue.length > 12) {
        throw const PluginContextMenuException(
          'error.invalid_params',
          'colors must contain 1-12 values',
        );
      }
      for (final value in colorsValue) {
        if (value is! Map) {
          throw const PluginContextMenuException(
            'error.invalid_params',
            'color must be an object',
          );
        }
        final colorJson = Map<String, dynamic>.from(value);
        final color = safeText(
          colorJson['color'],
          field: 'color',
          maxLength: 9,
        );
        if (!RegExp(r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$').hasMatch(color)) {
          throw const PluginContextMenuException(
            'error.invalid_params',
            'colors must use #RRGGBB or #RRGGBBAA',
          );
        }
        colors.add(
          PluginContextMenuColor(
            id: safeText(colorJson['id'], field: 'color.id', maxLength: 64),
            color: color,
            label: safeText(
              colorJson['label'],
              field: 'color.label',
              maxLength: 64,
            ),
            icon: optionalSafeText(colorJson['icon'], maxLength: 100),
            selected: colorJson['selected'] == true,
          ),
        );
      }
    }
    if (type == 'submenu' && children.isEmpty) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'submenu requires children',
      );
    }
    if (type == 'color-row' && colors.isEmpty) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'color-row requires colors',
      );
    }

    return PluginContextMenuItem(
      id: id,
      type: type,
      title: title,
      icon: optionalSafeText(json['icon'], maxLength: 100),
      contexts: contexts,
      onClickEvent: optionalEventName(json['onClickEvent']),
      onColorClickEvent: optionalEventName(json['onColorClickEvent']),
      children: children,
      colors: colors,
      openPlugin: json['openPlugin'] == true,
      param: json['param'],
      showWhenContainsAny: _parseShowWhen(json['showWhen']),
      when: parseWhen(json['when'], nested: depth > 0),
      action: _parseAction(json),
    );
  }

  /// פעולת host דקלרטיבית על הפריט — ולידציה מבנית בלבד; הצהרת ההרשאה
  /// נבדקת בוולידטור ההתקנה ושוב בזמן הלחיצה.
  Map<String, dynamic>? _parseAction(Map<String, dynamic> json) {
    final value = json['action'];
    if (value == null) return null;
    if (json['type'] != null && json['type'] != 'item') {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'action is only allowed on items',
      );
    }
    if (json['onClickEvent'] != null || json['openPlugin'] == true) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'action cannot be combined with onClickEvent or openPlugin',
      );
    }
    if (value is! Map) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'action must be an object',
      );
    }
    final action = Map<String, dynamic>.from(value);
    try {
      DeclarativeSelectionAction.validateTemplate(action);
    } on DeclarativeProgramException catch (error) {
      throw PluginContextMenuException('error.invalid_params', '$error');
    }
    return action;
  }

  /// `showWhen: {selectionContainsAny: [...]}` — עד 50 מילים, כל אחת עד 100
  /// תווים. בכוונה רשימת מילים ולא regex: ביטוי של תוסף היה רץ על כל סימון
  /// ופותח פתח ל-ReDoS.
  List<String> _parseShowWhen(Object? value) {
    if (value == null) return const [];
    if (value is! Map) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'showWhen must be an object',
      );
    }
    final words = value['selectionContainsAny'];
    if (words == null) return const [];
    if (words is! List || words.isEmpty || words.length > 50) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'showWhen.selectionContainsAny must contain 1-50 strings',
      );
    }
    return [
      for (final word in words)
        safeText(word, field: 'showWhen.selectionContainsAny', maxLength: 100),
    ];
  }
}
