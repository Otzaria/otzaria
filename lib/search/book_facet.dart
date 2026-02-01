import 'package:flutter/foundation.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

class BookFacet {
  BookFacet._();

  static String topicsToPath(String topics) {
    final t = topics.trim();
    if (t.isEmpty) return '';
    return '/${t.replaceAll(', ', '/')}';
  }

  static String buildFacetPath(
      {required String title, required String topics}) {
    final cleanTitle = title.trim();
    final topicsPath = topicsToPath(topics);
    return topicsPath.isEmpty ? '/$cleanTitle' : '$topicsPath/$cleanTitle';
  }

  static Future<String> resolveTopics({
    required String title,
    required String initialTopics,
    required Type? type,
    String? categoryPath,
  }) async {
    final t = initialTopics.trim();
    if (t.isNotEmpty) return t;

    try {
      // Try to find in library first
      final library = await DataRepository.instance.library;
      final book = library.findBookByTitle(title, type);
      if (book != null && book.topics.isNotEmpty) {
        debugPrint(
            '📚 BookFacet: Found book in library with topics: ${book.topics}');
        return book.topics;
      }

      // Fallback: try to get from database directly
      final sqliteProvider = SqliteDataProvider.instance;
      if (sqliteProvider.isInitialized) {
        final repository = sqliteProvider.repository;
        if (repository != null) {
          debugPrint('📚 BookFacet: Searching in DB for title: $title');

          final dbBook = await repository.getBookByTitle(title);
          if (dbBook != null) {
            // Try topics first
            final topics = dbBook.topics.map((t) => t.name).join(', ');
            if (topics.isNotEmpty) {
              debugPrint('📚 BookFacet: Found book in DB with topics: $topics');
              return topics;
            }

            // Fallback: build category path
            debugPrint(
                '📚 BookFacet: No topics, building category path for categoryId: ${dbBook.categoryId}');
            final categoryPath =
                await _buildCategoryPath(repository, dbBook.categoryId);
            if (categoryPath.isNotEmpty) {
              debugPrint('📚 BookFacet: Built category path: $categoryPath');
              return categoryPath;
            }
          } else {
            debugPrint('📚 BookFacet: Book not found in DB');
          }
        } else {
          debugPrint('📚 BookFacet: Repository is null');
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

  static Future<String> _buildCategoryPath(
      dynamic repository, int categoryId) async {
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
}
