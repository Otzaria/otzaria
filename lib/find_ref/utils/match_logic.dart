import 'package:otzaria/find_ref/utils/text_normalizer.dart';

/// Utility class for matching logic in reference search
class MatchLogic {
  /// Check if query matches target with the following rules:
  /// - Full match: all words from query exist in target (order doesn't matter)
  /// - Partial match: at least 1 word must match
  /// - Word must be complete (not partial)
  ///
  /// Returns:
  /// - 2.0 for full match (all words)
  /// - 1.0 for partial match (at least 1 word)
  /// - 0.0 for no match
  static double matchScore(String query, String target) {
    final queryWords = TextNormalizer.getWords(TextNormalizer.normalize(query));
    final targetWords =
        TextNormalizer.getWords(TextNormalizer.normalize(target));

    if (queryWords.isEmpty || targetWords.isEmpty) {
      return 0.0;
    }

    // Count how many query words match target words
    int matchedWords = 0;
    for (final qWord in queryWords) {
      if (targetWords.contains(qWord)) {
        matchedWords++;
      }
    }

    // Full match: all query words found in target
    if (matchedWords == queryWords.length) {
      return 2.0;
    }

    // Partial match: at least 1 word matches
    if (matchedWords >= 1) {
      return 1.0;
    }

    // No match
    return 0.0;
  }

  /// Check if there's a full match (all words)
  static bool isFullMatch(String query, String target) {
    return matchScore(query, target) == 2.0;
  }

  /// Check if there's any match (full or partial)
  static bool hasMatch(String query, String target) {
    return matchScore(query, target) > 0.0;
  }

  /// Extract remaining words from query that didn't match the target
  /// Used to search in sub-headings
  static List<String> getRemainingWords(String query, String target) {
    final queryWords = TextNormalizer.getWords(TextNormalizer.normalize(query));
    final targetWords =
        TextNormalizer.getWords(TextNormalizer.normalize(target));

    final remaining = <String>[];
    for (final qWord in queryWords) {
      if (!targetWords.contains(qWord)) {
        remaining.add(qWord);
      }
    }

    return remaining;
  }

  /// Check if query has additional words beyond what matches the target
  static bool hasAdditionalWords(String query, String target) {
    return getRemainingWords(query, target).isNotEmpty;
  }

  /// Create a sub-query from remaining words
  static String createSubQuery(List<String> words) {
    return words.join(' ');
  }

  /// Count how many words from query match target
  static int countMatchedWords(String query, String target) {
    final queryWords = TextNormalizer.getWords(TextNormalizer.normalize(query));
    final targetWords =
        TextNormalizer.getWords(TextNormalizer.normalize(target));

    int matchedWords = 0;
    for (final qWord in queryWords) {
      if (targetWords.contains(qWord)) {
        matchedWords++;
      }
    }
    return matchedWords;
  }

  /// Get the words from query that matched target
  static List<String> getMatchedWords(String query, String target) {
    final queryWords = TextNormalizer.getWords(TextNormalizer.normalize(query));
    final targetWords =
        TextNormalizer.getWords(TextNormalizer.normalize(target));

    final matched = <String>[];
    for (final qWord in queryWords) {
      if (targetWords.contains(qWord)) {
        matched.add(qWord);
      }
    }
    return matched;
  }
}
