import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:search_engine/search_engine.dart';

class FindRefRepository {
  final DataRepository dataRepository;

  FindRefRepository({required this.dataRepository});

  Future<List<ReferenceSearchResult>> findRefs(String ref) async {
    final cleanedQuery = _normalizeForMatch(ref);
    if (cleanedQuery.isEmpty) {
      return const [];
    }

    final queryTokens = _tokenize(cleanedQuery);
    if (queryTokens.isEmpty) {
      return const [];
    }

    // שלב 1: שלוף יותר תוצאות מהרגיל כדי לפצות על אלו שיסוננו
    final rawResults = await TantivyDataProvider.instance.searchRefs(
      replaceParaphrases(removeSectionNames(ref)),
      300,
      false,
    );

    // שלב 2: בצע סינון כפילויות (דה-דופליקציה) חכם
    final unique = _dedupeRefs(rawResults);

    // שלב 3: סנן ודירג בהתאם לכללי האיתור החדשים
    final ranked = _filterAndRank(unique, queryTokens);

    return ranked.length > 15
        ? ranked.take(15).toList(growable: false)
        : ranked;
  }

  /// מסננת רשימת תוצאות ומשאירה רק את הייחודיות על בסיס מפתח מורכב.
  List<ReferenceSearchResult> _dedupeRefs(List<ReferenceSearchResult> results) {
    final seen = <String>{}; // סט לשמירת מפתחות שכבר נראו
    final out = <ReferenceSearchResult>[];

    for (final r in results) {
      // יצירת מפתח ייחודי חכם שמורכב מ-3 חלקים:

      // 1. טקסט ההפניה לאחר נרמול
      final refKey = _normalize(r.reference);

      // 2. יעד ההפניה (קובץ ספציפי או שם ספר וסוג)
      final file = r.filePath.trim().toLowerCase();
      final title = r.title.trim().toLowerCase();
      final typ = r.isPdf ? 'pdf' : 'txt';
      final dest = file.isNotEmpty ? file : '$title|$typ';

      // 3. המיקום המדויק בתוך היעד
      final seg = _segNum(r.segment);

      // הרכבת המפתח הסופי
      final key = '$refKey|$dest|$seg';

      // הוסף לרשימת הפלט רק אם המפתח לא נראה בעבר
      if (seen.add(key)) {
        out.add(r);
      }
    }
    return out;
  }

  /// פונקציית עזר לנרמול טקסט: מורידה רווחים, הופכת לאותיות קטנות ומאחדת רווחים.
  String _normalize(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// פונקציית עזר להמרת 'segment' למספר שלם (int) בצורה בטוחה.
  int _segNum(dynamic s) {
    if (s is num) return s.round();
    return int.tryParse(s?.toString() ?? '') ?? 0;
  }

  String _normalizeForMatch(String input) {
    var cleaned = replaceParaphrases(input);
    cleaned = removeTeamim(removeVolwels(cleaned));
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s]'), ' ');
    cleaned = cleaned.toLowerCase();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _tokenize(String text) => text
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  List<ReferenceSearchResult> _filterAndRank(
    List<ReferenceSearchResult> results,
    List<String> queryTokens,
  ) {
    final entriesByBook = <String, List<_RefEntry>>{};

    for (int i = 0; i < results.length; i++) {
      final entry = _RefEntry.fromResult(results[i], i, _normalizeForMatch);
      if (entry == null) continue;
      entriesByBook.putIfAbsent(entry.bookKey, () => []).add(entry);
    }

    final matches = <_MatchInfo>[];
    for (final bookEntries in entriesByBook.values) {
      _annotateDepth(bookEntries);
      for (final entry in bookEntries) {
        final match = _matchEntry(entry, queryTokens);
        if (match != null) {
          matches.add(match);
        }
      }
    }

    matches.sort((a, b) {
      final levelCmp = a.level.compareTo(b.level);
      if (levelCmp != 0) return levelCmp;

      final bookCmp = _bookMatchRank(
        b.bookMatchType,
      ).compareTo(_bookMatchRank(a.bookMatchType));
      if (bookCmp != 0) return bookCmp;

      final headingCmp = b.headingTokensMatched.compareTo(
        a.headingTokensMatched,
      );
      if (headingCmp != 0) return headingCmp;

      return a.originalIndex.compareTo(b.originalIndex);
    });

    return matches.map((m) => m.entry.result).toList(growable: false);
  }

  void _annotateDepth(List<_RefEntry> entries) {
    final headingKeys = <String>{};
    for (final entry in entries) {
      if (entry.headingTokens.isEmpty) continue;
      headingKeys.add(entry.headingTokens.join(' '));
    }

    for (final entry in entries) {
      if (entry.headingTokens.isEmpty) {
        entry.depth = 1;
        entry.level2Tokens = const [];
        entry.level3Tokens = const [];
        continue;
      }

      int prefixLength = 0;
      for (int len = entry.headingTokens.length - 1; len >= 1; len--) {
        final prefix = entry.headingTokens.sublist(0, len).join(' ');
        if (headingKeys.contains(prefix)) {
          prefixLength = len;
          break;
        }
      }

      if (prefixLength > 0) {
        entry.depth = 3;
        entry.level2Tokens = entry.headingTokens.sublist(0, prefixLength);
        entry.level3Tokens = entry.headingTokens.sublist(
          prefixLength,
          entry.headingTokens.length,
        );
      } else {
        entry.depth = 2;
        entry.level2Tokens = entry.headingTokens;
        entry.level3Tokens = const [];
      }
    }
  }

  _MatchInfo? _matchEntry(_RefEntry entry, List<String> queryTokens) {
    final bookMatch = _matchBook(entry.bookTokens, queryTokens);
    if (bookMatch.type == _BookMatchType.none) {
      return null;
    }

    if (bookMatch.remainingTokens.isEmpty) {
      if (entry.depth == 1) {
        return _MatchInfo(
          entry: entry,
          bookMatchType: bookMatch.type,
          level: 1,
          headingTokensMatched: 0,
        );
      }
      return null;
    }

    if (entry.depth == 1) {
      return null;
    }

    final level2Match = _matchHeading(
      entry.level2Tokens,
      bookMatch.remainingTokens,
    );
    if (!level2Match.hasMatch) {
      return null;
    }

    if (level2Match.remainingTokens.isEmpty) {
      if (entry.depth == 2) {
        return _MatchInfo(
          entry: entry,
          bookMatchType: bookMatch.type,
          level: 2,
          headingTokensMatched: level2Match.matchedCount,
        );
      }
      return null;
    }

    if (entry.depth < 3) {
      return null;
    }

    final level3Match = _matchHeading(
      entry.level3Tokens,
      level2Match.remainingTokens,
    );
    if (!level3Match.hasMatch || level3Match.remainingTokens.isNotEmpty) {
      return null;
    }

    return _MatchInfo(
      entry: entry,
      bookMatchType: bookMatch.type,
      level: 3,
      headingTokensMatched: level2Match.matchedCount + level3Match.matchedCount,
    );
  }

  _BookMatchResult _matchBook(
    List<String> bookTokens,
    List<String> queryTokens,
  ) {
    final remaining = List<String>.from(queryTokens);
    int exactMatches = 0;

    for (final token in bookTokens) {
      final idx = remaining.indexOf(token);
      if (idx != -1) {
        exactMatches++;
        remaining.removeAt(idx);
      }
    }

    if (exactMatches == bookTokens.length && bookTokens.isNotEmpty) {
      return _BookMatchResult(
        type: _BookMatchType.full,
        remainingTokens: remaining,
      );
    }

    if (exactMatches > 0) {
      return _BookMatchResult(
        type: _BookMatchType.partial,
        remainingTokens: remaining,
      );
    }

    if (bookTokens.isNotEmpty) {
      final prefixIdx = remaining.indexWhere(
        (token) => token.length >= 2 && bookTokens.first.startsWith(token),
      );
      if (prefixIdx != -1) {
        remaining.removeAt(prefixIdx);
        return _BookMatchResult(
          type: _BookMatchType.prefix,
          remainingTokens: remaining,
        );
      }
    }

    return _BookMatchResult(
      type: _BookMatchType.none,
      remainingTokens: queryTokens,
    );
  }

  _HeadingMatchResult _matchHeading(
    List<String> headingTokens,
    List<String> queryTokens,
  ) {
    if (headingTokens.isEmpty) {
      return _HeadingMatchResult(false, 0, queryTokens);
    }

    final counts = <String, int>{};
    for (final token in headingTokens) {
      counts[token] = (counts[token] ?? 0) + 1;
    }

    final remaining = <String>[];
    int matched = 0;

    for (final token in queryTokens) {
      final current = counts[token];
      if (current != null && current > 0) {
        counts[token] = current - 1;
        matched++;
      } else {
        remaining.add(token);
      }
    }

    return _HeadingMatchResult(matched > 0, matched, remaining);
  }

  int _bookMatchRank(_BookMatchType type) {
    switch (type) {
      case _BookMatchType.full:
        return 3;
      case _BookMatchType.partial:
        return 2;
      case _BookMatchType.prefix:
        return 1;
      case _BookMatchType.none:
        return 0;
    }
  }
}

class _RefEntry {
  final ReferenceSearchResult result;
  final int originalIndex;
  final List<String> bookTokens;
  final List<String> headingTokens;
  final String bookKey;

  late int depth;
  late List<String> level2Tokens;
  late List<String> level3Tokens;

  _RefEntry({
    required this.result,
    required this.originalIndex,
    required this.bookTokens,
    required this.headingTokens,
    required this.bookKey,
  });

  static _RefEntry? fromResult(
    ReferenceSearchResult result,
    int index,
    String Function(String) normalizer,
  ) {
    final normalizedTitle = normalizer(result.title);
    final normalizedRef = normalizer(result.reference);

    if (normalizedTitle.isEmpty || normalizedRef.isEmpty) {
      return null;
    }

    final bookTokens = normalizedTitle
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final referenceTokens = normalizedRef
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);

    if (bookTokens.isEmpty || referenceTokens.length < bookTokens.length) {
      return null;
    }

    for (int i = 0; i < bookTokens.length; i++) {
      if (referenceTokens[i] != bookTokens[i]) {
        return null;
      }
    }

    final headingTokens = referenceTokens.sublist(bookTokens.length);

    return _RefEntry(
      result: result,
      originalIndex: index,
      bookTokens: bookTokens,
      headingTokens: headingTokens,
      bookKey: normalizedTitle,
    );
  }
}

class _MatchInfo {
  final _RefEntry entry;
  final _BookMatchType bookMatchType;
  final int level;
  final int headingTokensMatched;

  _MatchInfo({
    required this.entry,
    required this.bookMatchType,
    required this.level,
    required this.headingTokensMatched,
  });

  int get originalIndex => entry.originalIndex;
}

enum _BookMatchType { none, prefix, partial, full }

class _BookMatchResult {
  final _BookMatchType type;
  final List<String> remainingTokens;

  _BookMatchResult({required this.type, required this.remainingTokens});
}

class _HeadingMatchResult {
  final bool hasMatch;
  final int matchedCount;
  final List<String> remainingTokens;

  _HeadingMatchResult(this.hasMatch, this.matchedCount, this.remainingTokens);
}
