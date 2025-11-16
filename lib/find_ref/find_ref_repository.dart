import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/find_ref/utils/match_logic.dart';
import 'package:otzaria/find_ref/utils/scored_result.dart';
import 'package:search_engine/search_engine.dart';

/// Helper class for book matching
class _BookMatch {
  final ReferenceSearchResult result;
  final double score;

  _BookMatch({required this.result, required this.score});
}

class FindRefRepository {
  FindRefRepository();

  /// Fetch raw results from Tantivy (called once per base query)
  Future<List<ReferenceSearchResult>> fetchRawResults(String baseQuery) async {
    try {
      debugPrint('\n${'=' * 80}');
      debugPrint('🔍 FETCHING FROM TANTIVY: "$baseQuery"');
      debugPrint('=' * 80);

      // Get all results from Tantivy (existing index)
      final allResults =
          await TantivyDataProvider.instance.searchRefs(baseQuery, 300, false);

      debugPrint('📥 Got ${allResults.length} results from Tantivy index');
      debugPrint('\n--- RAW RESULTS FROM INDEX (first 100) ---');
      for (int i = 0; i < allResults.length && i < 100; i++) {
        debugPrint(
            '  [$i] title="${allResults[i].title}" | ref="${allResults[i].reference}"');
      }
      if (allResults.length > 100) {
        debugPrint('  ... and ${allResults.length - 100} more results');
      }
      debugPrint('=' * 80 + '\n');

      return allResults;
    } catch (e) {
      debugPrint('❌ Error fetching from Tantivy: $e');
      return [];
    }
  }

  /// Filter cached results based on full query (called on every keystroke)
  Future<List<ReferenceSearchResult>> filterResults(
      String query, List<ReferenceSearchResult> allResults) async {
    if (query.trim().length < 3) {
      return [];
    }

    try {
      debugPrint('\n${'=' * 80}');
      debugPrint('🔧 FILTERING CACHED RESULTS');
      debugPrint('Query: "$query"');
      debugPrint('Cached results: ${allResults.length}');

      // Apply new filtering logic with additional fetching if needed
      final filtered = await _applyNewLogicWithFetch(query, allResults);

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
      debugPrint('❌ Error filtering results: $e');
      return [];
    }
  }

  /// Apply the new search logic with additional fetching for book headings
  Future<List<ReferenceSearchResult>> _applyNewLogicWithFetch(
      String query, List<ReferenceSearchResult> allResults) async {
    // First, identify matching books
    final matchingBooks = await _identifyMatchingBooks(query, allResults);
    
    if (matchingBooks.isEmpty) {
      debugPrint('⚠️ לא נמצאו ספרים מתאימים');
      return [];
    }

    // Check if we need to search for headings
    final queryWords = query.trim().split(RegExp(r'\s+'));
    final hasMultipleWords = queryWords.length > 1;

    if (!hasMultipleWords) {
      debugPrint('\n🎯 מילה אחת בלבד - מחזיר רק ספרים');
      // Convert to ScoredResult
      final scoredBooks = matchingBooks.map((b) => ScoredResult(
        result: b.result,
        type: b.score == 2.0 ? 'ספר' : 'ספר_חלקי',
        level: 0,
        score: b.score == 2.0 ? 50.0 : 20.0,
      )).toList();
      return _sortAndReturn(scoredBooks);
    }

    // Fetch headings for ALL matching books (not just the first one)
    debugPrint('\n🔍 מביא כותרות עבור ${matchingBooks.length} ספרים...');
    final allHeadings = await _fetchHeadingsForBooks(matchingBooks, allResults);
    
    // Now apply the full logic with all results (including new headings)
    // Note: We pass matchingBooks so the logic knows which books matched
    return _applyNewLogicWithHeadings(query, allResults + allHeadings, matchingBooks);
  }

  /// Identify matching books from results
  Future<List<_BookMatch>> _identifyMatchingBooks(
      String query, List<ReferenceSearchResult> allResults) async {
    final bookResults = <ReferenceSearchResult>[];
    final seenBooks = <String>{};

    // Separate books from headings
    for (final result in allResults) {
      final normalizedRef =
          result.reference.trim().replaceAll(RegExp(r'\s+'), ' ');
      final normalizedTitle =
          result.title.trim().replaceAll(RegExp(r'\s+'), ' ');
      final isBook = normalizedRef == normalizedTitle;

      if (isBook && seenBooks.add(normalizedTitle)) {
        bookResults.add(result);
      }
    }

    debugPrint('\n--- זיהוי ספרים מתאימים ---');
    debugPrint('נמצאו ${bookResults.length} ספרים');

    final matchingBooks = <_BookMatch>[];
    for (final book in bookResults) {
      final matchScore = MatchLogic.matchScore(query, book.title);
      if (matchScore > 0.0) {
        matchingBooks.add(_BookMatch(
          result: book,
          score: matchScore,
        ));
        debugPrint('  ✅ "${book.title}" | matchScore=$matchScore');
      }
    }

    debugPrint('📊 ${matchingBooks.length} ספרים מתאימים');
    return matchingBooks;
  }

  /// Fetch headings for matching books from Tantivy
  Future<List<ReferenceSearchResult>> _fetchHeadingsForBooks(
      List<_BookMatch> matchingBooks, List<ReferenceSearchResult> existingResults) async {
    final newHeadings = <ReferenceSearchResult>[];
    
    // Use a Set to track which books we've already fetched to avoid duplicates
    final fetchedBooks = <String>{};
    
    for (final bookMatch in matchingBooks) {
      final bookTitle = bookMatch.result.title;
      
      // Skip if already fetched
      if (fetchedBooks.contains(bookTitle)) {
        debugPrint('  ⏭️ "$bookTitle" - כבר נבדק');
        continue;
      }
      fetchedBooks.add(bookTitle);
      
      // Check if we already have headings for this book in existing results
      final existingHeadingsCount = existingResults.where((r) => 
        r.title == bookTitle && r.reference != bookTitle
      ).length;
      
      if (existingHeadingsCount > 0) {
        debugPrint('  📚 "$bookTitle" - כבר יש ${existingHeadingsCount} כותרות ב-cache');
        continue;
      }

      // Fetch headings for this book - use HIGHER LIMIT to get more results
      debugPrint('  🔍 מביא כותרות עבור "$bookTitle"...');
      try {
        final headings = await TantivyDataProvider.instance.searchRefs(
          bookTitle, 1000, false  // Increased from 500 to 1000
        );
        
        debugPrint('     📥 Tantivy החזיר ${headings.length} תוצאות');
        
        // Filter only headings (not the book itself)
        final bookHeadings = headings.where((h) => 
          h.title == bookTitle && h.reference != bookTitle
        ).toList();
        
        debugPrint('     ✅ נמצאו ${bookHeadings.length} כותרות (אחרי סינון)');
        
        // Debug: show first few headings
        if (bookHeadings.isEmpty && headings.isNotEmpty) {
          debugPrint('     ⚠️ יש תוצאות אבל אין כותרות! דוגמאות:');
          for (int i = 0; i < headings.length && i < 5; i++) {
            debugPrint('        [$i] title="${headings[i].title}" | ref="${headings[i].reference}"');
          }
        }
        
        newHeadings.addAll(bookHeadings);
      } catch (e) {
        debugPrint('     ❌ שגיאה: $e');
      }
    }

    debugPrint('📊 סה"כ ${newHeadings.length} כותרות חדשות נוספו');
    return newHeadings;
  }

  /// Apply the new search logic with headings (don't show books if headings found)
  List<ReferenceSearchResult> _applyNewLogicWithHeadings(
      String query, 
      List<ReferenceSearchResult> allResults,
      List<_BookMatch> matchingBooks) {
    debugPrint('\n${'=' * 80}');
    debugPrint('🔧 APPLYING NEW LOGIC WITH HEADINGS');
    debugPrint('Query: "$query"');

    final scoredResults = <ScoredResult>[];
    final headingResults = <ReferenceSearchResult>[];

    // Separate books from headings
    final seenBooks = <String>{};
    debugPrint('\n--- שלב 0: הפרדת ספרים מכותרות ---');
    
    for (final result in allResults) {
      final normalizedRef =
          result.reference.trim().replaceAll(RegExp(r'\s+'), ' ');
      final normalizedTitle =
          result.title.trim().replaceAll(RegExp(r'\s+'), ' ');
      final isBook = normalizedRef == normalizedTitle;

      if (isBook) {
        if (seenBooks.add(normalizedTitle)) {
          // Don't add books to results yet - we'll add them only if no headings found
        }
      } else {
        headingResults.add(result);
      }
    }

    debugPrint('📊 ${matchingBooks.length} ספרים מתאימים, ${headingResults.length} כותרות');

    // Search in headings for ALL matching books
    debugPrint('\n--- שלב 2: חיפוש בכותרות H2 ---');
    bool foundAnyHeadings = false;
    
    for (final bookMatch in matchingBooks) {
      final book = bookMatch.result;
      final remainingWords = MatchLogic.getRemainingWords(query, book.title);
      
      if (remainingWords.isEmpty) {
        debugPrint('  📖 "${book.title}" - אין מילים נוספות, דולג על חיפוש כותרות');
        continue;
      }

      final subQuery = MatchLogic.createSubQuery(remainingWords);
      final bookWasFull = MatchLogic.isFullMatch(query, book.title);
      final bookScoreBonus = bookWasFull ? 40.0 : 10.0;

      debugPrint('  📖 "${book.title}" | מילים נוספות: $remainingWords | subQuery="$subQuery"');

      // Search headings for this book
      final bookHeadings = headingResults.where((h) => h.title == book.title).toList();
      debugPrint('     מצא ${bookHeadings.length} כותרות לספר זה');
      
      int h2Count = 0;
      int h2Checked = 0;
      int h2Skipped = 0;

      for (final heading in bookHeadings) {
        h2Checked++;
        final headingText = _extractHeadingText(heading.reference, book.title);
        final parts = _parseHeadingLevels(headingText);
        
        if (parts.isEmpty) {
          h2Skipped++;
          continue;
        }

        final h2Text = parts[0];
        final h2MatchedCount = MatchLogic.countMatchedWords(subQuery, h2Text);
        
        if (h2MatchedCount == 0) {
          h2Skipped++;
          if (h2Skipped <= 3) {
            debugPrint('     ❌ H2 לא מתאים: "$h2Text" | התאמות=0');
          }
          continue;
        }

        // Found matching heading!
        foundAnyHeadings = true;
        bool addedH3 = false;

        // Check for H3
        if (parts.length > 1) {
          final h2MatchedWords = MatchLogic.getMatchedWords(subQuery, h2Text);
          final remainingAfterH2 = remainingWords
              .where((w) => !h2MatchedWords.contains(w))
              .toList();

          debugPrint('     🔍 H2 מתאים: "$h2Text" | התאמות=$h2MatchedCount | בודק H3...');
          debugPrint('        מילים שנשארו אחרי H2: $remainingAfterH2');

          if (remainingAfterH2.isNotEmpty) {
            final h3SubQuery = MatchLogic.createSubQuery(remainingAfterH2);
            
            for (int i = 1; i < parts.length; i++) {
              final h3Text = parts[i];
              final h3MatchedCount = MatchLogic.countMatchedWords(h3SubQuery, h3Text);
              
              if (h3MatchedCount > 0) {
                final h3Score = 90.0 + h3MatchedCount;
                scoredResults.add(ScoredResult(
                  result: heading,
                  type: 'כותרת3',
                  level: 3,
                  score: h3Score,
                ));
                addedH3 = true;
                h2Count++;
                
                if (h2Count <= 3) {
                  debugPrint('        ✅ H3 מתאים: "$h3Text" | התאמות=$h3MatchedCount | ניקוד=$h3Score | הוסף כ-H3');
                }
                break;
              } else {
                if (h2Count <= 3) {
                  debugPrint('        ❌ H3 לא מתאים: "$h3Text" | התאמות=0');
                }
              }
            }
          } else {
            debugPrint('        אין מילים נוספות לחיפוש ב-H3');
          }
        }

        if (!addedH3) {
          final score = 80.0 + h2MatchedCount + bookScoreBonus;
          scoredResults.add(ScoredResult(
            result: heading,
            type: 'כותרת2',
            level: 2,
            score: score,
          ));
          h2Count++;
          
          if (h2Count <= 3) {
            debugPrint('     ✅ H2 מתאים: "$h2Text" | התאמות=$h2MatchedCount | ניקוד=$score | הוסף כ-H2');
          }
        }
      }

      if (h2Skipped > 3) {
        debugPrint('     ... ועוד ${h2Skipped - 3} כותרות H2 שלא התאימו');
      }
      debugPrint('     סיכום לספר: נבדקו $h2Checked כותרות, נמצאו $h2Count מתאימות, דולגו $h2Skipped');
    }

    // If no headings found, show the books
    if (!foundAnyHeadings) {
      debugPrint('\n⚠️ לא נמצאו כותרות מתאימות - מחזיר ספרים');
      for (final bookMatch in matchingBooks) {
        scoredResults.add(ScoredResult(
          result: bookMatch.result,
          type: bookMatch.score == 2.0 ? 'ספר' : 'ספר_חלקי',
          level: 0,
          score: bookMatch.score == 2.0 ? 50.0 : 20.0,
        ));
      }
    } else {
      debugPrint('\n✅ נמצאו כותרות - לא מציג ספרים');
    }

    debugPrint('\n📊 סה"כ ${scoredResults.length} תוצאות');
    return _sortAndReturn(scoredResults);
  }

  /// Apply the new search logic to filter and rank results
  List<ReferenceSearchResult> _applyNewLogic(
      String query, List<ReferenceSearchResult> allResults) {
    debugPrint('\n${'=' * 80}');
    debugPrint('🔧 APPLYING NEW LOGIC');
    debugPrint('Query: "$query"');

    final scoredResults = <ScoredResult>[];
    final bookResults = <ReferenceSearchResult>[];
    final headingResults = <ReferenceSearchResult>[];

    // הפרדת ספרים מכותרות
    final seenBooks = <String>{};
    debugPrint('\n--- שלב 0: הפרדת ספרים מכותרות ---');
    
    for (final result in allResults) {
      final normalizedRef =
          result.reference.trim().replaceAll(RegExp(r'\s+'), ' ');
      final normalizedTitle =
          result.title.trim().replaceAll(RegExp(r'\s+'), ' ');
      final isBook = normalizedRef == normalizedTitle;

      if (isBook) {
        if (seenBooks.add(normalizedTitle)) {
          bookResults.add(result);
        }
      } else {
        headingResults.add(result);
      }
    }

    debugPrint('📊 ${bookResults.length} ספרים, ${headingResults.length} כותרות');

    // שלב 1: בדיקה ראשונית - ספרים
    debugPrint('\n--- שלב 1: בדיקת ספרים ---');
    debugPrint('בודק ${bookResults.length} ספרים...');
    final matchingBooks = <ReferenceSearchResult>[];
    int checkedBooks = 0;
    int skippedBooks = 0;
    
    for (final book in bookResults) {
      checkedBooks++;
      final matchScore = MatchLogic.matchScore(query, book.title);
      
      if (matchScore == 2.0) {
        // התאמה מלאה
        final score = 50.0; // ניקוד בסיס גבוה
        scoredResults.add(ScoredResult(
          result: book,
          type: 'ספר',
          level: 0,
          score: score,
        ));
        matchingBooks.add(book);
        debugPrint('  ✅ התאמה מלאה: "${book.title}" | matchScore=$matchScore | ניקוד=$score');
      } else if (matchScore == 1.0) {
        // התאמה חלקית
        final score = 20.0; // ניקוד בסיס נמוך
        scoredResults.add(ScoredResult(
          result: book,
          type: 'ספר_חלקי',
          level: 0,
          score: score,
        ));
        matchingBooks.add(book);
        debugPrint('  ✅ התאמה חלקית: "${book.title}" | matchScore=$matchScore | ניקוד=$score');
      } else {
        skippedBooks++;
        if (skippedBooks <= 5) {
          debugPrint('  ❌ לא מתאים: "${book.title}" | matchScore=$matchScore');
        }
      }
    }
    
    if (skippedBooks > 5) {
      debugPrint('  ... ועוד ${skippedBooks - 5} ספרים שלא התאימו');
    }
    debugPrint('סיכום: נבדקו $checkedBooks ספרים, נמצאו ${matchingBooks.length} מתאימים, דולגו $skippedBooks');

    if (matchingBooks.isEmpty) {
      debugPrint('⚠️ לא נמצאו ספרים מתאימים');
      return [];
    }

    debugPrint('\n📊 נמצאו ${matchingBooks.length} ספרים מתאימים');

    // בדיקה אם יש יותר ממילה אחת (כלומר חיפוש מעבר לשם הספר)
    final queryWords = query.trim().split(RegExp(r'\s+'));
    final hasMultipleWords = queryWords.length > 1;

    if (!hasMultipleWords) {
      debugPrint('\n🎯 מילה אחת בלבד - מחזיר רק ספרים');
      return _sortAndReturn(scoredResults);
    }

    // שלב 2: חיפוש בכותרות רמה 2
    debugPrint('\n--- שלב 2: חיפוש בכותרות H2 ---');
    
    for (final book in matchingBooks) {
      final remainingWords = MatchLogic.getRemainingWords(query, book.title);
      
      if (remainingWords.isEmpty) {
        debugPrint('  📖 "${book.title}" - אין מילים נוספות, דולג על חיפוש כותרות');
        continue;
      }

      final subQuery = MatchLogic.createSubQuery(remainingWords);
      final bookWasFull = MatchLogic.isFullMatch(query, book.title);
      final bookScoreBonus = bookWasFull ? 40.0 : 10.0;

      debugPrint('  📖 "${book.title}" | מילים נוספות: $remainingWords | subQuery="$subQuery"');

      // חיפוש כותרות H2 של הספר
      final bookHeadings = headingResults.where((h) => h.title == book.title).toList();
      debugPrint('     מצא ${bookHeadings.length} כותרות לספר זה');
      
      int h2Count = 0;
      int h2Checked = 0;
      int h2Skipped = 0;

      for (final heading in bookHeadings) {
        h2Checked++;
        // חילוץ טקסט הכותרת
        final headingText = _extractHeadingText(heading.reference, book.title);
        final parts = _parseHeadingLevels(headingText);
        
        if (parts.isEmpty) {
          h2Skipped++;
          continue;
        }

        // שלב 2: בדיקת H2 קודם (חובה!)
        final h2Text = parts[0];
        final h2MatchedCount = MatchLogic.countMatchedWords(subQuery, h2Text);
        
        if (h2MatchedCount == 0) {
          // אין התאמה ב-H2 → דלג על הכותרת הזו לגמרי (כולל H3)
          h2Skipped++;
          if (h2Skipped <= 3) {
            debugPrint('     ❌ H2 לא מתאים: "$h2Text" | התאמות=0');
          }
          continue;
        }

        // יש התאמה ב-H2!
        bool addedH3 = false;

        // שלב 3: אם יש H3, בדוק אם יש התאמה גם שם
        if (parts.length > 1) {
          final h2MatchedWords = MatchLogic.getMatchedWords(subQuery, h2Text);
          final remainingAfterH2 = remainingWords
              .where((w) => !h2MatchedWords.contains(w))
              .toList();

          debugPrint('     🔍 H2 מתאים: "$h2Text" | התאמות=$h2MatchedCount | בודק H3...');
          debugPrint('        מילים שנשארו אחרי H2: $remainingAfterH2');

          if (remainingAfterH2.isNotEmpty) {
            final h3SubQuery = MatchLogic.createSubQuery(remainingAfterH2);
            
            for (int i = 1; i < parts.length; i++) {
              final h3Text = parts[i];
              final h3MatchedCount = MatchLogic.countMatchedWords(h3SubQuery, h3Text);
              
              if (h3MatchedCount > 0) {
                // יש התאמה גם ב-H3 → הוסף רק את H3 (הרמה העמוקה)
                final h3Score = 90.0 + h3MatchedCount;
                scoredResults.add(ScoredResult(
                  result: heading,
                  type: 'כותרת3',
                  level: 3,
                  score: h3Score,
                ));
                addedH3 = true;
                h2Count++;
                
                if (h2Count <= 3) {
                  debugPrint('        ✅ H3 מתאים: "$h3Text" | התאמות=$h3MatchedCount | ניקוד=$h3Score | הוסף כ-H3');
                }
                break; // נמצאה התאמה ב-H3, לא צריך להוסיף את H2
              } else {
                if (h2Count <= 3) {
                  debugPrint('        ❌ H3 לא מתאים: "$h3Text" | התאמות=0');
                }
              }
            }
          } else {
            debugPrint('        אין מילים נוספות לחיפוש ב-H3');
          }
        }

        // אם לא נמצאה התאמה ב-H3 (או שאין H3), הוסף את H2
        if (!addedH3) {
          final score = 80.0 + h2MatchedCount + bookScoreBonus;
          scoredResults.add(ScoredResult(
            result: heading,
            type: 'כותרת2',
            level: 2,
            score: score,
          ));
          h2Count++;
          
          if (h2Count <= 3) {
            debugPrint('     ✅ H2 מתאים: "$h2Text" | התאמות=$h2MatchedCount | ניקוד=$score | הוסף כ-H2');
          }
        }
      }

      if (h2Skipped > 3) {
        debugPrint('     ... ועוד ${h2Skipped - 3} כותרות H2 שלא התאימו');
      }
      debugPrint('     סיכום לספר: נבדקו $h2Checked כותרות, נמצאו $h2Count מתאימות, דולגו $h2Skipped');
    }

    debugPrint('\n📊 סה"כ ${scoredResults.length} תוצאות');
    return _sortAndReturn(scoredResults);
  }

  /// חילוץ טקסט כותרת (הסרת שם הספר)
  String _extractHeadingText(String reference, String bookTitle) {
    return reference
        .replaceFirst('$bookTitle, ', '')
        .replaceFirst('$bookTitle,', '')
        .replaceFirst(bookTitle, '')
        .trim();
  }

  /// פיצול כותרת לרמות (H2, H3, וכו')
  List<String> _parseHeadingLevels(String headingText) {
    // הנחה: רמות מופרדות בפסיק
    return headingText
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// מיון והחזרת תוצאות
  List<ReferenceSearchResult> _sortAndReturn(List<ScoredResult> scoredResults) {
    debugPrint('\n--- שלב 4: מיון תוצאות ---');
    
    // מיון לפי:
    // 1. ניקוד (גבוה קודם)
    // 2. רמה (עמוקה יותר קודם - 3, 2, 0)
    scoredResults.sort((a, b) {
      // ניקוד קודם
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      
      // רמה שנייה (עמוק יותר קודם)
      return b.level.compareTo(a.level);
    });

    debugPrint('📊 15 תוצאות מובילות:');
    for (int i = 0; i < scoredResults.length && i < 15; i++) {
      final s = scoredResults[i];
      debugPrint('  [$i] ${s.type} | רמה=${s.level} | ניקוד=${s.score} | "${s.result.reference}"');
    }

    return scoredResults.take(15).map((s) => s.result).toList();
  }
}
