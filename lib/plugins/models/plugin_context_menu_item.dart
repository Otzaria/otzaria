import 'package:otzaria/plugins/models/plugin_registry_item.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';

class PluginContextMenuColor {
  final String id;
  final String color;
  final String label;
  final String? icon;
  final bool selected;

  const PluginContextMenuColor({
    required this.id,
    required this.color,
    required this.label,
    this.icon,
    this.selected = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'color': color,
    'label': label,
    if (icon != null) 'icon': icon,
    if (selected) 'selected': true,
  };
}

class PluginContextMenuItem implements PluginRegistryItem {
  @override
  final String id;
  final String type;
  final String? title;
  final String? icon;
  final List<String> contexts;
  final String? onClickEvent;
  final String? onColorClickEvent;
  @override
  final List<PluginContextMenuItem> children;
  final List<PluginContextMenuColor> colors;

  /// לחיצה על הפריט תפתח את דף התוסף, ואירוע הלחיצה יימסר לו לאחר הטעינה.
  final bool openPlugin;

  /// ערך חופשי שהתוסף מסר ברישום — מוחזר לו כלשונו ב-payload של אירוע הלחיצה.
  final Object? param;

  /// הפריט מוצג רק כשהטקסט המסומן מכיל לפחות אחת מהמילים (ריק = תמיד).
  /// מאפשר פריט תלוי-תוכן גם כשהתוסף אינו רץ (רישום דקלרטיבי מהמניפסט).
  final List<String> showWhenContainsAny;

  /// תנאי הצגה על ערכי הגדרות/אחסון — מצטבר עם [showWhenContainsAny] (AND).
  @override
  final PluginWhenCondition? when;

  /// תבנית פעולת host דקלרטיבית — הלחיצה מבוצעת ע"י התוכנה בלי להעיר את
  /// מנוע התוסף. סותר את [onClickEvent] ואת [openPlugin].
  final Map<String, dynamic>? action;

  const PluginContextMenuItem({
    required this.id,
    this.type = 'item',
    String? title,
    String? label,
    this.icon,
    this.contexts = const ['reader-selection', 'reader-page-shape-selection'],
    this.onClickEvent,
    this.onColorClickEvent,
    this.children = const [],
    this.colors = const [],
    this.openPlugin = false,
    this.param,
    this.showWhenContainsAny = const [],
    this.when,
    this.action,
  }) : title = title ?? label;

  /// האם להציג את הפריט עבור [selectedText] לפי [showWhenContainsAny].
  bool isVisibleForSelection(String selectedText) {
    if (showWhenContainsAny.isEmpty) return true;
    return showWhenContainsAny.any(selectedText.contains);
  }

  String get label => title ?? '';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (title != null) 'title': title,
    if (icon != null) 'icon': icon,
    'contexts': contexts,
    if (onClickEvent != null) 'onClickEvent': onClickEvent,
    if (onColorClickEvent != null) 'onColorClickEvent': onColorClickEvent,
    if (children.isNotEmpty)
      'children': children.map((child) => child.toJson()).toList(),
    if (colors.isNotEmpty)
      'colors': colors.map((color) => color.toJson()).toList(),
    if (openPlugin) 'openPlugin': true,
    if (param != null) 'param': param,
    if (showWhenContainsAny.isNotEmpty)
      'showWhen': {'selectionContainsAny': showWhenContainsAny},
    if (when != null) 'when': when!.toJson(),
    if (action != null) 'action': action,
  };
}

class PluginContextMenuException implements Exception {
  final String code;
  final String message;

  const PluginContextMenuException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}
