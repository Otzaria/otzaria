/// מחזיר את שם המפרש בלי שם הספר שהוא מפרש.
/// "רמב"ן על ברכות" → "רמב"ן"; "יכין מקואות" עם [commentedBookTitle]
/// "משנה מקואות" → "יכין". יש משפחות מפרשים שאינן כוללות "על" בשם.
String? commentatorBaseName(
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

/// מה שהמסד יודע על ספר מפרש. [linkCount] נספר מול הספר הנקרא.
class CommentatorIdentity {
  final String? collectiveKey;
  final String? baseBookTitle;
  final int linkCount;

  CommentatorIdentity({
    String? collectiveTitle,
    this.baseBookTitle,
    this.linkCount = 0,
  }) : collectiveKey = _nonEmptyKey(collectiveTitle);

  static String? _nonEmptyKey(String? title) {
    final key = title == null ? null : normalizeCommentatorKey(title);
    return key == null || key.isEmpty ? null : key;
  }
}

String normalizeCommentatorKey(String value) =>
    value.replaceAll('״', '"').replaceAll('׳', "'").trim();

/// המפתח שמזהה את המפרש בין ספרים: שם האוסף מהמסד, ובלעדיו שם הבסיס.
String commentatorKey(
  String title, {
  String? commentedBookTitle,
  Map<String, CommentatorIdentity> identities = const {},
}) =>
    identities[title]?.collectiveKey ??
    _baseKey(title, identities[title], commentedBookTitle);

String _baseKey(
  String title,
  CommentatorIdentity? identity,
  String? commentedBookTitle,
) => normalizeCommentatorKey(
  commentatorBaseName(
    title,
    commentedBookTitle: identity?.baseBookTitle ?? commentedBookTitle,
  )!,
);

Set<String> _identityKeys(
  String title,
  Map<String, CommentatorIdentity> identities,
  String? commentedBookTitle,
) => {
  ?identities[title]?.collectiveKey,
  _baseKey(title, identities[title], commentedBookTitle),
};

/// מחפש את המפרש ב-[availableCommentators] שהוא [selection]: שם מלא זהה, או
/// מפתח זהה (שם אוסף או שם בסיס). [identities] מגיע מהמסד, לפי כותרת.
/// כמה התאמות: המפרש על הספר הנקרא, ואז בעל יותר קישורים אליו.
String? findMatchingCommentator(
  String? selection,
  List<String> availableCommentators, {
  String? commentedBookTitle,
  Map<String, CommentatorIdentity> identities = const {},
}) {
  if (selection == null) return null;
  if (availableCommentators.contains(selection)) return selection;

  final wanted = _identityKeys(selection, identities, commentedBookTitle);
  String? best;
  for (final commentator in availableCommentators) {
    final keys = _identityKeys(commentator, identities, commentedBookTitle);
    if (!keys.any(wanted.contains)) continue;
    if (best == null ||
        _outranks(commentator, best, identities, commentedBookTitle)) {
      best = commentator;
    }
  }
  return best;
}

bool _outranks(
  String candidate,
  String current,
  Map<String, CommentatorIdentity> identities,
  String? commentedBookTitle,
) {
  final candidateOnBook = _commentsOn(candidate, commentedBookTitle);
  if (candidateOnBook != _commentsOn(current, commentedBookTitle)) {
    return candidateOnBook;
  }
  return (identities[candidate]?.linkCount ?? 0) >
      (identities[current]?.linkCount ?? 0);
}

/// "רי"ף ברכות" ו"תוספות על ברכות" מפרשים את ברכות; "רי"ף שבת" לא.
bool _commentsOn(String title, String? bookTitle) {
  if (bookTitle == null || bookTitle.isEmpty) return false;
  if (title.contains(' על ')) return title.endsWith(' על $bookTitle');
  return commentatorBaseName(title, commentedBookTitle: bookTitle) != title;
}
