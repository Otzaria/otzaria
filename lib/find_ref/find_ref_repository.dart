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
      debugPrint('\n' + '=' * 80);
      debugPrint('🔍 NEW SEARCH: "$ref"');
      debugPrint('=' * 80);

      // Get all results from Tantivy (existing index)
      final allResults =
          await TantivyDataProvider.instance.searchRefs(ref, 300, false);

      debugPrint('📥 Got ${allResults.length} results from Tantivy index');
      debugPrint('\n--- RAW RESULTS FROM INDEX (first 100) ---');
      for (int i = 0; i < allResults.length && i < 100; i++) {
        debugPrint(
            '  [$i] title="${allResults[i].title}" | ref="${allResults[i].reference}"');
      }
      if (allResults.length > 100) {
        debugPrint('  ... and ${allResults.length - 100} more results');
      }

      // Apply new filtering logic
      final filtered = _applyNewLogic(ref, allResults);

      debugPrint(
          '\n✅ FINAL RESULTS: ${filtered.length} results after filtering');
      for (int i = 0; i < filtered.length && i < 20; i++) {
        debugPrint(
            '  [$i] title="${filtered[i].title}" | ref="${filtered[i].reference}"');
      }
      debugPrint('=' * 80 + '\n');

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
    debugPrint('\n🔧 APPLYING FILTER LOGIC');
    debugPrint('Query: "$query"');

    final results = <ReferenceSearchResult>[];
    final bookResults = <ReferenceSearchResult>[];
    final headingResults = <ReferenceSearchResult>[];

    // Separate books from headings and remove duplicates
    final seenBooks = <String>{};
    int duplicatesRemoved = 0;

    debugPrint('\n--- STEP 1: SEPARATING BOOKS FROM HEADINGS ---');
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
        debugPrint('  📚 BOOK: "${result.title}" | score=$titleScore');
        if (titleScore > 0.0) {
          // De-duplicate: only add if we haven't seen this book title before
          if (seenBooks.add(normalizedTitle)) {
            bookResults.add(result);
            debugPrint('    ✅ Added to bookResults');
          } else {
            duplicatesRemoved++;
            debugPrint('    ⚠️ Duplicate - skipped');
          }
        } else {
          debugPrint('    ❌ Score 0.0 - skipped');
        }
      } else {
        // This is a heading (reference contains more than just title)
        headingResults.add(result);
      }
    }

    debugPrint(
        '\n📊 Separation complete: ${bookResults.length} books, ${headingResults.length} headings, $duplicatesRemoved duplicates removed');

    // Step 1: Find matching books
    debugPrint('\n--- STEP 2: FINDING MATCHING BOOKS ---');
    final matchingBooks = <ReferenceSearchResult>[];
    bool hasFullBookMatch = false;

    for (final book in bookResults) {
      final score = MatchLogic.matchScore(query, book.title);
      debugPrint('  📖 "${book.title}" | score=$score');
      if (score == 2.0) {
        hasFullBookMatch = true;
        matchingBooks.add(book);
        debugPrint('    ✅ Full match - added');
      } else if (score == 1.0) {
        matchingBooks.add(book);
        debugPrint('    ✅ Partial match - added');
      } else {
        debugPrint('    ❌ No match - skipped');
      }
    }

    debugPrint(
        '\n📊 Found ${matchingBooks.length} matching books (hasFullBookMatch=$hasFullBookMatch)');

    // Step 2: Decide what to show
    if (matchingBooks.isEmpty) {
      debugPrint('⚠️ No matching books found - returning empty results');
      return [];
    }

    // Check if we should show headings
    debugPrint('\n--- STEP 3: DECIDING BOOKS vs HEADINGS ---');
    bool shouldShowHeadings = false;
    for (final book in matchingBooks) {
      final hasAdditional = MatchLogic.hasAdditionalWords(query, book.title);
      final remainingWords = MatchLogic.getRemainingWords(query, book.title);
      debugPrint(
          '  📖 "${book.title}" | hasAdditionalWords=$hasAdditional | remaining=$remainingWords');
      if (MatchLogic.isFullMatch(query, book.title)) {
        if (MatchLogic.hasAdditionalWords(query, book.title)) {
          shouldShowHeadings = true;
          debugPrint('    → Full match with additional words - SHOW HEADINGS');
          break;
        }
      } else if (MatchLogic.hasMatch(query, book.title)) {
        if (MatchLogic.hasAdditionalWords(query, book.title)) {
          shouldShowHeadings = true;
          debugPrint(
              '    → Partial match with additional words - SHOW HEADINGS');
          break;
        }
      }
    }

    debugPrint('\n🎯 Decision: shouldShowHeadings=$shouldShowHeadings');

    if (shouldShowHeadings) {
      debugPrint('\n--- STEP 4: SEARCHING IN HEADINGS ---');
      int headingsAdded = 0;
      for (final book in matchingBooks) {
        final remainingWords = MatchLogic.getRemainingWords(query, book.title);
        if (remainingWords.isEmpty) {
          debugPrint('  📖 "${book.title}" - no remaining words, skipping');
          continue;
        }

        final subQuery = MatchLogic.createSubQuery(remainingWords);
        debugPrint(
            '  📖 "${book.title}" | subQuery="$subQuery" | searching in ${headingResults.where((h) => h.title == book.title).length} headings');

        // Find matching headings for this book
        int matchedForBook = 0;
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
              matchedForBook++;
              headingsAdded++;
              if (matchedForBook <= 3) {
                debugPrint('    ✅ Match: "$headingText"');
              }
            }
          }
        }
        if (matchedForBook > 3) {
          debugPrint('    ... and ${matchedForBook - 3} more matches');
        }
        debugPrint('    📊 Total matches for this book: $matchedForBook');
      }
      debugPrint('\n📊 Total headings added: $headingsAdded');
    } else {
      debugPrint('\n--- STEP 4: SHOWING BOOKS ONLY ---');
      // Show only books
      // If there's a full match, show both full and partial matches
      if (hasFullBookMatch) {
        results.addAll(matchingBooks);
        debugPrint(
            '  ✅ Added all ${matchingBooks.length} matching books (including partial matches)');
      } else {
        // Show only the matching books
        results.addAll(matchingBooks);
        debugPrint('  ✅ Added ${matchingBooks.length} matching books');
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
