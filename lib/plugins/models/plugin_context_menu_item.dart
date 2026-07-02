/// סוג פריט תפריט הקשר שנרשם על ידי פלאגין.
enum PluginContextMenuItemType {
  /// פריט רגיל — לחיץ, מפעיל אירוע.
  item,

  /// כותרת מפרידה — לא לחיצה, מוצגת כ-header בין קבוצות פריטים.
  group,

  /// שורת כפתורים — פריט הורה שמציג את ילדיו כשורה אופקית של כפתורי אייקון/צבע.
  /// הילדים יכולים לציין [PluginContextMenuItem.icon] או [PluginContextMenuItem.color].
  buttonRow,
}

/// מודל המייצג פריט תפריט הקשר שנרשם על ידי פלאגין.
class PluginContextMenuItem {
  final String id;
  final String label;
  final String? icon;

  /// CSS color string (e.g. "#FF0000") — מציג גוש צבע במקום אייקון בשורת כפתורים.
  final String? color;

  /// מזהה הפריט ההורה (אופציונלי) — כשמוגדר, הפריט הוא בן של אותו הורה.
  final String? parentId;

  /// סוג הפריט: [PluginContextMenuItemType.item] (ברירת מחדל),
  /// [PluginContextMenuItemType.group] (כותרת לא-לחיצה), או
  /// [PluginContextMenuItemType.buttonRow] (שורת כפתורים אופקית).
  final PluginContextMenuItemType type;

  const PluginContextMenuItem({
    required this.id,
    required this.label,
    this.icon,
    this.color,
    this.parentId,
    this.type = PluginContextMenuItemType.item,
  });

  /// מחזיר `true` כשהפריט הוא ברמה הראשית (ללא הורה).
  bool get isRoot => parentId == null;

  /// מחזיר `true` כשהפריט הוא כותרת מפרידה.
  bool get isGroup => type == PluginContextMenuItemType.group;

  /// מחזיר `true` כשהפריט הוא שורת כפתורים אופקית.
  bool get isButtonRow => type == PluginContextMenuItemType.buttonRow;
}
