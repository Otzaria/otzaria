import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// שתי התוויות של תפריט "עריכה" שלא היו בקטלוג האנגלי ("עריכה", "בצע שוב"):
/// בלי ערך ב-`settings_en.arb` הן נשארות בעברית בתפריט המערכת של מק באנגלית.
Iterable<PlatformMenuItem> _items(Iterable<PlatformMenuItem> menus) sync* {
  for (final menu in menus) {
    yield menu;
    if (menu is PlatformMenu) yield* _items(menu.menus);
    if (menu is PlatformMenuItemGroup) yield* _items(menu.members);
  }
}

void main() {
  test('באנגלית כותרת התפריט היא Edit ופעולת החזרה היא Redo', () {
    final menu = buildMacEditMenu(language: SettingsLanguage.english);
    expect(menu.label, 'Edit');
    expect(
      [
        for (final item in _items(menu.menus))
          if (item.onSelected != null) item.label,
      ],
      ['Undo', 'Redo', 'Cut', 'Copy', 'Paste', 'Select All'],
    );
  });
}
