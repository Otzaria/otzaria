import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/core/models/book.dart' as migration;
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/migration/dao/daos/database.dart';
import 'package:otzaria/migration/adapters/model_adapters.dart';
import 'package:otzaria/data/constants/database_constants.dart';

/// A data provider that manages SQLite database operations for the library.
///
/// This class handles all database related operations including:
/// - Reading book content from the database
/// - Managing the library structure (categories and books)
/// - Providing table of contents functionality
/// - Falling back to file system when data is not in database
class SqliteDataProvider {
  late SeforimRepository _repository;
  late String _dbPath;
  bool _isInitialized = false;
  bool _isInitializedInProgress = false;

  /// Singleton instance
  static SqliteDataProvider? _instance;

  SqliteDataProvider._();

  static SqliteDataProvider get instance {
    _instance ??= SqliteDataProvider._();
    return _instance!;
  }

  /// Initializes the database connection
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('SQLite database is already initialized.');
      return;
    }

    if (_isInitializedInProgress) {
      debugPrint('SQLite database initialization is already in progress.');
      return;
    } else {
      debugPrint('Starting SQLite database initialization.');
    }
    _isInitializedInProgress = true;
    // Use centralized database path
    _dbPath = DatabaseConstants.getDatabasePath();

    debugPrint('Initializing SQLite database at: $_dbPath');

    // Check if database file exists
    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      debugPrint('Database file does not exist yet at: $_dbPath');
      // Database will be created when first book is migrated
      _isInitializedInProgress = false;
      return;
    }

    try {
      final database = MyDatabase.withPath(_dbPath);
      _repository = SeforimRepository(database);
      await _repository.ensureInitialized();
      _isInitialized = true;
      _isInitializedInProgress = false;
      debugPrint('SQLite database initialized successfully');
    } catch (e) {
      _isInitializedInProgress = false;
      debugPrint('Error initializing SQLite database: $e');
      rethrow;
    }
  }

  /// Checks if the database is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Checks if a book exists in the database
  Future<bool> isBookInDatabase(String title,
      [int? categoryId, String? fileType]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return false;

    try {
      if (categoryId != null && fileType != null) {
        final book = await _repository.getBookByTitleCategoryAndFileType(
            title, categoryId, fileType);
        return book != null;
      }
      final book = await _repository.getBookByTitle(title);
      return book != null;
    } catch (e) {
      debugPrint('Error checking if book exists in database: $e');
      return false;
    }
  }

  /// Retrieves quick preview of a book (40 lines around position) for instant display
  Future<String?> getBookQuickPreview(String title, int currentLine) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final book = await _repository.getBookByTitle(title);
      if (book == null) return null;

      // Load 10 lines before and 10 after (20 total)
      final startLine = (currentLine - 10).clamp(0, book.totalLines - 1);
      final endLine = (currentLine + 10).clamp(0, book.totalLines - 1);

      debugPrint(
          '⚡ Quick preview: lines $startLine-$endLine of ${book.totalLines}');

      final lines = await _repository.getLines(book.id, startLine, endLine);
      return migrationLinesToText(lines);
    } catch (e) {
      debugPrint('Error getting book quick preview: $e');
      return null;
    }
  }

  /// Retrieves the full text content of a book from the database
  Future<String?> getBookTextFromDb(String title,
      [int? categoryId, String? fileType]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      migration.Book? book;
      if (categoryId != null && fileType != null) {
        book = await _repository.getBookByTitleCategoryAndFileType(
            title, categoryId, fileType);
      } else {
        book = await _repository.getBookByTitle(title);
      }

      if (book == null) return null;

      final lines = await _repository.getLines(book.id, 0, book.totalLines - 1);
      return migrationLinesToText(lines);
    } catch (e) {
      debugPrint('Error getting book text from database: $e');
      return null;
    }
  }

  /// Retrieves the table of contents of a book from the database
  Future<List<TocEntry>?> getBookTocFromDb(String title,
      [int? categoryId, String? fileType]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      migration.Book? book;
      if (categoryId != null && fileType != null) {
        book = await _repository.getBookByTitleCategoryAndFileType(
            title, categoryId, fileType);
      } else {
        book = await _repository.getBookByTitle(title);
      }

      if (book == null) return null;

      final migrationTocEntries = await _repository.getBookTocs(book.id);

      // Convert migration TOC entries to otzaria TOC entries
      final Map<int, TocEntry> idToEntry = {};
      final List<TocEntry> rootEntries = [];

      for (final migrationToc in migrationTocEntries) {
        TocEntry? parent;
        if (migrationToc.parentId != null) {
          parent = idToEntry[migrationToc.parentId];
        }

        final otzariaToc = migrationTocToOtzariaToc(migrationToc, parent);
        idToEntry[migrationToc.id] = otzariaToc;

        if (parent != null) {
          parent.children.add(otzariaToc);
        } else {
          rootEntries.add(otzariaToc);
        }
      }

      return rootEntries;
    } catch (e) {
      debugPrint('Error getting book TOC from database: $e');
      return null;
    }
  }

  /// Retrieves source name for a book from DB source table.
  Future<String?> getBookSourceNameFromDb(String title,
      [int? categoryId, String? fileType]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      migration.Book? book;
      if (categoryId != null && fileType != null) {
        book = await _repository.getBookByTitleCategoryAndFileType(
            title, categoryId, fileType);
      } else {
        book = await _repository.getBookByTitle(title);
      }

      if (book == null) return null;
      final source = await _repository.getSourceById(book.sourceId);
      return source?.name;
    } catch (e) {
      debugPrint('Error getting book source name from database: $e');
      return null;
    }
  }

  /// Retrieves PDF bytes from the database (book_file) for a given PDF book.
  /// Returns null if not found or DB not initialized.
  Future<Uint8List?> getPdfBytesFromDb(PdfBook book) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      migration.Book? dbBook;
      final filePath = book.filePath ?? book.path;

      if (filePath.isNotEmpty) {
        dbBook = await _repository.getExternalBookByFilePath(filePath);
      }

      dbBook ??= await _repository.getBookByTitle(book.title);

      if (dbBook == null) return null;

      return await _repository.getBookFileContent(dbBook.id);
    } catch (e) {
      debugPrint('Error getting PDF bytes from database: $e');
      return null;
    }
  }

  /// Gets the repository instance (for advanced operations)
  SeforimRepository? get repository => _isInitialized ? _repository : null;

  /// Gets the database path
  String get dbPath => _dbPath;

  /// Checks if database file exists
  Future<bool> databaseExists() async {
    final dbFile = File(_dbPath);
    return await dbFile.exists();
  }

  /// Exports the database to a specified path
  Future<void> exportDatabase(String destinationPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file does not exist');
    }

    await dbFile.copy(destinationPath);
    debugPrint('Database exported to: $destinationPath');
  }

  /// Imports a database from a specified path
  Future<void> importDatabase(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source database file does not exist');
    }

    // Close existing connection if open
    if (_isInitialized) {
      _repository.database.close();
      _isInitialized = false;
    }

    // Copy the file
    await sourceFile.copy(_dbPath);
    debugPrint('Database imported from: $sourcePath');

    // Reinitialize
    await initialize();
  }

  /// Gets statistics about the database
  Future<Map<String, int>> getDatabaseStats() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) {
      return {'books': 0, 'lines': 0, 'links': 0};
    }

    try {
      final bookCount = await _repository.countAllBooks();
      final linkCount = await _repository.countLinks();

      return {
        'books': bookCount,
        'links': linkCount,
      };
    } catch (e) {
      debugPrint('Error getting database stats: $e');
      return {'books': 0, 'lines': 0, 'links': 0};
    }
  }

  /// Performs a health check on the database
  Future<Map<String, dynamic>> performHealthCheck() async {
    final results = <String, dynamic>{
      'healthy': true,
      'issues': <String>[],
      'warnings': <String>[],
    };

    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (!_isInitialized) {
        results['healthy'] = false;
        (results['issues'] as List).add('Database not initialized');
        return results;
      }

      // Check if database file exists
      if (!await databaseExists()) {
        results['healthy'] = false;
        (results['issues'] as List).add('Database file does not exist');
        return results;
      }

      // Check if we can query the database
      try {
        await _repository.countAllBooks();
      } catch (e) {
        results['healthy'] = false;
        (results['issues'] as List).add('Cannot query database: $e');
        return results;
      }

      debugPrint('✅ Database health check passed');
    } catch (e) {
      results['healthy'] = false;
      (results['issues'] as List).add('Health check failed: $e');
    }

    return results;
  }

  /// Optimizes the database (VACUUM)
  Future<void> optimizeDatabase() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) {
      throw Exception('Database not initialized');
    }

    try {
      debugPrint('🔧 Optimizing database...');
      final db = await _repository.database.database;
      await db.execute('VACUUM');
      debugPrint('✅ Database optimized');
    } catch (e) {
      debugPrint('❌ Error optimizing database: $e');
      rethrow;
    }
  }
}
