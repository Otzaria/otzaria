import 'package:flutter/material.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

List<AppContextMenuEntry> buildPluginContextMenuEntries({
  required List<(String pluginId, PluginContextMenuItem item)> records,
  required Map<String, dynamic> selection,
  String context = 'reader-selection',
  PluginRuntimeDispatcher? dispatcher,
}) {
  final runtime = dispatcher ?? PluginRuntimeDispatcher.instance;
  return [
    for (final record in records)
      if (record.$2.contexts.contains(context))
        _buildEntry(
          pluginId: record.$1,
          item: record.$2,
          selection: selection,
          context: context,
          dispatcher: runtime,
        ),
  ];
}

AppContextMenuEntry _buildEntry({
  required String pluginId,
  required PluginContextMenuItem item,
  required Map<String, dynamic> selection,
  required String context,
  required PluginRuntimeDispatcher dispatcher,
}) {
  if (item.type == 'separator') return const AppContextMenuEntry.divider();
  if (item.type == 'color-row') {
    return AppContextMenuEntry.colorRow([
      for (final color in item.colors)
        AppContextMenuColorAction(
          id: color.id,
          color: _parseColor(color.color),
          label: color.label,
          icon: fluentIconFromName(color.icon),
          selected: color.selected,
          onTap: () => dispatcher.dispatchEventToPlugin(
            pluginId,
            item.onColorClickEvent ?? 'contextMenu.colorClicked',
            {
              'itemId': item.id,
              'colorId': color.id,
              'color': color.color,
              'selection': selection,
            },
            preferBackground: true,
          ),
        ),
    ]);
  }
  if (item.type == 'submenu') {
    return AppContextMenuEntry(
      label: item.label,
      icon: fluentIconFromName(item.icon),
      children: [
        for (final child in item.children)
          if (child.contexts.contains(context))
            _buildEntry(
              pluginId: pluginId,
              item: child,
              selection: selection,
              context: context,
              dispatcher: dispatcher,
            ),
      ],
    );
  }
  return AppContextMenuEntry(
    label: item.label,
    icon: fluentIconFromName(item.icon),
    onTap: () => _dispatchItemClick(
      dispatcher: dispatcher,
      pluginId: pluginId,
      item: item,
      selection: selection,
    ),
  );
}

Future<void> _dispatchItemClick({
  required PluginRuntimeDispatcher dispatcher,
  required String pluginId,
  required PluginContextMenuItem item,
  required Map<String, dynamic> selection,
}) async {
  final payload = <String, dynamic>{
    'itemId': item.id,
    'selection': selection,
    'selectedText':
        selection['renderedSelectedText'] ?? selection['text'] ?? '',
    'currentRef': selection['currentRef'],
    'currentBook': selection['bookTitle'] ?? selection['currentBook'],
    'currentBookId': selection['bookId'] ?? selection['currentBookId'],
    'currentIndex': selection['sectionIndex'] ?? selection['currentIndex'],
    if (selection['id'] != null) 'id': selection['id'],
    if (selection['type'] != null) 'type': selection['type'],
    'param': item.param,
  };
  if (item.openPlugin) {
    // אותם אירועים כמו במסלול הרגיל, בתור המסירה של דף התוסף.
    PluginPageLauncher.instance.open(
      pluginId,
      topic: item.onClickEvent ?? 'contextMenu.itemClicked',
      payload: payload,
    );
    if (item.onClickEvent == null) {
      PluginPageLauncher.instance.open(
        pluginId,
        topic: 'reader.context_menu_item_clicked',
        payload: payload,
      );
    }
    return;
  }
  await dispatcher.dispatchEventToPlugin(
    pluginId,
    item.onClickEvent ?? 'contextMenu.itemClicked',
    payload,
    preferBackground: true,
  );
  if (item.onClickEvent == null) {
    await dispatcher.dispatchEventToPlugin(
      pluginId,
      'reader.context_menu_item_clicked',
      payload,
      preferBackground: true,
    );
  }
}

Color _parseColor(String value) {
  final hex = value.substring(1);
  final rgb = int.parse(hex.substring(0, 6), radix: 16);
  final alpha = hex.length == 8
      ? int.parse(hex.substring(6, 8), radix: 16)
      : 0xFF;
  return Color((alpha << 24) | rgb);
}
