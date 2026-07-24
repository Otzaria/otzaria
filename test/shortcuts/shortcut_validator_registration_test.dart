import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

void main() {
  group('ShortcutValidator - רישום קיצורי החלוניות', () {
    test('המפתחות החדשים נמצאים ב-shortcutKeys', () {
      expect(
        ShortcutValidator.shortcutKeys,
        containsAll(<String>[
          'key-shortcut-toggle-nav-pane',
          'key-shortcut-toggle-commentators-pane',
          'key-shortcut-open-commentators-tab',
          'key-shortcut-restore-closed-tab',
        ]),
      );
    });

    test('ברירות מחדל: קיצורי החלוניות והשחזור מוגדרים כמצופה', () {
      expect(
        ShortcutValidator.defaultShortcuts['key-shortcut-toggle-nav-pane'],
        'ctrl+shift+l',
      );
      expect(
        ShortcutValidator
            .defaultShortcuts['key-shortcut-toggle-commentators-pane'],
        'ctrl+shift+c',
      );
      expect(
        ShortcutValidator.defaultShortcuts['key-shortcut-restore-closed-tab'],
        'ctrl+shift+t',
      );
      expect(
        ShortcutValidator
            .defaultShortcuts['key-shortcut-calendar-toggle-times'],
        'ctrl+t',
      );
      expect(
        ShortcutValidator
            .defaultShortcuts['key-shortcut-calendar-toggle-events'],
        'ctrl+e',
      );
      expect(
        ShortcutValidator
            .defaultShortcuts['key-shortcut-shamor-zachor-cycle-filter'],
        'ctrl+s',
      );
    });

    test('קיצורי ניווט קטע/דף-פרק רשומים עם ברירות מחדל ושמות', () {
      const navKeys = {
        'key-shortcut-prev-segment': ('alt+arrowup', 'הקטע הקודם'),
        'key-shortcut-next-segment': ('alt+arrowdown', 'הקטע הבא'),
        'key-shortcut-prev-toc': ('alt+pageup', 'הדף/פרק הקודם'),
        'key-shortcut-next-toc': ('alt+pagedown', 'הדף/פרק הבא'),
      };
      for (final entry in navKeys.entries) {
        expect(ShortcutValidator.shortcutKeys, contains(entry.key));
        expect(
          ShortcutValidator.defaultShortcuts[entry.key],
          entry.value.$1,
        );
        expect(ShortcutValidator.shortcutNames[entry.key], entry.value.$2);
      }
    });

    test('פתיחת כרטיסיית מפרשים — ללא ברירת מחדל (המשתמש יבחר)', () {
      expect(
        ShortcutValidator
            .defaultShortcuts['key-shortcut-open-commentators-tab'],
        '',
      );
    });

    test('חיפוש מתקדם — ללא ברירת מחדל (המשתמש יבחר)', () {
      expect(
        ShortcutValidator.shortcutKeys,
        contains(ShortcutValidator.openAdvancedSearchKey),
      );
      expect(
        ShortcutValidator.defaultShortcuts[ShortcutValidator
            .openAdvancedSearchKey],
        '',
      );
      expect(
        ShortcutValidator.shortcutNames[ShortcutValidator
            .openAdvancedSearchKey],
        'חיפוש מתקדם',
      );
    });

    test('שמות תצוגה בעברית קיימים', () {
      expect(
        ShortcutValidator.shortcutNames['key-shortcut-toggle-nav-pane'],
        'פתח/סגור חלונית ניווט',
      );
      expect(
        ShortcutValidator
            .shortcutNames['key-shortcut-toggle-commentators-pane'],
        'פתח/סגור חלונית מפרשים',
      );
      expect(
        ShortcutValidator.shortcutNames['key-shortcut-open-commentators-tab'],
        'פתח כרטיסיית מפרשים',
      );
      expect(
        ShortcutValidator.shortcutNames['key-shortcut-restore-closed-tab'],
        'פתח כרטיסייה אחרונה שנסגרה',
      );
    });

    test(
      'Ctrl+Shift+C, Ctrl+Shift+L ו-Ctrl+Shift+T אינם מתנגשים עם קיצורים אחרים',
      () {
        // עוברים על כל ברירות המחדל ומוודאים שלא יש כפילות עם הקיצורים החדשים
        const newShortcuts = {'ctrl+shift+l', 'ctrl+shift+c', 'ctrl+shift+t'};
        final clashes = <String, List<String>>{};
        for (final entry in ShortcutValidator.defaultShortcuts.entries) {
          if (newShortcuts.contains(entry.value) &&
              entry.key != 'key-shortcut-toggle-nav-pane' &&
              entry.key != 'key-shortcut-toggle-commentators-pane' &&
              entry.key != 'key-shortcut-restore-closed-tab') {
            clashes.putIfAbsent(entry.value, () => []).add(entry.key);
          }
        }
        expect(
          clashes,
          isEmpty,
          reason: 'נמצאו התנגשויות עם הקיצורים החדשים: $clashes',
        );
      },
    );

    test('ברירות המחדל אינן מכילות קיצורים כפולים', () {
      final shortcutToKeys = <String, List<String>>{};

      for (final entry in ShortcutValidator.defaultShortcuts.entries) {
        if (entry.value.isEmpty) continue;
        shortcutToKeys.putIfAbsent(entry.value, () => []).add(entry.key);
      }

      final duplicates = Map.fromEntries(
        shortcutToKeys.entries.where((entry) => entry.value.length > 1),
      );

      expect(
        duplicates,
        isEmpty,
        reason: 'נמצאו קיצורי ברירת מחדל כפולים: $duplicates',
      );
    });
  });
}
