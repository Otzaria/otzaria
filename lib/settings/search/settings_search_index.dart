import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/search/settings_search_index.g.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';

/// אינדקס חיפוש בהגדרות. הפריטים עצמם מוצהרים בכל טאב/פנל בנפרד
/// (כ-`static const List<SettingsSearchEntry> searchEntries`),
/// והאיחוד נוצר אוטומטית אל קובץ `settings_search_index.g.dart`
/// (gitignored — לא נדחף לרפו).
///
/// **שתי דרכים לייצור הקובץ:**
/// 1. אוטומטית — `hook/build.dart` רץ על `flutter run` / `flutter build`.
/// 2. ידנית / CI — `dart run tool/generate_search_index.dart`.
///
/// **CI workflow** — הוסף לפני `flutter analyze` / `flutter test`:
/// ```yaml
/// - run: flutter pub get
/// - run: dart run tool/generate_search_index.dart
/// - run: flutter analyze
/// ```
///
/// **כדי להוסיף פריט חיפוש**: ערוך את `static const searchEntries`
/// שבטאב הרלוונטי. הקובץ המאוחד יתעדכן אוטומטית בבנייה הבאה.
class SettingsSearchIndex {
  static List<SettingsSearchEntry> get allEntries =>
      kGeneratedSettingsSearchEntries;

  /// מחפש לפי שאילתה ומחזיר תוצאות מסודרות לפי ציון התאמה.
  ///
  /// [language] היא שפת התצוגה של ההגדרות; בשפה שאינה עברית מחפשים גם
  /// בטקסטים המתורגמים, והמקור העברי נשאר בר-חיפוש.
  static List<SettingsSearchEntry> search(
    String query, {
    SettingsLanguage language = SettingsLanguage.source,
  }) {
    final normalized = SettingsSearchEntry.normalize(query);
    if (normalized.isEmpty) return const [];

    final scored = <(int, SettingsSearchEntry)>[];
    for (final entry in kGeneratedSettingsSearchEntries) {
      final score = entry.matchScoreIn(normalized, language);
      if (score > 0) {
        scored.add((score, entry));
      }
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((p) => p.$2).toList();
  }
}
