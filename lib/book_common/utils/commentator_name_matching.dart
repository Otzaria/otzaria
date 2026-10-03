/// מחזיר את שם המפרש בלי שם הספר שהוא מפרש.
/// "רמב"ן על ברכות" → "רמב"ן"; "יכין מקואות" עם [commentedBookTitle]
/// "משנה מקואות" → "יכין". יש משפחות מפרשים שאינן כוללות "על" בשם.
String? pageShapeCommentatorBaseName(
  String? fullName, {
  String? commentedBookTitle,
}) {
  if (fullName == null) return null;

  final onIndex = fullName.indexOf(' על ');
  if (onIndex > 0) {
    return fullName.substring(0, onIndex).trim();
  }

  if (commentedBookTitle == null || commentedBookTitle.isEmpty) {
    return fullName;
  }

  final nameWords = _splitWords(fullName);
  final bookWords = _splitWords(commentedBookTitle);

  // שם שכולו שם הספר אינו נושא חלק-מפרש שאפשר לבודד.
  if (nameWords.join(' ') == bookWords.join(' ')) return fullName;

  var shared = 0;
  while (shared < nameWords.length - 1 &&
      shared < bookWords.length &&
      nameWords[nameWords.length - 1 - shared] ==
          bookWords[bookWords.length - 1 - shared]) {
    shared++;
  }

  if (shared == 0) return fullName;
  return nameWords.take(nameWords.length - shared).join(' ');
}

List<String> _splitWords(String value) =>
    value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

/// מחפש את שם המפרש המלא מתוך רשימת המפרשים הזמינים.
///
/// [commentedBookTitle] מאפשר להתאים גם בחירה ישנה שנשמרה עם שם ספר אחר צרוב
/// בתוכה ("יכין מקואות" בזמן קריאה במסכת נדה).
String? findMatchingPageShapeCommentator(
  String? selection,
  List<String> availableCommentators, {
  String? commentedBookTitle,
}) {
  if (selection == null) {
    return null;
  }

  for (final predicate in <bool Function(String)>[
    (commentator) => commentator == selection,
    (commentator) => commentator.startsWith(selection),
    (commentator) => commentator.contains(selection),
    (commentator) => selection.contains(commentator),
  ]) {
    for (final commentator in availableCommentators) {
      if (predicate(commentator)) {
        return commentator;
      }
    }
  }

  return _matchByCommentatorBase(
    selection,
    availableCommentators,
    commentedBookTitle,
  );
}

/// מתאים בחירה ישנה למפרש שחלק-המפרש שלו הוא מילות הפתיחה של הבחירה.
/// דורש גבול-מילה מלא, ובוחר את ההתאמה הארוכה ביותר, כדי ש"תוספות רבי עקיבא
/// איגר" לא ייקלט כ"תוספות יום טוב".
String? _matchByCommentatorBase(
  String selection,
  List<String> availableCommentators,
  String? commentedBookTitle,
) {
  if (commentedBookTitle == null || commentedBookTitle.isEmpty) {
    return null;
  }

  String? best;
  var bestLength = 0;

  for (final commentator in availableCommentators) {
    final base = pageShapeCommentatorBaseName(
      commentator,
      commentedBookTitle: commentedBookTitle,
    );
    if (base == null || base == commentator || base.length <= bestLength) {
      continue;
    }
    if (selection.startsWith('$base ')) {
      best = commentator;
      bestLength = base.length;
    }
  }

  return best;
}
