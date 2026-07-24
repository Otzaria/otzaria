import 'dart:convert';

/// ערך מיוחד שמציין שבחלונית השמאלית יש להציג את כל המפרשים
/// שלא שובצו בחלוניות האחרות.
const String pageShapeRemainingCommentatorsValue =
    '__PAGE_SHAPE_REMAINING_COMMENTATORS__';

/// התווית המוצגת למשתמש עבור אפשרות שאר המפרשים.
const String pageShapeRemainingCommentatorsLabel = 'שאר המפרשים';

/// ערך מיוחד שמציין שהטור משתמש בבחירת מפרשים מרובים מתוך החלונית.
const String pageShapeMultipleCommentatorsModeValue =
    '__PAGE_SHAPE_MULTIPLE_COMMENTATORS_MODE__';

/// התווית המוצגת למשתמש עבור מצב בחירה מרובה.
const String pageShapeMultipleCommentatorsModeLabel = 'מפרשים מרובים';

const String _pageShapeMultiCommentatorsPrefix =
    '__PAGE_SHAPE_MULTI_COMMENTATORS__:';

/// מחזיר האם [value] מייצג את אפשרות "שאר המפרשים".
bool isPageShapeRemainingCommentatorsValue(String? value) {
  return value == pageShapeRemainingCommentatorsValue;
}

/// מחזיר האם [value] מייצג בחירה מרובה מפורשת של מפרשים.
bool isPageShapeMultiCommentatorsValue(String? value) {
  return value?.startsWith(_pageShapeMultiCommentatorsPrefix) ?? false;
}

/// מחזיר האם [value] מייצג מצב בחירה מרובה בטור הימני.
bool isPageShapeMultipleCommentatorsMode(String? value) {
  return value == pageShapeMultipleCommentatorsModeValue ||
      isPageShapeMultiCommentatorsValue(value);
}

/// מחפש את שם המפרש המלא מתוך רשימת המפרשים הזמינים.
String? findMatchingPageShapeCommentator(
  String? selection,
  List<String> availableCommentators,
) {
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

  return null;
}

List<String> _decodeMultiCommentators(String value) {
  if (!isPageShapeMultiCommentatorsValue(value)) {
    return [value];
  }

  final encoded = value.substring(_pageShapeMultiCommentatorsPrefix.length);
  final decoded = utf8.decode(base64Url.decode(encoded));
  final parsed = jsonDecode(decoded);
  if (parsed is! List) {
    return const [];
  }

  return parsed.whereType<String>().toList();
}

/// מקודד בחירת מפרשים לשמירה בהגדרות.
String? encodePageShapeCommentatorsSelection(
  Iterable<String> commentators, {
  bool forceMultipleMode = false,
}) {
  final normalized = <String>[];
  final seen = <String>{};

  for (final commentator in commentators) {
    final trimmed = commentator.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    normalized.add(trimmed);
  }

  if (normalized.isEmpty) {
    return forceMultipleMode ? pageShapeMultipleCommentatorsModeValue : null;
  }

  if (normalized.length == 1 && !forceMultipleMode) {
    return normalized.single;
  }

  final payload = base64Url.encode(utf8.encode(jsonEncode(normalized)));
  return '$_pageShapeMultiCommentatorsPrefix$payload';
}

/// מחזיר את רשימת המפרשים המפורשת שנשמרה בבחירה.
List<String> decodePageShapeCommentatorsSelection(String? value) {
  if (value == null ||
      isPageShapeRemainingCommentatorsValue(value) ||
      value == pageShapeMultipleCommentatorsModeValue) {
    return const [];
  }

  return _decodeMultiCommentators(value);
}

/// ממיר בחירה שמורה לשמות המלאים מתוך רשימת המפרשים הזמינים.
String? resolvePageShapeCommentatorSelection({
  required String? selection,
  required List<String> availableCommentators,
}) {
  if (selection == null ||
      isPageShapeRemainingCommentatorsValue(selection) ||
      selection == pageShapeMultipleCommentatorsModeValue) {
    return selection;
  }

  if (!isPageShapeMultiCommentatorsValue(selection)) {
    return findMatchingPageShapeCommentator(selection, availableCommentators) ??
        selection;
  }

  final resolved = <String>[];
  final seen = <String>{};
  for (final commentator in decodePageShapeCommentatorsSelection(selection)) {
    final match = findMatchingPageShapeCommentator(
      commentator,
      availableCommentators,
    );
    if (match != null && seen.add(match)) {
      resolved.add(match);
    }
  }

  if (resolved.isEmpty) {
    return null;
  }

  return encodePageShapeCommentatorsSelection(
    resolved,
    forceMultipleMode: true,
  );
}

/// מחזיר את רשימת המפרשים שיש להציג בפועל עבור הבחירה השמורה.
List<String> resolvePageShapeSelectedCommentators({
  required String? selection,
  required List<String> availableCommentators,
  Iterable<String?> excludedCommentators = const [],
}) {
  final normalizedSelection = resolvePageShapeCommentatorSelection(
    selection: selection,
    availableCommentators: availableCommentators,
  );

  if (normalizedSelection == null) {
    return const [];
  }

  if (normalizedSelection == pageShapeMultipleCommentatorsModeValue) {
    return const [];
  }

  if (isPageShapeRemainingCommentatorsValue(normalizedSelection)) {
    return resolveRemainingPageShapeCommentators(
      availableCommentators: availableCommentators,
      excludedCommentators: excludedCommentators,
    );
  }

  return decodePageShapeCommentatorsSelection(
    normalizedSelection,
  ).where(availableCommentators.contains).toList();
}

String? _resolvePageShapeSingleCommentator({
  required String? selection,
  required List<String> availableCommentators,
}) {
  final resolved = resolvePageShapeCommentatorSelection(
    selection: selection,
    availableCommentators: availableCommentators,
  );

  if (resolved == null ||
      isPageShapeRemainingCommentatorsValue(resolved) ||
      isPageShapeMultipleCommentatorsMode(resolved) ||
      !availableCommentators.contains(resolved)) {
    return null;
  }

  return resolved;
}

/// מחזיר את כל המפרשים שמוצגים בפועל בחלוניות צורת הדף.
///
/// הפונקציה מיישרת את הלוגיקה של טעינת הקישורים עם הלוגיקה של המסך עצמו:
/// טורים מוסתרים אינם נכללים, ובטור הימני נלקחים בחשבון רק המפרשים שנבחרו
/// בפועל לאחר החרגת המפרשים ששובצו בחלוניות הייעודיות.
List<String> resolvePageShapeDisplayedCommentators({
  required String? leftSelection,
  required String? rightSelection,
  required String? bottomSelection,
  required String? bottomRightSelection,
  required List<String> availableCommentators,
  Map<String, bool> columnVisibility = const {
    'left': true,
    'right': true,
    'bottom': true,
  },
}) {
  final resolvedLeft = _resolvePageShapeSingleCommentator(
    selection: leftSelection,
    availableCommentators: availableCommentators,
  );
  final resolvedBottom = _resolvePageShapeSingleCommentator(
    selection: bottomSelection,
    availableCommentators: availableCommentators,
  );
  final resolvedBottomRight = _resolvePageShapeSingleCommentator(
    selection: bottomRightSelection,
    availableCommentators: availableCommentators,
  );

  final excludedForRightPane = [
    resolvedLeft,
    resolvedBottom,
    resolvedBottomRight,
  ];

  final rightSelectableCommentators = availableCommentators
      .where((commentator) => !excludedForRightPane.contains(commentator))
      .toList();

  final rightCommentators = columnVisibility['right'] == false
      ? const <String>[]
      : resolvePageShapeSelectedCommentators(
          selection: rightSelection,
          availableCommentators: rightSelectableCommentators,
          excludedCommentators: excludedForRightPane,
        );

  final displayedCommentators = <String>[];
  final seenCommentators = <String>{};

  void addCommentator(String? commentator) {
    if (commentator == null || !seenCommentators.add(commentator)) {
      return;
    }
    displayedCommentators.add(commentator);
  }

  if (columnVisibility['left'] != false) {
    addCommentator(resolvedLeft);
  }

  if (columnVisibility['right'] != false) {
    for (final commentator in rightCommentators) {
      addCommentator(commentator);
    }
  }

  if (columnVisibility['bottom'] != false) {
    addCommentator(resolvedBottom);
  }

  if (columnVisibility['bottomRight'] != false) {
    addCommentator(resolvedBottomRight);
  }

  return displayedCommentators;
}

/// מחזיר את התווית המוצגת למשתמש עבור בחירת מפרש בצורת הדף.
String formatPageShapeCommentatorSelection(String? value) {
  if (isPageShapeRemainingCommentatorsValue(value)) {
    return pageShapeRemainingCommentatorsLabel;
  }

  if (value == pageShapeMultipleCommentatorsModeValue) {
    return pageShapeMultipleCommentatorsModeLabel;
  }

  if (isPageShapeMultiCommentatorsValue(value)) {
    final commentators = decodePageShapeCommentatorsSelection(value);
    if (commentators.isEmpty) {
      return pageShapeMultipleCommentatorsModeLabel;
    }
    if (commentators.length <= 2) {
      return commentators.join(', ');
    }
    return '${commentators.length} מפרשים';
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
      })
      .toSet();

  return availableCommentators.where((commentator) {
    return !explicitlySelectedCommentators.contains(commentator);
  }).toList();
}
