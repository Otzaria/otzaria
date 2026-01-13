import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/db_reference_result.dart';
import 'package:otzaria/find_ref/reference_books_cache.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/utils/text_manipulation.dart';

class FindRefRepository {
  final DataRepository dataRepository;

  final Future<void> Function()? warmUpReferenceBooksCache;
  final bool Function()? isReferenceBooksCacheLoaded;
  final List<ReferenceBookHit> Function(String query, {int limit})?
      searchReferenceBooks;
  final Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  })? getTocEntriesForReference;

  FindRefRepository({
    required this.dataRepository,
    this.warmUpReferenceBooksCache,
    this.isReferenceBooksCacheLoaded,
    this.searchReferenceBooks,
    this.getTocEntriesForReference,
  });

  Future<List<DbReferenceResult>> findRefs(String ref) async {
    final cleanedQuery = _normalizeForMatch(ref);
    if (cleanedQuery.isEmpty) {
      return const [];
    }

    final queryTokens = _tokenize(cleanedQuery);
    if (queryTokens.isEmpty) {
      return const [];
    }

    final SeforimRepository? repository =
        SqliteDataProvider.instance.repository;
    if (repository == null && getTocEntriesForReference == null) {
      debugPrint('[FindRef] Database not initialized');
      return const [];
    }

    Future<List<Map<String, dynamic>>> fetchTocEntries(
      int bookId,
      String bookTitle, {
      List<String>? queryTokens,
    }) {
      final injected = getTocEntriesForReference;
      if (injected != null) {
        return injected(bookId, bookTitle, queryTokens: queryTokens);
      }
      return repository!.getTocEntriesForReference(
        bookId,
        bookTitle,
        queryTokens: queryTokens,
      );
    }

    final cacheLoaded = isReferenceBooksCacheLoaded?.call() ??
        ReferenceBooksCache.instance.isLoaded;
    if (!cacheLoaded) {
      await (warmUpReferenceBooksCache?.call() ??
          ReferenceBooksCache.instance.warmUp());
    }

    final searchBooks =
        searchReferenceBooks ?? ReferenceBooksCache.instance.search;

    // Prefer matching the longest leading phrase (up to 3 tokens) as the book key.
    // This supports multi-word acronyms like "שוע אוח".
    final maxPhraseTokens = queryTokens.length >= 3 ? 3 : queryTokens.length;
    var bookQueryTokenCount = 1;
    List<ReferenceBookHit> bookHits = const <ReferenceBookHit>[];
    for (var n = maxPhraseTokens; n >= 1; n--) {
      final phrase = queryTokens.take(n).join(' ');
      final hits = searchBooks(phrase, limit: 50);
      if (hits.isNotEmpty) {
        bookHits = hits;
        bookQueryTokenCount = n;
        break;
      }
    }

    debugPrint(
        '[FindRef] Found ${bookHits.length} books matching leading phrase (memory)');

    final results = <DbReferenceResult>[];

    // Single-word query: do NOT search TOC at all.
    if (queryTokens.length == 1) {
      for (final hit in bookHits) {
        final isPdf = hit.fileType == 'pdf';

        results.add(DbReferenceResult(
          title: hit.title,
          reference: hit.title,
          segment: 0,
          isPdf: isPdf,
          filePath: hit.filePath,
        ));
      }

      final unique = _dedupeRefs(results);
      final ranked = _rankResults(unique, queryTokens);
      return ranked.length > 15 ? ranked.take(15).toList() : ranked;
    }

    // If the *next* token after the matched book-phrase is an exact book match,
    // avoid TOC search to prevent cross-book false positives.
    final nextTokenIndex = bookQueryTokenCount;
    final nextToken =
        queryTokens.length > nextTokenIndex ? queryTokens[nextTokenIndex] : '';
    final nextTokenMatches = nextToken.isEmpty
        ? const <ReferenceBookHit>[]
        : searchBooks(nextToken, limit: 50);
    final hasExactNextTokenMatch =
        nextTokenMatches.any((hit) => hit.matchRank == 0);

    for (final hit in bookHits) {
      final bookId = hit.bookId;
      final title = hit.title;
      final isPdf = hit.fileType == 'pdf';

      final titleTokens = _tokenize(_normalizeForMatch(title));
      final matchedByAcronym = hit.matchRank >= 3;
      final remainingTokens = _getRemainingTokens(
        queryTokens,
        titleTokens,
        stripLeadingTokensCount: matchedByAcronym ? bookQueryTokenCount : 0,
      );

      if (remainingTokens.isEmpty) {
        final tocEntries = await fetchTocEntries(bookId, title);

        results.add(DbReferenceResult(
          title: title,
          reference: title,
          segment: 0,
          isPdf: isPdf,
          filePath: hit.filePath,
        ));

        for (final entry in tocEntries) {
          final level = entry['level'] as int;
          if (level == 2 && entry['reference'] != title) {
            results.add(DbReferenceResult(
              title: title,
              reference: entry['reference'] as String,
              segment: entry['segment'] as int,
              isPdf: isPdf,
              filePath: hit.filePath,
            ));
          }
        }
      } else if (!hasExactNextTokenMatch) {
        final tocEntries = await fetchTocEntries(
          bookId,
          title,
          queryTokens: remainingTokens,
        );

        for (final entry in tocEntries) {
          results.add(DbReferenceResult(
            title: title,
            reference: entry['reference'] as String,
            segment: entry['segment'] as int,
            isPdf: isPdf,
            filePath: hit.filePath,
          ));
        }
      }
    }

    final unique = _dedupeRefs(results);
    final ranked = _rankResults(unique, queryTokens);

    debugPrint('[FindRef] Final results: ${ranked.length}');

    return ranked.length > 15 ? ranked.take(15).toList() : ranked;
  }

  List<String> _getRemainingTokens(
    List<String> queryTokens,
    List<String> titleTokens, {
    int stripLeadingTokensCount = 0,
    bool stripFirstQueryToken = false,
  }) {
    final remaining = List<String>.from(queryTokens);

    if (stripFirstQueryToken && stripLeadingTokensCount == 0) {
      stripLeadingTokensCount = 1;
    }

    if (stripLeadingTokensCount > 0) {
      final toRemove = stripLeadingTokensCount.clamp(0, remaining.length);
      remaining.removeRange(0, toRemove);
    }

    for (final token in titleTokens) {
      final idx = remaining.indexOf(token);
      if (idx != -1) {
        remaining.removeAt(idx);
      }
    }

    return remaining;
  }

  List<DbReferenceResult> _dedupeRefs(List<DbReferenceResult> results) {
    final seen = <String>{};
    final out = <DbReferenceResult>[];

    for (final r in results) {
      final key = '${_normalize(r.reference)}|${r.title}|${r.segment}';
      if (seen.add(key)) {
        out.add(r);
      }
    }

    return out;
  }

  List<DbReferenceResult> _rankResults(
      List<DbReferenceResult> results, List<String> queryTokens) {
    results.sort((a, b) {
      final aTitle = _normalize(a.title);
      final bTitle = _normalize(b.title);
      final query = queryTokens.join(' ');

      if (aTitle == query && bTitle != query) return -1;
      if (bTitle == query && aTitle != query) return 1;

      if (aTitle.startsWith(query) && !bTitle.startsWith(query)) return -1;
      if (bTitle.startsWith(query) && !aTitle.startsWith(query)) return 1;

      return a.reference.length.compareTo(b.reference.length);
    });

    return results;
  }

  String _normalize(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _normalizeForMatch(String input) {
    var cleaned = removeSectionNames(input);
    cleaned = cleaned.replaceAll('.', ' . ').replaceAll(':', ' : ');
    cleaned = removeTeamim(removeVolwels(cleaned));

    cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
    cleaned = cleaned.replaceAll('\u05F4', '').replaceAll('\u05F3', '');

    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s.:]'), ' ');
    cleaned = cleaned.toLowerCase();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _tokenize(String text) => text
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}
