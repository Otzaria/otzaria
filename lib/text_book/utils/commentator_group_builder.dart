import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath, notesBookBaseTitle;

/// ספרים גדולים (מעל [kRareCommentatorMinBookLines] שורות) מסתירים מרשימת
/// בחירת המפרשים מפרשים "נדירים" — כאלה עם פחות מ-[kRareCommentatorMinLinks]
/// קישורים לספר. הם מוצגים ברשימה רק כשהשורה הנוכחית כוללת קישור מהם.
const int kRareCommentatorMinBookLines = 100;
const int kRareCommentatorMinLinks = 10;

/// מחזיר את שמות המפרשים הנדירים שיש להסתיר מרשימת הבחירה הכללית.
/// בספרים עד [kRareCommentatorMinBookLines] שורות מוחזרת קבוצה ריקה (אין הסתרה).
Set<String> computeRareCommentators({
  required int bookTotalLines,
  required Map<String, int> linkCountByCommentator,
}) {
  if (bookTotalLines <= kRareCommentatorMinBookLines) return const <String>{};
  return {
    for (final entry in linkCountByCommentator.entries)
      if (entry.value < kRareCommentatorMinLinks) entry.key,
  };
}

/// מחזיר מתוך [rareCommentators] את אלו שיש להם קישור-מפרש על אחת השורות
/// הנוכחיות ([currentIndexes], 0-based), לפי [linksByLine] (ממופתח 1-based).
/// אלו המפרשים הנדירים שכן יוצגו ברשימה כי הם רלוונטיים לשורה שהמשתמש עליה.
Set<String> lineRelevantRareCommentators({
  required Set<String> rareCommentators,
  required Iterable<int> currentIndexes,
  required Map<int, List<Link>> linksByLine,
}) {
  if (rareCommentators.isEmpty) return const <String>{};
  final relevant = <String>{};
  for (final idx in currentIndexes) {
    final lineLinks = linksByLine[idx + 1];
    if (lineLinks == null) continue;
    for (final link in lineLinks) {
      if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
      final title = getTitleFromPath(link.path2);
      if (rareCommentators.contains(title)) relevant.add(title);
    }
  }
  return relevant;
}

/// בונה את קבוצות המפרשים לפי דורות.
///
/// [baseCommentators] - המפרשים הבסיסיים של הספר (ממוינים לפי position).
/// בתוך כל קבוצה הם מוקדמים לראש הרשימה בסדר זה, ושאר המפרשים אחריהם.
List<CommentatorGroup> buildCommentatorGroups(
  Map<String, List<String>> eras,
  List<String> availableCommentators, {
  List<String> baseCommentators = const [],
}) {
  final known = <String>{
    ...?eras['תורה שבכתב'],
    ...?eras['חז"ל'],
    ...?eras['ראשונים'],
    ...?eras['אחרונים'],
    ...?eras['מחברי זמננו'],
  };

  final others = (eras['מפרשים נוספים'] ?? [])
      .toSet()
      .union(
        availableCommentators.where((c) => !known.contains(c)).toList().toSet(),
      )
      .toList();

  List<String> promote(List<String> commentators) =>
      _promoteBase(commentators, baseCommentators);

  final groups = [
    CommentatorGroup(
      title: 'תורה שבכתב',
      commentators: promote(eras['תורה שבכתב'] ?? const []),
    ),
    CommentatorGroup(
      title: 'חז"ל',
      commentators: promote(eras['חז"ל'] ?? const []),
    ),
    CommentatorGroup(
      title: 'ראשונים',
      commentators: promote(eras['ראשונים'] ?? const []),
    ),
    CommentatorGroup(
      title: 'אחרונים',
      commentators: promote(eras['אחרונים'] ?? const []),
    ),
    CommentatorGroup(
      title: 'מחברי זמננו',
      commentators: promote(eras['מחברי זמננו'] ?? const []),
    ),
    CommentatorGroup(title: 'שאר מפרשים', commentators: promote(others)),
  ];

  return _anchorNotesAfterBase(groups);
}

/// מעביר כל ספר "הערות על XX" לקבוצת הדור של XX ומציב אותו מיד אחרי XX,
/// כך שההערות לא נשמטות לקבוצה נפרדת מהספר שעליו נכתבו.
/// ספר-הערות שבסיסו אינו זמין נשאר במקומו.
List<CommentatorGroup> _anchorNotesAfterBase(List<CommentatorGroup> groups) {
  final allCommentators = <String>{
    for (final g in groups) ...g.commentators,
  };

  final notesByBase = <String, List<String>>{};
  for (final c in allCommentators) {
    final base = notesBookBaseTitle(c);
    if (base != null && allCommentators.contains(base)) {
      (notesByBase[base] ??= []).add(c);
    }
  }
  if (notesByBase.isEmpty) return groups;
  for (final notes in notesByBase.values) {
    notes.sort();
  }

  final relocated = notesByBase.values.expand((n) => n).toSet();

  void addWithNotes(String commentator, List<String> out) {
    out.add(commentator);
    for (final note in notesByBase[commentator] ?? const <String>[]) {
      addWithNotes(note, out);
    }
  }

  final result = <CommentatorGroup>[];
  for (final g in groups) {
    final ordered = <String>[];
    for (final c in g.commentators) {
      if (relocated.contains(c)) continue; // יתווסף מיד אחרי הבסיס שלו
      addWithNotes(c, ordered);
    }
    result.add(g.copyWith(commentators: ordered));
  }
  return result;
}

/// מקדים את המפרשים הבסיסיים לראש הקבוצה (בסדר [base]), ושאר המפרשים אחריהם
/// בסדר המקורי. אם אין מפרשים בסיסיים בקבוצה - מוחזרת הרשימה ללא שינוי.
List<String> _promoteBase(List<String> commentators, List<String> base) {
  if (base.isEmpty || commentators.isEmpty) return commentators;

  final commentatorsSet = commentators.toSet();
  final baseInGroup = base
      .where(commentatorsSet.contains)
      .toList(); // לפי סדר position
  if (baseInGroup.isEmpty) return commentators;

  final baseSet = baseInGroup.toSet();
  final rest = commentators.where((c) => !baseSet.contains(c)).toList();
  return [...baseInGroup, ...rest];
}
