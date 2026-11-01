import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';

void main() {
  test('כל רשומת חיפוש של קיצור מפנה לכרטיס שבו הקיצור מוצג', () {
    const cardByPrefix = {
      'shortcuts.nav.': 'shortcuts.nav',
      'shortcuts.book.': 'shortcuts.book',
      'shortcuts.zoom': 'shortcuts.book',
      'shortcuts.calendar.': 'shortcuts.calendar',
      'shortcuts.shamor_zachor.': 'shortcuts.calendar',
      'shortcuts.open_tool.': 'shortcuts.open_tools',
      'shortcuts.copy_link.': 'shortcuts.copy_links',
    };

    for (final entry in ShortcutsSettingsTab.searchEntries) {
      if (entry.id == 'shortcuts.reset') {
        expect(entry.cardId, 'shortcuts.main');
        continue;
      }
      final prefix = cardByPrefix.keys.firstWhere(
        entry.id.startsWith,
        orElse: () => '',
      );
      expect(prefix, isNotEmpty, reason: 'אין כרטיס צפוי עבור ${entry.id}');
      expect(entry.cardId, cardByPrefix[prefix], reason: entry.id);
    }
  });
}
