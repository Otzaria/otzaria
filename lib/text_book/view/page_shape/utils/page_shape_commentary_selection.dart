/// ערך מיוחד שמציין שבחלונית השמאלית יש להציג את כל המפרשים
/// שלא שובצו בחלוניות האחרות.
const String pageShapeRemainingCommentatorsValue =
    '__PAGE_SHAPE_REMAINING_COMMENTATORS__';

/// התווית המוצגת למשתמש עבור אפשרות שאר המפרשים.
const String pageShapeRemainingCommentatorsLabel = 'שאר המפרשים';

/// מחזיר האם [value] מייצג את אפשרות "שאר המפרשים".
bool isPageShapeRemainingCommentatorsValue(String? value) {
  return value == pageShapeRemainingCommentatorsValue;
}

/// מחזיר את התווית המוצגת למשתמש עבור בחירת מפרש בצורת הדף.
String formatPageShapeCommentatorSelection(String? value) {
  if (isPageShapeRemainingCommentatorsValue(value)) {
    return pageShapeRemainingCommentatorsLabel;
  }

  return value ?? 'ללא מפרש';
}

/// מחשב את כל המפרשים שלא שובצו כבר בחלוניות האחרות.
List<String> resolveRemainingPageShapeCommentators({
  required List<String> availableCommentators,
  required Iterable<String?> excludedCommentators,
}) {
  final explicitlySelectedCommentators = excludedCommentators
      .whereType<String>()
      .where((commentator) {
    return !isPageShapeRemainingCommentatorsValue(commentator);
  }).toSet();

  return availableCommentators.where((commentator) {
    return !explicitlySelectedCommentators.contains(commentator);
  }).toList();
}
