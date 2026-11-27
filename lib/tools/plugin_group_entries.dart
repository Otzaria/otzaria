import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/tool_order.dart';

/// תיקייה במשגר בלבד; קטלוג הכלים ופתיחת הכרטיסיות נשארים ברמת התוסף.
class PluginGroupCatalogEntry extends ToolCatalogEntry {
  final PluginGroup group;
  final List<ToolCatalogEntry> members;

  PluginGroupCatalogEntry({required this.group, required this.members})
    : super(
        toolId: 'plugin-group:${group.id}',
        label: group.name,
        order: members.isEmpty ? 0 : members.first.order,
        icon: FluentIcons.folder_24_regular,
      );

  @override
  bool get isPlugin => true;
}

/// מציב כל קבוצה במקום החבר הראשון, בלי לשנות סדר או לחשוף תוספים מוסתרים.
List<ToolCatalogEntry> collapsePluginGroups(
  List<ToolCatalogEntry> entries,
  List<PluginGroup> groups,
) {
  if (groups.isEmpty) return entries;
  final groupForPlugin = <String, PluginGroup>{
    for (final group in groups)
      for (final id in group.pluginIds) id: group,
  };
  final members = <String, List<ToolCatalogEntry>>{};
  for (final entry in entries) {
    final group = entry.isPlugin ? groupForPlugin[entry.toolId] : null;
    if (group != null) (members[group.id] ??= []).add(entry);
  }
  final emitted = <String>{};
  final result = <ToolCatalogEntry>[];
  for (final entry in entries) {
    final group = entry.isPlugin ? groupForPlugin[entry.toolId] : null;
    if (group == null) {
      result.add(entry);
    } else if (emitted.add(group.id)) {
      result.add(
        PluginGroupCatalogEntry(group: group, members: members[group.id]!),
      );
    }
  }
  for (final group in groups) {
    if (emitted.add(group.id)) {
      result.add(PluginGroupCatalogEntry(group: group, members: const []));
    }
  }
  return result;
}

/// מזיז תיקייה יחד עם כל חבריה, כולל אלה שאינם מוצגים כרגע.
List<String> reorderPluginLauncherEntries(
  List<String> ids,
  ToolCatalogEntry source,
  ToolCatalogEntry target, {
  required bool placeAfter,
  List<String>? withinGroup,
}) {
  if (withinGroup != null) {
    final groupIds = withinGroup.toSet();
    final reordered = reorderIdsAroundTarget(
      ids.where(groupIds.contains).toList(),
      source.toolId,
      target.toolId,
      placeAfter: placeAfter,
    ).iterator;
    return [
      for (final id in ids)
        if (groupIds.contains(id) && reordered.moveNext())
          reordered.current
        else
          id,
    ];
  }
  Set<String> memberIds(ToolCatalogEntry entry) =>
      entry is PluginGroupCatalogEntry
      ? entry.group.pluginIds.toSet()
      : {entry.toolId};
  final sourceIds = memberIds(source);
  final targetIds = memberIds(target);
  final moved = ids.where(sourceIds.contains).toList();
  if (moved.isEmpty || sourceIds.intersection(targetIds).isNotEmpty) {
    return List.of(ids);
  }
  final remaining = ids.where((id) => !sourceIds.contains(id)).toList();
  final targetAnchor = target is PluginGroupCatalogEntry
      ? (target.members.isEmpty ? null : target.members.first.toolId)
      : target.toolId;
  final targetIndex = targetAnchor == null
      ? -1
      : remaining.indexOf(targetAnchor);
  if (targetIndex < 0) return List.of(ids);
  remaining.insertAll(targetIndex + (placeAfter ? 1 : 0), moved);
  return remaining;
}
