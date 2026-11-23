import 'dart:convert';

import 'package:otzaria/tools/shamor_zachor/services/pdf_tracking_identity.dart';

/// מיזוג ספרי PDF כתמונת מצב אחת לכל ספר.
class ShamorZachorBackupMerge {
  ShamorZachorBackupMerge._();

  static const _progressKey = 'sz:progress_by_id';
  static const _booksKey = 'sz:tracked_pdf_books';
  static const _lastTouchedPrefix = 'sz:last_touched:';
  static const _bookMaps = {
    _progressKey,
    'sz:completion_dates_by_id',
    'sz:column_completion_dates',
    'sz:book_columns',
  };

  /// מפתחות שליליים שייכים ל-PDF. את המיזוג של יתר הנתונים מבצעים כרגיל.
  static Map<String, Object?> withoutPdfData(Map<String, Object?> snapshot) {
    final result = Map<String, Object?>.of(snapshot)
      ..removeWhere((key, _) {
        if (key == _booksKey) return true;
        if (!key.startsWith(_lastTouchedPrefix)) return false;
        return _isPdfKey(key.substring(_lastTouchedPrefix.length));
      });
    for (final key in _bookMaps) {
      final entries = _decodeMap(result[key]);
      if (entries == null || !entries.keys.any(_isPdfKey)) continue;
      entries.removeWhere((key, _) => _isPdfKey(key));
      if (entries.isEmpty) {
        result.remove(key);
      } else {
        result[key] = json.encode(entries);
      }
    }
    return result;
  }

  static ({Map<String, Object?> data, int addedBooks}) mergePdfData(
    Map<String, Object?> winner,
    Map<String, Object?> other,
  ) {
    final preferred = _decodeBooks(winner[_booksKey]);
    final fallback = _decodeBooks(other[_booksKey]);
    final books = {
      ...preferred,
      for (final entry in fallback.entries)
        if (!preferred.containsKey(entry.key)) entry.key: entry.value,
    };
    final data = <String, Object?>{};
    if (books.isNotEmpty || winner.containsKey(_booksKey)) {
      data[_booksKey] = json.encode(books.values.toList());
    }

    var addedBooks = 0;
    for (final mapKey in _bookMaps) {
      final winnerEntries = _decodeMap(winner[mapKey]) ?? {};
      final otherEntries = _decodeMap(other[mapKey]) ?? {};
      final entries = <String, Object?>{};
      for (final entry in books.entries) {
        if (entry.value['deleted'] == true) continue;
        final bookKey = entry.value['key'].toString();
        final usesWinner = preferred.containsKey(entry.key);
        final source = usesWinner ? winnerEntries : otherEntries;
        if (!source.containsKey(bookKey)) continue;
        entries[bookKey] = source[bookKey];
        if (mapKey == _progressKey && !usesWinner) addedBooks++;
      }
      if (entries.isNotEmpty) data[mapKey] = entries;
    }

    for (final entry in books.entries) {
      if (entry.value['deleted'] == true) continue;
      final source = preferred.containsKey(entry.key) ? winner : other;
      final key = '$_lastTouchedPrefix${entry.value['key']}';
      if (source[key] != null) data[key] = source[key];
    }
    return (data: data, addedBooks: addedBooks);
  }

  static void addPdfData(
    Map<String, Object?> target,
    Map<String, Object?> pdfData,
    Map<String, Object?> official,
  ) {
    for (final entry in pdfData.entries) {
      if (_bookMaps.contains(entry.key)) {
        target[entry.key] = json.encode({
          ...?_decodeMap(official[entry.key]),
          ...entry.value as Map<String, Object?>,
        });
      } else {
        target[entry.key] = entry.value;
      }
    }
  }

  static bool _isPdfKey(String key) => (int.tryParse(key) ?? 0) < 0;

  static Object? _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return json.decode(raw);
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeMap(Object? raw) {
    final decoded = _decode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Map<String, Map<String, dynamic>> _decodeBooks(Object? raw) {
    final decoded = _decode(raw);
    if (decoded is! List) return {};
    return {
      for (final row in decoded.whereType<Map<String, dynamic>>())
        if (row['identity'] case final String identity
            when row['key'] == PdfTrackingIdentity.keyOf(identity))
          identity: row,
    };
  }
}
