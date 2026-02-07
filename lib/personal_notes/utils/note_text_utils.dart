import 'package:characters/characters.dart';

const int kReferenceWordsLimit = 10;

final RegExp wordPattern = RegExp(r'[\p{L}\d]+', unicode: true);
final RegExp wordCharPattern = RegExp(r'[\p{L}\d]', unicode: true);

List<String> splitBookContentIntoLines(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

List<String> extractReferenceWordsFromLine(
  String line, {
  int limit = kReferenceWordsLimit,
  String? excludeBookTitle,
}) {
  // Strip HTML tags from the line before extracting words
  final cleanedLine = _stripHtmlTags(line);
  final matches = wordPattern.allMatches(cleanedLine);
  final words = <String>[];

  // Split book title into words for exclusion
  final excludedWords = excludeBookTitle != null
      ? excludeBookTitle.split(RegExp(r'\s+')).map(normalizeWord).toSet()
      : <String>{};

  for (final match in matches) {
    final word = normalizeWord(match.group(0)!);
    // Skip words that are part of the book title
    if (!excludedWords.contains(word)) {
      words.add(word);
      if (words.length == limit) {
        break;
      }
    }
  }
  return words;
}

String _stripHtmlTags(String htmlText) {
  // Remove HTML tags
  final RegExp htmlTagPattern = RegExp(r'<[^>]*>');
  return htmlText.replaceAll(htmlTagPattern, '').trim();
}

List<String> extractReferenceWordsFromLines(
  List<String> lines,
  int lineNumber, {
  int limit = kReferenceWordsLimit,
  String? excludeBookTitle,
}) {
  final index = lineNumber - 1;
  if (index < 0 || index >= lines.length) {
    return const [];
  }
  return extractReferenceWordsFromLine(
    lines[index],
    limit: limit,
    excludeBookTitle: excludeBookTitle,
  );
}

/// Extract the beginning of a line as display text (without normalization).
/// This is used for showing the user a preview of the line content.
String extractDisplayTextFromLine(
  String line, {
  int maxWords = 5,
  String? excludeBookTitle,
}) {
  // Strip HTML tags from the line before extracting text
  final cleanedLine = _stripHtmlTags(line);

  if (cleanedLine.isEmpty) {
    return '';
  }

  // Remove nikud and te'amim (Hebrew diacritics) but keep the text structure
  final withoutNikud = removeHebrewDiacritics(cleanedLine);

  // Split book title into words for exclusion
  final excludedWords = excludeBookTitle != null
      ? removeHebrewDiacritics(excludeBookTitle)
          .split(RegExp(r'\s+'))
          .map((w) => w.trim().toLowerCase())
          .toSet()
      : <String>{};

  // Split the line into words by whitespace
  final words = withoutNikud.split(RegExp(r'\s+'));
  final selectedWords = <String>[];

  for (final word in words) {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) continue;

    // Skip words that are part of the book title
    if (!excludedWords.contains(trimmedWord.toLowerCase())) {
      selectedWords.add(trimmedWord);
      if (selectedWords.length == maxWords) {
        break;
      }
    }
  }

  // Join the selected words
  String result = selectedWords.join(' ').trim();

  // If the result is too long, truncate it
  if (result.length > 100) {
    result = result.substring(0, 100).trim();
  }

  return result;
}

/// Remove Hebrew nikud (vowel points) and te'amim (cantillation marks)
/// Unicode ranges: 0591-05C7 (te'amim and nikud)
/// Also replaces Hebrew maqaf (־) with space to separate words
String removeHebrewDiacritics(String text) {
  // Replace Hebrew maqaf (־) with space to separate words
  // U+05BE is the Hebrew maqaf
  String result = text.replaceAll('\u05BE', ' ');

  // Remove Hebrew diacritics (nikud and te'amim)
  // Range: U+0591 to U+05C7
  result = result.replaceAll(RegExp(r'[\u0591-\u05C7]'), '');

  return result;
}

/// Extract display text from a specific line number in the book.
String extractDisplayTextFromLines(
  List<String> lines,
  int lineNumber, {
  int maxWords = 5,
  String? excludeBookTitle,
}) {
  final index = lineNumber - 1;
  if (index < 0 || index >= lines.length) {
    return '';
  }
  return extractDisplayTextFromLine(
    lines[index],
    maxWords: maxWords,
    excludeBookTitle: excludeBookTitle,
  );
}

String normalizeWord(String word) {
  final cleaned =
      word.characters.where((c) => wordCharPattern.hasMatch(c)).toString();
  final normalized = cleaned.trim();
  if (normalized.isEmpty) {
    return word.trim();
  }
  return normalized;
}

double computeWordOverlapRatio(List<String> stored, List<String> actual) {
  if (stored.isEmpty) {
    return 1.0;
  }
  if (actual.isEmpty) {
    return 0.0;
  }
  final storedSet = stored.map(normalizeWord).toSet();
  final actualSet = actual.map(normalizeWord).toSet();
  if (storedSet.isEmpty) {
    return actualSet.isEmpty ? 1.0 : 0.0;
  }

  final matches = storedSet.intersection(actualSet).length;
  return matches / storedSet.length;
}
