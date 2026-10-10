import 'dart:typed_data';

import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// התוצאה המוכנה של חימום כינויי הספרים ואינדקס הביגרמים שלהם.
class AcronymCacheData {
  final Map<int, List<String>> acronymsByBookId;
  final Map<int, Int32List> bookIdsByBigram;
  final int rowCount;

  /// מילים שכינוי של הספר כותב בגרשיים ("רמב"ם"), בצורתן המנורמלת — הנרמול
  /// מוחק את הגרשיים, והאיתור מעדיף בשוויון ספר שכתוב כמו השאילתה.
  final Map<int, Set<String>> quotedWordsByBookId;

  const AcronymCacheData({
    required this.acronymsByBookId,
    required this.bookIdsByBigram,
    required this.rowCount,
    this.quotedWordsByBookId = const {},
  });
}

/// מנרמל זוגות `(bookId, term)` ובונה מהם את שני מבני הקאש.
AcronymCacheData buildAcronymCacheData(Iterable<(int, String)> rawPairs) {
  final acronymsByBookId = <int, List<String>>{};
  final quotedWordsByBookId = <int, Set<String>>{};
  var rowCount = 0;
  for (final (bookId, term) in rawPairs) {
    rowCount++;
    if (term.isEmpty) continue;
    final normalized = normalizeForFindRefMatch(term);
    if (normalized.isEmpty) continue;
    acronymsByBookId.putIfAbsent(bookId, () => <String>[]).add(normalized);
    final quoted = quotedWordsOf(term, normalizeForFindRefMatch);
    if (quoted.isNotEmpty) {
      quotedWordsByBookId.putIfAbsent(bookId, () => <String>{}).addAll(quoted);
    }
  }

  final postings = <int, List<int>>{};
  final bookIds = acronymsByBookId.keys.toList()..sort();
  for (final bookId in bookIds) {
    for (final term in acronymsByBookId[bookId]!) {
      var previous = -1;
      for (var i = 0; i < term.length; i++) {
        final current = term.codeUnitAt(i);
        if (previous >= 0) {
          final key = (previous << 16) | current;
          final list = postings[key];
          if (list == null) {
            postings[key] = <int>[bookId];
          } else if (list.last != bookId) {
            list.add(bookId);
          }
        }
        previous = current;
      }
    }
  }

  return AcronymCacheData(
    acronymsByBookId: acronymsByBookId,
    bookIdsByBigram: {
      for (final entry in postings.entries)
        entry.key: Int32List.fromList(entry.value),
    },
    rowCount: rowCount,
    quotedWordsByBookId: quotedWordsByBookId,
  );
}
