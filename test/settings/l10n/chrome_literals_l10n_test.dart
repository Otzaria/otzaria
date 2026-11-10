// מחרוזות כרום שעברו ל־settingsText (DD-20): בעברית הטקסט נשאר זהה בייט
// בבייט, ובאנגלית יש תרגום.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

const _chrome = {
  'צא ממסך מלא': null,
  'מסך מלא': null,
  'החלונית נעוצה לפי ההגדרות': 'The panel is pinned in the settings',
  'בטל נעיצה': 'Unpin',
  'נעץ את החלונית': 'Pin the panel',
  'הסתר ניווט': 'Hide navigation',
  'הצג ניווט': 'Show navigation',
  'סגור חיפוש': 'Close search',
  'עוד פעולות': null,
  'הזנת סיסמה': 'Enter password',
  'סיסמה': null,
  'אישור': null,
  'ביטול': null,
  'נסה שוב': null,
  'מחק': null,
  'ערוך תיאור': 'Edit description',
  'נקה סינון': 'Clear filter',
};

void main() {
  final english = kSettingsCatalogs['en']!;

  test('בעברית הטקסט זהה למקור, ובאנגלית יש תרגום', () {
    for (final MapEntry(key: hebrew, value: expected) in _chrome.entries) {
      expect(
        resolveSettingsText(hebrew, language: SettingsLanguage.hebrew),
        hebrew,
        reason: hebrew,
      );
      final translated = english[hebrew];
      expect(translated, isNotNull, reason: 'חסר תרגום: $hebrew');
      expect(translated, isNot(hebrew), reason: hebrew);
      if (expected != null) expect(translated, expected, reason: hebrew);
    }
  });

  test('הודעת השגיאה עם ערך: זהה בעברית, מתורגמת באנגלית', () {
    expect(
      resolveSettingsText(
        'שגיאה: {error}',
        language: SettingsLanguage.hebrew,
        args: {'error': 'x'},
      ),
      'שגיאה: x',
    );
    expect(english['שגיאה: {error}'], 'Error: {error}');
  });

  testWidgets('כפתור חלונית הניווט מתורגם לפי שפת הממשק', (tester) async {
    Future<String?> tooltip(SettingsLanguage language) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsTextScope(
            language: language,
            child: Scaffold(
              body: NavPanelToggleButton(isOpen: true, onToggle: () {}),
            ),
          ),
        ),
      );
      return tester.widget<IconButton>(find.byType(IconButton)).tooltip;
    }

    expect(await tooltip(SettingsLanguage.hebrew), 'הסתר ניווט');
    expect(await tooltip(SettingsLanguage.english), 'Hide navigation');
  });
}
