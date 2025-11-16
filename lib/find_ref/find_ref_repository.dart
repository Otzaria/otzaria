import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/find_ref/utils/match_logic.dart';
import 'package:otzaria/find_ref/utils/scored_result.dart';
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
    final matchingBooks = <ReferenceSearchResult>[];
    
    for (final book in bookResults) {
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
        debugPrint('  ✅ התאמה מלאה: "${book.title}" | ניקוד=$score');
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
        debugPrint('  ✅ התאמה חלקית: "${book.title}" | ניקוד=$score');
      }
    }

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
        debugPrint('  📖 "${book.title}" - אין מילים נוספות');
        continue;
      }

      final subQuery = MatchLogic.createSubQuery(remainingWords);
      final bookWasFull = MatchLogic.isFullMatch(query, book.title);
      final bookScoreBonus = bookWasFull ? 40.0 : 10.0;

      debugPrint('  📖 "${book.title}" | מילים נוספות: $remainingWords');

      // חיפוש כותרות H2 של הספר
      final bookHeadings = headingResults.where((h) => h.title == book.title);
      int h2Count = 0;

      for (final heading in bookHeadings) {
        // חילוץ טקסט הכותרת
        final headingText = _extractHeadingText(heading.reference, book.title);
        final parts = _parseHeadingLevels(headingText);
        
        if (parts.isEmpty) continue;

        // שלב 2: בדיקת H2 קודם (חובה!)
        final h2Text = parts[0];
        final h2MatchedCount = MatchLogic.countMatchedWords(subQuery, h2Text);
        
        if (h2MatchedCount == 0) {
          // אין התאמה ב-H2 → דלג על הכותרת הזו לגמרי (כולל H3)
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
                  debugPrint('      ✅ H3: "$h3Text" | התאמות=$h3MatchedCount | ניקוד=$h3Score');
                }
                break; // נמצאה התאמה ב-H3, לא צריך להוסיף את H2
              }
            }
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
            debugPrint('    ✅ H2: "$h2Text" | התאמות=$h2MatchedCount | ניקוד=$score');
          }
        }
      }

      if (h2Count > 3) {
        debugPrint('    ... ועוד ${h2Count - 3} כותרות H2');
      }
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
