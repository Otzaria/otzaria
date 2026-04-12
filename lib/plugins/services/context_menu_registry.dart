import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';

/// Singleton לניהול פריטי תפריט הקשר שנרשמו על ידי פלאגינים.
///
/// פלאגינים רושמים פריטים בעת boot ומסירים אותם בעת unload.
/// ה-registry הוא in-memory — אין פרסיסטנציה.
class ContextMenuRegistry {
  static final ContextMenuRegistry instance = ContextMenuRegistry._();
  ContextMenuRegistry._();

  // pluginId → list of items
  final Map<String, List<PluginContextMenuItem>> _items = {};

  /// רישום פריט תפריט עבור פלאגין.
  /// אם פריט עם אותו id כבר קיים לאותו פלאגין, הוא יוחלף.
  void register(String pluginId, PluginContextMenuItem item) {
    final list = _items.putIfAbsent(pluginId, () => []);
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.add(item);
    }
  }

  /// הסרת פריט תפריט לפי id עבור פלאגין מסוים.
  void remove(String pluginId, String itemId) {
    _items[pluginId]?.removeWhere((e) => e.id == itemId);
  }

  /// הסרת כל פריטי התפריט של פלאגין מסוים.
  void removeAll(String pluginId) {
    _items.remove(pluginId);
  }

  /// מחזיר את כל הפריטים הרשומים, עם ה-pluginId שלהם.
  List<(String pluginId, PluginContextMenuItem item)> getAll() {
    final result = <(String, PluginContextMenuItem)>[];
    for (final entry in _items.entries) {
      for (final item in entry.value) {
        result.add((entry.key, item));
      }
    }
    return result;
  }
}
