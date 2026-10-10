import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';

/// רישום כפתורי התוספים בשדות החיפוש — מהמניפסט בלבד, בלי מנוע JS.
///
/// מוזן ע"י PluginStartupContributionsService, ולכן מכיל רק תוספים מופעלים
/// שההרשאה `search.field_actions` הוענקה להם.
class PluginSearchFieldActionsRegistry extends ChangeNotifier {
  static final PluginSearchFieldActionsRegistry instance =
      PluginSearchFieldActionsRegistry._();
  PluginSearchFieldActionsRegistry._();

  @visibleForTesting
  PluginSearchFieldActionsRegistry.forTesting();

  /// מגבלה על מספר הכפתורים בשדה אחד, מכל התוספים יחד — כדי שהשדה לא
  /// יידחק לטובת כפתורים.
  static const int maxActionsPerField = 3;

  final Map<String, List<PluginSearchFieldAction>> _actions = {};

  void registerPayload(String pluginId, Map<String, dynamic> payload) {
    final action = PluginSearchFieldAction.fromPayload(payload);
    final actions = _actions.putIfAbsent(pluginId, () => []);
    final existing = actions.indexWhere((a) => a.id == action.id);
    if (existing >= 0) {
      actions[existing] = action;
    } else {
      if (actions.length >= PluginSearchFieldAction.maxActionsPerPlugin) {
        throw const PluginSearchFieldActionException(
          'a plugin can register at most 2 search field actions',
        );
      }
      actions.add(action);
    }
    notifyListeners();
  }

  void remove(String pluginId, String actionId) {
    final actions = _actions[pluginId];
    if (actions == null) return;
    final before = actions.length;
    actions.removeWhere((action) => action.id == actionId);
    if (actions.isEmpty) _actions.remove(pluginId);
    if (actions.length != before) notifyListeners();
  }

  void removeAll(String pluginId) {
    if (_actions.remove(pluginId) != null) notifyListeners();
  }

  PluginSearchFieldAction? find(String pluginId, String actionId) {
    for (final action in _actions[pluginId] ?? const []) {
      if (action.id == actionId) return action;
    }
    return null;
  }

  /// הכפתורים שמוצגים ב-[field], לפי סדר הרישום.
  List<(String pluginId, PluginSearchFieldAction action)> actionsFor(
    PluginSearchField field,
  ) {
    final result = <(String, PluginSearchFieldAction)>[];
    for (final entry in _actions.entries) {
      for (final action in entry.value) {
        if (!action.showsIn(field)) continue;
        result.add((entry.key, action));
        if (result.length == maxActionsPerField) return result;
      }
    }
    return result;
  }

  bool hasActionsFor(PluginSearchField field) =>
      _actions.values.any((list) => list.any((a) => a.showsIn(field)));
}
