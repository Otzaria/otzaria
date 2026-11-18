import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/search/settings_search_index.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

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

  test('לכל תוצאת קיצור יש מפתח פעולה תקף וייחודי', () {
    final entries = ShortcutsSettingsTab.searchEntries
        .where((entry) => entry.id != 'shortcuts.reset')
        .toList();
    expect(entries, hasLength(52));
    expect(
      entries.map((entry) => entry.expandSection).toSet(),
      hasLength(entries.length),
    );
    for (final entry in entries) {
      expect(entry.expandSection, isNotNull, reason: entry.id);
      expect(
        ShortcutValidator.shortcutKeys,
        contains(entry.expandSection),
        reason: entry.id,
      );
      expect(
        ShortcutValidator.shortcutNames[entry.expandSection],
        isNotEmpty,
        reason: entry.id,
      );
    }
    expect(
      ShortcutsSettingsTab.searchEntries
          .singleWhere((entry) => entry.id == 'shortcuts.reset')
          .expandSection,
      isNull,
    );
  });

  test('חיפוש הדיווח באנגלית מפנה לקיצור האופציונלי', () {
    final entry = ShortcutsSettingsTab.searchEntries.singleWhere(
      (entry) => entry.id == 'shortcuts.nav.app_report',
    );
    const language = SettingsLanguage.english;
    const shortcutKey = ShortcutValidator.openAppReportKey;
    expect(entry.expandSection, shortcutKey);
    expect(ShortcutValidator.defaultShortcuts[shortcutKey], isEmpty);
    expect(entry.titleIn(language), 'Shortcut to report a software problem');
    expect(entry.subtitleIn(language), 'Open the software problem report form');
    expect(
      SettingsSearchIndex.search(
        'report a software problem',
        language: language,
      ),
      contains(entry),
    );
  });
}
