import 'package:otzaria/settings/search/settings_search_index.g.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';

/// אינדקס חיפוש בהגדרות. הפריטים עצמם מוצהרים בכל טאב/פנל בנפרד
/// (כ-`static const List<SettingsSearchEntry> searchEntries`),
/// והאיחוד נוצר אוטומטית על ידי `hook/build.dart` בכל
/// `flutter run` / `flutter build` אל קובץ
/// `settings_search_index.g.dart`.
///
/// כדי להוסיף פריט חיפוש: ערוך את `static const searchEntries` שבטאב
/// הרלוונטי. הקובץ המאוחד יתעדכן אוטומטית בבנייה הבאה.
class SettingsSearchIndex {
  static List<SettingsSearchEntry> get allEntries =>
      kGeneratedSettingsSearchEntries;

  /// מחפש לפי שאילתה ומחזיר תוצאות מסודרות לפי ציון התאמה.
  static List<SettingsSearchEntry> search(String query) {
    final normalized = SettingsSearchEntry.normalize(query);
    if (normalized.isEmpty) return const [];

    final scored = <(int, SettingsSearchEntry)>[];
    for (final entry in kGeneratedSettingsSearchEntries) {
      final score = entry.matchScore(normalized);
      if (score > 0) {
        scored.add((score, entry));
      }
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((p) => p.$2).toList();
  }
}
