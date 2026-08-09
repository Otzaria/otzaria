import 'package:otzaria/indexing/repository/indexing_repository.dart';

/// זיהוי היקף חיפוש כ"ספרי יסוד", בלי לסרוק את הספרייה.
///
/// ה-facet של ספר מסתיים במפתח שלו (`id:123` / `uid:7`), ולכן די בהשוואה מול
/// מזהי ספרי היסוד — שאילתת DB זולה שנטענת ממילא — כדי לדעת שהוא ספר יסוד.
/// [treeFacets] מוסיף את מה שרק סיווג מלא של הספרייה יודע: ספרי יסוד ללא
/// מזהה, ותיקיות שכל ספריהן ספרי יסוד (בחירה מתקפלת לעתים ל-facet של תיקיה).
class BaseBooksScope {
  const BaseBooksScope({
    this.officialIds = const {},
    this.userIds = const {},
    this.treeFacets = const {},
  });

  final Set<int> officialIds;
  final Set<int> userIds;
  final Set<String> treeFacets;

  bool get isEmpty =>
      officialIds.isEmpty && userIds.isEmpty && treeFacets.isEmpty;

  BaseBooksScope withTreeFacets(Set<String> facets) => BaseBooksScope(
    officialIds: officialIds,
    userIds: userIds,
    treeFacets: facets,
  );

  /// האם [facet] כולו בתוך ספרי היסוד.
  bool covers(String facet) {
    if (treeFacets.contains(facet)) return true;
    final key = facet.substring(facet.lastIndexOf('/') + 1);
    final id = _idOf(key, IndexingRepository.officialBookKeyPrefix);
    if (id != null) return officialIds.contains(id);
    final userId = _idOf(key, IndexingRepository.userBookKeyPrefix);
    if (userId != null) return userIds.contains(userId);
    return false;
  }

  static int? _idOf(String key, String prefix) => key.startsWith(prefix)
      ? int.tryParse(key.substring(prefix.length))
      : null;
}
