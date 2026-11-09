import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
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

/// רשומת קטלוג ראשי תיבות לחיפוש: התווית המקורית לתצוגה, לצד המפתח המנורמל
/// שכבר חושב פעם אחת בזמן הטעינה (ראו [DictionaryLookupRepository.getAcronymSearchCatalog]).
class AcronymCatalogEntry {
  const AcronymCatalogEntry({
    required this.displayAcronym,
    required this.normalizedKey,
    required this.meanings,
  });

  final String displayAcronym;
  final String normalizedKey;
  final List<String> meanings;
}

/// מייצג רשומה במילון ארמי-עברי.
class AramaicDictionaryEntry {
  const AramaicDictionaryEntry({
    required this.aramaic,
    required this.hebrew,
    this.dictionary = peshitaDictionary,
  });

  /// המילון הראשי: ערכיו קודמים לשאר המילונים בתוצאות ובדירוג.
  static const String peshitaDictionary = 'מילון פשיטא';

  final String aramaic;
  final String hebrew;

  /// שם המילון שממנו הערך, כפי שהוא מופיע בקובץ הנתונים.
  final String dictionary;
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
    this.sourceLineIndex = 0,
  });

  /// אינדקס השורה במקור (1-based) בספר לעזי רש"י שממנה נותח הערך.
  /// חובה לקישור קישורי-הלעז: parseLines מדלגת על כותרות, ולכן מיקום הערך
  /// ברשימה אינו שווה למספר השורה שאליה מפנה index1 בקישור.
  final int sourceLineIndex;

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
  static final RegExp _hebrewLetter = RegExp('[א-ת]');
  static final RegExp _joinedLatinAndHebrew = RegExp(
    r'^([^א-ת]*[a-zA-Z])([א-ת].*)$',
  );

  /// מפרק את כל שורות הספר לערכי מילון; שורות כותרת ושורות לא-תקינות מדולגות.
  /// כל ערך נושא את [sourceLineIndex] (1-based) של שורת המקור שלו — נדרש כדי
  /// לקשר לפי index1 שבקישורי הספר, שאינו זהה למיקום ברשימה המסוננת.
  static List<LaazDictionaryEntry> parseLines(List<String> lines) {
    final entries = <LaazDictionaryEntry>[];
    for (var i = 0; i < lines.length; i++) {
      final entry = parseLine(lines[i], sourceLineIndex: i + 1);
      if (entry != null) entries.add(entry);
    }
    return List<LaazDictionaryEntry>.unmodifiable(entries);
  }

  /// מפרק שורת ערך בודדת; מחזיר null לשורת כותרת או שורה שאינה ערך.
  static LaazDictionaryEntry? parseLine(
    String line, {
    int sourceLineIndex = 0,
  }) {
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
      final middleField = _stripTags(parts[3]);
      final meaningField = _removeTrailingBlocks(parts.sublist(4).join(' / '));
      final trailingField =
          _matchGroup(_bold, meaningField) ?? _stripTags(meaningField);
      final headIsLatin =
          _latinLetter.hasMatch(afterLemma) &&
          !_hebrewLetter.hasMatch(afterLemma);
      final middleHasHebrew = _hebrewLetter.hasMatch(middleField);
      final trailingIsLatin =
          _latinLetter.hasMatch(trailingField) &&
          !_hebrewLetter.hasMatch(trailingField);

      if (headIsLatin && middleHasHebrew) {
        laazHebrew = middleField;
        laazLatin = afterLemma;
        meaning = trailingField;
      } else if (middleHasHebrew &&
          (trailingField.isEmpty || trailingIsLatin)) {
        laazLatin = trailingField;
        meaning = middleField;
      } else {
        laazLatin = middleField;
        meaning = trailingField;
      }
    } else if (parts.length == 4) {
      final lastField = _removeTrailingBlocks(parts[3]);
      final boldLast = _matchGroup(_bold, lastField) ?? _stripTags(lastField);
      final joinedFields = _joinedLatinAndHebrew.firstMatch(boldLast);
      if (joinedFields != null) {
        laazLatin = joinedFields.group(1)?.trim() ?? '';
        meaning = joinedFields.group(2)?.trim() ?? '';
      } else if (_latinLetter.hasMatch(boldLast)) {
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
      sourceLineIndex: sourceLineIndex,
    );
  }

  /// מפריד תעתיק מפירוש נגרר: מילות התעתיק מזוהות לפי גרשיים.
  static ({String translit, String meaning}) _splitTranslitAndMeaning(
    String text,
  ) {
    final tokens = text.split(RegExp(r'\s+'));
    var translitEnd = 0;
    while (translitEnd < tokens.length &&
        (tokens[translitEnd].contains('"') ||
            tokens[translitEnd].contains('״'))) {
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
    String? hebrewText,
    this.expression,
    this.expansion,
  }) : hebrewText = hebrewText ?? mainText;

  final String mainText;

  /// התרגום לחיפוש, בלי הביטוי או ההרחבה הארמית.
  final String hebrewText;
  final String? expression;
  final String? expansion;

  /// כל חלקי הפירוש המוצגים, להעתקה (בלי סימוני הדגשה).
  String get text => AramaicDictionaryEntryPresentation.stripBold(
    [
      ?expression,
      if (mainText.isNotEmpty) mainText,
      if (expansion != null) '(=$expansion)',
    ].join(' '),
  );
}

/// מייצג ערך מלא במילון לאחר חלוקה לפירושים.
class AramaicDictionaryEntryPresentation {
  const AramaicDictionaryEntryPresentation({
    required this.meanings,
  });

  final List<ParsedAramaicMeaning> meanings;

  static final RegExp _alternativeSeparator = RegExp('[,;]');
  static final RegExp _quotes = RegExp("[\"'״׳]");
  static final RegExp _meaningSeparator = RegExp(r'(?<!\*)\*\*\*(?!\*)');
  static final RegExp _bullet = RegExp(r'^\*(?!\*) *', multiLine: true);
  static final RegExp _tripleQuoteBold = RegExp(r"'''(?!\s)(.+?)(?<!\s)'''");

  /// הדגשת `**טקסט**`; תוכן חייב להתחיל ולהסתיים בתו שאינו רווח, כדי שלא
  /// להתבלבל עם `***`, מפריד הפירושים.
  static final RegExp boldMarkup = RegExp(r'\*\*(?!\s)(.+?)(?<!\s)\*\*');

  static String stripBold(String text) =>
      text.replaceAllMapped(boldMarkup, (match) => match[1]!);

  /// סימוני ויקי גולמיים: `<br>` לשורה חדשה, `*` בתחילת שורה לנקודת רשימה,
  /// ו-`'''טקסט'''` להדגשה אחידה `**טקסט**`.
  static String _normalizeMarkup(String raw) {
    final lines = utils
        .stripHtmlPreservingBreaks(raw)
        .replaceAllMapped(_tripleQuoteBold, (match) => '**${match[1]}**')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.join('\n').replaceAll(_bullet, '• ');
  }

  /// בלי פירוש שכל חלקיו (מופרדים בפסיק) כבר הופיעו בפירוש קודם, כדי שערך
  /// שמוזג מכמה מילונים לא יחזור על עצמו ("ארץ, קרקע" ואחריו "קרקע").
  AramaicDictionaryEntryPresentation withoutRepeatedMeanings() {
    final seen = <String>{};
    final kept = <ParsedAramaicMeaning>[];
    for (final meaning in meanings) {
      final parts =
          AramaicDictionaryEntryPresentation.stripBold(meaning.mainText)
              .split(_alternativeSeparator)
              .map(
                (part) =>
                    utils.removeVolwels(part).replaceAll(_quotes, '').trim(),
              )
              .where((part) => part.isNotEmpty)
              .toList();
      final repeated =
          parts.isNotEmpty &&
          meaning.expansion == null &&
          parts.every(seen.contains);
      if (repeated) continue;

      seen.addAll(parts);
      kept.add(meaning);
    }
    return AramaicDictionaryEntryPresentation(meanings: kept);
  }

  static AramaicDictionaryEntryPresentation parse(String raw) {
    final parts = raw
        .split(_meaningSeparator)
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

  static ParsedAramaicMeaning _parseMeaning(String rawMeaning) {
    final raw = _normalizeMarkup(rawMeaning);
    final expressionMatch =
        RegExp(r'^\{([^{}]+)\}\s*').firstMatch(raw) ??
        RegExp(r'^(\S+)(?=\(=)').firstMatch(raw);
    final expression = expressionMatch?.group(1)?.trim();
    var remaining = expressionMatch == null
        ? raw.trim()
        : raw.substring(expressionMatch.end).trim();

    var hebrewText = remaining;
    String? expansion;
    final expansionAtStart = RegExp(
      r'^\(=\s*([^)]+?)\)\s*',
    ).firstMatch(remaining);
    if (expansionAtStart != null) {
      expansion = expansionAtStart.group(1)?.trim();
      remaining = remaining.substring(expansionAtStart.end).trim();
      // הרחבה בתחילת פירוש היא ארמית, אלא אם היא הפירוש היחיד.
      hebrewText = remaining.isEmpty ? expansion! : remaining;
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
      hebrewText: stripBold(hebrewText),
      expression: expression,
      expansion: expansion,
    );
  }
}

typedef AramaicIndex = ({
  List<AramaicDictionaryEntry> entries,
  Set<String> terms,
  List<({String normalized, List<String> words})> index,
});

/// Repository משותף לטעינה וחיפוש במילוני הכלים.
class DictionaryLookupRepository {
  DictionaryLookupRepository({
    this._loadAcronyms,
    Future<List<AramaicDictionaryEntry>> Function()? loadAramaicEntries,
    Future<List<LaazDictionaryEntry>> Function()? loadLaazEntries,
    Future<List<Link>> Function()? loadLaazLinks,
  }) : _loadAramaic = loadAramaicEntries == null
           ? _defaultLoadAramaicIndex
           : (() async => _buildAramaicIndex(await loadAramaicEntries())),
       _loadLaazEntries = loadLaazEntries ?? _defaultLoadLaazEntries,
       _loadLaazLinks = loadLaazLinks ?? _defaultLoadLaazLinks;

  static final DictionaryLookupRepository instance =
      DictionaryLookupRepository();

  /// כותרת ספר לעזי רש"י ב-DB; הזיהוי תמיד לפי כותרת, לא לפי id.
  static const String laazBookTitle = 'אוצר לעזי רש"י';

  final Future<Map<String, List<String>>> Function()? _loadAcronyms;
  final Future<AramaicIndex> Function() _loadAramaic;
  final Future<List<LaazDictionaryEntry>> Function() _loadLaazEntries;
  final Future<List<Link>> Function() _loadLaazLinks;

  late final _acronyms = _DictionaryLoad(
    _loadAcronymsInternal,
    _resetAcronymsCache,
  );
  late final _aramaic = _DictionaryLoad(
    _loadAramaicInternal,
    _resetAramaicCache,
  );
  late final _laaz = _DictionaryLoad(_loadLaazInternal, _resetLaazCache);
  late final _laazLinks = _DictionaryLoad(
    _loadLaazLinksInternal,
    _resetLaazLinksCache,
  );

  Map<String, List<String>> _acronymsByKey = <String, List<String>>{};
  Map<String, String> _originalAcronymByKey = <String, String>{};
  List<AramaicDictionaryEntry> _aramaicEntries = <AramaicDictionaryEntry>[];
  Set<String> _aramaicTerms = <String>{};
  List<String> _aramaicDictionaryNames = const <String>[];
  // מקביל ל-_aramaicEntries: הנרמול נעשה פעם אחת בטעינה ולא בכל תפריט הקשר.
  List<({String normalized, List<String> words})> _aramaicIndex = const [];
  List<LaazDictionaryEntry> _laazEntries = <LaazDictionaryEntry>[];

  /// כותרת ספר-רש"י -> אינדקס-שורה (1-based) -> ערכי הלעז המקושרים לאותה שורה.
  Map<String, Map<int, List<LaazDictionaryEntry>>> _laazByRashiLine =
      <String, Map<int, List<LaazDictionaryEntry>>>{};

  bool get areAcronymsLoaded => _acronyms.isLoaded;
  bool get areAramaicLoaded => _aramaic.isLoaded;
  bool get areLaazLinksLoaded => _laazLinks.isLoaded;

  /// טוען את כל המילונים פעם אחת ומשאיר אותם בזיכרון.
  Future<void> ensureLoaded() async {
    await Future.wait<void>([
      ensureAcronymsLoaded(),
      ensureAramaicLoaded(),
      ensureLaazLoaded(),
    ]);
  }

  /// טוען את מילון ראשי התיבות בלבד.
  Future<void> ensureAcronymsLoaded() => _acronyms.ensure();

  /// טוען את המילון הארמי-עברי בלבד.
  Future<void> ensureAramaicLoaded() => _aramaic.ensure();

  /// טוען את מילון לעזי רש"י בלבד.
  Future<void> ensureLaazLoaded() => _laaz.ensure();

  /// טוען את מפת קישורי הלעז (שורת-רש"י -> ערכי לעז) בלבד, פעם אחת.
  ///
  /// ספר-הלעז חסר במסד => מפה ריקה, לא חריגה.
  Future<void> ensureLaazLinksLoaded() => _laazLinks.ensure();

  /// מחזיר את ערכי הלעז המקושרים לשורת רש"י נתונה (O(1)); רשימה ריקה אם אין.
  ///
  /// [rashiBookTitle] כותרת ספר-הרש"י (למשל "רש"י על בראשית").
  /// [rashiLineIndex] אינדקס השורה (1-based) של הדיבור ברש"י.
  List<LaazDictionaryEntry> laazForRashiLine({
    required String rashiBookTitle,
    required int rashiLineIndex,
  }) {
    return _laazByRashiLine[rashiBookTitle]?[rashiLineIndex] ??
        const <LaazDictionaryEntry>[];
  }

  /// קטלוג לחיפוש עם תווית מקורית ומפתח מנורמל, ממוין לפי אורך התווית ואז
  /// לפי א"ב — שוברי השוויון של דירוג החיפוש במסך ראשי התיבות.
  List<AcronymCatalogEntry> getAcronymSearchCatalog() {
    final catalog = [
      for (final entry in _acronymsByKey.entries)
        AcronymCatalogEntry(
          displayAcronym: _originalAcronymByKey[entry.key] ?? entry.key,
          normalizedKey: entry.key,
          meanings: entry.value,
        ),
    ];
    catalog.sort((a, b) {
      final lengthCompare = a.displayAcronym.length.compareTo(
        b.displayAcronym.length,
      );
      if (lengthCompare != 0) return lengthCompare;
      return a.displayAcronym.compareTo(b.displayAcronym);
    });
    return List<AcronymCatalogEntry>.unmodifiable(catalog);
  }

  /// מנרמל שאילתת חיפוש לראשי תיבות, לשימוש חד-פעמי מחוץ ל-repository —
  /// במקום לתת לכל קריאה ל-[acronymMatchesQuery] לנרמל את אותה שאילתה מחדש.
  String normalizeAcronymQuery(String raw) => _normalizeAcronym(raw);

  /// מחזיר את כל רשומות המילון הארמי-עברי, מכל המילונים ובסדר הקובץ.
  List<AramaicDictionaryEntry> getAllAramaicEntries() {
    return List<AramaicDictionaryEntry>.unmodifiable(_aramaicEntries);
  }

  /// בודק אם הטקסט נראה כמו ראשי תיבות.
  bool isLikelyAcronym(String raw) => _acronymMarks.hasMatch(raw);

  // אותם סימנים ש-_normalizeAcronym ממיר.
  static final _acronymMarks = RegExp('["״\'׳’‘“”]');

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

  /// שמות כל המילונים הארמיים שנטענו, בסדר הקובץ ("פשיטא" ראשון).
  List<String> get aramaicDictionaryNames => _aramaicDictionaryNames;

  /// ממזג התאמות בעלות אותו מפתח (גם ממילונים שונים) לערך אחד, בסדר הופעתן.
  static List<AramaicDictionaryEntry> mergeAramaicMatches(
    List<AramaicDictionaryEntry> matches,
  ) {
    final groups = <String, List<AramaicDictionaryEntry>>{};
    for (final entry in matches) {
      (groups[_normalizeAramaic(entry.aramaic)] ??= []).add(entry);
    }

    return [
      for (final group in groups.values)
        if (group.length == 1)
          group.single
        else
          AramaicDictionaryEntry(
            aramaic: group.first.aramaic,
            hebrew: mergeAramaicMeanings(group.map((entry) => entry.hebrew)),
            dictionary: group.first.dictionary,
          ),
    ];
  }

  /// מחבר פירושים של אותו מפתח לערך אחד; חלק ("***") זהה, בלי ניקוד, מופיע פעם.
  static String mergeAramaicMeanings(Iterable<String> meanings) {
    final seen = <String>{};
    return [
      for (final meaning in meanings)
        for (final part in meaning.split('***'))
          if (part.trim().isNotEmpty &&
              seen.add(utils.removeVolwels(part.trim())))
            part.trim(),
    ].join(' *** ');
  }

  /// התאמות מדויקות וכל פירושי עד [maxContainingMatches] הצירופים הקצרים, בסדר המילון.
  /// נדרשת מילה שקיימת במילון; [dictionaries] בוחר מילונים, כברירת מחדל "פשיטא" בלבד.
  List<AramaicDictionaryEntry> findAramaicMatches(
    String raw, {
    int? maxContainingMatches,
    Set<String> dictionaries = const {AramaicDictionaryEntry.peshitaDictionary},
  }) {
    assert(maxContainingMatches == null || maxContainingMatches >= 0);
    final normalizedWord = _normalizeAramaic(raw);
    if (normalizedWord.isEmpty) return const <AramaicDictionaryEntry>[];
    if (!_aramaicTerms.contains(normalizedWord)) {
      return const <AramaicDictionaryEntry>[];
    }

    final exact = <AramaicDictionaryEntry>[];
    var containing = <int>[];

    for (var i = 0; i < _aramaicEntries.length; i++) {
      if (!dictionaries.contains(_aramaicEntries[i].dictionary)) continue;
      final indexed = _aramaicIndex[i];
      if (indexed.normalized == normalizedWord) {
        exact.add(_aramaicEntries[i]);
        continue;
      }

      if (indexed.words.contains(normalizedWord)) {
        containing.add(i);
      }
    }

    if (maxContainingMatches != null &&
        containing.length > maxContainingMatches) {
      final selectedKeys =
          (containing..sort((a, b) {
                final byLength = _aramaicIndex[a].words.length.compareTo(
                  _aramaicIndex[b].words.length,
                );
                return byLength != 0 ? byLength : a.compareTo(b);
              }))
              .map((i) => _aramaicIndex[i].normalized)
              .toSet()
              .take(maxContainingMatches)
              .toSet();
      containing =
          containing
              .where((i) => selectedKeys.contains(_aramaicIndex[i].normalized))
              .toList()
            ..sort();
    }

    return <AramaicDictionaryEntry>[
      ...exact,
      for (final index in containing) _aramaicEntries[index],
    ];
  }

  Future<void> _loadAcronymsInternal() async {
    final loadAcronyms = _loadAcronyms;
    final index = loadAcronyms == null
        ? await _defaultLoadAcronymIndex()
        : _buildAcronymIndex(await loadAcronyms());
    _acronymsByKey = index.byKey;
    _originalAcronymByKey = index.originalByKey;
  }

  static ({Map<String, List<String>> byKey, Map<String, String> originalByKey})
  _buildAcronymIndex(Map<String, List<String>> acronyms) {
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

    return (
      byKey: normalizedAcronyms.map(
        (key, meanings) => MapEntry(
          key,
          List<String>.unmodifiable(meanings.toSet().toList()),
        ),
      ),
      originalByKey: originalAcronyms,
    );
  }

  Future<void> _loadAramaicInternal() async {
    final loaded = await _loadAramaic();
    _aramaicEntries = loaded.entries;
    _aramaicTerms = loaded.terms;
    _aramaicDictionaryNames = List<String>.unmodifiable(
      loaded.entries.map((entry) => entry.dictionary).toSet(),
    );
    _aramaicIndex = loaded.index;
  }

  static AramaicIndex _buildAramaicIndex(
    List<AramaicDictionaryEntry> aramaicEntries,
  ) {
    final aramaicTerms = <String>{};
    final aramaicIndex = <({String normalized, List<String> words})>[];

    for (final entry in aramaicEntries) {
      final normalizedEntry = _normalizeAramaic(entry.aramaic);
      final words = _splitAramaicWords(normalizedEntry);
      aramaicIndex.add((
        normalized: normalizedEntry,
        words: List.unmodifiable(words),
      ));
      if (normalizedEntry.isEmpty) {
        continue;
      }

      aramaicTerms.add(normalizedEntry);
      aramaicTerms.addAll(words);
    }

    return (
      entries: List<AramaicDictionaryEntry>.unmodifiable(aramaicEntries),
      terms: Set<String>.unmodifiable(aramaicTerms),
      index: List.unmodifiable(aramaicIndex),
    );
  }

  Future<void> _loadLaazInternal() async {
    final laazEntries = await _loadLaazEntries();
    _laazEntries = List<LaazDictionaryEntry>.unmodifiable(laazEntries);
  }

  Future<void> _loadLaazLinksInternal() async {
    // חובה שהערכים ייטענו קודם — המפתוח מסתמך על sourceLineIndex שלהם.
    await ensureLaazLoaded();

    final entryBySourceLine = <int, LaazDictionaryEntry>{};
    for (final entry in _laazEntries) {
      if (entry.sourceLineIndex > 0) {
        entryBySourceLine[entry.sourceLineIndex] = entry;
      }
    }

    final links = await _loadLaazLinks();
    final byRashiLine = <String, Map<int, List<LaazDictionaryEntry>>>{};
    for (final link in links) {
      if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
      final entry = entryBySourceLine[link.index1];
      if (entry == null) continue;
      final rashiTitle = utils.getTitleFromPath(link.path2);
      (byRashiLine.putIfAbsent(
        rashiTitle,
        () => <int, List<LaazDictionaryEntry>>{},
      )[link.index2] ??= <LaazDictionaryEntry>[]).add(entry);
    }

    _laazByRashiLine = byRashiLine;
  }

  static Future<
    ({Map<String, List<String>> byKey, Map<String, String> originalByKey})
  >
  _defaultLoadAcronymIndex() async {
    final String jsonString = await rootBundle.loadString(
      'assets/Acronyms.json',
    );
    // נרמול 13 אלף המפתחות תוקע פריימים על ה-UI isolate, ולכן רץ יחד עם הפענוח.
    return compute(decodeAcronymIndex, jsonString);
  }

  @visibleForTesting
  static ({Map<String, List<String>> byKey, Map<String, String> originalByKey})
  decodeAcronymIndex(String jsonString) {
    final jsonData = _decodeJsonObject(jsonString);

    return _buildAcronymIndex(
      jsonData.map((key, value) {
        if (value is List) {
          return MapEntry(key, value.cast<String>());
        }

        return MapEntry(key, <String>[]);
      }),
    );
  }

  static Future<AramaicIndex> _defaultLoadAramaicIndex() async {
    final String jsonString = await rootBundle.loadString(
      'assets/dictionary.json',
    );
    // נרמול הערכים תוקע את ה-UI isolate בבחירה הראשונה, ולכן רץ יחד עם הפענוח.
    return compute(decodeAramaicIndex, jsonString);
  }

  @visibleForTesting
  static AramaicIndex decodeAramaicIndex(String jsonString) {
    final jsonData = _decodeJsonObject(jsonString);
    // "פשיטא" ראשון, כדי שבמפתח זהה הוא יקדם את שאר המילונים.
    final names = <String>[
      if (jsonData[AramaicDictionaryEntry.peshitaDictionary] is List)
        AramaicDictionaryEntry.peshitaDictionary,
      for (final name in jsonData.keys)
        if (name != AramaicDictionaryEntry.peshitaDictionary &&
            jsonData[name] is List)
          name,
    ];

    final parsed = <AramaicDictionaryEntry>[];
    for (final name in names) {
      for (final entry in (jsonData[name] as List).whereType<Map>()) {
        if (entry.isEmpty) continue;

        final aramaic = entry.keys.first as String;
        final hebrew = entry[aramaic].toString();
        if (_isPlaceholderEntry(aramaic, hebrew)) continue;

        parsed.add(
          AramaicDictionaryEntry(
            aramaic: aramaic,
            hebrew: hebrew,
            dictionary: name,
          ),
        );
      }
    }
    return _buildAramaicIndex(parsed);
  }

  static const Set<String> _placeholderMeanings = {'*', '(סימן)'};
  static final RegExp _hebrewLetter = RegExp('[א-ת]');

  /// ערכי מילוי ("*", "(סימן)") ושורות בלי אות עברית אינם פירוש ואינם נטענים.
  static bool _isPlaceholderEntry(String aramaic, String hebrew) {
    if (!_hebrewLetter.hasMatch(aramaic)) return true;

    return hebrew
        .split('***')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .every(
          (part) =>
              _placeholderMeanings.contains(part) ||
              !_hebrewLetter.hasMatch(part),
        );
  }

  static Future<List<LaazDictionaryEntry>> _defaultLoadLaazEntries() async {
    // השורות מפוענחות ב-DbReadWorker; כאן רק מפרקים אותן ב-compute.
    final lines = await loadDictionaryBookLines(laazBookTitle);
    if (lines.isEmpty) return const <LaazDictionaryEntry>[];
    return compute(LaazDictionaryEntry.parseLines, lines);
  }

  /// שולף את הקישורים היוצאים מספר-הלעז מהמסד הרשמי בלבד.
  /// ספר-הלעז חסר במסד => רשימה ריקה (התכונה נעדרת בשקט).
  static Future<List<Link>> _defaultLoadLaazLinks() async {
    final resolved = await BookDatabaseResolver.resolveBook(
      title: laazBookTitle,
      officialOnly: true,
    );
    if (resolved == null) return const <Link>[];

    return DatabaseLibraryProvider.instance.getAllLinksForBook(
      laazBookTitle,
      resolved.book.categoryId,
      resolved.book.fileType ?? 'txt',
    );
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

    return _normalizeCommon(compact);
  }

  static String _normalizeAramaic(String raw) {
    return _normalizeCommon(_trimDecorations(raw));
  }

  static String _normalizeCommon(String raw) {
    return utils
        .removeVolwels(raw)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('"', '')
        .replaceAll('״', '')
        .replaceAll("'", '')
        .replaceAll('׳', '');
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
  }

  void _resetAramaicCache() {
    _aramaicEntries = <AramaicDictionaryEntry>[];
    _aramaicTerms = <String>{};
    _aramaicDictionaryNames = const <String>[];
    _aramaicIndex = const [];
  }

  void _resetLaazCache() {
    _laazEntries = <LaazDictionaryEntry>[];
  }

  void _resetLaazLinksCache() {
    _laazByRashiLine = <String, Map<int, List<LaazDictionaryEntry>>>{};
  }
}

/// טעינה חד-פעמית של מילון: קריאות מקבילות ממתינות לאותה טעינה, וטעינה
/// שנכשלה מאפסת את המילון ומאפשרת לנסות שוב.
class _DictionaryLoad {
  _DictionaryLoad(this._load, this._reset);

  final Future<void> Function() _load;
  final void Function() _reset;
  Future<void>? _pending;
  bool isLoaded = false;

  Future<void> ensure() async {
    if (isLoaded) return;
    final pending = _pending;
    if (pending != null) return pending;

    final load = _load();
    _pending = load;
    try {
      await load;
      isLoaded = true;
    } catch (_) {
      _reset();
      rethrow;
    } finally {
      if (identical(_pending, load)) _pending = null;
    }
  }
}
