import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// מייצג התאמה במילון ראשי התיבות.
class AcronymDictionaryEntry {
  const AcronymDictionaryEntry({
    required this.acronym,
    required this.meanings,
  });

  final String acronym;
  final List<String> meanings;
}

/// מייצג רשומה במילון ארמי-עברי.
class AramaicDictionaryEntry {
  const AramaicDictionaryEntry({
    required this.aramaic,
    required this.hebrew,
  });

  final String aramaic;
  final String hebrew;
}

/// מייצג פירוש בודד לאחר פענוח סימוני העיצוב של המילון.
class ParsedAramaicMeaning {
  const ParsedAramaicMeaning({
    required this.mainText,
    this.expression,
    this.expansion,
  });

  final String mainText;
  final String? expression;
  final String? expansion;
}

/// מייצג ערך מלא במילון לאחר חלוקה לפירושים.
class AramaicDictionaryEntryPresentation {
  const AramaicDictionaryEntryPresentation({
    required this.meanings,
  });

  final List<ParsedAramaicMeaning> meanings;

  static AramaicDictionaryEntryPresentation parse(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s*\*\*\*\s*'), '***').trim();
    final parts = normalized
        .split('***')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map(_parseMeaning)
        .toList();

    if (parts.isEmpty) {
      return const AramaicDictionaryEntryPresentation(
        meanings: <ParsedAramaicMeaning>[
          ParsedAramaicMeaning(mainText: ''),
        ],
      );
    }

    return AramaicDictionaryEntryPresentation(meanings: parts);
  }

  static ParsedAramaicMeaning _parseMeaning(String raw) {
    final expressionMatch = RegExp(r'^\{([^{}]+)\}\s*').firstMatch(raw);
    final expression = expressionMatch?.group(1)?.trim();
    var remaining = expressionMatch == null
        ? raw.trim()
        : raw.substring(expressionMatch.end).trim();

    String? expansion;
    final expansionAtStart =
        RegExp(r'^\(=\s*([^)]+?)\)\s*').firstMatch(remaining);
    if (expansionAtStart != null) {
      expansion = expansionAtStart.group(1)?.trim();
      remaining = remaining.substring(expansionAtStart.end).trim();
    } else {
      final inlineExpansion =
          RegExp(r'\s+\(=\s*([^)]+?)\)\s*').firstMatch(remaining);
      if (inlineExpansion != null) {
        expansion = inlineExpansion.group(1)?.trim();
        final before = remaining.substring(0, inlineExpansion.start).trim();
        final after = remaining.substring(inlineExpansion.end).trim();
        remaining = [before, after].where((part) => part.isNotEmpty).join(' ');
      }
    }

    return ParsedAramaicMeaning(
      mainText: remaining,
      expression: expression,
      expansion: expansion,
    );
  }
}

/// Repository משותף לטעינה וחיפוש במילוני הכלים.
class DictionaryLookupRepository {
  DictionaryLookupRepository({
    Future<Map<String, List<String>>> Function()? loadAcronyms,
    Future<List<AramaicDictionaryEntry>> Function()? loadAramaicEntries,
  })  : _loadAcronyms = loadAcronyms ?? _defaultLoadAcronyms,
        _loadAramaicEntries = loadAramaicEntries ?? _defaultLoadAramaicEntries;

  static final DictionaryLookupRepository instance =
      DictionaryLookupRepository();

  final Future<Map<String, List<String>>> Function() _loadAcronyms;
  final Future<List<AramaicDictionaryEntry>> Function() _loadAramaicEntries;

  Future<void>? _acronymsLoadFuture;
  Future<void>? _aramaicLoadFuture;
  bool _areAcronymsLoaded = false;
  bool _areAramaicLoaded = false;

  Map<String, List<String>> _acronymsByKey = <String, List<String>>{};
  Map<String, String> _originalAcronymByKey = <String, String>{};
  List<AramaicDictionaryEntry> _aramaicEntries = <AramaicDictionaryEntry>[];
  Set<String> _aramaicTerms = <String>{};

  bool get isLoaded => _areAcronymsLoaded && _areAramaicLoaded;
  bool get areAcronymsLoaded => _areAcronymsLoaded;
  bool get areAramaicLoaded => _areAramaicLoaded;

  /// טוען את שני המילונים פעם אחת ומשאיר אותם בזיכרון.
  Future<void> ensureLoaded() async {
    await Future.wait<void>([
      ensureAcronymsLoaded(),
      ensureAramaicLoaded(),
    ]);
  }

  /// טוען את מילון ראשי התיבות בלבד.
  Future<void> ensureAcronymsLoaded() async {
    if (_areAcronymsLoaded) return;

    final pendingFuture = _acronymsLoadFuture;
    if (pendingFuture != null) {
      await pendingFuture;
      return;
    }

    final loadFuture = _loadAcronymsInternal();
    _acronymsLoadFuture = loadFuture;

    try {
      await loadFuture;
      _areAcronymsLoaded = true;
    } catch (_) {
      _resetAcronymsCache();
      rethrow;
    } finally {
      if (identical(_acronymsLoadFuture, loadFuture)) {
        _acronymsLoadFuture = null;
      }
    }
  }

  /// טוען את המילון הארמי-עברי בלבד.
  Future<void> ensureAramaicLoaded() async {
    if (_areAramaicLoaded) return;

    final pendingFuture = _aramaicLoadFuture;
    if (pendingFuture != null) {
      await pendingFuture;
      return;
    }

    final loadFuture = _loadAramaicInternal();
    _aramaicLoadFuture = loadFuture;

    try {
      await loadFuture;
      _areAramaicLoaded = true;
    } catch (_) {
      _resetAramaicCache();
      rethrow;
    } finally {
      if (identical(_aramaicLoadFuture, loadFuture)) {
        _aramaicLoadFuture = null;
      }
    }
  }

  /// מחזיר את כלל רשומות ראשי התיבות.
  Map<String, List<String>> getAllAcronyms() {
    return Map<String, List<String>>.unmodifiable(_acronymsByKey.map(
      (key, meanings) => MapEntry(_originalAcronymByKey[key] ?? key, meanings),
    ));
  }

  /// מחזיר את כל רשומות המילון הארמי-עברי.
  List<AramaicDictionaryEntry> getAllAramaicEntries() {
    return List<AramaicDictionaryEntry>.unmodifiable(_aramaicEntries);
  }

  /// בודק אם הטקסט נראה כמו ראשי תיבות.
  bool isLikelyAcronym(String raw) {
    final trimmed = raw.trim();
    return trimmed.contains('"') ||
        trimmed.contains('״') ||
        trimmed.contains("'") ||
        trimmed.contains('׳');
  }

  /// מחזיר את כל הפירושים לראשי תיבות אם קיימים.
  /// בודק אם ל-[raw] יש אפשרות זמינה בתפריט ההקשר של המילון.
  ///
  /// מחזיר `true` אם קיימת פתיחת ראשי תיבות או התאמה למילון הארמי.
  Future<bool> hasContextMenuEntries(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final shouldCheckAcronyms = isLikelyAcronym(trimmed);
    if (shouldCheckAcronyms) {
      await ensureAcronymsLoaded();
      if (findAcronymMatches(trimmed).isNotEmpty) {
        return true;
      }
    }

    await ensureAramaicLoaded();
    return findAramaicMatches(trimmed).isNotEmpty;
  }

  AcronymDictionaryEntry? findAcronym(String raw) {
    final normalized = _normalizeAcronym(raw);
    if (normalized.isEmpty) return null;

    return _buildAcronymEntry(normalized);
  }

  /// מחזיר התאמות לראשי תיבות, כולל הרחבה לקיצורים שנכתבו בגרש בודד.
  List<AcronymDictionaryEntry> findAcronymMatches(String raw) {
    final normalized = _normalizeAcronym(raw);
    if (normalized.isEmpty) {
      return const <AcronymDictionaryEntry>[];
    }

    final exactMatch = _buildAcronymEntry(normalized);
    if (exactMatch != null) {
      return <AcronymDictionaryEntry>[exactMatch];
    }

    if (normalized.length < 2) {
      return const <AcronymDictionaryEntry>[];
    }

    return _acronymsByKey.keys
        .where((key) => key.startsWith(normalized))
        .map(_buildAcronymEntry)
        .whereType<AcronymDictionaryEntry>()
        .toList()
      ..sort((a, b) {
        final lengthCompare = a.acronym.length.compareTo(b.acronym.length);
        if (lengthCompare != 0) {
          return lengthCompare;
        }

        return a.acronym.compareTo(b.acronym);
      });
  }

  /// בודק אם מפתח ראשי תיבות תואם לשאילתת חיפוש לאחר נרמול גרשיים.
  bool acronymMatchesQuery({
    required String acronym,
    required String query,
  }) {
    final normalizedQuery = _normalizeAcronym(query);
    if (normalizedQuery.isEmpty) {
      return false;
    }

    return _normalizeAcronym(acronym).contains(normalizedQuery);
  }

  /// מחזיר את כל הביטויים הארמיים המכילים את המילה שנבחרה,
  /// אבל רק אם קיימת התאמה מילונית מדויקת למילה עצמה.
  List<AramaicDictionaryEntry> findAramaicMatches(String raw) {
    final normalizedWord = _normalizeAramaic(raw);
    if (normalizedWord.isEmpty) return const <AramaicDictionaryEntry>[];
    if (!_aramaicTerms.contains(normalizedWord)) {
      return const <AramaicDictionaryEntry>[];
    }

    final exact = <AramaicDictionaryEntry>[];
    final containsAsWord = <AramaicDictionaryEntry>[];

    for (final entry in _aramaicEntries) {
      final normalizedEntry = _normalizeAramaic(entry.aramaic);
      if (normalizedEntry == normalizedWord) {
        exact.add(entry);
        continue;
      }

      final words = _splitAramaicWords(normalizedEntry);
      if (words.contains(normalizedWord)) {
        containsAsWord.add(entry);
      }
    }

    return <AramaicDictionaryEntry>[
      ...exact,
      ...containsAsWord,
    ];
  }

  Future<void> _loadAcronymsInternal() async {
    final acronyms = await _loadAcronyms();

    final normalizedAcronyms = <String, List<String>>{};
    final originalAcronyms = <String, String>{};

    acronyms.forEach((acronym, meanings) {
      final normalized = _normalizeAcronym(acronym);
      if (normalized.isEmpty || meanings.isEmpty) return;

      normalizedAcronyms.update(
        normalized,
        (existingMeanings) => <String>[
          ...existingMeanings,
          ...meanings,
        ],
        ifAbsent: () => List<String>.from(meanings),
      );
      originalAcronyms.putIfAbsent(normalized, () => acronym);
    });

    _acronymsByKey = normalizedAcronyms.map(
      (key, meanings) => MapEntry(
        key,
        List<String>.unmodifiable(meanings.toSet().toList()),
      ),
    );
    _originalAcronymByKey = originalAcronyms;
  }

  Future<void> _loadAramaicInternal() async {
    final aramaicEntries = await _loadAramaicEntries();
    final aramaicTerms = <String>{};

    for (final entry in aramaicEntries) {
      final normalizedEntry = _normalizeAramaic(entry.aramaic);
      if (normalizedEntry.isEmpty) {
        continue;
      }

      aramaicTerms.add(normalizedEntry);
      aramaicTerms.addAll(_splitAramaicWords(normalizedEntry));
    }

    _aramaicEntries = List<AramaicDictionaryEntry>.unmodifiable(aramaicEntries);
    _aramaicTerms = Set<String>.unmodifiable(aramaicTerms);
  }

  static Future<Map<String, List<String>>> _defaultLoadAcronyms() async {
    final String jsonString =
        await rootBundle.loadString('assets/Acronyms.json');
    final jsonData = await compute(_decodeJsonObject, jsonString);

    return jsonData.map((key, value) {
      if (value is List) {
        return MapEntry(key, value.cast<String>());
      }

      return MapEntry(key, <String>[]);
    });
  }

  static Future<List<AramaicDictionaryEntry>>
      _defaultLoadAramaicEntries() async {
    final String jsonString =
        await rootBundle.loadString('assets/dictionary.json');
    final jsonData = await compute(_decodeJsonObject, jsonString);
    final List<dynamic> entries = jsonData['מילון פשיטא'] ?? <dynamic>[];

    return entries
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          if (entry.isEmpty) {
            return null;
          }

          final aramaic = entry.keys.first;

          return AramaicDictionaryEntry(
            aramaic: aramaic,
            hebrew: entry[aramaic].toString(),
          );
        })
        .whereType<AramaicDictionaryEntry>()
        .toList();
  }

  static Map<String, dynamic> _decodeJsonObject(String jsonString) {
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  static String _normalizeAcronym(String raw) {
    final compact = _trimDecorations(raw)
        .replaceAll('״', '"')
        .replaceAll('׳', "'")
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"');

    return _normalizeCommon(compact, keepQuotes: false);
  }

  static String _normalizeAramaic(String raw) {
    return _normalizeCommon(_trimDecorations(raw), keepQuotes: false);
  }

  static String _normalizeCommon(String raw, {required bool keepQuotes}) {
    var normalized = utils.removeVolwels(raw).trim();
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');

    if (!keepQuotes) {
      normalized = normalized
          .replaceAll('"', '')
          .replaceAll('״', '')
          .replaceAll("'", '')
          .replaceAll('׳', '');
    }

    return normalized;
  }

  static String _trimDecorations(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp("^[^א-ת\"״׳']+"), '')
        .replaceAll(RegExp("[^א-ת\"״׳'\\s]+\$"), '');
  }

  static Set<String> _splitAramaicWords(String normalizedEntry) {
    return normalizedEntry
        .split(RegExp(r'[\s\-]+'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toSet();
  }

  AcronymDictionaryEntry? _buildAcronymEntry(String normalized) {
    final meanings = _acronymsByKey[normalized];
    if (meanings == null || meanings.isEmpty) {
      return null;
    }

    return AcronymDictionaryEntry(
      acronym: _originalAcronymByKey[normalized] ?? normalized,
      meanings: meanings,
    );
  }

  void _resetAcronymsCache() {
    _acronymsByKey = <String, List<String>>{};
    _originalAcronymByKey = <String, String>{};
    _areAcronymsLoaded = false;
  }

  void _resetAramaicCache() {
    _aramaicEntries = <AramaicDictionaryEntry>[];
    _aramaicTerms = <String>{};
    _areAramaicLoaded = false;
  }
}
