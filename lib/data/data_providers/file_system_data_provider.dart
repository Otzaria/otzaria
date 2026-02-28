import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/toc_parser.dart';
import 'package:otzaria/migration/core/models/book.dart' as db_models;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as path;

/// A data provider that manages file system operations for the library.
///
/// This class handles all file system related operations including:
/// - Reading and parsing book content from various file formats (txt, docx, pdf)
/// - Managing the library structure (categories and books)
/// - Handling external book data from CSV files
/// - Managing book links and metadata
/// - Providing table of contents functionality
class FileSystemData {
  late String libraryPath;

  /// Future that resolves to metadata for all books and categories
  late Future<Map<String, Map<String, dynamic>>> metadata;

  late Future<Map<String, String>> titleToPath;

  /// Library provider manager for coordinating multiple data sources
  final LibraryProviderManager _providerManager =
      LibraryProviderManager.instance;

  /// Creates a new instance of [FileSystemData] and initializes the title to path mapping
  /// and metadata
  FileSystemData() {
    libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
    _initializeProviders();
  }

  /// Singleton instance of [FileSystemData]
  static FileSystemData instance = FileSystemData();

  /// Initializes the library providers
  Future<void> _initializeProviders() async {
    try {
      await _providerManager.initialize();
      debugPrint('Library providers initialized in FileSystemData');
    } catch (e) {
      debugPrint('Provider initialization failed: $e');
    }
  }

  Future<Map<String, String>> _getTitleToPath() async {
    await _providerManager.initialize();
    final Map<String, String> result = {};

    // Get paths from FileSystemProvider
    final keyToPath = await _providerManager.fileSystemProvider.keyToPath;
    for (var entry in keyToPath.entries) {
      final parts = entry.key.split('|');
      if (parts.isNotEmpty) {
        result[parts[0]] = entry.value;
      }
    }

    // Get paths from DatabaseProvider
    final dbKeys =
        await _providerManager.databaseProvider.getDatabaseOnlyBookTitles();
    for (var key in dbKeys) {
      final parts = key.split('|');
      if (parts.length >= 2) {
        // parts[0] is title, parts[1] is category path
        result[parts[0]] = parts[1];
      }
    }

    return result;
  }

  /// Finds the category path for a book by its title.
  /// Checks in-memory cache first, then queries valid providers.
  Future<String?> findBookCategoryPath(String title) async {
    await _providerManager.initialize();

    // 1. Check cached FileSystemData map
    // Note: titleToPath might be stale if DB loaded later
    // so we re-check providers below if not found.
    final path = (await titleToPath)[title];
    if (path != null && path.isNotEmpty) return path;

    // 2. Ask DatabaseProvider explicitly
    final dbPath =
        await _providerManager.databaseProvider.findCategoryPathForBook(title);
    if (dbPath != null) return dbPath;

    return null;
  }

  /// Checks if a book is stored in the database
  Future<bool> isBookInDatabase(String title,
      {String? category, String? fileType}) async {
    if (category != null && fileType != null) {
      final categoryId = category.hashCode; // Convert to ID
      return await _providerManager.databaseProvider
          .hasBook(title, categoryId, fileType);
    }
    return await _providerManager.databaseProvider.hasBookWithTitle(title);
  }

  /// Gets the data source for a book (DB, File, or Personal)
  /// Returns: 'DB' for database, 'ק' for file, 'א' for personal
  Future<String> getBookDataSource(String title,
      [String? category, String? fileType = 'txt']) async {
    return await _providerManager.getBookDataSource(
        title, category ?? '', fileType ?? 'txt');
  }

  /// Clears the book-in-database cache
  void clearBookCache() {
    _providerManager.clearCaches();
    debugPrint('Book cache cleared');
  }

  /// Gets statistics about database usage
  Future<Map<String, dynamic>> getDatabaseStats() async {
    return await _providerManager.getStats();
  }

  /// Gets the library provider manager for advanced operations
  LibraryProviderManager get providerManager => _providerManager;

  /// Gets the file system provider
  FileSystemLibraryProvider get fileSystemProvider =>
      _providerManager.fileSystemProvider;

  /// Gets the database provider
  DatabaseLibraryProvider get databaseProvider =>
      _providerManager.databaseProvider;

  /// Checks if a book is in the personal folder
  Future<bool> isPersonalBook(String title,
      {String? category, String? fileType}) async {
    return await _providerManager.fileSystemProvider
        .isPersonalBook(title, category: category, fileType: fileType);
  }

  /// Gets the path to the personal books folder
  String getPersonalBooksPath() {
    return _providerManager.fileSystemProvider.getPersonalBooksPath();
  }

  /// Ensures the personal books folder exists
  Future<void> ensurePersonalFolderExists() async {
    await _providerManager.fileSystemProvider.ensurePersonalFolderExists();
  }

  /// Retrieves the complete library structure from the file system.
  ///
  /// Reads the library from the configured path and combines it with metadata
  /// to create a full [Library] object containing all categories and books.
  /// Uses LibraryProviderManager for unified catalog building.
  Future<Library> getLibrary() async {
    final libraryDir = Directory(libraryPath);

    if (!libraryDir.existsSync()) {
      debugPrint('Library path does not exist: $libraryPath');
      return Library(categories: []);
    }

    // קבלת שם התיקייה מההגדרות
    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
            DatabaseConstants.otzariaFolderName;

    // בדיקה שתיקיית הספרים קיימת
    final otzariaPath = path.join(libraryPath, folderName);
    final otzariaDir = Directory(otzariaPath);
    if (!otzariaDir.existsSync()) {
      debugPrint('Books directory does not exist: $otzariaPath');
      return Library(categories: []);
    }

    metadata = _getMetadata();
    final metadataResult = await metadata;

    // Use the unified catalog builder from LibraryProviderManager
    final library = await _providerManager.buildLibraryCatalog(
      metadataResult,
      otzariaPath,
    );
    return library;
  }

  /// Retrieves the list of books from Otzar HaChochma
  static Future<List<ExternalLibraryBook>> getOtzarBooks() async {
    final books = await _getExternalCatalogBooks(ExternalCatalogType.otzar);
    return books.whereType<ExternalLibraryBook>().toList();
  }

  /// Retrieves the list of books from HebrewBooks
  static Future<List<Book>> getHebrewBooks() async {
    return _getExternalCatalogBooks(ExternalCatalogType.hebrew);
  }

  /// Internal implementation for loading external catalog books from DB
  static Future<List<Book>> _getExternalCatalogBooks(
      ExternalCatalogType catalogType) async {
    try {
      await SqliteDataProvider.instance.initialize();
      final repository = SqliteDataProvider.instance.repository;
      if (repository == null) return [];

      final dbBooks = await repository.getAllExternalContentBooks();
      final books = <Book>[];

      for (final dbBook in dbBooks) {
        final catalog = ExternalCatalogMapper.catalogFromLinkOrId(
          link: ExternalCatalogMapper.resolveLink(
            filePath: dbBook.filePath,
            externalLibraryId: dbBook.externalLibraryId,
          ),
          externalLibraryId: dbBook.externalLibraryId,
          filePath: dbBook.filePath,
        );

        if (catalog != catalogType) continue;

        final mapped = _mapDbBookToExternalBook(dbBook, catalogType);
        if (mapped != null) {
          books.add(mapped);
        }
      }

      return books;
    } catch (e) {
      debugPrint('Error loading external catalogs from DB: $e');
      return [];
    }
  }

  static Book? _mapDbBookToExternalBook(
    db_models.Book dbBook,
    ExternalCatalogType catalogType,
  ) {
    final link = ExternalCatalogMapper.resolveLink(
      filePath: dbBook.filePath,
      externalLibraryId: dbBook.externalLibraryId,
    );

    final author = dbBook.authors.isNotEmpty ? dbBook.authors.first.name : null;
    final pubPlace =
        dbBook.pubPlaces.isNotEmpty ? dbBook.pubPlaces.first.name : null;
    final pubDate =
        dbBook.pubDates.isNotEmpty ? dbBook.pubDates.first.date : null;
    final topics = dbBook.topics.map((t) => t.name).join(', ');

    if ((dbBook.fileType ?? '').toLowerCase() == 'pdf' &&
        dbBook.filePath != null &&
        dbBook.filePath!.isNotEmpty) {
      return PdfBook(
        title: dbBook.title,
        path: dbBook.filePath!,
        author: author,
        pubPlace: pubPlace,
        pubDate: pubDate,
        topics: topics,
        heShortDesc: dbBook.heShortDesc,
      );
    }

    if (link == null || link.isEmpty) return null;

    return ExternalLibraryBook(
      title: dbBook.title,
      id: dbBook.id,
      author: author,
      pubPlace: pubPlace,
      pubDate: pubDate,
      topics: topics,
      heShortDesc: dbBook.heShortDesc,
      link: link,
      fileType: 'url',
    );
  }

  /// Retrieves all links associated with a specific book.
  ///
  /// Links are stored in JSON files named '[book_title]_links.json' in the links directory.
  ///
  /// For commentary books whose title starts with "הערות על", this function will also
  /// retrieve reverse links from the source book, creating bidirectional navigation.
  Future<List<Link>> getAllLinksForBook(String title) async {
    try {
      // First, try to load direct links for this book
      File file = File(_getLinksPath(title));
      List<Link> directLinks = [];

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final jsonList =
            await Isolate.run(() async => jsonDecode(jsonString) as List);
        directLinks = jsonList.map((json) => Link.fromJson(json)).toList();
      }

      // Check if this is a commentary book (starts with "הערות על")
      final sourceBookTitle = _getSourceBookFromCommentary(title);
      if (sourceBookTitle != null) {
        // Load the source book's links and create reverse links
        final reverseLinks = await _getReverseLinksFromSourceBook(
          title,
          sourceBookTitle,
        );
        directLinks.addAll(reverseLinks);
      }

      return directLinks;
    } on Exception {
      return [];
    }
  }

  /// Checks if a book title starts with "הערות על" and extracts the source book name.
  ///
  /// For example, "הערות על סוכה" returns "סוכה".
  /// Returns null if the title doesn't start with "הערות על".
  String? _getSourceBookFromCommentary(String title) {
    const commentaryPrefix = 'הערות על ';
    if (title.startsWith(commentaryPrefix)) {
      return title.substring(commentaryPrefix.length);
    }
    return null;
  }

  /// Creates reverse links from a source book to its commentary.
  ///
  /// When the source book has links pointing to the commentary, this function
  /// creates the opposite links so readers of the commentary can navigate back
  /// to the source text.
  Future<List<Link>> _getReverseLinksFromSourceBook(
    String commentaryTitle,
    String sourceBookTitle,
  ) async {
    try {
      // Load links from the source book
      File sourceLinksFile = File(_getLinksPath(sourceBookTitle));
      if (!await sourceLinksFile.exists()) {
        return [];
      }

      final jsonString = await sourceLinksFile.readAsString();
      final jsonList =
          await Isolate.run(() async => jsonDecode(jsonString) as List);
      final sourceLinks = jsonList.map((json) => Link.fromJson(json)).toList();

      // Filter links that point to the commentary and create reverse links
      final reverseLinks = <Link>[];
      for (final link in sourceLinks) {
        final linkTargetTitle = getTitleFromPath(link.path2);

        // Check if this link points to the commentary book
        if (linkTargetTitle == commentaryTitle) {
          // Create a reverse link: from commentary back to source
          reverseLinks.add(Link(
            heRef: sourceBookTitle, // Reference to the source book
            index1: link.index2, // The commentary line that's being referenced
            path2: sourceBookTitle, // Path to the source book
            index2: link.index1, // The source book line that references it
            connectionType: link.connectionType,
            start: link.start,
            end: link.end,
          ));
        }
      }

      return reverseLinks;
    } on Exception catch (e) {
      debugPrint('Error creating reverse links for $commentaryTitle: $e');
      return [];
    }
  }

  /// Retrieves the text content of a book.
  ///
  /// Uses LibraryProviderManager to get text from the appropriate provider.
  Future<String> getBookText(String title,
      {String? category, String? fileType}) async {
    final text = await _providerManager.getBookText(
        title, category ?? '', fileType ?? 'txt');
    if (text != null) {
      return text;
    }

    // Fallback to direct file system access
    debugPrint(
        '⚠️ Provider manager failed, falling back to direct file access for "$title"');
    final path =
        await _getBookPath(title, category: category, fileType: fileType);
    if (path.startsWith('error:')) {
      throw Exception('Book not found: $title');
    }

    final file = File(path);
    return file.readAsString();
  }

  /// Saves text content to a book file.
  ///
  /// Only supports plain text files (.txt). DOCX files cannot be edited.
  /// Creates a backup of the original file before saving.
  Future<void> saveBookText(String title, String content) async {
    await _providerManager.fileSystemProvider.saveBookText(title, content);
  }

  /// Retrieves the content of a specific link within a book.
  ///
  /// Reads the file line by line and returns the content at the specified index.
  Future<String> getLinkContent(Link link) async {
    try {
      // Validate link data first
      if (link.path2.isEmpty) {
        debugPrint('⚠️ Empty path in link');
        return 'שגיאה: נתיב ריק';
      }

      if (link.index2 <= 0) {
        debugPrint('⚠️ Invalid index in link: ${link.index2}');
        return 'שגיאה: אינדקס לא תקין';
      }

      String path = await _getBookPath(getTitleFromPath(link.path2));
      if (path.startsWith('error:')) {
        debugPrint('⚠️ Book path not found for: ${link.path2}');
        return 'שגיאה בטעינת קובץ: ${link.path2}';
      }

      // Check if file exists before trying to read it
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('⚠️ File does not exist: $path');
        return 'שגיאה: הקובץ לא נמצא';
      }

      return await getLineFromFile(path, link.index2).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Timeout reading line from file: $path');
          return 'שגיאה: פג זמן קריאת הקובץ';
        },
      );
    } catch (e) {
      debugPrint('⚠️ Error loading link content: $e');
      return 'שגיאה בטעינת תוכן המפרש: $e';
    }
  }

  /// Returns a list of all book paths in the library directory.
  ///
  /// This operation is performed in an isolate to prevent blocking the main thread.
  static Future<List<String>> getAllBooksPathsFromDirecctory(
      String path) async {
    return Isolate.run(() async {
      List<String> paths = [];
      final files = await Directory(path).list(recursive: true).toList();
      for (var file in files) {
        if (file is File && !file.path.toLowerCase().endsWith('.pdf')) {
          paths.add(file.path);
        }
      }
      return paths;
    });
  }

  /// Retrieves the table of contents for a book.
  ///
  /// Uses LibraryProviderManager to get TOC from the appropriate provider.
  Future<List<TocEntry>> getBookToc(String title,
      {String? category, String? fileType}) async {
    final toc = await _providerManager.getBookToc(
        title, category ?? '', fileType ?? 'txt');
    if (toc != null && toc.isNotEmpty) {
      return toc;
    }

    // Fallback to parsing from text
    debugPrint(
        '⚠️ Provider manager failed, falling back to text parsing for "$title"');
    return _parseToc(
        getBookText(title, category: category, fileType: fileType));
  }

  /// Efficiently reads a specific line from a file.
  ///
  /// Uses a stream to read the file line by line until the desired index
  /// is reached, then closes the stream to conserve resources.
  Future<String> getLineFromFile(String path, int index) async {
    try {
      File file = File(path);

      // Validate that file exists
      if (!await file.exists()) {
        debugPrint('⚠️ File does not exist: $path');
        return 'שגיאה: הקובץ לא נמצא';
      }

      // Validate index is positive
      if (index <= 0) {
        debugPrint('⚠️ Invalid line index: $index for file: $path');
        return 'שגיאה: אינדקס שורה לא תקין';
      }

      // Add timeout to prevent hanging
      final lines = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(index)
          .timeout(
        const Duration(seconds: 5),
        onTimeout: (sink) {
          debugPrint('⚠️ Timeout reading file: $path');
          sink.close();
        },
      ).toList();

      if (lines.isEmpty) {
        debugPrint('⚠️ No lines found in file: $path');
        return 'שגיאה: הקובץ ריק';
      }

      if (lines.length < index) {
        debugPrint(
            '⚠️ Line index $index exceeds file length ${lines.length} in: $path');
        return 'שגיאה: אינדקס השורה חורג מגודל הקובץ';
      }

      return lines.last;
    } catch (e) {
      debugPrint('⚠️ Error reading line from file $path: $e');
      return 'שגיאה בקריאת הקובץ: $e';
    }
  }

  /// Updates the mapping of book titles to their file system paths.
  ///

  /// Loads and parses the metadata for all books in the library.
  ///
  /// Reads metadata from a JSON file and creates a structured mapping of
  /// book titles to their metadata information.
  Future<Map<String, Map<String, dynamic>>> _getMetadata() async {
    if (!Settings.isInitialized) {
      await Settings.init(cacheProvider: HiveCache());
    }
    String metadataString = '';
    Map<String, Map<String, dynamic>> metadata = {};
    try {
      File file = File(
          '${Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.'}${Platform.pathSeparator}metadata.json');
      metadataString = await file.readAsString();
    } catch (e) {
      return {};
    }
    final tempMetadata =
        await Isolate.run(() => jsonDecode(metadataString) as List);

    for (int i = 0; i < tempMetadata.length; i++) {
      final row = tempMetadata[i] as Map<String, dynamic>;
      metadata[row['title'].replaceAll('"', '')] = {
        'author': row['author'] ?? '',
        'heCategories': row['heCategories'] is List
            ? (row['heCategories'] as List).join(', ')
            : row['heCategories'] ?? '',
        'heEra': row['heEra'] ?? '',
        'compDateStringHe': row['compDateStringHe'] ?? '',
        'compPlaceStringHe': row['compPlaceStringHe'] ?? '',
        'pubDateStringHe': row['pubDateStringHe'] ?? '',
        'pubPlaceStringHe': row['pubPlaceStringHe'] ?? '',
        'heDesc': row['heDesc'] ?? '',
        'heShortDesc': row['heShortDesc'] ?? '',
        'pubDate': row['pubDate'] ?? '',
        'pubPlace': row['pubPlace'] ?? '',
        'extraTitles': row['extraTitles'] == null
            ? [row['title'].toString()]
            : row['extraTitles'].map<String>((e) => e.toString()).toList()
                as List<String>,
        'extraTitlesHe': row['extraTitlesHe'] is List
            ? (row['extraTitlesHe'] as List)
                .map<String>((e) => e.toString())
                .toList()
            : [],
        'order': row['order'] == null || row['order'] == ''
            ? 999
            : row['order'].runtimeType == double
                ? row['order'].toInt()
                : row['order'] as int,
      };
    }
    return metadata;
  }

  /// Retrieves the file system path for a book with the given title.
  Future<String> _getBookPath(String title,
      {String? category, String? fileType}) async {
    await _providerManager.initialize();
    final keyToPath = await _providerManager.fileSystemProvider.keyToPath;

    if (category != null && fileType != null) {
      final key = '$title|$category|$fileType';
      if (keyToPath.containsKey(key)) return keyToPath[key]!;
    }

    // Fallback: fuzzy search by title
    for (final key in keyToPath.keys) {
      if (key.startsWith('$title|')) {
        return keyToPath[key]!;
      }
    }

    return 'error: book path not found: $title';
  }

  /// Parses the table of contents from book content.
  ///
  /// Creates a hierarchical structure based on HTML heading levels (h1, h2, etc.).
  /// Each entry contains the heading text, its level, and its position in the document.
  Future<List<TocEntry>> _parseToc(Future<String> bookContentFuture) async {
    final String bookContent = await bookContentFuture;

    // Build the hierarchy using the shared parser in an isolate
    return Isolate.run(() => TocParser.parseEntriesFromContent(bookContent));
  }

  /// Gets the path to the JSON file containing links for a specific book.
  String _getLinksPath(String title) {
    return '${Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.'}${Platform.pathSeparator}links${Platform.pathSeparator}${title}_links.json';
  }

  /// Checks if a book with the given title exists in the library.
  Future<bool> bookExists(String title) async {
    final keyToPath = await _providerManager.fileSystemProvider.keyToPath;
    for (final key in keyToPath.keys) {
      if (key.startsWith('$title|')) return true;
    }
    return false;
  }

  /// Returns true if the book belongs to Tanach (Torah, Neviim or Ketuvim).
  ///
  /// The check is performed by examining the book path and verifying that it
  /// resides under one of the Tanach directories.
  Future<bool> isTanachBook(String title) async {
    final path = await _getBookPath(title);
    final normalized = path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
    final tanachBase =
        '${Platform.pathSeparator}אוצריא${Platform.pathSeparator}תנך${Platform.pathSeparator}';
    final torah = '$tanachBaseתורה';
    final neviim = '$tanachBaseנביאים';
    final ktuvim = '$tanachBaseכתובים';
    return normalized.contains(torah) ||
        normalized.contains(neviim) ||
        normalized.contains(ktuvim);
  }
}
