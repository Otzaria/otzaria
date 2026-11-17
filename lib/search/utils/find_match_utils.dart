import 'dart:typed_data';

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

/// מנרמל טקסט לחיפוש בסגנון איתור, במעבר יחיד על יחידות הקוד: הוא רץ על כל
/// כותרות תוכן העניינים בחיפוש הראשון בספר, ו-RegExp-ים בשרשרת איטיים שם.
String normalizeFindText(String rawText) {
  final out = Uint16List(rawText.length);
  var length = 0;
  var pendingSpace = false;
  for (var i = 0; i < rawText.length; i++) {
    var c = rawText.codeUnitAt(i);
    // מקף ופסק הם מפרידים, ולכן אינם נמחקים עם הניקוד.
    final hebrew = c >= 0x0590 && c <= 0x05FF && c != 0x05BE && c != 0x05C0;
    if (c == 0x22 || c == 0x27 || c == 0x05F3 || c == 0x05F4) continue;
    if (hebrew && c >= 0x0591 && c <= 0x05C7) continue;
    if (c >= 0x41 && c <= 0x5A) c += 0x20;
    if (hebrew ||
        (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39) ||
        c == 0x2F) {
      if (pendingSpace) out[length++] = 0x20;
      pendingSpace = false;
      out[length++] = c;
    } else {
      pendingSpace = length > 0;
    }
  }
  return String.fromCharCodes(out, 0, length);
}

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
  final primaryDelta = (normalizedPrimaryText.length - normalizedQuery.length)
      .abs();
  if (normalizedSecondaryText.isEmpty) return primaryDelta;
  final secondaryDelta =
      (normalizedSecondaryText.length - normalizedQuery.length).abs();
  return primaryDelta < secondaryDelta ? primaryDelta : secondaryDelta;
}
