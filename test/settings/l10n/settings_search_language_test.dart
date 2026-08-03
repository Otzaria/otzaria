import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/search/settings_search_index.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';

void main() {
  const entry = SettingsSearchEntry(
    id: 'design.theme.dark_mode',
    title: 'מצב כהה',
    subtitle: 'מעבר בין מצב בהיר למצב כהה',
    tab: SettingsTab.design,
    keywords: ['ערכת נושא'],
  );

  String norm(String q) => SettingsSearchEntry.normalize(q);

  group('matchScoreIn', () {
    test('בעברית מוצא לפי המקור', () {
      expect(
        entry.matchScoreIn(norm('מצב כהה'), SettingsLanguage.hebrew),
        greaterThan(0),
      );
      expect(
        entry.matchScoreIn(norm('dark mode'), SettingsLanguage.hebrew),
        0,
        reason: 'במצב עברי אין חיפוש בתרגום',
      );
    });

    test('באנגלית מוצא לפי התרגום', () {
      expect(
        entry.matchScoreIn(norm('Dark mode'), SettingsLanguage.english),
        greaterThan(0),
      );
    });

    test('באנגלית גם עברית ממשיכה למצוא — לטובת דו-לשוניים', () {
      expect(
        entry.matchScoreIn(norm('מצב כהה'), SettingsLanguage.english),
        greaterThan(0),
      );
    });

    test('באנגלית מוצא לפי מילת מפתח מתורגמת', () {
      expect(
        entry.matchScoreIn(norm('Theme'), SettingsLanguage.english),
        greaterThan(0),
      );
    });

    test('שאילתה שאינה קיימת בשום שפה אינה מתאימה', () {
      for (final language in SettingsLanguage.values) {
        expect(entry.matchScoreIn(norm('zzzz'), language), 0);
      }
    });
  });

  group('SettingsSearchIndex.search', () {
    test('ברירת המחדל היא חיפוש עברי', () {
      expect(SettingsSearchIndex.search('מצב כהה'), isNotEmpty);
    });

    // "Interface density" הוא תרגום בלבד — אין לו מילת מפתח אנגלית בהצהרה,
    // בשונה מ-'dark mode' שכבר קיים כ-keyword בקוד המקורי.
    test('שאילתה שקיימת רק בתרגום מוצאת רק כשהשפה אנגלית', () {
      expect(
        SettingsSearchIndex.search('Interface density'),
        isEmpty,
        reason: 'במצב עברי אין חיפוש בתרגום',
      );
      expect(
        SettingsSearchIndex.search(
          'Interface density',
          language: SettingsLanguage.english,
        ),
        isNotEmpty,
      );
    });

    test('שאילתה עברית עובדת גם כשהשפה אנגלית', () {
      expect(
        SettingsSearchIndex.search(
          'מצב כהה',
          language: SettingsLanguage.english,
        ),
        isNotEmpty,
      );
    });

    test('שאילתה ריקה מחזירה ריק בכל שפה', () {
      for (final language in SettingsLanguage.values) {
        expect(SettingsSearchIndex.search('   ', language: language), isEmpty);
      }
    });
  });
}
