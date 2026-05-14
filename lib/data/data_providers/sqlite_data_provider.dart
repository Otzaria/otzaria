import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/model_adapters.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

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
  Future<void>? _initializationFuture;

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
      return;
    }

    // If initialization already started, await the same future
    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _initializeInternal();

    try {
      await _initializationFuture;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    // Use centralized database path
    _dbPath = DatabaseConstants.getDatabasePath();

    // Check if database file exists
    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      // Database will be created when first book is migrated
      return;
    }

    try {
      final database = MyDatabase.withPath(_dbPath);
      _repository = SeforimRepository(database);
      await _repository.ensureInitialized();
      _isInitialized = true;
    } on SqliteException catch (e) {
      // SQLITE_CANTOPEN (code 14): the native library cannot open the file.
      // On Android this happens when the DB is in Scoped Storage and sqlite3
      // native cannot access it via a raw file path.
      // Clear any stale keyDbEffectivePath so that the next
      // checkLibraryIsEmpty() returns true and the user reaches the
      // "select library" screen where the copy-to-internal flow is offered.
      if (Platform.isAndroid && e.resultCode == 14) {
        debugPrint('[SqliteDataProvider] SQLITE_CANTOPEN on Android — '
            'clearing keyDbEffectivePath to trigger library-selection flow.');
        await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
        // Do NOT rethrow: returning without _isInitialized = true causes the
        // app to treat the DB as missing and show the empty-library screen.
        return;
      }
      debugPrint('Error initializing SQLite database: $e');
      rethrow;
    } catch (e) {
      debugPrint('Error initializing SQLite database: $e');
      rethrow;
    }
  }

  /// Checks if the database is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Closes the database connection to free resources
  Future<void> dispose() async {
    if (_isInitialized) {
      _repository.database.close();
      _isInitialized = false;
    }
  }

  /// Checks if a book exists in the database
  Future<bool> isBookInDatabase(String title,
      [int? categoryId, String? fileType]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return false;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
      );
      return resolvedBook != null;
    } catch (e) {
      return false;
    }
  }

  /// Retrieves quick preview of a book (40 lines around position) for instant display
  Future<String?> getBookQuickPreview(
    String title,
    int currentLine, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      // Load 10 lines before and 10 after (20 total)
      final startLine = (currentLine - 10).clamp(0, book.totalLines - 1);
      final endLine = (currentLine + 10).clamp(0, book.totalLines - 1);

      final lines =
          await resolvedBook.repository.getLines(book.id, startLine, endLine);
      return migrationLinesToText(lines);
    } catch (e) {
      return null;
    }
  }

  Future<({int startLine, int endLine, int totalLines, String text})?>
      getBookTextRangeFromDb(
    String title, {
    required int startLine,
    required int endLine,
    int? categoryId,
    String? fileType,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
      );
      if (resolvedBook == null || resolvedBook.book.totalLines <= 0) {
        return null;
      }
      final book = resolvedBook.book;

      final normalizedStart = startLine.clamp(0, book.totalLines - 1);
      final normalizedEnd = endLine.clamp(normalizedStart, book.totalLines - 1);
      final lines = await resolvedBook.repository
          .getLines(book.id, normalizedStart, normalizedEnd);

      return (
        startLine: normalizedStart,
        endLine: normalizedEnd,
        totalLines: book.totalLines,
        text: migrationLinesToText(lines),
      );
    } catch (e) {
      return null;
    }
  }

  /// Retrieves the full text content of a book from the database
  Future<String?> getBookTextFromDb(String title,
      [int? categoryId, String? fileType, bool preferUserBooks = false]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      final lines = await resolvedBook.repository
          .getLines(book.id, 0, book.totalLines - 1);
      return migrationLinesToText(lines);
    } catch (e) {
      return null;
    }
  }

  /// Retrieves the table of contents of a book from the database
  Future<List<TocEntry>?> getBookTocFromDb(String title,
      [int? categoryId, String? fileType, bool preferUserBooks = false]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      final migrationTocEntries =
          await resolvedBook.repository.getBookTocs(book.id);

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
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
      );
      if (resolvedBook == null) return null;
      final source = await resolvedBook.repository
          .getSourceById(resolvedBook.book.sourceId);
      return source?.name;
    } catch (e) {
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
      final db = await _repository.database.database;
      db.execute('VACUUM');
    } catch (e) {
      debugPrint('❌ Error optimizing database: $e');
      rethrow;
    }
  }

  Future<ResolvedDbBookRecord?> _resolveBookRecord(
    String title, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    return await BookDatabaseResolver.resolveBook(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    );
  }
}
