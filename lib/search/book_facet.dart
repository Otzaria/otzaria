import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';

class BookFacet {
  BookFacet._();

  static String topicsToPath(String topics) {
    final t = topics.trim();
    if (t.isEmpty) return '';
    return '/${t.replaceAll(', ', '/')}';
  }

  static String resolveFacetCategoryPath({
    String? categoryPath,
    String? topics,
  }) {
    final normalizedCategoryPath = _normalizeCategoryPath(categoryPath);
    if (normalizedCategoryPath.isNotEmpty) {
      return normalizedCategoryPath;
    }

    final topicsPath = topicsToPath(topics ?? '');
    return _normalizeCategoryPath(topicsPath);
  }

  static String buildFacetPath(
      {required String title,
      required String topics,
      String? externalLibraryId,
      int? bookId,
      bool isUserBook = false,
      String? categoryPath,
      String? fileType,
      String? filePath}) {
    final categoryFacetPath = resolveFacetCategoryPath(
      categoryPath: categoryPath,
      topics: topics,
    );

    // בניית מפתח ייחודי לספר (אותה לוגיקה כמו IndexingRepository.catalogueOrderKey)
    String bookKey;
    if (externalLibraryId != null && externalLibraryId.isNotEmpty) {
      bookKey = 'ext:$externalLibraryId';
    } else if (bookId != null) {
      // id טבעי חופף בין שני ה-DB — ראה IndexingRepository.catalogueOrderKey.
      bookKey = isUserBook ? 'uid:$bookId' : 'id:$bookId';
    } else {
      final categoryKey = categoryPath ?? '';
      final fileTypeKey = fileType ?? '';
      final pathKey = filePath ?? '';
      bookKey = '$title|$categoryKey|$fileTypeKey|$pathKey';
    }

    return categoryFacetPath.isEmpty
        ? '/$bookKey'
        : '$categoryFacetPath/$bookKey';
  }

  static Future<String> resolveTopics({
    required String title,
    required String initialTopics,
    required Type? type,
    String? categoryPath,
    String? externalLibraryId,
    int? bookId,
    String? fileType,
    String? filePath,
  }) async {
    final t = initialTopics.trim();
    if (t.isNotEmpty) return t;

    try {
      // Try to find in library first
      final library = await DataRepository.instance.library;
      final book = findMatchingBook(
        library.getAllBooks(),
        title: title,
        type: type,
        categoryPath: categoryPath,
        externalLibraryId: externalLibraryId,
        bookId: bookId,
        fileType: fileType,
        filePath: filePath,
      );
      if (book != null && book.topics.isNotEmpty) {
        debugPrint(
            '📚 BookFacet: Found book in library with topics: ${book.topics}');
        return book.topics;
      }

      final normalizedCategoryTopics = _categoryPathToTopics(categoryPath);
      if (normalizedCategoryTopics.isNotEmpty) {
        debugPrint(
            '📚 BookFacet: Falling back to normalized category path: $normalizedCategoryTopics');
        return normalizedCategoryTopics;
      }

      // Fallback: try to get from database directly
      final sqliteProvider = SqliteDataProvider.instance;
      if (sqliteProvider.isInitialized) {
        final resolvedBook = bookId != null
            ? await BookDatabaseResolver.resolveBookById(
                bookId,
                preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
                  categoryPath: categoryPath,
                ),
              )
            : await BookDatabaseResolver.resolveBook(
                title: title,
                fileType: fileType,
                filePath: filePath,
                preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
                  categoryPath: categoryPath,
                ),
              );
        if (resolvedBook != null) {
          debugPrint('📚 BookFacet: Searching in DB for title: $title');

          final topics = resolvedBook.book.topics.map((t) => t.name).join(', ');
          if (topics.isNotEmpty) {
            debugPrint('📚 BookFacet: Found book in DB with topics: $topics');
            return topics;
          }

          debugPrint(
              '📚 BookFacet: No topics, building category path for categoryId: ${resolvedBook.book.categoryId}');
          final builtPath = await _buildCategoryPath(
            resolvedBook.repository,
            resolvedBook.book.categoryId,
          );
          if (builtPath.isNotEmpty) {
            debugPrint('📚 BookFacet: Built category path: $builtPath');
            return builtPath;
          }
        } else {
          debugPrint('📚 BookFacet: Book not found in DB');
        }
      } else {
        debugPrint('📚 BookFacet: SqliteProvider not initialized');
      }

      return '';
    } catch (e, stackTrace) {
      debugPrint('📚 BookFacet.resolveTopics error: $e');
      debugPrint('📚 BookFacet.resolveTopics stackTrace: $stackTrace');
      return '';
    }
  }

  /// מחזיר את הספר המתאים ביותר מתוך אוסף מועמדים עבור בניית facet.
  @visibleForTesting
  static Book? findMatchingBook(
    Iterable<Book> books, {
    required String title,
    required Type? type,
    String? categoryPath,
    String? externalLibraryId,
    int? bookId,
    String? fileType,
    String? filePath,
  }) {
    final candidates = books.where((book) {
      if (type != null && book.runtimeType != type) return false;
      return book.title == title;
    }).toList();

    if (candidates.isEmpty) {
      return null;
    }

    final normalizedFilePath = _normalizeText(filePath);
    final normalizedCategoryPath = _normalizeText(categoryPath);
    final normalizedFileType = _normalizeText(fileType);

    Book? matchWhere(bool Function(Book book) predicate) {
      for (final book in candidates) {
        if (predicate(book)) {
          return book;
        }
      }
      return null;
    }

    final byExternalId = matchWhere((book) =>
        _normalizeText(book.externalLibraryId) ==
            _normalizeText(externalLibraryId) &&
        _normalizeText(externalLibraryId).isNotEmpty);
    if (byExternalId != null) return byExternalId;

    final byBookId = matchWhere((book) => bookId != null && book.id == bookId);
    if (byBookId != null) return byBookId;

    final byFilePath = matchWhere(
      (book) =>
          normalizedFilePath.isNotEmpty &&
          _normalizeText(_bookFilePath(book)) == normalizedFilePath,
    );
    if (byFilePath != null) return byFilePath;

    final byCategoryAndType = matchWhere(
      (book) =>
          normalizedCategoryPath.isNotEmpty &&
          normalizedFileType.isNotEmpty &&
          _normalizeText(book.categoryPath) == normalizedCategoryPath &&
          _normalizeText(book.fileType) == normalizedFileType,
    );
    if (byCategoryAndType != null) return byCategoryAndType;

    final byCategory = matchWhere(
      (book) =>
          normalizedCategoryPath.isNotEmpty &&
          _normalizeText(book.categoryPath) == normalizedCategoryPath,
    );
    if (byCategory != null) return byCategory;

    final byFileType = matchWhere(
      (book) =>
          normalizedFileType.isNotEmpty &&
          _normalizeText(book.fileType) == normalizedFileType,
    );
    if (byFileType != null) return byFileType;

    return candidates.first;
  }

  static Future<String> _buildCategoryPath(
      SeforimRepository repository, int categoryId) async {
    try {
      final List<String> pathParts = [];
      int? currentId = categoryId;

      while (currentId != null) {
        final category = await repository.getCategory(currentId);
        if (category == null) break;

        pathParts.insert(0, category.title);
        currentId = category.parentId;
      }

      return pathParts.join(', ');
    } catch (e) {
      debugPrint('📚 BookFacet._buildCategoryPath error: $e');
      return '';
    }
  }

  static String _bookFilePath(Book book) {
    if (book is FileBook) {
      return book.path;
    }
    return book.filePath ?? '';
  }

  static String _categoryPathToTopics(String? categoryPath) {
    final raw = (categoryPath ?? '').trim();
    if (raw.isEmpty) return '';
    if (!raw.startsWith('/')) return raw;
    return raw.split('/').where((part) => part.isNotEmpty).join(', ');
  }

  static String _normalizeCategoryPath(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';

    final separatorPattern = RegExp(r'\s*(?:/|,)\s*');
    final parts =
        raw.split(separatorPattern).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    return '/${parts.join('/')}';
  }

  static String _normalizeText(String? value) => value?.trim() ?? '';
}
