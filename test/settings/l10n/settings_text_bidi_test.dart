import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

// \u2068 = First Strong Isolate, \u2069 = Pop Directional Isolate.
// כתובים כ-escape כדי שהציפייה תהיה קריאה — הם תווים בלתי נראים.

void main() {
  const catalog = {
    'חיפוש': 'Search',
    'מחיקת "{title}"?': 'Delete "{title}"?',
    '{count} ספרים': '{count} seforim',
  };

  group('בידוד כיווניות בהקשר LTR', () {
    test('טקסט שנפל ל-fallback העברי מבודד — הנקודה לא בורחת', () {
      final result = resolveSettingsText(
        'משפט עברי שאין לו תרגום.',
        language: SettingsLanguage.english,
        catalog: catalog,
      );

      expect(result, '\u2068משפט עברי שאין לו תרגום.\u2069');
    });

    test('טקסט מתורגם לאנגלית אינו מבודד — אין בו עברית', () {
      expect(
        resolveSettingsText(
          'חיפוש',
          language: SettingsLanguage.english,
          catalog: catalog,
        ),
        'Search',
      );
    });

    test('ערך עברי דינמי בתוך משפט אנגלי מבודד בנפרד', () {
      final result = resolveSettingsText(
        'מחיקת "{title}"?',
        language: SettingsLanguage.english,
        args: {'title': 'בבא קמא'},
        catalog: catalog,
      );

      // הגרשיים סביב שם הספר נשארים במקומם.
      expect(result, 'Delete "\u2068בבא קמא\u2069"?');
    });

    test('ערך דינמי שאינו עברי אינו מבודד', () {
      expect(
        resolveSettingsText(
          '{count} ספרים',
          language: SettingsLanguage.english,
          args: {'count': 42},
          catalog: catalog,
        ),
        '42 seforim',
      );
    });
  });

  group('בשפת המקור אין בידוד', () {
    test('כיוון הפסקה כבר RTL, ולכן הטקסט נקי מתווי בקרה', () {
      expect(
        resolveSettingsText(
          'משפט עברי שאין לו תרגום.',
          language: SettingsLanguage.hebrew,
          catalog: catalog,
        ),
        'משפט עברי שאין לו תרגום.',
      );
    });

    test('גם ערך דינמי עברי נשאר נקי', () {
      expect(
        resolveSettingsText(
          'מחיקת "{title}"?',
          language: SettingsLanguage.hebrew,
          args: {'title': 'בבא קמא'},
          catalog: catalog,
        ),
        'מחיקת "בבא קמא"?',
      );
    });
  });
}
