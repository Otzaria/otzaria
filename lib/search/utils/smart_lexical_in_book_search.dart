import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// ציטוטים לפי כללי המנוע החכם; גרשיים בין אותיות עבריות שייכים לראשי תיבות.
List<String> smartSearchQuotedPhrases(String query) {
  const quotes = {'"', '״', '“', '”', '„'};
  bool letter(String? c) =>
      c != null && c.codeUnitAt(0) >= 0x05d0 && c.codeUnitAt(0) <= 0x05ea;
  final phrases = <String>[];
  int? start;
  String? previous;
  for (var i = 0; i < query.length; i++) {
    final c = query[i];
    final next = i + 1 < query.length ? query[i + 1] : null;
    if (quotes.contains(c) && !(letter(previous) && letter(next))) {
      if (start == null) {
        start = i + 1;
      } else {
        final phrase = query.substring(start, i).trim();
        if (phrase.isNotEmpty) phrases.add(phrase);
        start = null;
      }
    }
    final code = c.codeUnitAt(0);
    if (!(code >= 0x0591 && code <= 0x05bd ||
        code >= 0x05bf && code <= 0x05c7)) {
      previous = c;
    }
  }
  return phrases;
}

/// חיתוך fuzzy עם כל הביטויים הליטרליים, בסדר הקטלוג בזיכרון של עמוד וקבוצת מזהים שווים.
Future<List<SearchResult>> searchSmartLexicalInBook(
  SearchRepository repository, {
  required String query,
  required String bookPath,
  required int limit,
  required int distance,
  required List<String> phrases,
}) async {
  if (limit <= 0) return const [];
  if (phrases.length == 1 &&
      listEquals(
        queryWordSpans(query: query).map((s) => s.word).toList(),
        queryWordSpans(query: phrases.single).map((s) => s.word).toList(),
      )) {
    return repository.searchLiteralPhrase(
      query,
      [bookPath],
      limit,
      includeAdjacentLine: true,
    );
  }
  final exact = [
    for (final phrase in phrases.toSet())
      StreamIterator(
        _catalogueResults(
          (offset) => repository.searchLiteralPhrase(
            phrase,
            [bookPath],
            limit,
            offset: offset,
          ),
          limit,
        ),
      ),
  ];
  final fuzzy = StreamIterator(
    _catalogueResults(
      (offset) => repository.searchTexts(
        SearchEngineRequest(
          query: query,
          facets: [bookPath],
          limit: limit,
          offset: offset,
          searchMode: SearchMode.fuzzy,
          distance: distance,
          negativeDistance: distance,
          order: ResultsOrder.catalogue,
        ),
      ),
      limit,
    ),
  );
  final results = <SearchResult>[];
  try {
    for (final iterator in exact) {
      if (!await iterator.moveNext()) return results;
    }
    while (results.length < limit && await fuzzy.moveNext()) {
      final candidate = fuzzy.current;
      var matches = true;
      for (final iterator in exact) {
        while (_compare(iterator.current, candidate) < 0) {
          if (!await iterator.moveNext()) return results;
        }
        if (_compare(iterator.current, candidate) != 0) matches = false;
      }
      if (matches) results.add(candidate);
    }
    return results;
  } finally {
    await fuzzy.cancel();
    for (final iterator in exact) {
      await iterator.cancel();
    }
  }
}

int _compare(SearchResult a, SearchResult b) {
  final id = a.id.compareTo(b.id);
  return id != 0 ? id : a.filePath.compareTo(b.filePath);
}

// הקטלוג במנוע מסודר לפי id. סדר נתיבים קבוע מונע חיתוך בין ספרים בעלי id זהה.
Stream<SearchResult> _catalogueResults(
  Future<List<SearchResult>> Function(int offset) fetch,
  int pageSize,
) async* {
  var offset = 0;
  final tied = <SearchResult>[];
  while (true) {
    final page = await fetch(offset);
    for (final result in page) {
      if (tied.isNotEmpty && tied.first.id != result.id) {
        tied.sort(_compare);
        for (final result in tied) {
          yield result;
        }
        tied.clear();
      }
      tied.add(result);
    }
    if (page.length < pageSize) {
      tied.sort(_compare);
      for (final result in tied) {
        yield result;
      }
      return;
    }
    offset += page.length;
  }
}
