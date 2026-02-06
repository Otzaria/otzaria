import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// A reusable navigation tree tile widget for displaying hierarchical items
/// in a sidebar navigation tree. Used by Personal Notes Manager and Shamor Zachor.
class NavigationTreeTile extends StatelessWidget {
  /// The title text to display
  final String title;

  /// The indentation level (0 = root, 1 = first level, etc.)
  final int level;

  /// Whether this tile is currently selected
  final bool isSelected;

  /// Whether this tile is expanded (shows children)
  final bool isExpanded;

  /// Whether this tile has children that can be expanded
  final bool hasChildren;

  /// Optional count to display (e.g., number of items)
  final int? count;

  /// The icon to display. Defaults to folder icons that change based on expansion state.
  final IconData? icon;

  /// Whether to use folder open/closed icons based on expansion state.
  /// If false, uses [icon] directly.
  final bool useFolderIcon;

  /// Callback when the tile is tapped
  final VoidCallback? onTap;

  /// Callback when the expand/collapse chevron is tapped
  final VoidCallback? onToggleExpand;

  /// Icon size. Defaults to 20 for categories, 18 for books.
  final double iconSize;

  /// Font size for the title. Defaults to 15 for categories, 14 for books.
  final double fontSize;

  /// Font weight for the title.
  final FontWeight fontWeight;

  /// Whether to show the bottom border divider
  final bool showDivider;

  /// Extra horizontal padding for nested items (e.g., books under categories)
  final double extraIndent;

  const NavigationTreeTile({
    super.key,
    required this.title,
    required this.level,
    this.isSelected = false,
    this.isExpanded = false,
    this.hasChildren = false,
    this.count,
    this.icon,
    this.useFolderIcon = true,
    this.onTap,
    this.onToggleExpand,
    this.iconSize = 20,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w600,
    this.showDivider = true,
    this.extraIndent = 0,
  });

  /// Factory constructor for category tiles (folders)
  factory NavigationTreeTile.category({
    Key? key,
    required String title,
    required int level,
    bool isSelected = false,
    bool isExpanded = false,
    bool hasChildren = false,
    int? count,
    VoidCallback? onTap,
    VoidCallback? onToggleExpand,
  }) {
    return NavigationTreeTile(
      key: key,
      title: title,
      level: level,
      isSelected: isSelected,
      isExpanded: isExpanded,
      hasChildren: hasChildren,
      count: count,
      useFolderIcon: true,
      onTap: onTap,
      onToggleExpand: onToggleExpand,
      iconSize: 20,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
  }

  /// Factory constructor for book tiles (leaf items)
  factory NavigationTreeTile.book({
    Key? key,
    required String title,
    required int level,
    bool isSelected = false,
    int? count,
    VoidCallback? onTap,
  }) {
    return NavigationTreeTile(
      key: key,
      title: title,
      level: level,
      isSelected: isSelected,
      isExpanded: false,
      hasChildren: false,
      count: count,
      icon: FluentIcons.book_24_regular,
      useFolderIcon: false,
      onTap: onTap,
      onToggleExpand: null,
      iconSize: 18,
      fontSize: 14,
      fontWeight: FontWeight.normal,
      extraIndent: 32.0, // Books are indented more than categories
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate horizontal padding based on level
    final rightPadding = 16.0 + (level * 24.0) + extraIndent;

    // Determine the icon to show
    IconData displayIcon;
    if (useFolderIcon) {
      displayIcon = isExpanded
          ? FluentIcons.folder_open_24_regular
          : FluentIcons.folder_24_regular;
    } else {
      displayIcon = icon ?? FluentIcons.document_24_regular;
    }

    // Icon color - primary for categories, onSurfaceVariant for books
    final iconColor =
        useFolderIcon ? colorScheme.primary : colorScheme.onSurfaceVariant;

    // Text color - primary for categories when using folder icon, otherwise default
    final textColor =
        useFolderIcon ? colorScheme.primary : colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsetsDirectional.only(
              start: rightPadding, // In RTL, start is on the right
              end: 16.0,
              top: 12.0,
              bottom: 12.0,
            ),
            child: Row(
              children: [
                Icon(
                  displayIcon,
                  color: iconColor,
                  size: iconSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: fontSize - 1,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (hasChildren)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onToggleExpand,
                      borderRadius: BorderRadius.circular(4),
                      excludeFromSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          isExpanded
                              ? FluentIcons.chevron_up_24_regular
                              : FluentIcons.chevron_down_24_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
