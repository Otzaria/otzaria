import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/find_ref/utils/match_logic.dart';
import 'package:search_engine/search_engine.dart';

class FindRefRepository {
  FindRefRepository();

  /// Search for references using the new logic
  Future<List<ReferenceSearchResult>> findRefs(String ref) async {
    if (ref.trim().length < 3) {
      return [];
    }

    try {
      // Get all results from Tantivy (existing index)
      final allResults =
          await TantivyDataProvider.instance.searchRefs(ref, 300, false);

      // Apply new filtering logic
      final filtered = _applyNewLogic(ref, allResults);

      // Debug: show filtered results
      debugPrint('✅ Filtered to ${filtered.length} results:');
      for (int i = 0; i < filtered.length && i < 20; i++) {
        debugPrint(
            '  [$i] title="${filtered[i].title}" ref="${filtered[i].reference}"');
      }

      // Return max 15 results
      return filtered.take(15).toList();
    } catch (e) {
      debugPrint('❌ Error searching references: $e');
      return [];
    }
  }

  /// Apply the new search logic to filter and rank results
  List<ReferenceSearchResult> _applyNewLogic(
      String query, List<ReferenceSearchResult> allResults) {
    final results = <ReferenceSearchResult>[];
    final bookResults = <ReferenceSearchResult>[];
    final headingResults = <ReferenceSearchResult>[];

    // Separate books from headings and remove duplicates
    final seenBooks = <String>{};

    for (final result in allResults) {
      // A result is a "book" if reference equals title (H1 or book name)
      // We normalize both to handle whitespace differences
      final normalizedRef =
          result.reference.trim().replaceAll(RegExp(r'\s+'), ' ');
      final normalizedTitle =
          result.title.trim().replaceAll(RegExp(r'\s+'), ' ');
      final isBook = normalizedRef == normalizedTitle;

      if (isBook) {
        // Check if this book matches the query
        final titleScore = MatchLogic.matchScore(query, result.title);
        if (titleScore > 0.0) {
          // De-duplicate: only add if we haven't seen this book title before
          if (seenBooks.add(normalizedTitle)) {
            bookResults.add(result);
          }
        }
      } else {
        // This is a heading (reference contains more than just title)
        headingResults.add(result);
      }
    }

    // Step 1: Find matching books
    final matchingBooks = <ReferenceSearchResult>[];
    bool hasFullBookMatch = false;

    for (final book in bookResults) {
      final score = MatchLogic.matchScore(query, book.title);
      if (score == 2.0) {
        hasFullBookMatch = true;
        matchingBooks.add(book);
      } else if (score == 1.0) {
        matchingBooks.add(book);
      }
    }

    // Step 2: Decide what to show
    if (matchingBooks.isEmpty) {
      return [];
    }

    // Check if we should show headings
    bool shouldShowHeadings = false;
    for (final book in matchingBooks) {
      if (MatchLogic.isFullMatch(query, book.title)) {
        if (MatchLogic.hasAdditionalWords(query, book.title)) {
          shouldShowHeadings = true;
          break;
        }
      } else if (MatchLogic.hasMatch(query, book.title)) {
        if (MatchLogic.hasAdditionalWords(query, book.title)) {
          shouldShowHeadings = true;
          break;
        }
      }
    }

    if (shouldShowHeadings) {
      // Show matching headings
      for (final book in matchingBooks) {
        final remainingWords = MatchLogic.getRemainingWords(query, book.title);
        if (remainingWords.isEmpty) continue;

        final subQuery = MatchLogic.createSubQuery(remainingWords);

        // Find matching headings for this book
        for (final heading in headingResults) {
          if (heading.title == book.title) {
            // Extract heading text (after book title)
            final headingText = heading.reference
                .replaceFirst('${book.title}, ', '')
                .replaceFirst('${book.title},', '')
                .replaceFirst(book.title, '')
                .trim();

            if (MatchLogic.hasMatch(subQuery, headingText)) {
              results.add(heading);
            }
          }
        }
      }
    } else {
      // Show only books
      // If there's a full match, show both full and partial matches
      if (hasFullBookMatch) {
        results.addAll(matchingBooks);
      } else {
        // Show only the matching books
        results.addAll(matchingBooks);
      }
    }

    // Sort: books first, then by relevance
    results.sort((a, b) {
      final aIsBook = a.reference.trim() == a.title.trim();
      final bIsBook = b.reference.trim() == b.title.trim();

      if (aIsBook && !bIsBook) return -1;
      if (!aIsBook && bIsBook) return 1;

      return 0;
    });

    return results;
  }
}
