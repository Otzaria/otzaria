import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as db_models;

class ResolvedBookRepositoryCandidate {
  final SeforimRepository repository;
  final bool isUserBooks;

  const ResolvedBookRepositoryCandidate({
    required this.repository,
    required this.isUserBooks,
  });
}

class ResolvedDbBookRecord {
  final migration_models.Book book;
  final SeforimRepository repository;
  final bool isUserBooks;

  const ResolvedDbBookRecord({
    required this.book,
    required this.repository,
    required this.isUserBooks,
  });
}

class BookDatabaseResolver {
  static const String _personalRootTitle = 'ספרים אישיים';

  static bool isLikelyUserBook({
    bool isUserBook = false,
    String? categoryPath,
  }) {
    if (isUserBook) return true;
    if (categoryPath == null || categoryPath.trim().isEmpty) {
      return false;
    }

    final normalized = categoryPath
        .replaceAll('\\', '/')
        .replaceAll(', ', '/')
        .replaceAll(',', '/')
        .trim();
    if (normalized.isEmpty) {
      return false;
    }

    final firstSegment = normalized
        .split('/')
        .map((segment) => segment.trim())
        .firstWhere((segment) => segment.isNotEmpty, orElse: () => '');
    return firstSegment == _personalRootTitle;
  }

  /// מאתר ספר לפי מאפייניו במסדי הספרייה.
  ///
  /// [officialOnly] מונע fallback ל-`user_books.db`.
  static Future<ResolvedDbBookRecord?> resolveBook({
    required String title,
    int? categoryId,
    String? fileType,
    String? filePath,
    bool preferUserBooks = false,
    bool officialOnly = false,
  }) async {
    final List<ResolvedBookRepositoryCandidate> candidates;
    if (officialOnly) {
      final repository = await _loadOfficialRepository();
      candidates = repository == null
          ? const <ResolvedBookRepositoryCandidate>[]
          : <ResolvedBookRepositoryCandidate>[
              ResolvedBookRepositoryCandidate(
                repository: repository,
                isUserBooks: false,
              ),
            ];
    } else {
      candidates = await _loadRepositoryCandidates(
        preferUserBooks: preferUserBooks,
      );
    }

    return resolveBookInCandidates(
      title: title,
      candidates: candidates,
      categoryId: categoryId,
      fileType: fileType,
      filePath: filePath,
    );
  }

  /// מאתר ספר ב-DB לפי `bookId`.
  ///
  /// [isUserBook] קובע באיזה DB לחפש. ב-`true` → `user_books.db`,
  /// אחרת → `seforim.db`. אין יותר זיהוי לפי טווח-ID (offset), ולכן הקורא
  /// חייב לדעת את המקור (בד"כ מ-`Book.isUserBook`).
  ///
  /// [preferUserBooks] משמר את התנהגות ה-fallback ההיסטורית במקרים שבהם
  /// [isUserBook] לא מסופק או false אבל הספר עשוי להיות ב-user_books.
  static Future<ResolvedDbBookRecord?> resolveBookById(
    int bookId, {
    bool isUserBook = false,
    bool preferUserBooks = false,
  }) async {
    if (isUserBook) {
      final repository = await _loadUserBooksRepositoryIfExists();
      if (repository == null) return null;
      final book = await repository.getBook(bookId);
      if (book == null) return null;
      return ResolvedDbBookRecord(
        book: book,
        repository: repository,
        isUserBooks: true,
      );
    }

    final candidates = <ResolvedBookRepositoryCandidate>[];
    if (preferUserBooks) {
      final userBooksRepository = await _loadUserBooksRepositoryIfExists();
      if (userBooksRepository != null) {
        candidates.add(
          ResolvedBookRepositoryCandidate(
            repository: userBooksRepository,
            isUserBooks: true,
          ),
        );
      }
    } else {
      final officialRepository = await _loadOfficialRepository();
      if (officialRepository != null) {
        candidates.add(
          ResolvedBookRepositoryCandidate(
            repository: officialRepository,
            isUserBooks: false,
          ),
        );
      }
    }

    for (final candidate in candidates) {
      final book = await candidate.repository.getBook(bookId);
      if (book != null) {
        return ResolvedDbBookRecord(
          book: book,
          repository: candidate.repository,
          isUserBooks: candidate.isUserBooks,
        );
      }
    }

    return null;
  }

  static Future<List<ResolvedBookRepositoryCandidate>>
  loadRepositoryCandidates({
    bool preferUserBooks = false,
  }) {
    return _loadRepositoryCandidates(preferUserBooks: preferUserBooks);
  }

  @visibleForTesting
  static Future<ResolvedDbBookRecord?> resolveBookInCandidates({
    required String title,
    required List<ResolvedBookRepositoryCandidate> candidates,
    int? categoryId,
    String? fileType,
    String? filePath,
  }) async {
    final normalizedFileType = fileType?.trim().toLowerCase();
    final normalizedFilePath = filePath?.trim();

    for (final candidate in candidates) {
      final repository = candidate.repository;
      // categoryId טבעי לשני ה-DBs — אין יותר צורך בהמרה. אם הקורא העביר
      // categoryId שייך ל-seforim ואנחנו ב-candidate של user_books, החיפוש
      // פשוט יחזיר null וננסה את המועמד הבא.
      final candidateCategoryId = categoryId;

      // filePath ו-fileType שייכים רק לסכמת user_books; ל-seforim.db v3 אין
      // עמודות אלה, ולכן מריצים את החיפושים האלה רק על מועמד user_books.
      if (candidate.isUserBooks &&
          normalizedFilePath != null &&
          normalizedFilePath.isNotEmpty) {
        final bookByPath = await repository.getExternalBookByFilePath(
          normalizedFilePath,
        );
        if (bookByPath != null) {
          return ResolvedDbBookRecord(
            book: bookByPath,
            repository: repository,
            isUserBooks: candidate.isUserBooks,
          );
        }
      }

      if (candidate.isUserBooks &&
          candidateCategoryId != null &&
          normalizedFileType != null &&
          normalizedFileType.isNotEmpty) {
        final bookByCompositeKey = await repository
            .getBookByTitleCategoryAndFileType(
              title,
              candidateCategoryId,
              normalizedFileType,
            );
        if (bookByCompositeKey != null) {
          return ResolvedDbBookRecord(
            book: bookByCompositeKey,
            repository: repository,
            isUserBooks: candidate.isUserBooks,
          );
        }
      }

      if (candidateCategoryId != null) {
        final bookByCategory = await repository.getBookByTitleAndCategory(
          title,
          candidateCategoryId,
        );
        if (bookByCategory != null) {
          return ResolvedDbBookRecord(
            book: bookByCategory,
            repository: repository,
            isUserBooks: candidate.isUserBooks,
          );
        }
      }

      final bookByTitle = await repository.getBookByTitle(title);
      if (bookByTitle != null) {
        return ResolvedDbBookRecord(
          book: bookByTitle,
          repository: repository,
          isUserBooks: candidate.isUserBooks,
        );
      }
    }

    return null;
  }

  static Future<String> buildCategoryPath(
    SeforimRepository repository,
    int categoryId,
  ) async {
    final categoriesById = <int, db_models.Category>{};
    final pathParts = <String>[];
    final visited = <int>{};
    int? currentId = categoryId;

    while (currentId != null && visited.add(currentId)) {
      var category = categoriesById[currentId];
      category ??= await repository.getCategory(currentId);
      if (category == null) {
        break;
      }

      categoriesById[category.id] = category;
      pathParts.insert(0, category.title);
      currentId = category.parentId;
    }

    return pathParts.join(', ');
  }

  static Future<List<ResolvedBookRepositoryCandidate>>
  _loadRepositoryCandidates({
    required bool preferUserBooks,
  }) async {
    final candidates = <ResolvedBookRepositoryCandidate>[];

    final officialRepository = await _loadOfficialRepository();
    final userBooksRepository = await _loadUserBooksRepositoryIfExists();

    if (preferUserBooks) {
      if (userBooksRepository != null) {
        candidates.add(
          ResolvedBookRepositoryCandidate(
            repository: userBooksRepository,
            isUserBooks: true,
          ),
        );
      }
      if (officialRepository != null) {
        candidates.add(
          ResolvedBookRepositoryCandidate(
            repository: officialRepository,
            isUserBooks: false,
          ),
        );
      }
      return candidates;
    }

    if (officialRepository != null) {
      candidates.add(
        ResolvedBookRepositoryCandidate(
          repository: officialRepository,
          isUserBooks: false,
        ),
      );
    }
    if (userBooksRepository != null) {
      candidates.add(
        ResolvedBookRepositoryCandidate(
          repository: userBooksRepository,
          isUserBooks: true,
        ),
      );
    }
    return candidates;
  }

  static Future<SeforimRepository?> _loadOfficialRepository() async {
    final provider = SqliteDataProvider.instance;
    if (!provider.isInitialized) {
      await provider.initialize();
    }
    return provider.repository;
  }

  static Future<SeforimRepository?> _loadUserBooksRepositoryIfExists() async {
    final userBooksDbPath = await UserBooksDatabaseHolder.resolveDbPath();
    if (!await File(userBooksDbPath).exists()) {
      return null;
    }

    return UserBooksDatabaseHolder.instance.repository;
  }
}
