import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';

/// קבוצה אישית של תוספים, בלי לשנות את רישום ההתקנות שלהם.
class PluginGroup extends Equatable {
  static const int maxNameLength = 80;

  final String id;
  final String name;
  final List<String> pluginIds;

  PluginGroup({
    required this.id,
    required String name,
    required Iterable<String> pluginIds,
  }) : name = name.trim(),
       pluginIds = List.unmodifiable(pluginIds.toSet()) {
    if (id.isEmpty ||
        this.name.isEmpty ||
        this.name.characters.length > maxNameLength) {
      throw ArgumentError('Invalid plugin group');
    }
  }

  @override
  List<Object?> get props => [id, name, pluginIds];

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'pluginIds': pluginIds,
  };

  factory PluginGroup.fromJson(Map<String, dynamic> json) => PluginGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    pluginIds: (json['pluginIds'] as List).cast<String>(),
  );
}

/// הקבוצות והסדר נקראים יחד, כדי שהוספת חבר לא תזיז את תיקיית היעד.
class PluginGroupsSnapshot {
  final List<PluginGroup> groups;
  final Map<String, int?> userOrders;

  PluginGroupsSnapshot({
    required Iterable<PluginGroup> groups,
    required Map<String, int?> userOrders,
  }) : groups = List.unmodifiable(groups),
       userOrders = Map.unmodifiable(userOrders);

  /// גם טעינת תוספים שהתחילה לפני שמירה משתמשת בסדר האחרון שהתקבל.
  List<InstalledPlugin> applyOrderTo(List<InstalledPlugin> plugins) {
    final ordered = [
      for (final plugin in plugins)
        if (userOrders.containsKey(plugin.pluginId) &&
            plugin.userOrder != userOrders[plugin.pluginId])
          plugin.copyWith(
            userOrder: userOrders[plugin.pluginId],
            clearUserOrder: userOrders[plugin.pluginId] == null,
          )
        else
          plugin,
    ];
    ordered.sort(InstalledPlugin.compareForDisplay);
    return ordered;
  }
}

/// הקבוצה השתנתה בזמן שטופס העריכה היה פתוח.
class PluginGroupChanged implements Exception {
  const PluginGroupChanged();
}

class PluginGroupNameInUse implements Exception {
  const PluginGroupNameInUse();
}
