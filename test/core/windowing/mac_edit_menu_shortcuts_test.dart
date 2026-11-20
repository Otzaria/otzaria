import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// מקשי הקיצור של תפריט "עריכה" במק (q114, 19.11): קיימים בקוד אבל כבויים עד
/// בדיקה על מק אמיתי. החשש: מקש שמוצהר בתפריט נתפס בידי macOS לפני Flutter,
/// ועלול לבלוע Cmd+C לפני תצוגת ה-WebView של תוסף.
Iterable<PlatformMenuItem> _actionItems(PlatformMenu menu) sync* {
  for (final group in menu.menus.whereType<PlatformMenuItemGroup>()) {
    for (final member in group.members) {
      if (member.onSelected != null) yield member;
    }
  }
}

/// SingleActivator אינו מגדיר ==, ולכן משווים תיאור טקסטואלי שלו.
String? _describe(MenuSerializableShortcut? shortcut) {
  if (shortcut == null) return null;
  final a = shortcut as SingleActivator;
  return [
    if (a.control) 'Ctrl',
    if (a.alt) 'Alt',
    if (a.shift) 'Shift',
    if (a.meta) 'Cmd',
    a.trigger.keyLabel,
  ].join('+');
}

Map<String, String?> _shortcuts(PlatformMenu menu) => {
  for (final item in _actionItems(menu)) item.label: _describe(item.shortcut),
};

void main() {
  test('הדגל כבוי כברירת מחדל', () {
    expect(kMacEditMenuShortcutsEnabled, isFalse);
  });

  test('כשהדגל כבוי (ברירת המחדל) אין מקש באף פריט', () {
    final menu = buildMacEditMenu(language: SettingsLanguage.hebrew);
    expect(_actionItems(menu), hasLength(6));
    for (final entry in _shortcuts(menu).entries) {
      expect(entry.value, isNull, reason: entry.key);
    }
  });

  test(
    'כשהוא מופעל דרך הפרמטר, המקשים מוגדרים נכון (Cmd, לפי המוסכמה של מק)',
    () {
      final menu = buildMacEditMenu(
        language: SettingsLanguage.hebrew,
        shortcutsEnabled: true,
      );
      expect(_shortcuts(menu), {
        'בטל': 'Cmd+Z',
        'בצע שוב': 'Shift+Cmd+Z',
        'גזור': 'Cmd+X',
        'העתק': 'Cmd+C',
        'הדבק': 'Cmd+V',
        'בחר הכל': 'Cmd+A',
      });
    },
  );

  test('הפעלת המקשים לא משנה את המבנה והתוויות', () {
    List<List<String>> labels(PlatformMenu menu) => [
      for (final group in menu.menus.whereType<PlatformMenuItemGroup>())
        [for (final member in group.members) member.label],
    ];
    expect(
      labels(
        buildMacEditMenu(
          language: SettingsLanguage.hebrew,
          shortcutsEnabled: true,
        ),
      ),
      labels(buildMacEditMenu(language: SettingsLanguage.hebrew)),
    );
  });
}
