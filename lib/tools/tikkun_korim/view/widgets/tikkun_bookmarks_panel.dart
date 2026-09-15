/// חלונית הסימניות של "תיקון קוראים".
library;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

class TikkunBookmarksPanel extends StatelessWidget {
  final List<TikkunBookmark> bookmarks;

  /// `null` כשאין מה לסמן (אין תוכן מוצג).
  final VoidCallback? onAdd;
  final ValueChanged<TikkunBookmark> onOpen;
  final ValueChanged<TikkunBookmark> onRemove;

  const TikkunBookmarksPanel({
    super.key,
    required this.bookmarks,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ActionButton.recommended(
            text: 'הוסף סימניה למיקום הנוכחי',
            icon: FluentIcons.bookmark_add_24_regular,
            onPressed: onAdd,
          ),
        ),
        if (bookmarks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'אין סימניות עדיין',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final bookmark in bookmarks)
          ListTile(
            hoverColor: Colors.transparent,
            leading: const Icon(FluentIcons.bookmark_24_regular),
            title: Text(bookmark.title),
            subtitle: Text(bookmark.nav.section.label),
            onTap: () => onOpen(bookmark),
            trailing: IconButton(
              tooltip: 'מחק סימניה',
              icon: const Icon(FluentIcons.delete_24_regular),
              onPressed: () => onRemove(bookmark),
            ),
          ),
      ],
    );
  }
}
