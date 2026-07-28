import 'package:otzaria/search/search_query_builder.dart';

/// מנרמל שאילתת איתור כך שתתנהג כמו האיתור הוותיק.
String normalizeFindQuery(String rawQuery) {
  return normalizeFindText(SearchQueryBuilder.sanitizeQuery(rawQuery));
}

/// מנרמל טקסט לדירוג כמו שאילתה, ללא קריאת FFI לכל כותרת.
String normalizeFindRankText(
  String rawText, {
  String? normalizedFindText,
}) {
  if (!_findRankIgnoredChars.hasMatch(rawText)) {
    return normalizedFindText ?? normalizeFindText(rawText);
  }
  return normalizeFindText(rawText.replaceAll(_findRankIgnoredChars, ''));
}

/// מנרמל טקסט לחיפוש בסגנון איתור.
String normalizeFindText(String rawText) {
  var cleaned = rawText.replaceAll(_findSeparators, ' ');
  cleaned = cleaned.replaceAll(_findVowels, '');
  cleaned = cleaned.replaceAll(_findQuotes, '');
  cleaned = cleaned.replaceAll(_nonSearchableChars, ' ');
  return cleaned.toLowerCase().replaceAll(_whitespaceRun, ' ').trim();
}

// מהודרים פעם אחת: הנרמול רץ על כל ערכי ה-TOC של הספר בכל הקלדה.
final RegExp _findSeparators = RegExp(r'[־׀|]');
final RegExp _findVowels = RegExp(r'[֑-ׇ]');
final RegExp _findQuotes = RegExp(r'''["'״׳]''');
final RegExp _nonSearchableChars = RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s/]');
final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _findRankIgnoredChars = RegExp(
  r'[*\[\]^$\\+.~`\u200B-\u200F\u2018\u2019\u201C\u201D\u202A-\u202E\u2066-\u2069\uFEFF]',
);

/// מחזירה האם יש התאמה בין הטקסטים המנורמלים לבין שאילתת האיתור.
bool findNormalizedTextMatches({
  required String normalizedQuery,
  required String normalizedPrimaryText,
  String normalizedSecondaryText = '',
}) {
  if (normalizedQuery.isEmpty) {
    return false;
  }

  return normalizedPrimaryText.contains(normalizedQuery) ||
      normalizedSecondaryText.contains(normalizedQuery);
}

/// מחזירה דירוג רלוונטיות כמו באיתור: מדויק, תחילית, contains.
int findNormalizedTextMatchRank({
  required String normalizedQuery,
  required String normalizedPrimaryText,
  String normalizedSecondaryText = '',
}) {
  if (normalizedPrimaryText == normalizedQuery) return 0;
  if (normalizedSecondaryText == normalizedQuery) return 1;
  if (normalizedPrimaryText.startsWith(normalizedQuery)) return 2;
  if (normalizedSecondaryText.startsWith(normalizedQuery)) return 3;
  if (normalizedPrimaryText.contains(normalizedQuery)) return 4;
  if (normalizedSecondaryText.contains(normalizedQuery)) return 5;
  return 6;
}

/// מחזירה את סטיית האורך המינימלית בין השאילתה לבין הטקסטים המנורמלים.
int findNormalizedTextMatchLengthDelta({
  required String normalizedQuery,
  required String normalizedPrimaryText,
  String normalizedSecondaryText = '',
}) {
  final primaryLength = normalizedPrimaryText.length;
  final secondaryLength = normalizedSecondaryText.isEmpty
      ? primaryLength
      : normalizedSecondaryText.length;
  final bestLength = primaryLength < secondaryLength
      ? primaryLength
      : secondaryLength;
  return (bestLength - normalizedQuery.length).abs();
}
