import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// מנרמל שאילתת איתור כך שתתנהג כמו האיתור הוותיק.
String normalizeFindQuery(String rawQuery) {
  return normalizeFindText(SearchQueryBuilder.sanitizeQuery(rawQuery));
}

/// מנרמל טקסט לחיפוש בסגנון איתור.
String normalizeFindText(String rawText) {
  var cleaned = utils.removeVolwels(rawText);
  cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
  cleaned = cleaned.replaceAll('״', '').replaceAll('׳', '');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s/]'), ' ');
  return cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

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
