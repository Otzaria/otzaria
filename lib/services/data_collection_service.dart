import 'package:flutter/foundation.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// Service for collecting data required for phone error reporting
class DataCollectionService {
  /// Read library version from the database (schema_meta).
  /// Returns "unknown" if not found or cannot be read.
  Future<String> readLibraryVersion() async {
    try {
      // Try reading from schema_meta table first (db_meta הוסר ב-v3)
      final dbProvider = SqliteDataProvider.instance;
      if (await dbProvider.databaseExists()) {
        sqlite3.Database? db;
        try {
          // קריאה בלבד — נפתח read-only כדי לתמוך ב-seforim.db על מדיה
          // לקריאה-בלבד ולא ליצור קובצי WAL צדדיים.
          db = sqlite3.sqlite3.open(
            DatabaseConstants.getDatabasePath(),
            mode: sqlite3.OpenMode.readOnly,
          );
          final result = db.select(
            'SELECT value FROM schema_meta WHERE key = ? LIMIT 1',
            ['db_version'],
          );

          if (result.isNotEmpty) {
            final version = result.first['value']?.toString();
            if (version != null && version.isNotEmpty) {
              debugPrint('Library version from schema_meta: $version');
              return version;
            }
          }
        } catch (e) {
          debugPrint('Error reading library version from schema_meta: $e');
        } finally {
          db?.close();
        }
      }

      // גרסת הספרייה מגיעה רק מ-schema_meta; קובץ "גירסת ספריה.txt" הוסר ב-v3.
      return 'unknown';
    } catch (e) {
      debugPrint('Error reading library version: $e');
      return 'unknown';
    }
  }

  /// Find book ID by matching the book title in database
  /// Returns the book ID if found, null if not found or error
  Future<int?> findBookIdInDb(String bookTitle) async {
    try {
      final resolvedBook = await BookDatabaseResolver.resolveBook(
        title: bookTitle,
      );
      if (resolvedBook != null) {
        debugPrint('Book ID from DB: ${resolvedBook.book.id} for $bookTitle');
        return resolvedBook.book.id;
      }

      debugPrint('Book not found in DB: $bookTitle');
      return null;
    } catch (e) {
      debugPrint('Error reading book ID: $e');
      return null;
    }
  }

  /// Get current line number from ItemPosition data
  /// Returns the first visible item index, or 0 if no positions available
  int getCurrentLineNumber(List<ItemPosition> positions) {
    try {
      if (positions.isEmpty) {
        return 0;
      }

      // Sort positions by index and return the first one
      final sortedPositions = positions.toList()
        ..sort((a, b) => a.index.compareTo(b.index));

      return sortedPositions.first.index + 1; // Convert to 1-based
    } catch (e) {
      debugPrint('Error getting current line number: $e');
      return 0;
    }
  }

  /// Get total number of books from database
  /// Returns the number of books in the database
  Future<int> getTotalBookCount() async {
    try {
      final dbProvider = SqliteDataProvider.instance;
      if (await dbProvider.databaseExists() && dbProvider.isInitialized) {
        final stats = await dbProvider.getDatabaseStats();
        final bookCount = stats['books'] ?? 0;
        debugPrint('Book count from DB: $bookCount');
        return bookCount;
      }
      debugPrint('Database not available');
      return 0;
    } catch (e) {
      debugPrint('Error counting books from DB: $e');
      return 0;
    }
  }

  /// Check if all required data is available for phone reporting
  /// Returns a map with availability status and error messages
  Future<Map<String, dynamic>> checkDataAvailability(String bookTitle) async {
    final result = <String, dynamic>{
      'available': true,
      'errors': <String>[],
      'libraryVersion': null,
      'bookId': null,
    };

    // Check library version
    final libraryVersion = await readLibraryVersion();
    result['libraryVersion'] = libraryVersion;

    if (libraryVersion == 'unknown') {
      result['available'] = false;
      result['errors'].add('לא ניתן לקרוא את גירסת הספרייה');
    }

    // Check book ID
    final bookId = await findBookIdInDb(bookTitle);
    result['bookId'] = bookId;

    if (bookId == null) {
      result['available'] = false;
      result['errors'].add('לא ניתן למצוא את הספר במאגר הנתונים');
    }

    return result;
  }
}
