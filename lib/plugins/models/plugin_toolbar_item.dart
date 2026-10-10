import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/plugin_registry_item.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';

/// פריט שתוסף רושם בשורת הפקדים של מסך העיון.
///
/// `type == 'button'` — לחצן בודד; `type == 'menu'` — תפריט נפתח שילדיו
/// הם לחצנים ([children]); `type == 'split'` — לחצן מפוצל שפעולתו הראשית היא
/// הפריט עצמו, ולצידה חץ שפותח את [children].
class PluginToolbarItem implements PluginRegistryItem {
  @override
  final String id;
  final String type;
  final String title;
  final String? icon;
  final List<String> contexts;
  final String? onClickEvent;
  @override
  final List<PluginToolbarItem> children;

  /// לחיצה על הפריט תפתח את דף התוסף, ואירוע הלחיצה יימסר לו לאחר הטעינה.
  final bool openPlugin;

  /// ערך חופשי שהתוסף מסר ברישום — מוחזר לו כלשונו ב-payload של אירוע הלחיצה.
  final Object? param;

  /// פעולה שה-Host מבצע ישירות, בלי להעיר את מנוע התוסף.
  final CompiledDeclarativeAction? hostAction;

  /// מיקום הפריט בסרגל: 'primary' — בשורת הפקדים (ברירת מחדל, נדחס לתפריט
  /// כשאין מקום); 'overflow' — תמיד בתוך תפריט "עוד פעולות" (שלוש נקודות).
  final String placement;

  /// משקל מיון בתוך תפריט "עוד פעולות" (רלוונטי רק ל-placement 'overflow'):
  /// הפריטים המובנים תופסים משקלים קבועים בקפיצות של 10 (הדפסה = 60 בשני
  /// מסכי העיון), ופריט תוסף משתבץ ביניהם לפי ערכו. ברירת המחדל
  /// [defaultOrder] ממקמת את הפריט אחרי כל הפריטים המובנים.
  final int order;

  static const int defaultOrder = 1000;

  /// תנאי הצגה על ערכי הגדרות/אחסון — null = מוצג תמיד.
  @override
  final PluginWhenCondition? when;

  const PluginToolbarItem({
    required this.id,
    this.type = 'button',
    required this.title,
    this.icon,
    this.contexts = const ['reader-text', 'reader-pdf'],
    this.onClickEvent,
    this.children = const [],
    this.openPlugin = false,
    this.param,
    this.hostAction,
    this.placement = 'primary',
    this.order = defaultOrder,
    this.when,
  });

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    if (icon != null) 'icon': icon,
    'contexts': contexts,
    if (onClickEvent != null) 'onClickEvent': onClickEvent,
    if (children.isNotEmpty)
      'children': children.map((child) => child.toJson()).toList(),
    if (openPlugin) 'openPlugin': true,
    if (param != null) 'param': param,
    if (placement != 'primary') 'placement': placement,
    if (order != defaultOrder) 'order': order,
    if (when != null) 'when': when!.toJson(),
  };
}

class PluginToolbarException implements Exception {
  final String code;
  final String message;

  const PluginToolbarException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}
