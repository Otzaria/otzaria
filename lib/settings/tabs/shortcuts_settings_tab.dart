import 'package:flutter/material.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

/// טאב קיצורי מקלדת — מוצג רק בדסקטופ.
class ShortcutsSettingsTab extends StatelessWidget {
  const ShortcutsSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'shortcuts.reset',
      title: 'איפוס קיצורי מקשים',
      subtitle: 'החזרת כל קיצורי המקלדת לברירת המחדל',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['איפוס', 'ברירת מחדל', 'מקלדת'],
    ),
    // ── ניווט כללי ──
    SettingsSearchEntry(
      id: 'shortcuts.nav.library',
      title: 'קיצור לספרייה',
      subtitle: 'פתיחת מסך הספרייה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['ספרייה', 'ctrl+l', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.find_ref',
      title: 'קיצור לאיתור',
      subtitle: 'פתיחת מסך איתור מהיר',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['איתור', 'ctrl+o', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.reading',
      title: 'קיצור לעיון',
      subtitle: 'פתיחת מסך העיון בספרים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['עיון', 'ctrl+r', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.search_window',
      title: 'קיצור לחלון חיפוש חדש',
      subtitle: 'פתיחת חלון חיפוש',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['חיפוש', 'ctrl+q', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.settings',
      title: 'קיצור להגדרות',
      subtitle: 'פתיחת מסך ההגדרות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הגדרות', 'ctrl+comma', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.tools',
      title: 'קיצור לכלים',
      subtitle: 'פתיחת מסך הכלים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['כלים', 'ctrl+m', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.bookmarks',
      title: 'קיצור לסימניות',
      subtitle: 'פתיחת מסך הסימניות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סימניות', 'ctrl+shift+b', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.history',
      title: 'קיצור להיסטוריה',
      subtitle: 'פתיחת מסך ההיסטוריה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['היסטוריה', 'ctrl+h', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.workspace',
      title: 'קיצור להחלף שולחן עבודה',
      subtitle: 'מעבר בין שולחנות עבודה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['שולחן עבודה', 'workspace', 'ctrl+k', 'מקלדת'],
    ),
    // ── תצוגת ספר ──
    SettingsSearchEntry(
      id: 'shortcuts.book.search_in_book',
      title: 'קיצור לחיפוש בחלון הנוכחי',
      subtitle: 'משמש לחיפוש מהיר במסכי תוכן וכלים תומכים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['חיפוש', 'בספר', 'ctrl+f', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.print',
      title: 'קיצור להדפסה',
      subtitle: 'הדפסת התוכן הנוכחי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הדפסה', 'ctrl+p', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.bookmark',
      title: 'קיצור להוסף סימניה',
      subtitle: 'שמירת סימניה במיקום הנוכחי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סימניה', 'הוסף סימניה', 'ctrl+b', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.note',
      title: 'קיצור להוספת הערה',
      subtitle: 'הוספת הערה אישית',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הערה', 'אישית', 'ctrl+n', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.close',
      title: 'קיצור לסגור ספר נוכחי',
      subtitle: 'סגירת הספר הפתוח',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סגור ספר', 'ctrl+w', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.close_all',
      title: 'קיצור לסגור כל הספרים',
      subtitle: 'סגירת כל הספרים הפתוחים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סגור הכל', 'ctrl+shift+w', 'מקלדת'],
    ),
  ];

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
      primary: true,
      padding: const EdgeInsets.all(16.0),
      child: ToolPanelWrapper(
        key: tourShortcutsSettingsTargetKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── כללי (איפוס) ──────────────────────────────────────────────
            SettingsAnchor(
              cardId: 'shortcuts.main',
              child: SettingsCard(
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
                  settingKey: ShortcutValidator.currentWindowSearchKey,
                  label: 'חיפוש בחלון הנוכחי',
                  subtitle: 'משמש לחיפוש מהיר במסכי תוכן וכלים תומכים',
                  defaultShortcut: 'ctrl+f',
                  icon: FluentIcons.search_24_regular,
                  allShortcuts: _shortcutsList,
                ),
                // _ShortcutTile(
                //   settingKey: 'key-shortcut-edit-section',
                //   label: 'עריכת קטע',
                //   defaultShortcut: 'ctrl+e',
                //   icon: FluentIcons.document_edit_24_regular,
                //   allShortcuts: _shortcutsList,
                // ),
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
  final String? subtitle;
  final String defaultShortcut;
  final IconData icon;
  final Map<String, String> allShortcuts;

  const _ShortcutTile({
    required this.settingKey,
    required this.label,
    this.subtitle,
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
        subtitle: subtitle,
        selected: defaultShortcut,
        allShortcuts: allShortcuts,
        leading: Icon(icon),
      ),
    );
  }
}
