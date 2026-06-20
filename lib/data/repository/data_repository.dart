import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// DataRepository acts as a centralized data access layer that coordinates between different
/// data providers (file system, Hive storage, and Tantivy search engine).
///
/// This repository implements the Repository pattern to abstract the data source
/// implementation details from the business logic. It provides a clean API for
/// accessing and manipulating application data from various sources.
class DataRepository {
  /// Handles file system operations like reading book texts and metadata
  final FileSystemData _fileSystemData = FileSystemData.instance;

  /// Singleton instance of the DataRepository
  static final DataRepository _singleton = DataRepository();

  /// Provides access to the singleton instance
  static DataRepository get instance => _singleton;

  Future<Library>? _libraryFuture;
  Future<Library> get library => _libraryFuture ??= _getLibrary();
  set library(Future<Library> value) => _libraryFuture = value;

  // Lazy-loaded: only fetched when user actually searches for external books.
  // Previously these ran getAllBooksWithRelations() eagerly at startup,
  // competing with library loading for DB I/O.
  Future<List<Book>>? _hebrewBooksFuture;
  Future<List<Book>>? _localHebrewBooksFuture;
  Future<List<ExternalLibraryBook>>? _otzarBooksFuture;
  Future<List<Book>> get hebrewBooks => _hebrewBooksFuture ??= getHebrewBooks();

  /// ספרי היברובוקס שקיים להם PDF מקומי (כ-[PdfBook]). נחשבים מקומיים
  /// ומוצגים בחיפוש גם כשהצגת ספרים חיצוניים כבויה.
  Future<List<Book>> get localHebrewBooks =>
      _localHebrewBooksFuture ??= FileSystemData.getLocalHebrewBooks();
  Future<List<ExternalLibraryBook>> get otzarBooks =>
      _otzarBooksFuture ??= getOtzarBooks();

  /// Invalidates cached external books so they are re-fetched on next access.
  /// Call this when the library is refreshed.
  void invalidateExternalBooksCache() {
    _hebrewBooksFuture = null;
    _localHebrewBooksFuture = null;
    _otzarBooksFuture = null;
  }

  DataRepository();

  /// Retrieves the complete library metadata including all available books
  ///
  /// Returns a [Future] that completes with a [Library] object containing
  /// the full library structure and metadata
  Future<Library> _getLibrary() async {
    return _fileSystemData.getLibrary();
  }

  /// Retrieves the list of books from the Otzar HaHochma project
  ///
  /// Returns a [Future] that completes with a list of [ExternalLibraryBook] objects
  /// representing books from the Otzar HaHochma collection
  Future<List<ExternalLibraryBook>> getOtzarBooks() {
    return FileSystemData.getOtzarBooks();
  }

  /// Retrieves the list of books from the Hebrew Books project
  ///
  /// Returns a [Future] that completes with a list of [Book] objects
  /// representing books from the Hebrew Books collection
  Future<List<Book>> getHebrewBooks() {
    return FileSystemData.getHebrewBooks();
  }

  /// Retrieves the full text content of a specific book
  ///
  /// Parameters:
  ///   - [title]: The title of the book to retrieve
  ///
  /// Returns a [Future] that completes with the book's text content as a [String]
  Future<String> getBookText(String title,
      {int? categoryId, String? fileType}) async {
    return _fileSystemData.getBookText(title,
        categoryId: categoryId, fileType: fileType);
  }

  /// Retrieves the table of contents for a specific book
  ///
  /// Parameters:
  ///   - [title]: The title of the book whose TOC should be retrieved
  ///
  /// Returns a [Future] that completes with a list of [TocEntry] objects
  /// representing the book's table of contents structure
  Future<List<TocEntry>> getBookToc(String title,
      {int? categoryId, String? fileType}) async {
    return _fileSystemData.getBookToc(title,
        categoryId: categoryId, fileType: fileType);
  }

  /// Searches for references by relevance to a given reference string
  ///
  /// Parameters:
  ///   - [ref]: The reference string to search for
  ///   - [limit]: Maximum number of results to return (defaults to 10)
  ///
  /// Returns a [Future] that completes with a list of [Ref] objects sorted by relevance

  /// Adds text content from the library to the Tantivy search index
  ///
  /// Parameters:
  ///   - [library]: The library containing books to index
  ///
  /// This method now uses the IndexingBloc to handle the indexing process
  Future<void> addAllTextsToTantivy(
    Library library,
  ) async {
    // Create an instance of IndexingBloc
    final indexingBloc = IndexingBloc.create();

    // Start the indexing process
    indexingBloc.add(StartIndexing(library));
  }

  /// Searches for books based on query text and optional filters
  ///
  /// Parameters:
  ///   - [query]: The search text to match against book titles
  ///   - [category]: Optional category to filter results
  ///   - [topics]: Optional list of topics to filter results
  ///   - [includeOtzar]: Whether to include Otzar HaChochma books
  ///   - [includeHebrewBooks]: Whether to include HebrewBooks.org books
  ///
  /// Returns a [Future] that completes with a list of [Book] objects matching the criteria
  Future<List<Book>> findBooks(
    String query,
    Category? category, {
    List<String>? topics,
    bool includeOtzar = false,
    bool includeHebrewBooks = false,
    bool sortByRatio = true,
  }) async {
    final normalizedQuery = _normalizeForSearch(query);
    final queryWords = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (queryWords.isEmpty) {
      return [];
    }

    final allBooks = <Book>[
      ...(category?.getAllBooks() ?? (await library).getAllBooks()),
    ];

    if (includeOtzar) {
      allBooks.addAll(await otzarBooks);
    }
    if (includeHebrewBooks) {
      allBooks.addAll(await hebrewBooks);
    } else {
      // ספרי היברובוקס שיש להם PDF מקומי הם ספרים שכבר נמצאים במחשב,
      // ולכן מוצגים תמיד — גם כשהצגת ספרים חיצוניים כבויה.
      allBooks.addAll(await localHebrewBooks);
    }

    // no-op אם הקאשים כבר חוממו בעליית האפליקציה
    await AcronymsCache.instance.warmUp();
    await GenerationCache.instance.warmUp();

    final searchEntries = <BookSearchEntry>[
      for (var i = 0; i < allBooks.length; i++)
        BookSearchEntry(
          index: i,
          title: allBooks[i].title,
          author: allBooks[i].author ?? '',
          topics: allBooks[i].topics,
          acronyms: allBooks[i].id == null
              ? const []
              : AcronymsCache.instance.getAcronymsForBook(allBooks[i].id!) ??
                  const [],
          eraOrder: GenerationCache.instance.getOrderForBook(allBooks[i].id),
        ),
    ];

    final matchingIndices = await Isolate.run(
      () => filterBookSearchEntries(
        entries: searchEntries,
        queryWords: queryWords,
        topics: topics ?? const <String>[],
        sortByRatio: sortByRatio,
        normalizedQuery: normalizedQuery,
      ),
    );

    return [
      for (final index in matchingIndices) allBooks[index],
    ];
  }

  String _normalizeForSearch(String input) {
    var cleaned = removeTeamim(removeVolwels(input));
    cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
    cleaned = cleaned.replaceAll('\u05F4', '').replaceAll('\u05F3', '');
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s]'), ' ');
    return cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

@visibleForTesting
class BookSearchEntry {
  final int index;
  final String title;
  final String author;
  final String topics;

  /// כינויים מנורמלים מראש מטבלת book_acronym (ראה [AcronymsCache]).
  final List<String> acronyms;

  /// סדר הדור של הספר (נמוך = מוקדם). ראה [GenerationCache]; ברירת מחדל = סוף.
  final int eraOrder;

  const BookSearchEntry({
    required this.index,
    required this.title,
    required this.author,
    required this.topics,
    this.acronyms = const [],
    this.eraOrder = 5,
  });
}

@visibleForTesting
List<int> filterBookSearchEntries({
  required List<BookSearchEntry> entries,
  required List<String> queryWords,
  required List<String> topics,
  required bool sortByRatio,
  required String normalizedQuery,
}) {
  final preparedEntries = entries.map((entry) {
    final normalizedTitle = _normalizeBookSearchText(entry.title);
    final normalizedAuthor = _normalizeBookSearchText(entry.author);
    final topics = entry.topics
        .split(',')
        .map((topic) => topic.trim())
        .where((topic) => topic.isNotEmpty)
        .toSet();

    // כל המילים שמולן נבדקת השאילתה — כותרת, מחבר וכינויים יחד
    final searchWords = <String>{
      ...normalizedTitle.split(' '),
      ...normalizedAuthor.split(' '),
      for (final acronym in entry.acronyms) ...acronym.split(' '),
    }..remove('');

    return _PreparedBookSearchEntry(
      index: entry.index,
      normalizedTitle: normalizedTitle,
      searchWords: searchWords,
      topics: topics,
      acronyms: entry.acronyms,
      eraOrder: entry.eraOrder,
    );
  });

  // מטמון לזוגות (מילת שאילתה, מילת טקסט) — מילים נפוצות ('מסכת', 'על')
  // חוזרות באלפי ספרים ומחושבות פעם אחת בלבד.
  final pairMemo = {
    for (final word in queryWords) word: <String, bool>{},
  };
  bool wordMatchesEntry(String queryWord, Set<String> searchWords) {
    final memo = pairMemo[queryWord]!;
    for (final textWord in searchWords) {
      if (memo[textWord] ??= _wordPairMatches(queryWord, textWord)) {
        return true;
      }
    }
    return false;
  }

  final filtered = preparedEntries.where((entry) {
    final matchesQuery = queryWords.every(
      (word) => wordMatchesEntry(word, entry.searchWords),
    );
    final matchesTopics =
        topics.isEmpty || topics.every((topic) => entry.topics.contains(topic));

    return matchesQuery && matchesTopics;
  }).toList();

  if (sortByRatio) {
    final scored = [
      for (final entry in filtered)
        _ScoredBookSearchEntry(
          index: entry.index,
          // שכבות עדיפות שאינן חופפות (כותרת מדויקת > מכילה > כינוי > fuzzy).
          // התאמה מדויקת קודמת לדור כדי שספר יסוד נטול-דור ('קידושין') לא ייקבר
          // מתחת לפירושים מתוארכים. בתוך כל שכבה: דור ואז ratio.
          tier: entry.normalizedTitle == normalizedQuery
              ? 3
              : entry.normalizedTitle.contains(normalizedQuery)
                  ? 2
                  : entry.acronyms.any((a) => a.contains(normalizedQuery))
                      ? 1
                      : 0,
          eraOrder: entry.eraOrder,
          ratio: ratio(normalizedQuery, entry.normalizedTitle),
        ),
    ]..sort((a, b) {
        if (a.tier != b.tier) return b.tier.compareTo(a.tier);
        if (a.eraOrder != b.eraOrder) return a.eraOrder.compareTo(b.eraOrder);
        if (a.ratio != b.ratio) return b.ratio.compareTo(a.ratio);
        return a.index.compareTo(b.index);
      });

    return [
      for (final entry in scored) entry.index,
    ];
  }

  return [
    for (final entry in filtered) entry.index,
  ];
}

class _PreparedBookSearchEntry {
  final int index;
  final String normalizedTitle;

  /// כל המילים המנורמלות של הכותרת, המחבר והכינויים — מאוחדות לבדיקה אחת.
  final Set<String> searchWords;
  final Set<String> topics;
  final List<String> acronyms;
  final int eraOrder;

  const _PreparedBookSearchEntry({
    required this.index,
    required this.normalizedTitle,
    required this.searchWords,
    required this.topics,
    required this.acronyms,
    required this.eraOrder,
  });
}

class _ScoredBookSearchEntry {
  final int index;
  final int tier;
  final int eraOrder;
  final int ratio;

  const _ScoredBookSearchEntry({
    required this.index,
    required this.tier,
    required this.eraOrder,
    required this.ratio,
  });
}

// Damerau-Levenshtein (OSA) הבודק רק האם המרחק ≤ k, עם שורות מתגלגלות
// ויציאה מוקדמת. הנרמול משאיר תווי BMP בלבד, לכן codeUnit == תו.
bool _editDistanceAtMost(String a, String b, int k) {
  final la = a.length;
  final lb = b.length;
  var prev2 = List<int>.filled(lb + 1, 0);
  var prev = List<int>.generate(lb + 1, (j) => j);
  var curr = List<int>.filled(lb + 1, 0);
  var prevMin = 0;
  for (var i = 1; i <= la; i++) {
    curr[0] = i;
    var rowMin = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= lb; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = prev[j - 1] + cost; // substitution
      final deletion = prev[j] + 1;
      if (deletion < best) best = deletion;
      final insertion = curr[j - 1] + 1;
      if (insertion < best) best = insertion;
      // transposition of two adjacent characters
      // e.g. אבועלפיה → אבולעפיה counts as 1 edit, not 2
      if (i > 1 &&
          j > 1 &&
          ca == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final transposition = prev2[j - 2] + cost;
        if (transposition < best) best = transposition;
      }
      curr[j] = best;
      if (best < rowMin) rowMin = best;
    }
    // ערכים עתידיים נגזרים משתי השורות האחרונות בתוספת עלות לא-שלילית,
    // ולכן כשהמינימום בשתיהן חצה את k המרחק כבר לא ירד חזרה
    if (rowMin > k && prevMin > k) return false;
    final recycled = prev2;
    prev2 = prev;
    prev = curr;
    curr = recycled;
    prevMin = rowMin;
  }
  return prev[lb] <= k;
}

// Allowed edit distance by word length:
// 1-4  chars → 0 (exact)
// 4-8  chars → 1 typo
// 8-12 chars → 2 typos
// 12-16 chars → 3 typos
// 16+  chars → 4 typos
int _maxAllowedEdits(int len) {
  if (len <= 4) return 0;
  if (len <= 8) return 1;
  if (len <= 12) return 2;
  if (len <= 16) return 3;
  return 4;
}

/// התאמת זוג מילים בודדות: הכלה, או מרחק עריכה שסיפו נגזר מהארוכה
/// מבין השתיים — כך ההתאמה הדדית (מדות↔מידות).
bool _wordPairMatches(String queryWord, String textWord) {
  if (textWord.contains(queryWord)) return true;
  if (queryWord.length < 3) return false;

  final allowed = _maxAllowedEdits(
      queryWord.length > textWord.length ? queryWord.length : textWord.length);
  // שוויון מלא כבר כוסה ע"י contains
  if (allowed == 0) return false;
  // הפרש האורכים הוא חסם תחתון למרחק העריכה
  if ((textWord.length - queryWord.length).abs() > allowed) return false;
  return _editDistanceAtMost(queryWord, textWord, allowed);
}

/// התאמת מילת שאילתה לטקסט שלם (כותרת/מחבר מנורמלים) עם סלחנות לשגיאות כתיב.
@visibleForTesting
bool bookSearchWordMatchesFuzzy(String queryWord, String text) {
  for (final textWord in text.split(' ')) {
    if (textWord.isEmpty) continue;
    if (_wordPairMatches(queryWord, textWord)) return true;
  }
  return false;
}

String _normalizeBookSearchText(String input) {
  var cleaned = removeTeamim(removeVolwels(input));
  cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
  cleaned = cleaned.replaceAll('\u05F4', '').replaceAll('\u05F3', '');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s]'), ' ');
  return cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
