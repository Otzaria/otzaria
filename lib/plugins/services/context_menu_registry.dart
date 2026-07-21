import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';

class ContextMenuRegistry extends ChangeNotifier {
  static const int maxTopLevelItemsPerPlugin = 2;

  static final ContextMenuRegistry instance = ContextMenuRegistry._();
  ContextMenuRegistry._();

  @visibleForTesting
  ContextMenuRegistry.forTesting();

  final Map<String, List<PluginContextMenuItem>> _items = {};

  void register(String pluginId, PluginContextMenuItem item) {
    final list = _items.putIfAbsent(pluginId, () => []);
    final index = list.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      list[index] = item;
    } else {
      if (list.length >= maxTopLevelItemsPerPlugin) {
        throw const PluginContextMenuException(
          'error.invalid_params',
          'a plugin can register at most 2 top-level context menu items',
        );
      }
      list.add(item);
    }
    notifyListeners();
  }

  PluginContextMenuItem registerPayload(
    String pluginId,
    Map<String, dynamic> payload,
  ) {
    final item = _parseItem(payload, depth: 0);
    register(pluginId, item);
    return item;
  }

  PluginContextMenuItem update(
    String pluginId,
    String itemId,
    Map<String, dynamic> patch,
  ) {
    final list = _items[pluginId];
    final index = list?.indexWhere((item) => item.id == itemId) ?? -1;
    if (list == null || index < 0) {
      throw const PluginContextMenuException(
        'error.not_found',
        'context menu item was not found',
      );
    }
    // toJson פולט תמיד title, ולכן patch עם label בלבד היה נבלע בשקט.
    final merged = {
      ...list[index].toJson(),
      ...patch,
      if (patch.containsKey('label') && !patch.containsKey('title'))
        'title': patch['label'],
      'id': itemId,
    };
    final updated = _parseItem(merged, depth: 0);
    list[index] = updated;
    notifyListeners();
    return updated;
  }

  void remove(String pluginId, String itemId) {
    final list = _items[pluginId];
    final previousLength = list?.length ?? 0;
    list?.removeWhere((item) => item.id == itemId);
    if (list?.isEmpty == true) _items.remove(pluginId);
    if ((list?.length ?? 0) != previousLength) notifyListeners();
  }

  void removeAll(String pluginId) {
    if (_items.remove(pluginId) != null) notifyListeners();
  }

  List<(String pluginId, PluginContextMenuItem item)> getAll() {
    return List.unmodifiable([
      for (final entry in _items.entries)
        for (final item in entry.value) (entry.key, item),
    ]);
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
    final id = _safeText(json['id'], field: 'id', maxLength: 128);
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
        : _safeText(titleValue, field: 'title', maxLength: 100);
    final contextsValue = json['contexts'];
    if (contextsValue != null &&
        (contextsValue is! List ||
            contextsValue.any((value) => value is! String))) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'contexts must be an array of strings',
      );
    }
    // ברירת מחדל: שני ההקשרים — פריטי legacy (בלי contexts) הופיעו מאז ומעולם
    // גם בתפריט של צורת הדף.
    final contexts = contextsValue == null
        ? inheritedContexts ??
              const ['reader-selection', 'reader-page-shape-selection']
        : List<String>.from(contextsValue as List);
    const supportedContexts = {
      'reader-selection',
      'reader-page-shape-selection',
    };
    if (contexts.isEmpty ||
        contexts.toSet().length != contexts.length ||
        (contextsValue != null &&
            inheritedContexts != null &&
            contexts.any((context) => !inheritedContexts.contains(context))) ||
        contexts.any((context) => !supportedContexts.contains(context))) {
      throw const PluginContextMenuException(
        'error.unsupported_context',
        'contexts must be unique, supported, and within the parent contexts',
      );
    }

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
        final color = _safeText(
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
            id: _safeText(colorJson['id'], field: 'color.id', maxLength: 64),
            color: color,
            label: _safeText(
              colorJson['label'],
              field: 'color.label',
              maxLength: 64,
            ),
            icon: _optionalSafeText(colorJson['icon'], maxLength: 100),
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
      icon: _optionalSafeText(json['icon'], maxLength: 100),
      contexts: contexts,
      onClickEvent: _optionalEventName(json['onClickEvent']),
      onColorClickEvent: _optionalEventName(json['onColorClickEvent']),
      children: children,
      colors: colors,
      openPlugin: json['openPlugin'] == true,
      param: json['param'],
    );
  }

  String _safeText(
    Object? value, {
    required String field,
    required int maxLength,
  }) {
    final text = _optionalSafeText(value, maxLength: maxLength);
    if (text == null || text.isEmpty) {
      throw PluginContextMenuException(
        'error.invalid_params',
        '$field is required',
      );
    }
    return text;
  }

  String? _optionalSafeText(Object? value, {required int maxLength}) {
    if (value == null) return null;
    if (value is! String ||
        value.length > maxLength ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'text field has an invalid type or content',
      );
    }
    return value;
  }

  String? _optionalEventName(Object? value) {
    final event = _optionalSafeText(value, maxLength: 128);
    if (event != null && !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(event)) {
      throw const PluginContextMenuException(
        'error.invalid_params',
        'event name contains unsupported characters',
      );
    }
    return event;
  }
}
