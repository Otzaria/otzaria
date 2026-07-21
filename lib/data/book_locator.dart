import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_book;

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
    int? categoryId,
    String? fileType,
  }) async {
    try {
      // קודם ננסה למצוא ב-DB
      final dbLocation = await _locateInDatabase(
        bookTitle,
        category,
        categoryId: categoryId,
        fileType: fileType,
      );
      if (dbLocation != null) {
        return dbLocation;
      }

      // אם לא נמצא ב-DB, נחפש בתיקיות
      final fileLocation = await _locateInFileSystem(
        bookTitle,
        category,
        categoryId: categoryId,
      );
      return fileLocation;
    } catch (e) {
      debugPrint('❌ Error locating book "$bookTitle": $e');
      return null;
    }
  }

  /// איתור ספר במסד הנתונים
  static Future<BookLocation?> _locateInDatabase(
    String bookTitle,
    Category? category, {
    int? categoryId,
    String? fileType,
  }) async {
    try {
      if (categoryId != null) {
        // fileType קריטי כשלספר יש "תאום" באותה כותרת וקטגוריה בסוג קובץ
        // אחר (EPUB לצד PDF) — בלעדיו נשלפת השורה הראשונה שנמצאה.
        final resolved = await BookDatabaseResolver.resolveBook(
          title: bookTitle,
          categoryId: categoryId,
          fileType: fileType,
          preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
            categoryPath: category?.path,
          ),
        );
        if (resolved != null) {
          return BookLocation(
            book: resolved.book,
            source: BookSource.database,
            filePath: null,
            categoryId: resolved.book.categoryId,
            repository: resolved.repository,
            isUserBooks: resolved.isUserBooks,
          );
        }

        return null;
      }

      // אם יש קטגוריה, נחפש לפי קטגוריה
      if (category != null) {
        final candidate = await _findBookInDatabaseByCategory(
          bookTitle,
          category,
        );
        if (candidate != null) {
          return BookLocation(
            book: candidate.book,
            source: BookSource.database,
            filePath: null,
            categoryId: candidate.book.categoryId,
            repository: candidate.repository,
            isUserBooks: candidate.isUserBooks,
          );
        }

        return null;
      }

      // אם לא מצאנו לפי קטגוריה, נחפש לפי שם בלבד
      final resolved = await BookDatabaseResolver.resolveBook(
        title: bookTitle,
      );
      if (resolved != null) {
        return BookLocation(
          book: resolved.book,
          source: BookSource.database,
          filePath: null,
          categoryId: resolved.book.categoryId,
          repository: resolved.repository,
          isUserBooks: resolved.isUserBooks,
        );
      }
    } catch (e) {
      debugPrint('❌ Error searching in database: $e');
    }

    return null;
  }

  /// חיפוש ספר במסד הנתונים לפי קטגוריה
  static Future<ResolvedDbBookRecord?> _findBookInDatabaseByCategory(
    String bookTitle,
    Category category,
  ) async {
    try {
      final preferUserBooks = BookDatabaseResolver.isLikelyUserBook(
        categoryPath: category.path,
      );
      final repositories = await BookDatabaseResolver.loadRepositoryCandidates(
        preferUserBooks: preferUserBooks,
      );

      for (final candidate in repositories) {
        final categories = await candidate.repository.getRootCategories();
        final categoryId = await _findCategoryIdByPath(
          candidate.repository,
          categories,
          category.path,
        );

        if (categoryId == null) {
          continue;
        }

        final booksInCategory = await candidate.repository.getBooksByCategory(
          categoryId,
        );
        for (final dbBook in booksInCategory) {
          if (dbBook.title == bookTitle) {
            return ResolvedDbBookRecord(
              book: dbBook,
              repository: candidate.repository,
              isUserBooks: candidate.isUserBooks,
            );
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
    Category? category, {
    int? categoryId,
  }) async {
    try {
      final keyToPath = await FileSystemLibraryProvider.instance.keyToPath;
      String? filePath;

      final resolvedCategoryId =
          categoryId ??
          category?.path
              .split('/')
              .where((part) => part.isNotEmpty)
              .join(', ')
              .hashCode;

      if (resolvedCategoryId != null) {
        for (final entry in keyToPath.entries) {
          final key = BookCompositeKey.tryParse(entry.key);
          if (key == null) continue;
          if (key.title == bookTitle && key.categoryId == resolvedCategoryId) {
            filePath = entry.value;
            break;
          }
        }

        if (filePath == null) {
          return null;
        }
      }

      // If not found or no category, try fuzzy match by title
      if (filePath == null) {
        for (final entry in keyToPath.entries) {
          final key = BookCompositeKey.tryParse(entry.key);
          if (key == null) continue;
          if (key.title == bookTitle) {
            filePath = entry.value;
            break;
          }
        }
      }

      if (filePath == null) {
        return null;
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

  /// מחיקת ספר (מ-DB או מהקובץ)
  ///
  /// [bookTitle] - שם הספר
  /// [category] - הקטגוריה שבה נמצא הספר (אופציונלי)
  ///
  /// מחזיר true אם המחיקה הצליחה, false אחרת
  static Future<bool> deleteBook(
    String bookTitle, {
    Category? category,
    int? categoryId,
  }) async {
    try {
      final location = await locateBook(
        bookTitle,
        category: category,
        categoryId: categoryId,
      );
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
  ///
  /// מותרת **רק** לספרי `user_books.db` (ספרים אישיים, DB כתיב). הספרייה
  /// הרשמית (`seforim.db`) היא read-only ואינה ניתנת למחיקה — ניסיון למחוק
  /// ספר רשמי מסורב.
  static Future<bool> _deleteFromDatabase(BookLocation location) async {
    final repository = location.repository;
    if (repository == null || location.book == null) {
      return false;
    }

    if (!location.isUserBooks) {
      debugPrint(
        '⛔ Refusing to delete official (read-only) book: '
        '${location.book!.title}',
      );
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
    int? categoryId,
  }) async {
    final location = await locateBook(
      bookTitle,
      category: category,
      categoryId: categoryId,
    );
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
    int? categoryId,
    String? fileType,
  }) async {
    final location = await locateBook(
      bookTitle,
      category: category,
      categoryId: categoryId,
      fileType: fileType,
    );
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

  /// ה-repository שבו הספר נמצא בפועל.
  final SeforimRepository? repository;

  /// האם הספר נמצא ב-`user_books.db` (כתיב) ולא ב-`seforim.db` הרשמי
  /// (read-only). קובע אם מחיקה יכולה לרוץ ישירות על [repository] או שהיא
  /// חייבת לעבור דרך write-session.
  final bool isUserBooks;

  BookLocation({
    required this.book,
    required this.source,
    required this.filePath,
    required this.categoryId,
    this.repository,
    this.isUserBooks = false,
  });
}

/// מקור הספר
enum BookSource {
  /// ספר נמצא במסד הנתונים
  database,

  /// ספר נמצא במערכת הקבצים
  fileSystem,
}
