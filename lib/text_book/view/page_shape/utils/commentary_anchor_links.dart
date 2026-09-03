import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

/// עוגני מפרשי-המפרש בעמודת מפרש בצורת הדף — למשל אותיות שער הציון בתוך
/// המשנה ברורה (במסד: קישור COMMENTARY שמקורו במשנה ברורה, עם עוגן-אות).
/// המפרש-על אינו מוגדר כמפרש של הספר הראשי; רק סמני האותיות שלו מוזרקים
/// לטקסט המפרש, עם פופאפ צפייה (issue #1069).

/// שמות הספרים התלויים בספר המפרש (מפרשיו שלו), מתוך סיכום קישורי הספר.
/// LINKER והפניות צדדיות מוחרגים — רק טקסט תלוי מקבל סמן-אות.
Set<String> commentaryAnchorTargetTitles(List<LinkTargetSummary> targets) {
  return {
    for (final target in targets)
      if (LinkTypes.isDependentTextLink(target.connectionType))
        target.targetTitle,
  };
}

/// מסנן מקישורי הטווח את עוגני מפרשי-המפרש בלבד — קישור תלוי-טקסט שנושא
/// מיקום עוגן בתוך השורה.
List<Link> filterCommentaryAnchorLinks(Iterable<Link> links) {
  return links
      .where(
        (link) =>
            link.anchorStart != null &&
            LinkTypes.isDependentTextLink(link.connectionType),
      )
      .toList();
}

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
