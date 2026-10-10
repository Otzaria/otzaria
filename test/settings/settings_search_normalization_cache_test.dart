import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/search/settings_search_index.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';

/// הציון במסלול שמנרמל את טקסטי הפריט מחדש בכל קריאה.
int _referenceScore(
  SettingsSearchEntry entry,
  String query,
  SettingsLanguage language,
) {
  int scoreFor(String title, String subtitle, List<String> keywords) {
    final n = SettingsSearchEntry.normalize;
    final t = n(title);
    var score = 0;
    if (t == query) {
      score += 100;
    } else if (t.startsWith(query)) {
      score += 60;
    } else if (t.contains(query)) {
      score += 40;
    }
    if (n(subtitle).contains(query)) score += 15;
    if (keywords.map(n).any((k) => k.contains(query))) score += 10;
    return score;
  }

  final source = SettingsLanguage.source;
  final hebrew = scoreFor(
    entry.titleIn(source),
    entry.subtitleIn(source),
    entry.keywords,
  );
  if (language == source) return hebrew;
  final translated = scoreFor(
    entry.titleIn(language),
    entry.subtitleIn(language),
    [
      for (final k in entry.keywords)
        resolveSettingsText(k, language: language),
    ],
  );
  return hebrew > translated ? hebrew : translated;
}

void main() {
  test('הטקסטים המנורמלים של פריט מחושבים פעם אחת לכל שפה', () {
    final entry = SettingsSearchIndex.allEntries.first;
    for (final language in SettingsLanguage.values) {
      expect(
        identical(entry.searchTextsIn(language), entry.searchTextsIn(language)),
        isTrue,
      );
    }
  });

  test('ציון ההתאמה זהה למסלול שמנרמל בכל קריאה, על כל האינדקס', () {
    const words = ['מצב כהה', 'גופן', 'גיבוי', 'קיצורי', 'dark mode', 'font'];
    final queries = {
      for (final w in words)
        for (var i = 1; i <= w.length; i++)
          SettingsSearchEntry.normalize(w.substring(0, i)),
    }..remove('');
    for (final language in SettingsLanguage.values) {
      for (final entry in SettingsSearchIndex.allEntries) {
        for (final q in queries) {
          expect(
            entry.matchScoreIn(q, language),
            _referenceScore(entry, q, language),
            reason: '${entry.id} / $language / "$q"',
          );
        }
      }
    }
  });
}
