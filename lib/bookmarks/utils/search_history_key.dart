import 'dart:convert';

import 'package:collection/collection.dart';

/// זהות חיפוש בהיסטוריה ובגיבוי: השאילתה, התחום והסינון בעץ התוצאות.
/// סדר בחירת הספרים אינו משנה את זהות החיפוש. בפריטים ישנים תחום חסר
/// פירושו כל הספרייה; סינון ריק במפורש פירושו שאין ספרים מסומנים.
String searchHistoryKey({
  required String query,
  List<String>? scopeFacets,
  List<String>? filterFacets,
}) {
  List<String> canonical(List<String> facets) =>
      facets.toSet().toList()..sort();
  final scope = canonical(
    scopeFacets == null || scopeFacets.isEmpty ? const ['/'] : scopeFacets,
  );
  final filter = filterFacets == null ? scope : canonical(filterFacets);
  return 'search:${jsonEncode([
    query,
    scope,
    if (!const ListEquality<String>().equals(scope, filter)) filter,
  ])}';
}
