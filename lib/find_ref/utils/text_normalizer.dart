import 'package:otzaria/utils/text_manipulation.dart';

/// Utility class for normalizing text for reference search
class TextNormalizer {
  /// Normalize text for searching:
  /// - Remove nikud (vowels)
  /// - Remove teamim (cantillation marks)
  /// - Remove special characters (', ", -, etc.)
  /// - Keep spaces (important for word boundaries)
  /// - Convert to lowercase (not relevant for Hebrew but good practice)
  static String normalize(String text) {
    // Remove HTML tags
    text = stripHtmlIfNeeded(text);

    // Remove nikud and teamim
    text = removeVolwels(text);

    // Remove special characters but keep spaces
    text = _removeSpecialChars(text);

    // Normalize whitespace (multiple spaces to single space)
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Remove special characters: ', ", -, etc.
  /// Keep: Hebrew letters, numbers, spaces
  static String _removeSpecialChars(String text) {
    // Remove common special characters
    text = text
        .replaceAll("'", '')
        .replaceAll('"', '')
        .replaceAll('״', '')
        .replaceAll('׳', '')
        .replaceAll('-', '')
        .replaceAll('־', '')
        .replaceAll('–', '')
        .replaceAll('—', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll(',', '')
        .replaceAll('.', '')
        .replaceAll(':', '')
        .replaceAll(';', '')
        .replaceAll('!', '')
        .replaceAll('?', '');

    return text;
  }

  /// Split text into words (by spaces)
  static List<String> getWords(String text) {
    return text.split(' ').where((w) => w.isNotEmpty).toList();
  }

  /// Check if a word matches another word exactly
  static bool wordMatches(String word1, String word2) {
    return normalize(word1) == normalize(word2);
  }

  /// Check if any word from list1 matches any word from list2
  static bool anyWordMatches(List<String> words1, List<String> words2) {
    for (final w1 in words1) {
      for (final w2 in words2) {
        if (wordMatches(w1, w2)) {
          return true;
        }
      }
    }
    return false;
  }
}
