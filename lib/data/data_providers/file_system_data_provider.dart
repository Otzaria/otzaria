import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/utils/docx_to_otzaria.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/toc_parser.dart';

/// A data provider that manages file system operations for the library.
///
/// This class handles all file system related operations including:
/// - Reading and parsing book content from various file formats (txt, docx, pdf)
/// - Managing the library structure (categories and books)
/// - Handling external book data from CSV files
/// - Managing book links and metadata
/// - Providing table of contents functionality
class FileSystemData {
  /// Future that resolves to a mapping of book titles to their file system paths
  late Future<Map<String, String>> titleToPath;

  late String libraryPath;

  /// Future that resolves to metadata for all books and categories
  late Future<Map<String, Map<String, dynamic>>> metadata;

  /// Creates a new instance of [FileSystemData] and initializes the title to path mapping
  /// and metadata
  FileSystemData() {
    libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
  }

  /// Singleton instance of [FileSystemData]
  static FileSystemData instance = FileSystemData();

  /// Retrieves the complete library structure from the file system.
  ///
  /// Reads the library from the configured path and combines it with metadata
  /// to create a full [Library] object containing all categories and books.
  Future<Library> getLibrary() async {
    // בדיקה שהתיקייה הראשית קיימת
    final rootDir = Directory(libraryPath);
    if (!rootDir.existsSync()) {
      debugPrint('Library root directory does not exist: $libraryPath');
      return Library(categories: []);
    }

    // בדיקה שתיקיית אוצריא קיימת
    final otzariaPath = '$libraryPath${Platform.pathSeparator}אוצריא';
    final otzariaDir = Directory(otzariaPath);
    if (!otzariaDir.existsSync()) {
      debugPrint('Otzaria directory does not exist: $otzariaPath');
      return Library(categories: []);
    }

    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
    return _getLibraryFromDirectory(otzariaPath, await metadata);
  }

  /// Recursively builds the library structure from a directory.
  ///
  /// Creates a hierarchical structure of categories and books by traversing
  /// the file system directory structure.
  Future<Library> _getLibraryFromDirectory(
      String path, Map<String, dynamic> metadata) async {
    /// Recursive helper function to process directories and build category structure
    Future<Category> getAllCategoriesAndBooksFromDirectory(
        Directory dir, Category? parent) async {
      final title = getTitleFromPath(dir.path);
      Category category = Category(
          title: title,
          description: metadata[title]?['heDesc'] ?? '',
          shortDescription: metadata[title]?['heShortDesc'] ?? '',
          order: metadata[title]?['order'] ?? 999,
          subCategories: [],
          books: [],
          parent: parent);

      // Process each entity in the directory
      await for (FileSystemEntity entity in dir.list()) {
        // Check if entity is accessible before processing
        try {
          // Verify we can access the entity
          await entity.stat();

          if (entity is Directory) {
            // Recursively process subdirectories as categories
            category.subCategories.add(
                await getAllCategoriesAndBooksFromDirectory(
                    Directory(entity.path), category));
          } else if (entity is File) {
            // Only process actual files, not directories mistaken as files
            // Extract topics from the file path
            var topics = entity.path
                .split('אוצריא${Platform.pathSeparator}')
                .last
                .split(Platform.pathSeparator)
                .toList();
            topics = topics.sublist(0, topics.length - 1);

            // Handle special case where title contains " על "
            if (getTitleFromPath(entity.path).contains(' על ')) {
              topics.add(getTitleFromPath(entity.path).split(' על ')[1]);
            }

            // Process PDF files
            if (entity.path.toLowerCase().endsWith('.pdf')) {
              final title = getTitleFromPath(entity.path);
              category.books.add(
                PdfBook(
                  title: title,
                  category: category,
                  path: entity.path,
                  author: metadata[title]?['author'],
                  heCategories: metadata[title]?['heCategories'],
                  heEra: metadata[title]?['heEra'],
                  compDateStringHe: metadata[title]?['compDateStringHe'],
                  compPlaceStringHe: metadata[title]?['compPlaceStringHe'],
                  pubDateStringHe: metadata[title]?['pubDateStringHe'],
                  pubPlaceStringHe: metadata[title]?['pubPlaceStringHe'],
                  heShortDesc: metadata[title]?['heShortDesc'],
                  heDesc: metadata[title]?['heDesc'],
                  pubDate: metadata[title]?['pubDate'],
                  pubPlace: metadata[title]?['pubPlace'],
                  order: metadata[title]?['order'] ?? 999,
                  topics: topics.join(', '),
                ),
              );
            }

            // Process text and docx files
            if (entity.path.toLowerCase().endsWith('.txt') ||
                entity.path.toLowerCase().endsWith('.docx')) {
              final title = getTitleFromPath(entity.path);
              category.books.add(TextBook(
                  title: title,
                  category: category,
                  author: metadata[title]?['author'],
                  heCategories: metadata[title]?['heCategories'],
                  heEra: metadata[title]?['heEra'],
                  compDateStringHe: metadata[title]?['compDateStringHe'],
                  compPlaceStringHe: metadata[title]?['compPlaceStringHe'],
                  pubDateStringHe: metadata[title]?['pubDateStringHe'],
                  pubPlaceStringHe: metadata[title]?['pubPlaceStringHe'],
                  heShortDesc: metadata[title]?['heShortDesc'],
                  heDesc: metadata[title]?['heDesc'],
                  pubDate: metadata[title]?['pubDate'],
                  pubPlace: metadata[title]?['pubPlace'],
                  order: metadata[title]?['order'] ?? 999,
                  topics: topics.join(', '),
                  extraTitles: metadata[title]?['extraTitles']));
            }
          }
        } catch (e) {
          // Skip entities that can't be accessed (like directories mistaken as files)
          debugPrint('Skipping inaccessible entity: ${entity.path} - $e');
          continue;
        }
      }

      // Sort categories and books by their order
      category.subCategories.sort((a, b) => a.order.compareTo(b.order));
      category.books.sort((a, b) => a.order.compareTo(b.order));
      return category;
    }

    // Initialize empty library
    Library library = Library(categories: []);

    // Process top-level directories
    await for (FileSystemEntity entity in Directory(path).list()) {
      if (entity is Directory) {
        // Skip "אודות התוכנה" directory
        final dirName = entity.path.split(Platform.pathSeparator).last;
        if (dirName == 'אודות התוכנה') {
          continue;
        }

        library.subCategories.add(await getAllCategoriesAndBooksFromDirectory(
            Directory(entity.path), library));
      }
    }
    library.subCategories.sort((a, b) => a.order.compareTo(b.order));
    return library;
  }

  /// Retrieves the list of books from Otzar HaChochma
  static Future<List<ExternalBook>> getOtzarBooks() {
    return _getOtzarBooks();
  }

  /// Retrieves the list of books from HebrewBooks
  static Future<List<Book>> getHebrewBooks() {
    return _getHebrewBooks();
  }

  /// Loads a CSV file from assets and parses it into a table using Isolate.
  static Future<List<List<dynamic>>> _loadCsvTable(String assetPath,
      {bool shouldParseNumbers = false}) async {
    final csvData = await rootBundle.loadString(assetPath);
    return await Isolate.run(() {
      // Normalize line endings for cross-platform compatibility
      final normalizedCsvData =
          csvData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      return CsvToListConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        eol: '\n',
        shouldParseNumbers: shouldParseNumbers,
      ).convert(normalizedCsvData);
    });
  }

  /// Internal implementation for loading Otzar HaChochma books from CSV
  static Future<List<ExternalBook>> _getOtzarBooks() async {
    try {
      final table = await _loadCsvTable('assets/otzar_books.csv',
          shouldParseNumbers: false);
      return table.skip(1).map((row) {
        return ExternalBook(
          title: row[1],
          id: int.tryParse(row[0]) ?? -1,
          author: row[2],
          pubPlace: row[3],
          pubDate: row[4],
          topics: row[5],
          link: row[7],
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Internal implementation for loading HebrewBooks from CSV
  static Future<List<Book>> _getHebrewBooks() async {
    try {
      final hebrewBooksPath =
          Settings.getValue<String>('key-hebrew-books-path');

      final table = await _loadCsvTable('assets/hebrew_books.csv',
          shouldParseNumbers: true);

      final books = <Book>[];
      for (final row in table.skip(1)) {
        try {
          if (row[0] == null || row[0].toString().isEmpty) continue;

          // Check if the ID is numeric
          final bookId = row[0].toString().trim();
          if (!RegExp(r'^\d+$').hasMatch(bookId)) continue;
          String? localPath;

          if (hebrewBooksPath != null) {
            localPath =
                '$hebrewBooksPath${Platform.pathSeparator}Hebrewbooks_org_$bookId.pdf';
            if (!File(localPath).existsSync()) {
              localPath =
                  '$hebrewBooksPath${Platform.pathSeparator}$bookId.pdf';
              if (!File(localPath).existsSync()) {
                localPath = null;
              }
            }
          }

          if (localPath != null) {
            // If local file exists, add as PdfBook
            books.add(PdfBook(
              title: row[1].toString(),
              path: localPath,
              author: row[2].toString(),
              pubPlace: row[3].toString(),
              pubDate: row[4].toString(),
              topics: row[15].toString().replaceAll(';', ', '),
              heShortDesc: row[13].toString(),
            ));
          } else {
            // If no local file, add as ExternalBook
            books.add(ExternalBook(
              title: row[1].toString(),
              id: int.parse(bookId),
              author: row[2].toString(),
              pubPlace: row[3].toString(),
              pubDate: row[4].toString(),
              topics: row[15].toString().replaceAll(';', ', '),
              heShortDesc: row[13].toString(),
              link: 'https://beta.hebrewbooks.org/$bookId',
            ));
          }
        } catch (e) {
          debugPrint('Error loading book: $e');
        }
      }
      return books;
    } catch (e) {
      debugPrint('Error loading hebrewbooks: $e');
      return [];
    }
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
  /// Supports both plain text and DOCX formats. DOCX files are processed
  /// using a special converter to extract their content.
  Future<String> getBookText(String title) async {
    final path = await _getBookPath(title);
    final file = File(path);

    if (path.endsWith('.docx')) {
      final bytes = await file.readAsBytes();
      return Isolate.run(() => docxToText(bytes, title));
    } else {
      return file.readAsString();
    }
  }

  /// Saves text content to a book file.
  ///
  /// Only supports plain text files (.txt). DOCX files cannot be edited.
  /// Creates a backup of the original file before saving.
  Future<void> saveBookText(String title, String content) async {
    final path = await _getBookPath(title);
    final file = File(path);

    // Only allow saving to text files, not DOCX
    if (path.endsWith('.docx')) {
      throw Exception(
          'Cannot save to DOCX files. Only text files are supported.');
    }

    // Create backup of original file
    final backupPath = '$path.backup.${DateTime.now().millisecondsSinceEpoch}';
    await file.copy(backupPath);

    try {
      // Save the new content
      await file.writeAsString(content, encoding: utf8);

      // Clean up old backups after successful save
      await _cleanupOldBackups(path);
    } catch (e) {
      // If save fails, restore from backup
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.copy(path);
      }
      rethrow;
    }
  }

  /// Cleans up old backup files for a given file path.
  /// Keeps only the most recent 3 backups, deletes older ones.
  Future<void> _cleanupOldBackups(String originalPath) async {
    try {
      final directory = Directory(originalPath).parent;
      final baseName = originalPath.split(Platform.pathSeparator).last;

      // Find all backup files for this document
      final backupFiles = <File>[];
      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.startsWith('$baseName.backup.')) {
            backupFiles.add(entity);
          }
        }
      }

      // Sort by timestamp (newest first)
      backupFiles.sort((a, b) {
        final aTime = _getBackupTimestamp(a.path);
        final bTime = _getBackupTimestamp(b.path);
        return bTime.compareTo(aTime); // Descending order
      });

      // Keep only the first 3 (most recent)
      for (int i = 3; i < backupFiles.length; i++) {
        try {
          await backupFiles[i].delete();
          debugPrint('Deleted old backup: ${backupFiles[i].path}');
        } catch (e) {
          debugPrint('Failed to delete backup ${backupFiles[i].path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error during backup cleanup: $e');
    }
  }

  /// Extracts timestamp from backup filename
  int _getBackupTimestamp(String backupPath) {
    try {
      final fileName = backupPath.split(Platform.pathSeparator).last;
      final timestampStr = fileName.split('.backup.').last;
      return int.parse(timestampStr);
    } catch (e) {
      return 0; // Return 0 for files that can't be parsed
    }
  }

  /// Manual cleanup of old backup files across the entire library
  Future<int> cleanupAllOldBackups() async {
    int deletedCount = 0;
    try {
      final libraryDir =
          Directory('$libraryPath${Platform.pathSeparator}אוצריא');

      // בדיקה שהתיקייה קיימת לפני ניסיון לגשת אליה
      if (!libraryDir.existsSync()) {
        debugPrint('Library directory does not exist, skipping cleanup');
        return 0;
      }

      await for (final entity in libraryDir.list(recursive: true)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.contains('.backup.')) {
            // Check if this backup is old (older than 7 days)
            final timestamp = _getBackupTimestamp(entity.path);
            final backupDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final daysOld = DateTime.now().difference(backupDate).inDays;

            if (daysOld > 7) {
              try {
                await entity.delete();
                deletedCount++;
              } catch (e) {
                debugPrint('Failed to delete backup ${entity.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error during global backup cleanup: $e');
    }

    return deletedCount;
  }

  /// Retrieves the content of a specific link within a book.
  ///
  /// Reads the file line by line and returns the content at the specified index.
  Future<String> getLinkContent(Link link) async {
    try {
      String path = await _getBookPath(getTitleFromPath(link.path2));
      if (path.startsWith('error:')) {
        return 'שגיאה בטעינת קובץ: ${link.path2}';
      }
      return await getLineFromFile(path, link.index2);
    } catch (e) {
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
  /// Parses the book content to extract headings and create a hierarchical
  /// table of contents structure.
  Future<List<TocEntry>> getBookToc(String title) async {
    return _parseToc(getBookText(title));
  }

  /// Efficiently reads a specific line from a file.
  ///
  /// Uses a stream to read the file line by line until the desired index
  /// is reached, then closes the stream to conserve resources.
  Future<String> getLineFromFile(String path, int index) async {
    File file = File(path);
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(index)
        .toList();
    return (await lines).last;
  }

  /// Updates the mapping of book titles to their file system paths.
  ///
  /// Creates a map where keys are book titles and values are their corresponding
  /// file system paths, excluding PDF files.
  Future<Map<String, String>> _getTitleToPath() async {
    Map<String, String> titleToPath = {};
    List<String> paths = await getAllBooksPathsFromDirecctory(libraryPath);
    for (var path in paths) {
      if (path.toLowerCase().endsWith('.pdf')) continue;
      titleToPath[getTitleFromPath(path)] = path;
    }
    return titleToPath;
  }

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
          '${Settings.getValue<String>('key-library-path') ?? '.'}${Platform.pathSeparator}metadata.json');
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
  Future<String> _getBookPath(String title) async {
    final titleToPath = await this.titleToPath;
    return titleToPath[title] ?? 'error: book path not found: $title';
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
    return '${Settings.getValue<String>('key-library-path') ?? '.'}${Platform.pathSeparator}links${Platform.pathSeparator}${title}_links.json';
  }

  /// Checks if a book with the given title exists in the library.
  Future<bool> bookExists(String title) async {
    final titleToPath = await this.titleToPath;
    return titleToPath.keys.contains(title);
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
