import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/tools/dictionary/repository/db_dictionary_book_source.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

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

/// מייצג ערך במילון לעזי רש"י (ספר "אוצר לעזי רש"י").
class LaazDictionaryEntry {
  const LaazDictionaryEntry({
    required this.entryNumber,
    required this.sourceReference,
    required this.lemma,
    required this.laazHebrew,
    required this.laazLatin,
    required this.meaning,
    this.note,
    this.english,
  });

  /// המספר הרץ של הערך בספר.
  final String entryNumber;

  /// המקור ברש"י (למשל "ברכות ט:" או "בראשית א,ב").
  final String sourceReference;

  /// מילת הערך מדברי רש"י.
  final String lemma;

  /// הלעז בתעתיק עברי, כולל גרשיים כפי שמודפס.
  final String laazHebrew;

  /// הלעז באותיות לטיניות (עשוי להיות ריק).
  final String laazLatin;

  /// הפירוש העברי (עשוי להיות ריק בערכים חריגים).
  final String meaning;

  /// הערת העורך, אם קיימת.
  final String? note;

  /// תרגום אנגלי, אם קיים.
  final String? english;

  static final RegExp _htmlTag = RegExp(r'<[^>]*>');
  static final RegExp _bold = RegExp(r'<b>(.*?)</b>', dotAll: true);
  static final RegExp _small = RegExp(r'<small>(.*?)</small>', dotAll: true);
  static final RegExp _ltrSpan = RegExp(
    r'<span[^>]*>(.*?)</span>',
    dotAll: true,
  );
  static final RegExp _latinLetter = RegExp(r'[a-zA-Z]');

  /// מפרק את כל שורות הספר לערכי מילון; שורות כותרת ושורות לא-תקינות מדולגות.
  static List<LaazDictionaryEntry> parseLines(List<String> lines) {
    return lines
        .map(parseLine)
        .whereType<LaazDictionaryEntry>()
        .toList(growable: false);
  }

  /// מפרק שורת ערך בודדת; מחזיר null לשורת כותרת או שורה שאינה ערך.
  static LaazDictionaryEntry? parseLine(String line) {
    // פענוח ישויות HTML לפני הפירוק, כדי שלא ידלפו לשדות או ישבשו את המפריד.
    final trimmed = line
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
    if (trimmed.isEmpty || trimmed.startsWith('<h')) return null;
    if (!trimmed.contains(' / ')) return null;

    final parts = trimmed.split(' / ');
    if (parts.length < 3) return null;

    final entryNumber = _stripTags(parts[0]);
    var sourceReference = parts[1].trim();
    if (sourceReference.startsWith('(') && sourceReference.endsWith(')')) {
      sourceReference = sourceReference
          .substring(1, sourceReference.length - 1)
          .trim();
    }

    final note = _matchGroup(_small, trimmed);
    final english = _cleanEnglish(_matchGroup(_ltrSpan, trimmed));

    final headField = _removeTrailingBlocks(parts[2]);
    final lemmaMatch = _bold.firstMatch(headField);
    if (lemmaMatch == null) return null;
    final lemma = _stripTags(lemmaMatch.group(1) ?? '');
    if (lemma.isEmpty) return null;
    final afterLemma = _stripTags(
      headField.replaceRange(lemmaMatch.start, lemmaMatch.end, ' '),
    );

    var laazHebrew = afterLemma;
    var laazLatin = '';
    var meaning = '';

    if (parts.length >= 5) {
      laazLatin = _stripTags(parts[3]);
      final meaningField = _removeTrailingBlocks(parts.sublist(4).join(' / '));
      meaning = _matchGroup(_bold, meaningField) ?? _stripTags(meaningField);
    } else if (parts.length == 4) {
      final lastField = _removeTrailingBlocks(parts[3]);
      final boldLast = _matchGroup(_bold, lastField) ?? _stripTags(lastField);
      if (_latinLetter.hasMatch(boldLast)) {
        // וריאנט שבו הלטינית מודגשת בשדה האחרון והפירוש נגרר אחרי התעתיק.
        laazLatin = boldLast;
        final split = _splitTranslitAndMeaning(afterLemma);
        laazHebrew = split.translit;
        meaning = split.meaning;
      } else {
        meaning = boldLast;
      }
    }

    return LaazDictionaryEntry(
      entryNumber: entryNumber,
      sourceReference: sourceReference,
      lemma: lemma,
      laazHebrew: laazHebrew,
      laazLatin: laazLatin,
      meaning: meaning,
      note: note,
      english: english,
    );
  }

  /// מפריד תעתיק מפירוש נגרר: מילות התעתיק מזוהות לפי גרשיים.
  static ({String translit, String meaning}) _splitTranslitAndMeaning(
    String text,
  ) {
    final tokens = text.split(RegExp(r'\s+'));
    var translitEnd = 0;
    while (translitEnd < tokens.length && tokens[translitEnd].contains('"')) {
      translitEnd++;
    }
    if (translitEnd == 0) translitEnd = 1;

    return (
      translit: tokens.take(translitEnd).join(' '),
      meaning: tokens.skip(translitEnd).join(' '),
    );
  }

  static String _removeTrailingBlocks(String text) {
    return text.replaceAll(_small, ' ').replaceAll(_ltrSpan, ' ');
  }

  static String? _matchGroup(RegExp pattern, String text) {
    final value = _stripTags(pattern.firstMatch(text)?.group(1) ?? '');
    return value.isEmpty ? null : value;
  }

  static String? _cleanEnglish(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceFirst('✭', '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _stripTags(String text) {
    return text
        .replaceAll(_htmlTag, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
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
    final expansionAtStart = RegExp(
      r'^\(=\s*([^)]+?)\)\s*',
    ).firstMatch(remaining);
    if (expansionAtStart != null) {
      expansion = expansionAtStart.group(1)?.trim();
      remaining = remaining.substring(expansionAtStart.end).trim();
    } else {
      final inlineExpansion = RegExp(
        r'\s+\(=\s*([^)]+?)\)\s*',
      ).firstMatch(remaining);
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
    Future<List<LaazDictionaryEntry>> Function()? loadLaazEntries,
  }) : _loadAcronyms = loadAcronyms ?? _defaultLoadAcronyms,
       _loadAramaicEntries = loadAramaicEntries ?? _defaultLoadAramaicEntries,
       _loadLaazEntries = loadLaazEntries ?? _defaultLoadLaazEntries;

  static final DictionaryLookupRepository instance =
      DictionaryLookupRepository();

  /// כותרת ספר לעזי רש"י ב-DB; הזיהוי תמיד לפי כותרת, לא לפי id.
  static const String laazBookTitle = 'אוצר לעזי רש"י';

  final Future<Map<String, List<String>>> Function() _loadAcronyms;
  final Future<List<AramaicDictionaryEntry>> Function() _loadAramaicEntries;
  final Future<List<LaazDictionaryEntry>> Function() _loadLaazEntries;

  Future<void>? _acronymsLoadFuture;
  Future<void>? _aramaicLoadFuture;
  Future<void>? _laazLoadFuture;
  bool _areAcronymsLoaded = false;
  bool _areAramaicLoaded = false;
  bool _areLaazLoaded = false;

  Map<String, List<String>> _acronymsByKey = <String, List<String>>{};
  Map<String, String> _originalAcronymByKey = <String, String>{};
  List<AramaicDictionaryEntry> _aramaicEntries = <AramaicDictionaryEntry>[];
  Set<String> _aramaicTerms = <String>{};
  List<LaazDictionaryEntry> _laazEntries = <LaazDictionaryEntry>[];
  Map<String, List<LaazDictionaryEntry>> _laazByTranslit =
      <String, List<LaazDictionaryEntry>>{};

  bool get isLoaded =>
      _areAcronymsLoaded && _areAramaicLoaded && _areLaazLoaded;
  bool get areAcronymsLoaded => _areAcronymsLoaded;
  bool get areAramaicLoaded => _areAramaicLoaded;
  bool get areLaazLoaded => _areLaazLoaded;

  /// טוען את כל המילונים פעם אחת ומשאיר אותם בזיכרון.
  Future<void> ensureLoaded() async {
    await Future.wait<void>([
      ensureAcronymsLoaded(),
      ensureAramaicLoaded(),
      ensureLaazLoaded(),
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

  /// טוען את מילון לעזי רש"י בלבד.
  Future<void> ensureLaazLoaded() async {
    if (_areLaazLoaded) return;

    final pendingFuture = _laazLoadFuture;
    if (pendingFuture != null) {
      await pendingFuture;
      return;
    }

    final loadFuture = _loadLaazInternal();
    _laazLoadFuture = loadFuture;

    try {
      await loadFuture;
      _areLaazLoaded = true;
    } catch (_) {
      _resetLaazCache();
      rethrow;
    } finally {
      if (identical(_laazLoadFuture, loadFuture)) {
        _laazLoadFuture = null;
      }
    }
  }

  /// מחזיר את כלל רשומות ראשי התיבות.
  Map<String, List<String>> getAllAcronyms() {
    return Map<String, List<String>>.unmodifiable(
      _acronymsByKey.map(
        (key, meanings) =>
            MapEntry(_originalAcronymByKey[key] ?? key, meanings),
      ),
    );
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

  static final RegExp _innerGershayim = RegExp(
    '[א-ת][֑-ׇ]*["״][א-ת]',
  );

  /// בודק אם הטקסט נראה כתעתיק לעז: גרשיים בין אותיות בתוך המילה.
  bool isLikelyLaazTranslit(String raw) {
    return _innerGershayim.hasMatch(raw.trim());
  }

  /// מחזיר את כל הפירושים לראשי תיבות אם קיימים.
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

  /// מחזיר את כל רשומות מילון לעזי רש"י.
  List<LaazDictionaryEntry> getAllLaazEntries() {
    return List<LaazDictionaryEntry>.unmodifiable(_laazEntries);
  }

  /// מחזיר התאמות מדויקות ללעז לפי התעתיק העברי, עמיד לחילופי כתיב בין דפוסים.
  List<LaazDictionaryEntry> findLaazMatches(String raw) {
    final key = _foldLaazTranslit(_normalizeAramaic(raw));
    if (key.isEmpty) return const <LaazDictionaryEntry>[];

    return _laazByTranslit[key] ?? const <LaazDictionaryEntry>[];
  }

  /// מחזיר את התאמות הלעז מקובצות: ערכים עם אותו תעתיק ואותו פירוש
  /// (ממקורות רש"י שונים) מאוחדים לקבוצה אחת, לפי סדר ההופעה בספר.
  List<List<LaazDictionaryEntry>> findLaazMatchGroups(String raw) {
    final groups = <String, List<LaazDictionaryEntry>>{};
    for (final entry in findLaazMatches(raw)) {
      final title = entry.laazHebrew.isNotEmpty
          ? entry.laazHebrew
          : entry.lemma;
      final description = entry.meaning.isNotEmpty
          ? entry.meaning
          : (entry.note ?? '');
      final key =
          '${_normalizeAramaic(title)}|${_normalizeAramaic(description)}';
      groups.putIfAbsent(key, () => <LaazDictionaryEntry>[]).add(entry);
    }
    return groups.values.toList(growable: false);
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

  Future<void> _loadLaazInternal() async {
    final laazEntries = await _loadLaazEntries();
    final byTranslit = <String, List<LaazDictionaryEntry>>{};

    for (final entry in laazEntries) {
      final translit = _foldLaazTranslit(_normalizeAramaic(entry.laazHebrew));
      if (translit.isNotEmpty) {
        byTranslit
            .putIfAbsent(translit, () => <LaazDictionaryEntry>[])
            .add(entry);
      }
    }

    _laazEntries = List<LaazDictionaryEntry>.unmodifiable(laazEntries);
    _laazByTranslit = byTranslit;
  }

  static Future<Map<String, List<String>>> _defaultLoadAcronyms() async {
    final String jsonString = await rootBundle.loadString(
      'assets/Acronyms.json',
    );
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
    final String jsonString = await rootBundle.loadString(
      'assets/dictionary.json',
    );
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

  static Future<List<LaazDictionaryEntry>> _defaultLoadLaazEntries() async {
    // קריאת ה-DB נשארת ב-main isolate (FFI); רק הפירוק עובר ל-compute.
    final lines = await loadDictionaryBookLines(laazBookTitle);
    if (lines.isEmpty) return const <LaazDictionaryEntry>[];
    return compute(LaazDictionaryEntry.parseLines, lines);
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

  static final RegExp _consonantBeforeVav = RegExp('[בי](?=ו)');

  /// מקפל חילופי כתיב בין דפוסים בתעתיקי לעז: העיצור שלפני ו' נכתב ב/ו/י
  /// (שבו"ן=שוו"ן=שיו"ן). ההחלפה משמרת אורך כדי לא למזג מילים שונות (שו"ן).
  static String _foldLaazTranslit(String normalized) {
    return normalized.replaceAll(_consonantBeforeVav, 'ו');
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

  void _resetLaazCache() {
    _laazEntries = <LaazDictionaryEntry>[];
    _laazByTranslit = <String, List<LaazDictionaryEntry>>{};
    _areLaazLoaded = false;
  }
}
