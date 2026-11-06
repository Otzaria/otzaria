import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

/// עוגני ספר המפרש בטור מפרש בצורת הדף: אותיות מפרשי-המפרש (שער הציון בתוך
/// המשנה ברורה, issue #1069) וציטוטי הלינקר. המפרש-על אינו מפרש של הספר הראשי.

/// שמות הספרים שעוגניהם מוצגים בטור המפרש, מתוך סיכום קישורי הספר.
Set<String> commentaryAnchorTargetTitles(List<LinkTargetSummary> targets) {
  return {
    for (final target in targets)
      if (_isColumnAnchorType(target.connectionType)) target.targetTitle,
  };
}

/// מסנן מקישורי הטווח את עוגני הטור בלבד — קישור תלוי-טקסט או לינקר שנושא
/// מיקום עוגן בתוך השורה.
List<Link> filterCommentaryAnchorLinks(Iterable<Link> links) {
  return links
      .where(
        (link) =>
            link.anchorStart != null &&
            _isColumnAnchorType(link.connectionType),
      )
      .toList();
}

bool _isColumnAnchorType(String? type) =>
    LinkTypes.isDependentTextLink(type) ||
    LinkTypes.normalize(type) == LinkTypes.linker;

/// ממזג קישורי עוגן שנשלפו לטווח שורות אל המפה הקיימת (מפתח: מספר שורה
/// 1-based, כמו [Link.index1]). מחזיר מפה חדשה — הקיימת אינה משתנה, כדי
/// שהשוואת זהות תזהה עדכון.
Map<int, List<Link>> mergeAnchorLinksByLine(
  Map<int, List<Link>> existing,
  Iterable<Link> fetched,
) {
  final byLine = <int, List<Link>>{};
  for (final link in fetched) {
    byLine.putIfAbsent(link.index1, () => []).add(link);
  }
  if (byLine.isEmpty) return existing;
  // שורה שנשלפה מחדש מוחלפת כולה — שליפה חוזרת של טווח אינה מכפילה סמנים.
  return Map<int, List<Link>>.of(existing)..addAll(byLine);
}
