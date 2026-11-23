import 'dart:convert';

import 'package:otzaria/tools/shamor_zachor/services/pdf_tracking_identity.dart';

/// כללי המיזוג של נתוני שמור וזכור, המשותפים לייבוא ממזג ולארכיון המתגלגל.
///
/// ההתקדמות וכל רשומה מקושרת לספר נשמרות לפי מפתח הספר: מזהה seforim.db, או
/// מפתח PDF שנגזר מזהות הספר ([PdfTrackingIdentity.keyOf]) וזהה בכל מכשיר,
/// ולכן מיזוג לפי המפתח מחבר רק נתונים של אותו ספר. מפתח PDF ממונה מקומי של
/// גרסה קודמת ([PdfTrackingIdentity.isLegacyKey]) מזהה קובץ רק במכשיר שהקצה
/// אותו, ולכן נלקח רק מהמקור המנצח (המקומי, או הגיבוי החדש).
class ShamorZachorBackupMerge {
  ShamorZachorBackupMerge._();

  static const String progressKey = 'sz:progress_by_id';
  static const String trackedPdfBooksKey = 'sz:tracked_pdf_books';

  /// מפות שמפתחן הוא מפתח הספר.
  static const Set<String> bookKeyedMaps = {
    progressKey,
    'sz:completion_dates_by_id',
    'sz:column_completion_dates',
    'sz:book_columns',
  };

  static const String _lastTouchedPrefix = 'sz:last_touched:';

  /// מפתח שמור-וזכור שאסור לקחת מהמקור המפסיד: מיקום אחרון של ספר PDF
  /// במפתח מונה מקומי.
  static bool isLegacyPdfRecordKey(String key) =>
      key.startsWith(_lastTouchedPrefix) &&
      _isLegacyBookKey(key.substring(_lastTouchedPrefix.length));

  static bool _isLegacyBookKey(String bookKey) {
    final key = int.tryParse(bookKey);
    return key != null && PdfTrackingIdentity.isLegacyKey(key);
  }

  /// מיזוג פר-ספר של מפה לפי מפתח ספר: לכל ספר [winner] מנצח בשלמותו (מיזוג
  /// פר-דף היה מחזיר סימונים שבוטלו בכוונה), וספר שרק ב-[other] נוסף.
  static ({Map<String, dynamic>? merged, int added}) mergeBookMap(
    Object? winner,
    Object? other,
  ) {
    final winnerMap = _decodeJsonMap(winner);
    final otherMap = _decodeJsonMap(other);
    if (otherMap == null) return (merged: winnerMap, added: 0);
    final merged = {...?winnerMap};
    var added = 0;
    for (final entry in otherMap.entries) {
      if (merged.containsKey(entry.key) || _isLegacyBookKey(entry.key)) {
        continue;
      }
      merged[entry.key] = entry.value;
      added++;
    }
    return (merged: merged, added: added);
  }

  /// איחוד רשימות ספרי ה-PDF לפי זהות הספר; [winner] מנצח.
  static ({List<Map<String, dynamic>>? merged, int added}) mergeTrackedPdfBooks(
    Object? winner,
    Object? other,
  ) {
    final winnerList = _decodeEntries(winner);
    final otherList = _decodeEntries(other);
    if (otherList == null) return (merged: winnerList, added: 0);
    final merged = [...?winnerList];
    final identities = merged.map((e) => e['identity']).toSet();
    var added = 0;
    for (final entry in otherList) {
      final key = entry['key'];
      if (key is! int || PdfTrackingIdentity.isLegacyKey(key)) continue;
      if (!identities.add(entry['identity'])) continue;
      merged.add(entry);
      added++;
    }
    return (merged: merged, added: added);
  }

  static Map<String, dynamic>? _decodeJsonMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>>? _decodeEntries(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is List
          ? decoded
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
          : null;
    } catch (_) {
      return null;
    }
  }
}
