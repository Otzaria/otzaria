import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// Describes a context menu as one line per entry, for characterization
/// tests. Disabled entries end with " (disabled)", selected ones with " [x]",
/// dividers are "---", and submenu entries are indented under their parent.
List<String> describeContextMenu(
  List<AppContextMenuEntry> entries, {
  int depth = 0,
}) {
  final indent = '  ' * depth;
  final lines = <String>[];
  for (final entry in entries) {
    if (entry.isDivider) {
      lines.add('$indent---');
      continue;
    }
    final icons = entry.iconRowActions;
    if (icons != null) {
      final labels = [
        for (final action in icons)
          '${action.label ?? action.tooltip}'
              '${action.enabled ? '' : ' (disabled)'}'
              '${action.submenuBuilder != null ? ' >' : ''}',
      ];
      lines.add('$indent[${labels.join(' | ')}]');
      continue;
    }
    if (entry.colorRowActions != null) {
      lines.add('$indent[colors]');
      continue;
    }
    lines.add(
      '$indent${entry.label}'
      '${entry.enabled ? '' : ' (disabled)'}'
      '${entry.isSelected ? ' [x]' : ''}',
    );
    final children = entry.children ?? entry.childrenBuilder?.call();
    if (children != null) {
      lines.addAll(describeContextMenu(children, depth: depth + 1));
    }
  }
  return lines;
}
