import 'package:flutter/material.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/shortcuts/shortcut_dropdown_tile.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_card.dart';

/// טאב קיצורי מקלדת — מוצג רק בדסקטופ.
class ShortcutsSettingsTab extends StatelessWidget {
  const ShortcutsSettingsTab({super.key});

  static const Map<String, String> _shortcutsList = {
    'ctrl+a': 'CTRL + A',
    'ctrl+b': 'CTRL + B',
    'ctrl+c': 'CTRL + C',
    'ctrl+d': 'CTRL + D',
    'ctrl+e': 'CTRL + E',
    'ctrl+f': 'CTRL + F',
    'ctrl+g': 'CTRL + G',
    'ctrl+h': 'CTRL + H',
    'ctrl+i': 'CTRL + I',
    'ctrl+j': 'CTRL + J',
    'ctrl+k': 'CTRL + K',
    'ctrl+l': 'CTRL + L',
    'ctrl+m': 'CTRL + M',
    'ctrl+n': 'CTRL + N',
    'ctrl+o': 'CTRL + O',
    'ctrl+p': 'CTRL + P',
    'ctrl+q': 'CTRL + Q',
    'ctrl+r': 'CTRL + R',
    'ctrl+s': 'CTRL + S',
    'ctrl+t': 'CTRL + T',
    'ctrl+u': 'CTRL + U',
    'ctrl+v': 'CTRL + V',
    'ctrl+w': 'CTRL + W',
    'ctrl+x': 'CTRL + X',
    'ctrl+y': 'CTRL + Y',
    'ctrl+z': 'CTRL + Z',
    'ctrl+0': 'CTRL + 0',
    'ctrl+1': 'CTRL + 1',
    'ctrl+2': 'CTRL + 2',
    'ctrl+3': 'CTRL + 3',
    'ctrl+4': 'CTRL + 4',
    'ctrl+5': 'CTRL + 5',
    'ctrl+6': 'CTRL + 6',
    'ctrl+7': 'CTRL + 7',
    'ctrl+8': 'CTRL + 8',
    'ctrl+9': 'CTRL + 9',
    'ctrl+comma': 'CTRL + ,',
    'ctrl+shift+b': 'CTRL + SHIFT + B',
    'ctrl+shift+w': 'CTRL + SHIFT + W',
  };

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return const Center(child: Text('קיצורי מקשים זמינים רק בדסקטופ'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── כללי (איפוס) ──────────────────────────────────────────────
          SettingsCard(
            title: 'כללי',
            children: [
              ListTile(
                hoverColor: Colors.transparent,
                leading: const Icon(FluentIcons.arrow_reset_24_regular),
                title: const Text('איפוס קיצורי מקשים',
                    style: kSettingsTitleStyle),
                subtitle: const Text(
                  'החזר את כל קיצורי המקשים לברירת המחדל',
                  style: kSettingsSubtitleStyle,
                ),
                trailing: NeutralActionButton(
                  text: 'איפוס',
                  onPressed: () => _resetShortcuts(context),
                ),
              ),
            ],
          ),

          kSettingsCardSpacing,

          // ── ניווט כללי ────────────────────────────────────────────────
          SettingsCard(
            title: 'ניווט כללי',
            children: [
              _ShortcutTile(
                settingKey: 'key-shortcut-open-library-browser',
                label: 'ספרייה',
                defaultShortcut: 'ctrl+l',
                icon: FluentIcons.library_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-find-ref',
                label: 'איתור',
                defaultShortcut: 'ctrl+o',
                icon: FluentIcons.book_search_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-reading-screen',
                label: 'עיון',
                defaultShortcut: 'ctrl+r',
                icon: FluentIcons.book_open_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-new-search',
                label: 'חלון חיפוש חדש',
                defaultShortcut: 'ctrl+q',
                icon: FluentIcons.search_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-settings',
                label: 'הגדרות',
                defaultShortcut: 'ctrl+comma',
                icon: FluentIcons.settings_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-more',
                label: 'כלים',
                defaultShortcut: 'ctrl+m',
                icon: FluentIcons.apps_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-bookmarks',
                label: 'סימניות',
                defaultShortcut: 'ctrl+shift+b',
                icon: FluentIcons.bookmark_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-open-history',
                label: 'היסטוריה',
                defaultShortcut: 'ctrl+h',
                icon: FluentIcons.history_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-switch-workspace',
                label: 'החלף שולחן עבודה',
                defaultShortcut: 'ctrl+k',
                icon: FluentIcons.grid_24_regular,
                allShortcuts: _shortcutsList,
              ),
            ],
          ),

          kSettingsCardSpacing,

          // ── תצוגת ספר ─────────────────────────────────────────────────
          SettingsCard(
            title: 'תצוגת ספר',
            children: [
              _ShortcutTile(
                settingKey: 'key-shortcut-search-in-book',
                label: 'חיפוש בספר',
                defaultShortcut: 'ctrl+f',
                icon: FluentIcons.search_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-edit-section',
                label: 'עריכת קטע',
                defaultShortcut: 'ctrl+e',
                icon: FluentIcons.document_edit_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-print',
                label: 'הדפסה',
                defaultShortcut: 'ctrl+p',
                icon: FluentIcons.print_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-add-bookmark',
                label: 'הוסף סימניה',
                defaultShortcut: 'ctrl+b',
                icon: FluentIcons.bookmark_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-add-note',
                label: 'הוספת הערה',
                defaultShortcut: 'ctrl+n',
                icon: FluentIcons.note_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-close-tab',
                label: 'סגור ספר נוכחי',
                defaultShortcut: 'ctrl+w',
                icon: FluentIcons.dismiss_circle_24_regular,
                allShortcuts: _shortcutsList,
              ),
              _ShortcutTile(
                settingKey: 'key-shortcut-close-all-tabs',
                label: 'סגור כל הספרים',
                defaultShortcut: 'ctrl+shift+w',
                icon: FluentIcons.dismiss_24_regular,
                allShortcuts: _shortcutsList,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resetShortcuts(BuildContext context) async {
    final confirmed = await showWarningDialog(
      context: context,
      title: 'איפוס קיצורי מקשים?',
      content: 'כל קיצורי המקשים המותאמים אישית יאופסו לברירת המחדל.',
      subtitle: 'פעולה זו אינה הפיכה',
    );
    if (confirmed == true && context.mounted) {
      context.read<SettingsBloc>().add(ResetShortcuts());
      UiSnack.showSuccess('קיצורי המקשים אופסו בהצלחה');
    }
  }
}

// ── _ShortcutTile ─────────────────────────────────────────────────────────────
// פה מחקנו את כל עטיפות ה-Theme המסורבלות
class _ShortcutTile extends StatelessWidget {
  final String settingKey;
  final String label;
  final String defaultShortcut;
  final IconData icon;
  final Map<String, String> allShortcuts;

  const _ShortcutTile({
    required this.settingKey,
    required this.label,
    required this.defaultShortcut,
    required this.icon,
    required this.allShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.merge(kSettingsTitleStyle),
      child: ShortcutDropDownTile(
        settingKey: settingKey,
        title: label,
        selected: defaultShortcut,
        allShortcuts: allShortcuts,
        leading: Icon(icon),
      ),
    );
  }
}
