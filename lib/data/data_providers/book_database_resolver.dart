import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/models/book_source.dart';

class ResolvedBookRepositoryCandidate {
  final SeforimRepository repository;
  final BookSource source;

  const ResolvedBookRepositoryCandidate({
    required this.repository,
    required this.source,
  });
}

class ResolvedDbBookRecord {
  final migration_models.Book book;
  final SeforimRepository repository;
  final BookSource source;

  const ResolvedDbBookRecord({
    required this.book,
    required this.repository,
    required this.source,
  });
}

class BookDatabaseResolver {
  static const String _personalRootTitle = 'ספרים אישיים';

  /// המקור המשוער של ספר: [source] כשאינו רשמי, אחרת אישי כשהנתיב שלו
  /// מתחיל בשורש 'ספרים אישיים' (ספר שהמקור שלו לא נשמר).
  static BookSource likelySource({
    BookSource source = BookSource.official,
    String? categoryPath,
  }) {
    if (!source.isOfficial) return source;
    return _isUnderPersonalRoot(categoryPath)
        ? BookSource.user
        : BookSource.official;
  }

  static bool _isUnderPersonalRoot(String? categoryPath) {
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
  /// [preferSource] נבדק ראשון; [officialOnly] מונע fallback ל-`user_books.db`.
  static Future<ResolvedDbBookRecord?> resolveBook({
    required String title,
    int? categoryId,
    String? fileType,
    String? filePath,
    BookSource preferSource = BookSource.official,
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
                source: BookSource.official,
              ),
            ];
    } else {
      candidates = await _loadRepositoryCandidates(preferSource: preferSource);
    }

    return resolveBookInCandidates(
      title: title,
      candidates: candidates,
      categoryId: categoryId,
      fileType: fileType,
      filePath: filePath,
    );
  }

  /// מאתר ספר ב-DB לפי `bookId` במסד של [source] בלבד — מרחבי ה-id של
  /// המסדים חופפים, ולכן הקורא חייב לדעת את המקור.
  static Future<ResolvedDbBookRecord?> resolveBookById(
    int bookId, {
    BookSource source = BookSource.official,
  }) async {
    final repository = await _loadRepositoryFor(source);
    if (repository == null) return null;
    final book = await repository.getBook(bookId);
    if (book == null) return null;
    return ResolvedDbBookRecord(
      book: book,
      repository: repository,
      source: source,
    );
  }

  static Future<List<ResolvedBookRepositoryCandidate>>
  loadRepositoryCandidates({BookSource preferSource = BookSource.official}) {
    return _loadRepositoryCandidates(preferSource: preferSource);
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
      if (candidate.source.isUser &&
          normalizedFilePath != null &&
          normalizedFilePath.isNotEmpty) {
        final bookByPath = await repository.getExternalBookByFilePath(
          normalizedFilePath,
        );
        if (bookByPath != null) {
          return ResolvedDbBookRecord(
            book: bookByPath,
            repository: repository,
            source: candidate.source,
          );
        }
      }

      if (candidate.source.isUser &&
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
            source: candidate.source,
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
            source: candidate.source,
          );
        }
      }

      final bookByTitle = await repository.getBookByTitle(title);
      if (bookByTitle != null) {
        return ResolvedDbBookRecord(
          book: bookByTitle,
          repository: repository,
          source: candidate.source,
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

  /// מועמדי המסדים לפי הסדר: [preferSource] תחילה, ואחריו רשמי ואז אישי.
  /// מסד מצורף אינו נופל לשאר המסדים — ספר בשם זהה שם הוא ספר אחר.
  static Future<List<ResolvedBookRepositoryCandidate>>
  _loadRepositoryCandidates({required BookSource preferSource}) async {
    final order = preferSource.isAttached
        ? <BookSource>{preferSource}
        : <BookSource>{preferSource, BookSource.official, BookSource.user};
    final candidates = <ResolvedBookRepositoryCandidate>[];
    for (final source in order) {
      final repository = await _loadRepositoryFor(source);
      if (repository != null) {
        candidates.add(
          ResolvedBookRepositoryCandidate(
            repository: repository,
            source: source,
          ),
        );
      }
    }
    return candidates;
  }

  /// המאגר של [source], או null כשהמסד אינו קיים או אינו נגיש.
  static Future<SeforimRepository?> _loadRepositoryFor(BookSource source) {
    return switch (source) {
      OfficialBookSource() => _loadOfficialRepository(),
      UserBookSource() => _loadUserBooksRepositoryIfExists(),
      AttachedBookSource(:final slug) =>
        AttachedLibraryRegistry.instance.repositoryFor(slug),
    };
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
