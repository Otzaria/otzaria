/// Outcome of a rebase operation
enum RebaseOutcome {
  /// Rebase was successful
  success,

  /// Rebase resulted in conflicts that need manual resolution
  conflict,

  /// Rebase was not needed (content hasn't changed)
  notNeeded,

  /// Rebase failed due to an error
  failed,
}

/// Context information for a rebase conflict
class RebaseContext {
  /// Book identifier
  final String bookId;

  /// Section identifier
  final String sectionId;

  /// Original content when override was created
  final String originalContent;

  /// New source content from updated book
  final String newSourceContent;

  /// User's override content
  final String overrideContent;

  /// When the override was last modified
  final DateTime lastModified;

  const RebaseContext({
    required this.bookId,
    required this.sectionId,
    required this.originalContent,
    required this.newSourceContent,
    required this.overrideContent,
    required this.lastModified,
  });
}

/// Abstract service for rebasing overrides when source content changes
abstract class OverridesRebaseService {
  /// Attempts to rebase an override when source content has changed
  Future<RebaseOutcome> rebaseIfSourceChanged({
    required String bookId,
    required String sectionId,
    required String originalCandidate,
    required String overrideMarkdown,
  });

  /// Gets rebase context for manual conflict resolution
  Future<RebaseContext?> getRebaseContext({
    required String bookId,
    required String sectionId,
    required String newSourceContent,
  });
}

/// Default implementation of OverridesRebaseService
class DefaultOverridesRebaseService implements OverridesRebaseService {
  @override
  Future<RebaseOutcome> rebaseIfSourceChanged({
    required String bookId,
    required String sectionId,
    required String originalCandidate,
    required String overrideMarkdown,
  }) async {
    try {
      // First, check if content actually changed
      final originalNormalized = _normalizeContent(originalCandidate);

      // For now, we'll implement a simple hash-based comparison
      // In a real implementation, you'd compare against the stored sourceHashOnOpen

      // If content hasn't changed, no rebase needed
      // This is a simplified check - in practice you'd compare hashes
      if (originalNormalized.isEmpty) {
        return RebaseOutcome.notNeeded;
      }

      // Attempt different matching strategies

      // Strategy 1: Direct sectionId matching (already handled by caller)
      // This method is called when we know the sectionId matches

      // Strategy 2: Content hash matching
      final overrideNormalized = _normalizeContent(overrideMarkdown);
      if (_contentHashMatches(originalNormalized, overrideNormalized)) {
        return RebaseOutcome.success;
      }

      // Strategy 3: Fuzzy matching using rolling hash
      if (await _fuzzyMatch(originalNormalized, overrideNormalized)) {
        return RebaseOutcome.success;
      }

      // If all strategies fail, mark as conflict
      return RebaseOutcome.conflict;
    } catch (e) {
      return RebaseOutcome.failed;
    }
  }

  @override
  Future<RebaseContext?> getRebaseContext({
    required String bookId,
    required String sectionId,
    required String newSourceContent,
  }) async {
    // This would typically load the override and create context
    // For now, return null as this requires integration with repository
    return null;
  }

  /// Normalizes content for comparison by removing nikud, HTML tags, and extra whitespace
  String _normalizeContent(String content) {
    return content
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '') // Remove Hebrew nikud
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Checks if two normalized content strings have matching hashes
  bool _contentHashMatches(String content1, String content2) {
    return content1.hashCode == content2.hashCode;
  }

  /// Performs fuzzy matching using rolling hash on short windows
  Future<bool> _fuzzyMatch(String original, String override) async {
    const windowSize = 50; // Characters
    const threshold = 0.8; // 80% similarity threshold

    if (original.length < windowSize || override.length < windowSize) {
      // For short content, use simple similarity
      return _calculateSimilarity(original, override) >= threshold;
    }

    // Rolling hash approach for longer content
    final originalWindows = _getWindows(original, windowSize);
    final overrideWindows = _getWindows(override, windowSize);

    int matches = 0;
    int totalWindows = originalWindows.length;

    for (final originalWindow in originalWindows) {
      for (final overrideWindow in overrideWindows) {
        if (_calculateSimilarity(originalWindow, overrideWindow) >= threshold) {
          matches++;
          break;
        }
      }
    }

    return (matches / totalWindows) >= threshold;
  }

  /// Gets sliding windows of specified size from content
  List<String> _getWindows(String content, int windowSize) {
    final windows = <String>[];
    for (int i = 0; i <= content.length - windowSize; i += windowSize ~/ 2) {
      windows.add(content.substring(i, i + windowSize));
    }
    return windows;
  }

  /// Calculates similarity between two strings using a simple algorithm
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    if (str1.isEmpty || str2.isEmpty) return 0.0;

    final longer = str1.length > str2.length ? str1 : str2;
    final shorter = str1.length > str2.length ? str2 : str1;

    if (longer.isEmpty) return 1.0;

    final editDistance = _levenshteinDistance(longer, shorter);
    return (longer.length - editDistance) / longer.length;
  }

  /// Calculates Levenshtein distance between two strings
  int _levenshteinDistance(String str1, String str2) {
    final matrix = List.generate(
      str1.length + 1,
      (i) => List.generate(str2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= str1.length; i++) {
      matrix[i][0] = i;
    }

    for (int j = 0; j <= str2.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= str1.length; i++) {
      for (int j = 1; j <= str2.length; j++) {
        final cost = str1[i - 1] == str2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[str1.length][str2.length];
  }
}
