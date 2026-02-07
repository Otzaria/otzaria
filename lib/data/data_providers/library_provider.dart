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
      Map<String, Map<String, dynamic>> metadata);

  /// Checks if a specific book exists in this provider
  Future<bool> hasBook(String title, String category, String fileType);

  /// Gets the text content of a book
  Future<String?> getBookText(String title, String category, String fileType);

  /// Gets the table of contents for a book
  Future<List<TocEntry>?> getBookToc(
      String title, String category, String fileType);

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
      String title, String category, String fileType);

  /// Gets the content of a specific link
  ///
  /// [link] - The link to get content for
  /// Returns the text content at the link's target location
  Future<String> getLinkContent(Link link);
}
