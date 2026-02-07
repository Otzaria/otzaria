import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/migration/core/models/book.dart' as migration_book;

/// מתווך מרכזי לאיתור ספרים במערכת
///
/// פונקציה זו מקבלת שם ספר וקטגוריה, ומחפשת את הספר
/// גם ב-DB וגם בתיקיות, ומחזירה את הספר המתאים.
///
/// זהו המתווך היחיד בין הקוד לבין הנתונים האמיתיים.
class BookLocator {
  /// איתור ספר לפי שם וקטגוריה
  ///
  /// [bookTitle] - שם הספר
  /// [category] - הקטגוריה שבה נמצא הספר (אופציונלי)
  ///
  /// מחזיר את המיקום של הספר אם נמצא, או null אם לא נמצא
  static Future<BookLocation?> locateBook(
    String bookTitle, {
    Category? category,
  }) async {
    try {
      // קודם ננסה למצוא ב-DB
      final dbLocation = await _locateInDatabase(bookTitle, category);
      if (dbLocation != null) {
        return dbLocation;
      }

      // אם לא נמצא ב-DB, נחפש בתיקיות
      final fileLocation = await _locateInFileSystem(bookTitle, category);
      return fileLocation;
    } catch (e) {
      debugPrint('❌ Error locating book "$bookTitle": $e');
      return null;
    }
  }

  /// איתור ספר במסד הנתונים
  static Future<BookLocation?> _locateInDatabase(
    String bookTitle,
    Category? category,
  ) async {
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      return null;
    }

    try {
      // אם יש קטגוריה, נחפש לפי קטגוריה
      if (category != null) {
        final dbBook = await _findBookInDatabaseByCategory(
          repository,
          bookTitle,
          category,
        );
        if (dbBook != null) {
          return BookLocation(
            book: dbBook,
            source: BookSource.database,
            filePath: null,
            categoryId: dbBook.categoryId,
          );
        }
      }

      // אם לא מצאנו לפי קטגוריה, נחפש לפי שם בלבד
      final dbBook = await repository.getBookByTitle(bookTitle);
      if (dbBook != null) {
        return BookLocation(
          book: dbBook,
          source: BookSource.database,
          filePath: null,
          categoryId: dbBook.categoryId,
        );
      }
    } catch (e) {
      debugPrint('❌ Error searching in database: $e');
    }

    return null;
  }

  /// חיפוש ספר במסד הנתונים לפי קטגוריה
  static Future<migration_book.Book?> _findBookInDatabaseByCategory(
    dynamic repository,
    String bookTitle,
    Category category,
  ) async {
    try {
      // מציאת ID של הקטגוריה ב-DB
      final categories = await repository.getRootCategories();
      final categoryId = await _findCategoryIdByPath(
        repository,
        categories,
        category.path,
      );

      if (categoryId != null) {
        // חיפוש הספר בקטגוריה הספציפית
        final booksInCategory = await repository.getBooksByCategory(categoryId);
        for (final dbBook in booksInCategory) {
          if (dbBook.title == bookTitle) {
            return dbBook;
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error finding book by category in DB: $e');
    }

    return null;
  }

  /// חיפוש ID של קטגוריה לפי נתיב
  static Future<int?> _findCategoryIdByPath(
    dynamic repository,
    List<dynamic> categories,
    String path,
  ) async {
    final pathParts = path.split('/');

    for (final category in categories) {
      if (category.title == pathParts.first) {
        if (pathParts.length == 1) {
          return category.id;
        }
        // חיפוש רקורסיבי בתת-קטגוריות
        final subCategories = await repository.getCategoryChildren(category.id);
        final remainingPath = pathParts.sublist(1).join('/');
        return await _findCategoryIdByPath(
          repository,
          subCategories,
          remainingPath,
        );
      }
    }
    return null;
  }

  /// איתור ספר במערכת הקבצים
  static Future<BookLocation?> _locateInFileSystem(
    String bookTitle,
    Category? category,
  ) async {
    try {
      final keyToPath =
          await FileSystemData.instance.fileSystemProvider.keyToPath;
      String? filePath;

      if (category != null) {
        // Try to find exact match with category
        // Note: We don't have fileType here, so we might need to iterate
        final categoryPath = category.path.replaceAll('/', ', ');
        for (final key in keyToPath.keys) {
          if (key.startsWith('$bookTitle|$categoryPath|')) {
            filePath = keyToPath[key];
            break;
          }
        }
      }

      // If not found or no category, try fuzzy match by title
      if (filePath == null) {
        for (final key in keyToPath.keys) {
          if (key.startsWith('$bookTitle|')) {
            filePath = keyToPath[key];
            break;
          }
        }
      }

      if (filePath == null) {
        return null;
      }

      // אם יש קטגוריה, נוודא שהקובץ נמצא בתיקייה הנכונה
      if (category != null) {
        final expectedPath = _buildExpectedPath(category);
        if (!filePath.contains(expectedPath)) {
          debugPrint(
              '⚠️ File "$bookTitle" found but not in expected category: $expectedPath');
          return null;
        }
      }

      // בדיקה שהקובץ קיים
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      return BookLocation(
        book: null,
        source: BookSource.fileSystem,
        filePath: filePath,
        categoryId: null,
      );
    } catch (e) {
      debugPrint('❌ Error searching in file system: $e');
      return null;
    }
  }

  /// בניית נתיב צפוי לפי קטגוריה
  static String _buildExpectedPath(Category category) {
    final pathParts = category.path.split('/');
    return pathParts.join(Platform.pathSeparator);
  }

  /// מחיקת ספר (מ-DB או מהקובץ)
  ///
  /// [bookTitle] - שם הספר
  /// [category] - הקטגוריה שבה נמצא הספר (אופציונלי)
  ///
  /// מחזיר true אם המחיקה הצליחה, false אחרת
  static Future<bool> deleteBook(
    String bookTitle, {
    Category? category,
  }) async {
    try {
      final location = await locateBook(bookTitle, category: category);
      if (location == null) {
        debugPrint('❌ Book "$bookTitle" not found');
        return false;
      }

      if (location.source == BookSource.database) {
        return await _deleteFromDatabase(location);
      } else {
        return await _deleteFromFileSystem(location);
      }
    } catch (e) {
      debugPrint('❌ Error deleting book "$bookTitle": $e');
      return false;
    }
  }

  /// מחיקת ספר ממסד הנתונים
  static Future<bool> _deleteFromDatabase(BookLocation location) async {
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null || location.book == null) {
      return false;
    }

    try {
      await repository.deleteBookCompletely(location.book!.id);
      debugPrint('✅ Book deleted from database: ${location.book!.title}');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting from database: $e');
      return false;
    }
  }

  /// מחיקת קובץ ספר
  static Future<bool> _deleteFromFileSystem(BookLocation location) async {
    if (location.filePath == null) {
      return false;
    }

    try {
      final file = File(location.filePath!);
      if (!await file.exists()) {
        debugPrint('❌ File not found: ${location.filePath}');
        return false;
      }

      await file.delete();
      debugPrint('✅ File deleted: ${location.filePath}');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting file: $e');
      return false;
    }
  }

  /// בדיקה אם ספר קיים
  ///
  /// [bookTitle] - שם הספר
  /// [category] - הקטגוריה שבה נמצא הספר (אופציונלי)
  ///
  /// מחזיר true אם הספר קיים, false אחרת
  static Future<bool> bookExists(
    String bookTitle, {
    Category? category,
  }) async {
    final location = await locateBook(bookTitle, category: category);
    return location != null;
  }

  /// קבלת ספר מ-DB (אם קיים)
  ///
  /// [bookTitle] - שם הספר
  /// [category] - הקטגוריה שבה נמצא הספר (אופציונלי)
  ///
  /// מחזיר את הספר מ-DB אם נמצא, או null אחרת
  static Future<migration_book.Book?> getBookFromDatabase(
    String bookTitle, {
    Category? category,
  }) async {
    final location = await locateBook(bookTitle, category: category);
    if (location == null || location.source != BookSource.database) {
      return null;
    }
    return location.book;
  }
}

/// מיקום ספר במערכת
class BookLocation {
  /// הספר מ-DB (אם נמצא ב-DB)
  final migration_book.Book? book;

  /// מקור הספר
  final BookSource source;

  /// נתיב הקובץ (אם נמצא בתיקיות)
  final String? filePath;

  /// ID של הקטגוריה ב-DB (אם נמצא ב-DB)
  final int? categoryId;

  BookLocation({
    required this.book,
    required this.source,
    required this.filePath,
    required this.categoryId,
  });
}

/// מקור הספר
enum BookSource {
  /// ספר נמצא במסד הנתונים
  database,

  /// ספר נמצא במערכת הקבצים
  fileSystem,
}
