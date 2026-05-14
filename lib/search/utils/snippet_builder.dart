import 'dart:math';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/regex_patterns.dart';

class _SnippetMatchRange {
  final int start;
  final int end;

  const _SnippetMatchRange(this.start, this.end);
}

class _ApproximateSnippetMatchCandidate {
  final _SnippetMatchRange range;
  final int distance;

  const _ApproximateSnippetMatchCandidate({
    required this.range,
    required this.distance,
  });
}

class _PreparedHighlightData {
  final String plainText;
  final List<_SnippetMatchRange> exactMatches;
  final List<_SnippetMatchRange> individualWordMatches;
  final List<_SnippetMatchRange> approximateMatches;
  final List<_SnippetMatchRange> allMatches;

  const _PreparedHighlightData({
    required this.plainText,
    required this.exactMatches,
    required this.individualWordMatches,
    required this.approximateMatches,
    required this.allMatches,
  });
}

class SnippetBuilder {
  /// פונקציה לחישוב כמה תווים יכולים להיכנס בשורה אחת
  static int calculateCharsPerLine(double availableWidth, TextStyle textStyle) {
    final textPainter = TextPainter(
      text: TextSpan(text: 'א' * 100, style: textStyle),
      textDirection: TextDirection.rtl,
    );
    textPainter.layout(maxWidth: availableWidth);

    final singleCharWidth = textPainter.width / 100;
    final charsPerLine = (availableWidth / singleCharWidth).floor();

    textPainter.dispose();
    return charsPerLine;
  }

  /// פונקציה חכמה ליצירת קטע טקסט עם הדגשות - מבטיחה שכל ההתאמות יופיעו!
  static List<InlineSpan> createSnippetSpans({
    required String fullHtml,
    required String query,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
    required double availableWidth,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
    Map<String, String> customSpacing = const {},
    int searchDistance = 0,
  }) {
    final plainText =
        html_parser.parse(fullHtml).documentElement?.text.trim() ?? '';
    final prepared = _prepareHighlightData(
      plainText: plainText,
      query: query,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: customSpacing,
      searchDistance: searchDistance,
      fallbackToIndividualWords: false,
    );

    if (prepared.plainText.isEmpty || prepared.allMatches.isEmpty) {
      return [TextSpan(text: plainText, style: defaultStyle)];
    }

    final allMatches = prepared.allMatches;

    // 4. מיון ההתאמות וקביעת הגבולות המוחלטים
    final int absoluteFirstMatch = allMatches.first.start;
    final int absoluteLastMatch = allMatches.last.end;
    final int totalMatchesSpan = absoluteLastMatch - absoluteFirstMatch;

    // 5. קביעת הקטע - עקרון ברזל: כל ההתאמות חייבות להיכלל!
    int snippetStart;
    int snippetEnd;

    // חישוב אורך הטקסט הנדרש לשלוש שורות בהתבסס על רוחב המסך בפועל
    final charsPerLine = calculateCharsPerLine(availableWidth, defaultStyle);
    final targetLength = (charsPerLine * 3).clamp(120, 400);

    // תמיד מתחילים מהגבולות המוחלטים של ההתאמות
    snippetStart = absoluteFirstMatch;
    snippetEnd = absoluteLastMatch;

    if (totalMatchesSpan < 50) {
      // אם המילים קרובות מאוד (כולל מילה אחת)
      // נוסיף הקשר מוגבל - מקסימום 60 תווים מכל צד
      const limitedPadding = 60;
      snippetStart =
          (absoluteFirstMatch - limitedPadding).clamp(0, plainText.length);
      snippetEnd =
          (absoluteLastMatch + limitedPadding).clamp(0, plainText.length);
    } else if (totalMatchesSpan < targetLength) {
      // אם ההתאמות קצרות מהיעד, נוסיף הקשר עד שנגיע ל-3 שורות
      int remainingSpace = targetLength - totalMatchesSpan;
      int paddingBefore = remainingSpace ~/ 2;
      int paddingAfter = remainingSpace - paddingBefore;

      snippetStart =
          (absoluteFirstMatch - paddingBefore).clamp(0, plainText.length);
      snippetEnd =
          (absoluteLastMatch + paddingAfter).clamp(0, plainText.length);
    } else {
      // אם ההתאמות ארוכות, נוסיף רק מעט הקשר
      const minPadding = 30;
      snippetStart =
          (absoluteFirstMatch - minPadding).clamp(0, plainText.length);
      snippetEnd = (absoluteLastMatch + minPadding).clamp(0, plainText.length);
    }

    // התאמה לגבולות מילים - אבל לא על חשבון ההתאמות!
    if (snippetStart > 0 && snippetStart < absoluteFirstMatch) {
      int? spaceIndex = plainText.lastIndexOf(' ', snippetStart);
      if (spaceIndex != -1 && spaceIndex >= snippetStart - 50) {
        snippetStart = spaceIndex + 1;
      } else {
        while (snippetStart > 0 && plainText[snippetStart - 1] != ' ') {
          snippetStart--;
        }
      }
    }

    if (snippetEnd < plainText.length && snippetEnd > absoluteLastMatch) {
      int? spaceIndex = plainText.indexOf(' ', snippetEnd);
      if (spaceIndex != -1 && spaceIndex <= snippetEnd + 50) {
        snippetEnd = spaceIndex;
      } else {
        while (snippetEnd < plainText.length && plainText[snippetEnd] != ' ') {
          snippetEnd++;
        }
      }
    }

    if (snippetStart > absoluteFirstMatch) {
      snippetStart = absoluteFirstMatch;
    }
    if (snippetEnd < absoluteLastMatch) {
      snippetEnd = absoluteLastMatch;
    }

    final snippetText = plainText.substring(snippetStart, snippetEnd);

    // 6. בדיקה נוספת - ספירת ההתאמות בקטע הסופי
    final snippetMatches = allMatches
        .where(
            (match) => match.start >= snippetStart && match.end <= snippetEnd)
        .map((match) => _SnippetMatchRange(
            match.start - snippetStart, match.end - snippetStart))
        .toList();

    final int finalMatchCount = snippetMatches.length;

    if (finalMatchCount < allMatches.length) {
      snippetStart = (absoluteFirstMatch - 100).clamp(0, plainText.length);
      snippetEnd = (absoluteLastMatch + 100).clamp(0, plainText.length);
      final expandedSnippet = plainText.substring(snippetStart, snippetEnd);

      final expandedMatches = allMatches
          .where(
              (match) => match.start >= snippetStart && match.end <= snippetEnd)
          .map((match) => _SnippetMatchRange(
              match.start - snippetStart, match.end - snippetStart))
          .toList();

      if (expandedMatches.length >= allMatches.length) {
        return _buildTextSpans(
            expandedSnippet, expandedMatches, defaultStyle, highlightStyle);
      }
    }

    return _buildTextSpans(
        snippetText, snippetMatches, defaultStyle, highlightStyle);
  }

  static List<InlineSpan> buildHighlightSpans({
    required String plainText,
    required String query,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
    Map<String, String> spacingValues = const {},
    int searchDistance = 0,
    bool fallbackToIndividualWords = true,
  }) {
    final prepared = _prepareHighlightData(
      plainText: plainText,
      query: query,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      searchDistance: searchDistance,
      fallbackToIndividualWords: fallbackToIndividualWords,
    );

    final matches = prepared.exactMatches.isNotEmpty
        ? _mergeOverlappingRanges(
            [...prepared.exactMatches, ...prepared.approximateMatches])
        : fallbackToIndividualWords
            ? _mergeOverlappingRanges([
                ...prepared.individualWordMatches,
                ...prepared.approximateMatches,
              ])
            : prepared.approximateMatches;

    if (prepared.plainText.isEmpty || matches.isEmpty) {
      return [TextSpan(text: prepared.plainText, style: defaultStyle)];
    }

    return _buildTextSpans(
      prepared.plainText,
      matches,
      defaultStyle,
      highlightStyle,
    );
  }

  static String buildExcerptText({
    required String fullText,
    required String query,
    required int maxChars,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
    Map<String, String> spacingValues = const {},
    int searchDistance = 0,
    bool fallbackToIndividualWords = true,
  }) {
    final text = fullText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxChars) return text;

    int findWordEnd(int fromIndex) {
      if (fromIndex >= text.length) return text.length;
      final nextSpace = text.indexOf(' ', fromIndex);
      return nextSpace != -1 ? nextSpace : text.length;
    }

    int findWordStart(int fromIndex) {
      if (fromIndex <= 0) return 0;
      final lastSpace = text.lastIndexOf(' ', fromIndex);
      return lastSpace != -1 ? lastSpace + 1 : 0;
    }

    if (query.trim().isEmpty) {
      final end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    final prepared = _prepareHighlightData(
      plainText: text,
      query: query,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      searchDistance: searchDistance,
      fallbackToIndividualWords: fallbackToIndividualWords,
    );

    final anchorRange = prepared.exactMatches.isNotEmpty
        ? prepared.exactMatches.first
        : prepared.individualWordMatches.isNotEmpty
            ? prepared.individualWordMatches.first
            : prepared.approximateMatches.isNotEmpty
                ? prepared.approximateMatches.first
                : null;

    if (anchorRange == null) {
      final end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    final len = text.length;
    var start = (anchorRange.start - (maxChars ~/ 3)).clamp(0, len);
    var end = (start + maxChars).clamp(0, len);

    if (end - start < maxChars) {
      start = (end - maxChars).clamp(0, len);
    }

    start = findWordStart(start);
    end = findWordEnd(end);

    final prefix = start > 0 ? '... ' : '';
    final suffix = end < len ? ' ...' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  /// מציאת התאמות ביטוי (phrase matching) בשיטת token-based:
  /// מוצאים רק הופעות שבהן כל המילים מופיעות ברצף כשמספר הטוקנים
  /// ביניהם <= customSpacing. תואם את סמנטיקת slop מנוע החיפוש.
  /// אם לא נמצא ביטוי - מחזיר רשימה ריקה (אין הדגשה), לא מחזיר בodim בודדות.
  static List<_SnippetMatchRange> _collectPhraseWordMatches(
    String plainText,
    List<List<_TokenPattern>> patternsByWord, {
    Map<String, String> customSpacing = const {},
  }) {
    if (patternsByWord.isEmpty) return const [];

    final tokens = _collectSearchTokens(plainText);
    final matchesByWord = _collectWordMatchesByWord(tokens, patternsByWord);

    // מילה אחת - נחזיר את כל ההופעות
    if (patternsByWord.length == 1) {
      return _mergeOverlappingRanges(matchesByWord[0]);
    }

    // 2. בניית רשימת תחילות הטוקנים (מילים לא-רווח) לספירת טוקנים בין היתורים
    final tokenStarts =
        tokens.map((token) => token.start).toList(growable: false);

    // 3. Phrase matching: עבור כל הופעה של המילה הראשונה, בודק אם שאר המילים מופיעות ברצף.
    // משתמשים ב-backtracking כדי לא לפספס התאמה חוקית בגלל בחירה גרידית מוקדמת.
    final result = <_SnippetMatchRange>[];
    final continuationCache = <String, int?>{};

    for (final firstMatch in matchesByWord[0]) {
      final phraseMatches = [firstMatch];
      if (_tryMatchPhraseContinuation(
        matchesByWord: matchesByWord,
        tokenStarts: tokenStarts,
        customSpacing: customSpacing,
        wordIdx: 1,
        prevEnd: firstMatch.end,
        phraseMatches: phraseMatches,
        continuationCache: continuationCache,
      )) {
        result.addAll(phraseMatches);
      }
    }

    // אם לא נמצא ביטוי - מחזירים רשימה ריקה. דע caller יבחר להציג קטע ללא הדגשה.
    // זה הוגן מהדגשת הופעות בודדות לא-קשורות.
    final merged = _mergeOverlappingRanges(result);
    return _mergeAdjacentQuoteGaps(plainText, merged);
  }

  static bool _tryMatchPhraseContinuation({
    required List<List<_SnippetMatchRange>> matchesByWord,
    required List<int> tokenStarts,
    required Map<String, String> customSpacing,
    required int wordIdx,
    required int prevEnd,
    required List<_SnippetMatchRange> phraseMatches,
    required Map<String, int?> continuationCache,
  }) {
    if (wordIdx >= matchesByWord.length) {
      return true;
    }

    final cacheKey = '$wordIdx:$prevEnd';
    if (continuationCache.containsKey(cacheKey)) {
      final cachedIndex = continuationCache[cacheKey];
      if (cachedIndex == null) {
        return false;
      }

      final cachedCandidate = matchesByWord[wordIdx][cachedIndex];
      phraseMatches.add(cachedCandidate);
      final hasContinuation = _tryMatchPhraseContinuation(
        matchesByWord: matchesByWord,
        tokenStarts: tokenStarts,
        customSpacing: customSpacing,
        wordIdx: wordIdx + 1,
        prevEnd: cachedCandidate.end,
        phraseMatches: phraseMatches,
        continuationCache: continuationCache,
      );
      if (!hasContinuation) {
        phraseMatches.removeLast();
      }
      return hasContinuation;
    }

    final spacingKey = '${wordIdx - 1}-$wordIdx';
    final maxTokensBetween = int.tryParse(customSpacing[spacingKey] ?? '') ?? 0;
    final candidates = matchesByWord[wordIdx];
    final startIndex = _firstRangeStartingAtOrAfter(candidates, prevEnd);

    for (var candidateIndex = startIndex;
        candidateIndex < candidates.length;
        candidateIndex++) {
      final candidate = candidates[candidateIndex];

      final tokensBetween =
          _countTokensInRange(tokenStarts, prevEnd, candidate.start);
      if (tokensBetween > maxTokensBetween) {
        break;
      }

      phraseMatches.add(candidate);
      if (_tryMatchPhraseContinuation(
        matchesByWord: matchesByWord,
        tokenStarts: tokenStarts,
        customSpacing: customSpacing,
        wordIdx: wordIdx + 1,
        prevEnd: candidate.end,
        phraseMatches: phraseMatches,
        continuationCache: continuationCache,
      )) {
        continuationCache[cacheKey] = candidateIndex;
        return true;
      }
      phraseMatches.removeLast();
    }

    continuationCache[cacheKey] = null;
    return false;
  }

  static int _firstRangeStartingAtOrAfter(
    List<_SnippetMatchRange> ranges,
    int minStart,
  ) {
    int lo = 0;
    int hi = ranges.length;

    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (ranges[mid].start < minStart) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    return lo;
  }

  /// ספירת טוקנים בטווח [fromPos, toPos) עם binary search.
  static int _countTokensInRange(
      List<int> sortedStarts, int fromPos, int toPos) {
    if (sortedStarts.isEmpty || toPos <= fromPos) return 0;

    int lo = 0, hi = sortedStarts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (sortedStarts[mid] < fromPos) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final left = lo;

    lo = 0;
    hi = sortedStarts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (sortedStarts[mid] < toPos) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final right = lo;

    return right - left;
  }

  static List<_ApproximateSnippetMatchCandidate> _collectApproximateMatches(
    String plainText,
    List<String> searchTerms, {
    required List<_SnippetMatchRange> existingMatches,
  }) {
    final matches = <_ApproximateSnippetMatchCandidate>[];
    final normalizedTerms = searchTerms
        .map(_normalizeForApproximateComparison)
        .where((term) => term.length >= 2)
        .toSet();

    if (normalizedTerms.isEmpty) {
      return matches;
    }

    final tokenRegex = RegExp(r'[א-תA-Za-z0-9]+');
    for (final tokenMatch in tokenRegex.allMatches(plainText)) {
      if (_overlapsExistingMatch(
          tokenMatch.start, tokenMatch.end, existingMatches)) {
        continue;
      }

      final token = tokenMatch.group(0) ?? '';
      final normalizedToken = _normalizeForApproximateComparison(token);
      if (normalizedToken.length < 2) {
        continue;
      }

      final distance = normalizedTerms
          .map((term) => _editDistanceUpToOne(normalizedToken, term))
          .whereType<int>()
          .fold<int?>(null, (best, current) {
        if (best == null || current < best) {
          return current;
        }
        return best;
      });

      if (distance != null) {
        matches.add(
          _ApproximateSnippetMatchCandidate(
            range: _SnippetMatchRange(tokenMatch.start, tokenMatch.end),
            distance: distance,
          ),
        );
      }
    }

    return matches;
  }

  static List<_SnippetMatchRange> _selectApproximateMatchesForSnippet(
    List<_ApproximateSnippetMatchCandidate> candidates, {
    required int plainTextLength,
  }) {
    if (candidates.isEmpty) {
      return const [];
    }

    const clusterRadius = 90;
    final center = plainTextLength / 2;

    final sortedCandidates = [...candidates]..sort((left, right) {
        final distanceCompare = left.distance.compareTo(right.distance);
        if (distanceCompare != 0) {
          return distanceCompare;
        }

        final leftCenter = (left.range.start + left.range.end) / 2;
        final rightCenter = (right.range.start + right.range.end) / 2;
        final centerCompare =
            (leftCenter - center).abs().compareTo((rightCenter - center).abs());
        if (centerCompare != 0) {
          return centerCompare;
        }

        return left.range.start.compareTo(right.range.start);
      });

    final anchor = sortedCandidates.first;
    final anchorCenter = (anchor.range.start + anchor.range.end) / 2;

    final cluster = sortedCandidates
        .where((candidate) {
          final candidateCenter =
              (candidate.range.start + candidate.range.end) / 2;
          return (candidateCenter - anchorCenter).abs() <= clusterRadius;
        })
        .map((candidate) => candidate.range)
        .toList();

    return _mergeOverlappingRanges(cluster);
  }

  static List<_SnippetMatchRange> _selectApproximateMatchesNearExactMatches(
    List<_ApproximateSnippetMatchCandidate> candidates,
    List<_SnippetMatchRange> exactMatches,
  ) {
    if (candidates.isEmpty || exactMatches.isEmpty) {
      return const [];
    }

    const clusterRadius = 90;
    final nearbyRanges = candidates
        .where((candidate) {
          final candidateCenter =
              (candidate.range.start + candidate.range.end) / 2;
          return exactMatches.any((exactMatch) {
            final exactCenter = (exactMatch.start + exactMatch.end) / 2;
            return (candidateCenter - exactCenter).abs() <= clusterRadius;
          });
        })
        .map((candidate) => candidate.range)
        .toList();

    return _mergeOverlappingRanges(nearbyRanges);
  }

  static List<_SnippetMatchRange> _mergeOverlappingRanges(
    List<_SnippetMatchRange> ranges,
  ) {
    if (ranges.isEmpty) {
      return const [];
    }

    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <_SnippetMatchRange>[sorted.first];

    for (final range in sorted.skip(1)) {
      final previous = merged.last;
      if (range.start <= previous.end) {
        merged[merged.length - 1] =
            _SnippetMatchRange(previous.start, max(previous.end, range.end));
      } else {
        merged.add(range);
      }
    }

    return merged;
  }

  static final RegExp _quoteOnlyGap = RegExp(r'''^["'״׳]+$''');

  static List<_SnippetMatchRange> _mergeAdjacentQuoteGaps(
    String plainText,
    List<_SnippetMatchRange> ranges,
  ) {
    if (ranges.length < 2) return ranges;
    final result = <_SnippetMatchRange>[ranges.first];
    for (final range in ranges.skip(1)) {
      final prev = result.last;
      if (range.start > prev.end) {
        final gap = plainText.substring(prev.end, range.start);
        if (_quoteOnlyGap.hasMatch(gap)) {
          result[result.length - 1] = _SnippetMatchRange(prev.start, range.end);
          continue;
        }
      }
      result.add(range);
    }
    return result;
  }

  static bool _overlapsExistingMatch(
    int start,
    int end,
    List<_SnippetMatchRange> existingMatches,
  ) {
    return existingMatches
        .any((match) => start < match.end && end > match.start);
  }

  static String _normalizeForApproximateComparison(String text) {
    return text
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '')
        .replaceAll(RegExp("[\"״׳' ]"), '')
        .trim()
        .toLowerCase();
  }

  static int? _editDistanceUpToOne(String left, String right) {
    if (left == right) {
      return 0;
    }

    final lengthDifference = (left.length - right.length).abs();
    if (lengthDifference > 1) {
      return null;
    }

    if (left.length == right.length &&
        _isSingleAdjacentTransposition(left, right)) {
      return 1;
    }

    final shorter = left.length <= right.length ? left : right;
    final longer = left.length <= right.length ? right : left;

    int shortIndex = 0;
    int longIndex = 0;
    int edits = 0;

    while (shortIndex < shorter.length && longIndex < longer.length) {
      if (shorter[shortIndex] == longer[longIndex]) {
        shortIndex++;
        longIndex++;
        continue;
      }

      edits++;
      if (edits > 1) {
        return null;
      }

      if (shorter.length == longer.length) {
        shortIndex++;
      }
      longIndex++;
    }

    if (shortIndex < shorter.length || longIndex < longer.length) {
      edits++;
    }

    return edits <= 1 ? edits : null;
  }

  static bool _isSingleAdjacentTransposition(String left, String right) {
    int mismatchIndex = -1;

    for (int i = 0; i < left.length; i++) {
      if (left[i] == right[i]) {
        continue;
      }

      if (mismatchIndex != -1) {
        return i == mismatchIndex + 1 &&
            left[mismatchIndex] == right[i] &&
            left[i] == right[mismatchIndex] &&
            left.substring(i + 1) == right.substring(i + 1);
      }

      mismatchIndex = i;
    }

    return false;
  }

  /// מימוש ישן שנשאר לצורכי תאימות בזמן מעבר ללוגיקה החדשה.
  // ignore: unused_element
  static String _termToRegexPatternLegacy(String term) {
    const optionalQuotesAndMarks = r'["״׳]?[591-5C7]*';
    final chars = term.split('');
    if (chars.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      buffer.write(RegExp.escape(chars[i]));
      buffer.write(r'[591-5C7]*');
      if (i < chars.length - 1) {
        buffer.write(optionalQuotesAndMarks);
      }
    }

    return buffer.toString();
  }

  static _PreparedHighlightData _prepareHighlightData({
    required String plainText,
    required String query,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
    required Map<String, String> spacingValues,
    required int searchDistance,
    required bool fallbackToIndividualWords,
  }) {
    final searchTerms = SearchQueryBuilder.splitQueryWords(query);
    if (plainText.isEmpty || searchTerms.isEmpty) {
      return const _PreparedHighlightData(
        plainText: '',
        exactMatches: [],
        individualWordMatches: [],
        approximateMatches: [],
        allMatches: [],
      );
    }

    final effectiveSpacingValues = SearchQueryBuilder.effectiveSpacingValues(
      wordCount: searchTerms.length,
      spacingValues: spacingValues,
      searchDistance: searchDistance,
    );

    final patternsByWord = <List<_TokenPattern>>[];
    final approximateTerms = <String>[];
    for (int i = 0; i < searchTerms.length; i++) {
      final word = searchTerms[i];
      final wordOptions =
          searchOptions[SearchQueryBuilder.buildWordKey(word, i)] ??
              const <String, bool>{};
      final alternatives = alternativeWords[i] ?? const <String>[];
      approximateTerms.addAll(
        _buildExpandedTermsForWord(
          word,
          wordOptions,
          alternatives: alternatives,
        ),
      );
      patternsByWord.add(
        _buildPatternsForWord(
          word,
          wordOptions,
          alternatives: alternatives,
        ),
      );
    }

    final exactMatches = _collectPhraseWordMatches(
      plainText,
      patternsByWord,
      customSpacing: effectiveSpacingValues,
    );

    final individualWordMatches = fallbackToIndividualWords
        ? _mergeOverlappingRanges(
            _collectWordMatchesByWord(
                    _collectSearchTokens(plainText), patternsByWord)
                .expand((matches) => matches)
                .toList(growable: false),
          )
        : const <_SnippetMatchRange>[];

    final approximateMatches =
        SearchQueryBuilder.hasTypoToleranceEnabled(searchOptions)
            ? _selectApproximateMatches(
                plainText: plainText,
                searchTerms: approximateTerms,
                exactMatches: exactMatches,
                fallbackMatches: individualWordMatches,
              )
            : const <_SnippetMatchRange>[];

    final allMatches = _mergeOverlappingRanges(
      exactMatches.isNotEmpty
          ? [...exactMatches, ...approximateMatches]
          : fallbackToIndividualWords
              ? [...individualWordMatches, ...approximateMatches]
              : approximateMatches,
    );

    return _PreparedHighlightData(
      plainText: plainText,
      exactMatches: exactMatches,
      individualWordMatches: individualWordMatches,
      approximateMatches: approximateMatches,
      allMatches: allMatches,
    );
  }

  static List<_SnippetMatchRange> _selectApproximateMatches({
    required String plainText,
    required List<String> searchTerms,
    required List<_SnippetMatchRange> exactMatches,
    required List<_SnippetMatchRange> fallbackMatches,
  }) {
    final approxCandidates = _collectApproximateMatches(
      plainText,
      searchTerms,
      existingMatches: exactMatches.isNotEmpty ? exactMatches : fallbackMatches,
    );

    if (approxCandidates.isEmpty) {
      return const <_SnippetMatchRange>[];
    }

    return exactMatches.isNotEmpty
        ? _selectApproximateMatchesNearExactMatches(
            approxCandidates,
            exactMatches,
          )
        : _selectApproximateMatchesForSnippet(
            approxCandidates,
            plainTextLength: plainText.length,
          );
  }

  static List<List<_SnippetMatchRange>> _collectWordMatchesByWord(
    List<_SearchToken> tokens,
    List<List<_TokenPattern>> patternsByWord,
  ) {
    return patternsByWord.map((patterns) {
      final wordMatches = <_SnippetMatchRange>[];
      for (final token in tokens) {
        for (final pattern in patterns) {
          final match = pattern.regex.firstMatch(token.text);
          if (match == null) {
            continue;
          }

          final highlightedText = match.group(1);
          if (highlightedText == null || highlightedText.isEmpty) {
            continue;
          }

          final groupStart = token.text.indexOf(highlightedText, match.start);
          if (groupStart == -1) {
            continue;
          }

          final groupEnd = groupStart + highlightedText.length;

          wordMatches.add(
            _SnippetMatchRange(
              token.start + groupStart,
              token.start + groupEnd,
            ),
          );
        }
      }

      wordMatches.sort((a, b) => a.start.compareTo(b.start));
      return _mergeOverlappingRanges(wordMatches);
    }).toList(growable: false);
  }

  static List<_SearchToken> _collectSearchTokens(String plainText) {
    final tokens = <_SearchToken>[];
    for (final match
        // מחריגים ־ (U+05BE) ו-׀ (U+05C0) מהטווח כדי שמילים מופרדות במקף יפוצלו
        // לטוקנים נפרדים — sanitizeQuery ממיר ־ לרווח בשאילתה.
        in RegExp(r'''[א-תA-Za-z0-9֑-ֽֿׁ-ׇ]+(?:['׳](?![א-תA-Za-z0-9֑-ֽֿׁ-ׇ]))?''')
            .allMatches(plainText)) {
      final token = match.group(0);
      if (token == null || token.isEmpty) {
        continue;
      }
      tokens.add(_SearchToken(token, match.start, match.end));
    }
    return tokens;
  }

  static List<_TokenPattern> _buildPatternsForWord(
    String word,
    Map<String, bool> wordOptions, {
    required List<String> alternatives,
  }) {
    final terms = _buildExpandedTermsForWord(
      word,
      wordOptions,
      alternatives: alternatives,
    );

    final patterns = <_TokenPattern>[];
    for (final term in terms) {
      patterns.addAll(_buildPatternsForSingleTerm(term, wordOptions));
    }
    return patterns;
  }

  static List<String> _buildExpandedTermsForWord(
    String word,
    Map<String, bool> wordOptions, {
    required List<String> alternatives,
  }) {
    final hasFullPartialSpelling = wordOptions['כתיב מלא/חסר'] == true;
    final baseTerms = <String>[word, ...alternatives]
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty);

    final expandedTerms = <String>{};
    for (final term in baseTerms) {
      if (hasFullPartialSpelling) {
        expandedTerms.addAll(
          SearchRegexPatterns.generateFullPartialSpellingVariations(term),
        );
      } else {
        expandedTerms.add(term);
      }
    }

    return expandedTerms.toList(growable: false);
  }

  static List<_TokenPattern> _buildPatternsForSingleTerm(
    String term,
    Map<String, bool> wordOptions,
  ) {
    final hasPrefix = wordOptions['קידומות'] == true;
    final hasSuffix = wordOptions['סיומות'] == true;
    final hasGrammaticalPrefixes = wordOptions['קידומות דקדוקיות'] == true;
    final hasGrammaticalSuffixes = wordOptions['סיומות דקדוקיות'] == true;
    final hasPartialWord = wordOptions['חלק ממילה'] == true;
    return [
      _TokenPattern(
        RegExp(
          '^(?:${_buildTokenPatternForLiteral(
            term,
            hasPrefix: hasPrefix,
            hasSuffix: hasSuffix,
            hasGrammaticalPrefixes: hasGrammaticalPrefixes,
            hasGrammaticalSuffixes: hasGrammaticalSuffixes,
            hasPartialWord: hasPartialWord,
          )})'
          r'$',
          caseSensitive: false,
        ),
      ),
    ];
  }

  /// בניית תבנית רגקס שמאפשרת מרכאות וניקוד אופציונליים בין תווים.
  static String _termToRegexPattern(String term) {
    const optionalQuotesAndMarks = r'["״׳]?[\u0591-\u05C7]*';
    final chars = term.split('');
    if (chars.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      // " ו-' בשאילתה מתאימים גם ל-״ ו-׳ בטקסט המוצג.
      if (ch == '"') {
        buffer.write('["\u05F4]');
      } else if (ch == "'") {
        buffer.write("['\u05F3]");
      } else {
        buffer.write(RegExp.escape(ch));
      }
      buffer.write(r'[\u0591-\u05C7]*');
      if (i < chars.length - 1) {
        buffer.write(optionalQuotesAndMarks);
      }
    }

    return buffer.toString();
  }

  static String _buildTokenPatternForLiteral(
    String literal, {
    required bool hasPrefix,
    required bool hasSuffix,
    required bool hasGrammaticalPrefixes,
    required bool hasGrammaticalSuffixes,
    required bool hasPartialWord,
  }) {
    final captured = '(${_termToRegexPattern(literal)})';

    if (hasPrefix && hasSuffix) {
      return literal.length <= 3
          ? '.{0,3}$captured.{0,3}'
          : '.{0,2}$captured.{0,2}';
    }

    if (hasGrammaticalPrefixes && hasGrammaticalSuffixes) {
      return '$_grammaticalPrefixPattern$captured$_grammaticalSuffixPattern';
    }

    if (hasPrefix) {
      if (literal.length <= 1) {
        return '.{1,5}$captured';
      }
      if (literal.length <= 2) {
        return '.{1,4}$captured';
      }
      if (literal.length <= 3) {
        return '.{1,3}$captured';
      }
      return '.*$captured';
    }

    if (hasSuffix) {
      if (literal.length <= 1) {
        return '$captured.{1,7}';
      }
      if (literal.length <= 2) {
        return '$captured.{1,6}';
      }
      if (literal.length <= 3) {
        return '$captured.{1,5}';
      }
      return '$captured.*';
    }

    if (hasGrammaticalPrefixes) {
      return '$_grammaticalPrefixPattern$captured';
    }

    if (hasGrammaticalSuffixes) {
      return '$captured$_grammaticalSuffixPattern';
    }

    if (hasPartialWord) {
      return literal.length <= 3
          ? '.{0,3}$captured.{0,3}'
          : '.{0,2}$captured.{0,2}';
    }

    return captured;
  }

  static const String _grammaticalPrefixPattern =
      r'(?:ו|מ|דא|א|כש|כ|ב|ש|ל|ה|ד)?(?:כ|ב|ש|ל|ה|ד)?(?:ה)?';

  static const String _grammaticalSuffixPattern =
      r'(?:ותי|ותַי|ותיך|ותֶיךָ|ותַיִךְ|ותיו|ותָיו|ותיה|ותֶיהָ|ותינו|ותֵינוּ|ותיכם|ותֵיכם|ותיכן|ותֵיכן|ותיהם|ותֵיהם|ותיהן|ותֵיהן|יות|יי|יַי|יך|יךָ|יִךְ|יו|יה|יא|תא|יהָ|ינו|יכם|יכן|יהם|יהן|י|ך|ךָ|ךְ|ו|ה|הּ|נו|כם|כן|ם|ן|ים|ות)?';

  static List<InlineSpan> _buildTextSpans(
    String text,
    List<_SnippetMatchRange> matches,
    TextStyle defaultStyle,
    TextStyle highlightStyle,
  ) {
    final List<InlineSpan> spans = [];
    int currentPosition = 0;

    for (final match in matches) {
      if (match.start > currentPosition) {
        spans.add(TextSpan(
          text: text.substring(currentPosition, match.start),
          style: defaultStyle,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: highlightStyle,
      ));
      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentPosition),
        style: defaultStyle,
      ));
    }

    return spans;
  }
}

class _SearchToken {
  final String text;
  final int start;
  final int end;

  const _SearchToken(this.text, this.start, this.end);
}

class _TokenPattern {
  final RegExp regex;

  const _TokenPattern(this.regex);
}
