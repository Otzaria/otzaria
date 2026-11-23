import 'dart:isolate';

import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/library/models/library.dart';

/// Interface for library data providers.
///
/// Defines the contract for loading books and categories from different sources
/// (file system, database, etc.)
abstract class LibraryProvider {
  /// Unique identifier for this provider
  String get providerId;

  /// Display name for this provider (for UI)
  String get displayName;

  /// Data source indicator (e.g., 'ק' for files, 'DB' for database, 'א' for personal)
  String get sourceIndicator;

  /// Priority for loading (lower = higher priority)
  int get priority;

  /// Initializes the provider
  Future<void> initialize();

  /// Checks if the provider is ready to use
  bool get isInitialized;

  /// Loads all books from this provider
  ///
  /// Returns a map of category name -> list of books
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  );

  /// Checks if a specific book exists in this provider
  Future<bool> hasBook(String title, int categoryId, String fileType);

  /// Gets the text content of a book
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  });

  /// Gets the table of contents for a book
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  });

  /// Gets all book titles available in this provider
  Future<Set<String>> getAvailableBookTitles();

  /// Builds a library catalog from this provider.
  ///
  /// [metadata] - Book metadata for enriching book information
  /// [rootPath] - The root path of the library (used by file system provider)
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  );

  /// Gets all links for a specific book
  ///
  /// [title] - The title of the book to get links for
  /// Returns a list of Link objects associated with the book
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  );

  /// Gets the content of a specific link
  ///
  /// [link] - The link to get content for
  /// Returns the text content at the link's target location
  Future<String> getLinkContent(Link link);
}

/// ספק שמחזיר טווח בשאילתה אחת, בלי לאבד את גבולות שורות המקור.
abstract interface class LinkLinesProvider {
  Future<List<LinkContentLine>> getLinkContentLines(Link link);
}

/// A provider that reads a book straight into its lines.
///
/// One format for every source: a database book hands its rows over as lines,
/// a text file is split once when read. The viewer and every consumer take
/// the list; a joined string is built only where one is genuinely needed.
abstract interface class BookLinesProvider {
  /// The book's lines, or null when this provider has no text for it.
  /// Equals splitting [LibraryProvider.getBookText] on '\n'.
  Future<List<String>?> getBookLines(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  });
}

/// Splits a whole book text into its lines once (off the UI isolate).
/// An empty text has no lines.
Future<List<String>> splitBookText(String content) async {
  if (content.isEmpty) return const [];
  return Isolate.run(() => content.split('\n'));
}

/// Whether [lines] hold any text (the lines of an empty string do not).
bool bookLinesHaveText(List<String>? lines) =>
    lines != null &&
    lines.isNotEmpty &&
    (lines.length > 1 || lines.first.isNotEmpty);

/// The lines of a book stored as rows: one line per row; a row that holds
/// '\n' gives several lines, as splitting the joined rows would.
List<String> rowsToBookLines(Iterable<String> rows) {
  final lines = <String>[];
  for (final row in rows) {
    if (row.contains('\n')) {
      lines.addAll(row.split('\n'));
    } else {
      lines.add(row);
    }
  }
  return lines;
}
