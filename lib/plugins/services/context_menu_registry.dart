import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// מספר ה-RootItems המקסימלי שתוסף בודד רשאי לרשום.
const int _kMaxRootItemsPerPlugin = 2;

/// מחלקת עזר המייצגת קבוצה מובנית: פריט הורה + רשימת בנים.
/// כשאין parentId — rootItem הוא הפריט עצמו ו-[children] ריק.
class PluginContextMenuGroup {
  final String pluginId;
  final PluginContextMenuItem rootItem;
  final List<PluginContextMenuItem> children;

  const PluginContextMenuGroup({
    required this.pluginId,
    required this.rootItem,
    this.children = const [],
  });
}

/// Singleton לניהול פריטי תפריט הקשר שנרשמו על ידי פלאגינים.
///
/// פלאגינים רושמים פריטים בעת boot ומסירים אותם בעת unload.
/// ה-registry הוא in-memory — אין פרסיסטנציה.
///
/// ## מדיניות מכסה
/// כל תוסף רשאי לרשום לכל היותר [_kMaxRootItemsPerPlugin] RootItems (פריטי
/// ברמה ראשית, כולל GroupHeaders). פריטי בנים (עם parentId) אינם מוגבלים.
class ContextMenuRegistry {
  static final ContextMenuRegistry instance = ContextMenuRegistry._();
  ContextMenuRegistry._();

  // pluginId → { itemId → PluginContextMenuItem }
  // מאחסן את כל הפריטים (root וגם children) בשטוח, עם lookup מהיר.
  final Map<String, Map<String, PluginContextMenuItem>> _items = {};

  /// רישום פריט תפריט עבור פלאגין.
  ///
  /// מחזיר `null` בהצלחה, או מחרוזת שגיאה אם הרישום נדחה:
  /// - `"error.quota_exceeded"` — התוסף כבר מיצה את מכסת 2 ה-RootItems שלו
  /// - `"error.invalid_params"` — ה-[item.parentId] אינו מזהה פריט הורה קיים
  ///   לאותו תוסף.
  ///
  /// עדכון פריט קיים (אותו id) מותר תמיד ואינו צורך slot חדש.
  String? register(String pluginId, PluginContextMenuItem item) {
    final byPlugin = _items.putIfAbsent(pluginId, () => {});

    // ── ולידציה: parentId לא ריק וקיים ────────────────────────────────────
    final parentId = item.parentId;
    if (parentId != null) {
      if (parentId.isEmpty) {
        return 'error.invalid_params: parentId must not be empty';
      }
      if (!byPlugin.containsKey(parentId)) {
        return 'error.invalid_params: parentId "$parentId" does not refer to a registered item for plugin "$pluginId"';
      }
    }

    // ── ולידציה: type חוקי (enum מוודא זאת בזמן קומפילציה; בדיקה כאן לגנריות)

    // ── בדיקת מכסה — root items חדשים או עדכון שהופך פריט-בן ל-root ─────────
    final isUpdate = byPlugin.containsKey(item.id);
    final wasRoot = isUpdate && byPlugin[item.id]!.isRoot;
    if (item.isRoot && (!isUpdate || !wasRoot)) {
      final currentRootCount = byPlugin.values.where((e) => e.isRoot).length;
      if (currentRootCount >= _kMaxRootItemsPerPlugin) {
        return 'error.quota_exceeded: plugin "$pluginId" has reached the maximum of $_kMaxRootItemsPerPlugin root context menu items';
      }
    }

    byPlugin[item.id] = item;
    return null; // הצלחה
  }

  /// הסרת פריט תפריט לפי id עבור פלאגין מסוים.
  /// אם הפריט הוא הורה, כל הבנים שלו נמחקים אוטומטית (cascade deletion).
  void remove(String pluginId, String itemId) {
    final byPlugin = _items[pluginId];
    if (byPlugin == null) return;
    byPlugin.remove(itemId);
    // cascade: מחק כל בן שמפנה ל-itemId הזה כ-parentId
    byPlugin.removeWhere((_, child) => child.parentId == itemId);
  }

  /// הסרת כל פריטי התפריט של פלאגין מסוים.
  void removeAll(String pluginId) {
    _items.remove(pluginId);
  }

  /// מחזיר את כל הפריטים ה**שורשיים** הרשומים (ללא בנים), עם ה-pluginId.
  /// שמור לתאימות לאחור עם קוד קיים שצורך את ה-registry.
  List<(String pluginId, PluginContextMenuItem item)> getAll() {
    final result = <(String, PluginContextMenuItem)>[];
    for (final entry in _items.entries) {
      for (final item in entry.value.values) {
        if (item.isRoot) result.add((entry.key, item));
      }
    }
    return result;
  }

  /// מחזיר מבנה מקונן של קבוצות: כל [PluginContextMenuGroup] מכיל פריט הורה
  /// ורשימת הבנים שלו לפי סדר רישום.
  ///
  /// GroupHeaders (type == group) מוחזרים ללא בנים גם אם נרשמו עם parentId
  /// (אין תת-כותרת בתוך כותרת).
  List<PluginContextMenuGroup> getStructured() {
    final result = <PluginContextMenuGroup>[];
    for (final entry in _items.entries) {
      final pluginId = entry.key;
      final byId = entry.value;
      // מעבר על root items בלבד, לפי סדר הכנסה
      for (final root in byId.values.where((e) => e.isRoot)) {
        final children = root.isGroup
            ? const <PluginContextMenuItem>[] // group header — no children
            : byId.values.where((e) => e.parentId == root.id).toList();
        result.add(PluginContextMenuGroup(
          pluginId: pluginId,
          rootItem: root,
          children: children,
        ));
      }
    }
    return result;
  }
}

/// ממיר את פריטי תפריט ההקשר של הפלאגינים ל-[AppContextMenuEntry] מקונן,
/// כולל תמיכה ב-buttonRow ותת-תפריט רגיל.
/// [eventData] — שדות נוספים שיועברו ל-[reader.context_menu_item_clicked].
List<AppContextMenuEntry> buildPluginContextMenuEntries(
    Map<String, dynamic> eventData) {
  final groups = ContextMenuRegistry.instance.getStructured();
  if (groups.isEmpty) return const [];

  return groups.map((group) {
    final pluginId = group.pluginId;
    final root = group.rootItem;

    void dispatch(String itemId) {
      PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        pluginId,
        'reader.context_menu_item_clicked',
        {'itemId': itemId, ...eventData},
      );
    }

    // buttonRow: שורת כפתורי צבע אופקית
    if (root.isButtonRow) {
      final buttons = group.children
          .map((child) => AppContextMenuEntry(
                label: child.label,
                icon: fluentIconFromName(child.icon),
                onTap: () => dispatch(child.id),
              ))
          .toList();
      return AppContextMenuEntry.buttonRow(
        label: root.label,
        children: buttons,
      );
    }

    // submenu רגיל: תת-תפריט עם ילדים
    if (group.children.isNotEmpty) {
      final childEntries = group.children
          .map((child) => AppContextMenuEntry(
                label: child.label,
                icon: fluentIconFromName(child.icon),
                onTap: () => dispatch(child.id),
              ))
          .toList();
      return AppContextMenuEntry(
        label: root.label,
        icon: fluentIconFromName(root.icon),
        children: childEntries,
      );
    }

    // פריט בודד ללא ילדים
    return AppContextMenuEntry(
      label: root.label,
      icon: fluentIconFromName(root.icon),
      onTap: () => dispatch(root.id),
    );
  }).toList();
}
