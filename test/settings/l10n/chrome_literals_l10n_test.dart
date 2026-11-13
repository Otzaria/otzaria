// מחרוזות כרום שעברו ל־settingsText (DD-20): בעברית הטקסט נשאר זהה בייט
// בבייט, ובאנגלית יש תרגום. הודעות התיקיות האישיות עברו לקטלוג UiSnack
// בלי שינוי בתוכן.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

const _chrome = {
  'לבטל את כל ההסתרות?': 'Unhide everything?',
  'כל הספרים והקטגוריות המוסתרים יחזרו להיראות בממשק.':
      'All hidden books and categories will be shown again.',
  'בטל הכול': null,
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

  test('הודעות התיקיות האישיות בקטלוג זהות לנוסח הקודם', () {
    expect(
      SettingsMessages.customFolderBooksChanged(3, 2),
      '3 ספרים נוספו, 2 עודכנו',
    );
    expect(SettingsMessages.customFolderFailedCount(4), 'כשל: 4');
    expect(
      SettingsMessages.customFolderAddedNoNewBooks,
      'התיקייה נוספה. לא נמצאו ספרים חדשים.',
    );
    expect(
      SettingsMessages.customFolderRemovedWithBooks,
      'התיקייה והספרים הוסרו מהתוכנה.',
    );
    expect(
      SettingsMessages.customFolderRemovedKeptBooks,
      'התיקייה הוסרה. הספרים נשארו בתוכנה.',
    );
    expect(
      SettingsMessages.customFolderContentRescanned,
      'תוכן הספרים נסרק ועודכן.\nמעתה הספרים ייקראו ישירות מהקבצים.',
    );
    expect(
      SettingsMessages.customFolderScanDone(5, 0),
      'הסריקה הושלמה: 5 ספרים נוספו, 0 עודכנו',
    );
    expect(
      SettingsMessages.customFolderScanNoNewBooks,
      'הסריקה הושלמה. לא נמצאו ספרים חדשים.',
    );
  });
}
