import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

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

/// הקבוצה השתנתה בזמן שטופס העריכה היה פתוח.
class PluginGroupChanged implements Exception {
  const PluginGroupChanged();
}

class PluginGroupNameInUse implements Exception {
  const PluginGroupNameInUse();
}
