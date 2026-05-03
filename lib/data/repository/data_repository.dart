import 'dart:isolate';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/utils/text_manipulation.dart';

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

  late Future<Library> library;

  // Lazy-loaded: only fetched when user actually searches for external books.
  // Previously these ran getAllBooksWithRelations() eagerly at startup,
  // competing with library loading for DB I/O.
  Future<List<Book>>? _hebrewBooksFuture;
  Future<List<ExternalLibraryBook>>? _otzarBooksFuture;
  Future<List<Book>> get hebrewBooks => _hebrewBooksFuture ??= getHebrewBooks();
  Future<List<ExternalLibraryBook>> get otzarBooks =>
      _otzarBooksFuture ??= getOtzarBooks();

  /// Invalidates cached external books so they are re-fetched on next access.
  /// Call this when the library is refreshed.
  void invalidateExternalBooksCache() {
    _hebrewBooksFuture = null;
    _otzarBooksFuture = null;
  }

  DataRepository() {
    library = _getLibrary();
  }

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
    }

    final searchEntries = <_BookSearchEntry>[
      for (var i = 0; i < allBooks.length; i++)
        _BookSearchEntry(
          index: i,
          title: allBooks[i].title,
          author: allBooks[i].author ?? '',
          topics: allBooks[i].topics,
        ),
    ];

    final matchingIndices = await Isolate.run(
      () => _filterBookSearchEntries(
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

class _BookSearchEntry {
  final int index;
  final String title;
  final String author;
  final String topics;

  const _BookSearchEntry({
    required this.index,
    required this.title,
    required this.author,
    required this.topics,
  });
}

List<int> _filterBookSearchEntries({
  required List<_BookSearchEntry> entries,
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

    return _PreparedBookSearchEntry(
      index: entry.index,
      normalizedTitle: normalizedTitle,
      normalizedAuthor: normalizedAuthor,
      topics: topics,
    );
  });

  final filtered = preparedEntries.where((entry) {
    final matchesQuery = queryWords.every(
      (word) =>
          entry.normalizedTitle.contains(word) ||
          entry.normalizedAuthor.contains(word),
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
          score: ratio(normalizedQuery, entry.normalizedTitle),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));

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
  final String normalizedAuthor;
  final Set<String> topics;

  const _PreparedBookSearchEntry({
    required this.index,
    required this.normalizedTitle,
    required this.normalizedAuthor,
    required this.topics,
  });
}

class _ScoredBookSearchEntry {
  final int index;
  final int score;

  const _ScoredBookSearchEntry({
    required this.index,
    required this.score,
  });
}

String _normalizeBookSearchText(String input) {
  var cleaned = removeTeamim(removeVolwels(input));
  cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
  cleaned = cleaned.replaceAll('\u05F4', '').replaceAll('\u05F3', '');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s]'), ' ');
  return cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
