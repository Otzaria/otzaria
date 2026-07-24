import 'dart:io';

import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/models/books.dart';

/// המידע הזמין על ספר להצגה למשתמש.
class BookInformation {
  final Book book;
  final migration_models.Book? databaseBook;
  final String? source;
  final String? generation;
  final Map<String, String> fileDetails;

  const BookInformation({
    required this.book,
    required this.databaseBook,
    required this.source,
    required this.generation,
    required this.fileDetails,
  });

  /// התיאור הקצר, אם קיים.
  String? get shortDescription => _firstAvailable(
    book.heShortDesc,
    databaseBook?.heShortDesc,
  );

  /// התיאור המלא, אם קיים.
  String? get fullDescription => _firstAvailable(
    databaseBook?.heDesc,
    book.heDesc,
  );

  /// שמות המחברים, אם קיימים.
  List<String> get authors {
    final databaseAuthors =
        databaseBook?.authors
            .map((author) => author.name.trim())
            .where((name) => name.isNotEmpty)
            .toList() ??
        const <String>[];
    if (databaseAuthors.isNotEmpty) return databaseAuthors;
    final author = book.author?.trim();
    return author == null || author.isEmpty ? const [] : [author];
  }

  /// הנושאים המשויכים לספר במסד הנתונים.
  List<String> get topics =>
      databaseBook?.topics
          .map((topic) => topic.name.trim())
          .where((name) => name.isNotEmpty)
          .toList() ??
      const <String>[];

  /// מקומות הפרסום, אם קיימים.
  List<String> get publicationPlaces {
    final places =
        databaseBook?.pubPlaces
            .map((place) => place.name.trim())
            .where((name) => name.isNotEmpty)
            .toList() ??
        const <String>[];
    if (places.isNotEmpty) return places;
    return _compactValues([book.pubPlaceStringHe, book.pubPlace]);
  }

  /// תאריכי הפרסום, אם קיימים.
  List<String> get publicationDates {
    final dates =
        databaseBook?.pubDates
            .map((date) => date.date.trim())
            .where((date) => date.isNotEmpty)
            .toList() ??
        const <String>[];
    if (dates.isNotEmpty) return dates;
    return _compactValues([book.pubDateStringHe, book.pubDate]);
  }

  /// הקטגוריות, אם קיימות.
  String? get categories =>
      _firstAvailable(book.heCategories, book.categoryPath);

  /// המזהה העברי של הספר במסד, אם קיים.
  String? get reference => _firstAvailable(databaseBook?.heRef);

  /// מספר שורות התוכן, אם זמין.
  int? get lineCount => databaseBook?.totalLines;

  static String? _firstAvailable(String? first, [String? second]) {
    final firstValue = first?.trim();
    if (firstValue != null && firstValue.isNotEmpty) return firstValue;
    final secondValue = second?.trim();
    return secondValue == null || secondValue.isEmpty ? null : secondValue;
  }

  static List<String> _compactValues(Iterable<String?> values) {
    return values
        .map((value) => value?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }
}

/// שירות מרכזי להפקת פרטי ספר לתצוגה/דיווח מתוך DB.
class BookDetailsService {
  static const String bookNotFoundText = 'לא ניתן למצוא את הספר';
  static const String _customFolderSourcePrefix = 'Personal::';

  /// מחזיר את כל המידע הזמין על הספר לתצוגת "אודות הספר".
  Future<BookInformation> getBookInformation(Book book) async {
    final resolvedBook = await _tryResolveDbBook(book);
    final databaseBook = resolvedBook?.book;
    final source = await _tryGetDbSourceName(resolvedBook);
    final generation = await _tryGetGeneration(resolvedBook);
    final fileDetails = _buildFileDetails(book, databaseBook, source);

    return BookInformation(
      book: book,
      databaseBook: databaseBook,
      source: source,
      generation: generation,
      fileDetails: fileDetails,
    );
  }

  /// מחזיר פרטי ספר בפורמט אחיד:
  /// - שם הקובץ
  /// - נתיב הקובץ
  /// - תיקיית המקור
  Future<Map<String, String>> getBookDetails(Book book) async {
    return (await getBookInformation(book)).fileDetails;
  }

  Map<String, String> _buildFileDetails(
    Book book,
    migration_models.Book? databaseBook,
    String? source,
  ) {
    final details = <String, String>{
      'שם הקובץ': bookNotFoundText,
      'נתיב הקובץ': bookNotFoundText,
      'תיקיית המקור': bookNotFoundText,
    };

    final fileType = _resolveFileType(book, databaseBook);
    final inferredName = _inferFileName(
      title: book.title,
      fileType: fileType,
      rawPath: databaseBook?.filePath ?? book.filePath,
    );

    final resolvedPath = _resolveFilePath(
      rawPath: databaseBook?.filePath ?? book.filePath,
      fileType: fileType,
      inferredFileName: inferredName,
      categoryPath: book.categoryPath,
    );

    if (inferredName != null && inferredName.isNotEmpty) {
      details['שם הקובץ'] = inferredName;
    }
    if (resolvedPath != null && resolvedPath.isNotEmpty) {
      details['נתיב הקובץ'] = resolvedPath;
    }
    if (source != null && source.isNotEmpty) {
      details['תיקיית המקור'] = source;
    }

    return details;
  }

  Future<ResolvedDbBookRecord?> _tryResolveDbBook(Book book) async {
    try {
      return await BookDatabaseResolver.resolveBook(
        title: book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
        filePath: book.filePath,
        preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
          isUserBook: book.isUserBook,
          categoryPath: book.categoryPath,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryGetDbSourceName(
    ResolvedDbBookRecord? resolvedBook,
  ) async {
    if (resolvedBook == null) return null;
    try {
      final source = await resolvedBook.repository.getSourceById(
        resolvedBook.book.sourceId,
      );
      final sourceName = source?.name.trim();
      if (sourceName == null || sourceName.isEmpty) {
        return null;
      }
      if (sourceName.startsWith(_customFolderSourcePrefix)) {
        return sourceName.substring(_customFolderSourcePrefix.length);
      }
      return sourceName;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryGetGeneration(
    ResolvedDbBookRecord? resolvedBook,
  ) async {
    if (resolvedBook == null) return null;
    try {
      return (await resolvedBook.repository.getBookGenerationInfo(
        resolvedBook.book.id,
      ))?.generationName;
    } catch (_) {
      return null;
    }
  }

  String _resolveFileType(Book book, migration_models.Book? dbBook) {
    final dbType = dbBook?.fileType?.trim();
    if (dbType != null && dbType.isNotEmpty) return dbType;

    final appType = book.fileType?.trim();
    if (appType != null && appType.isNotEmpty) return appType;

    return 'txt';
  }

  String? _inferFileName({
    required String title,
    required String fileType,
    String? rawPath,
  }) {
    final normalizedRaw = _normalizeSeparators(rawPath);
    if (normalizedRaw != null && normalizedRaw.isNotEmpty) {
      final slash = normalizedRaw.lastIndexOf('/');
      final candidate = slash >= 0
          ? normalizedRaw.substring(slash + 1)
          : normalizedRaw;
      if (candidate.isNotEmpty) {
        final withExt = _ensureExtension(candidate, fileType);
        return withExt;
      }
    }

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;
    return _ensureExtension(cleanTitle, fileType);
  }

  String? _resolveFilePath({
    String? rawPath,
    required String fileType,
    required String? inferredFileName,
    required String? categoryPath,
  }) {
    final normalizedRaw = _normalizeSeparators(rawPath);
    if (normalizedRaw != null && normalizedRaw.isNotEmpty) {
      final pathWithExt = _ensurePathHasExtension(normalizedRaw, fileType);
      if (_isAbsolutePath(pathWithExt)) {
        return pathWithExt;
      }
      if (pathWithExt.startsWith('אוצריא/')) {
        return pathWithExt;
      }
      return 'אוצריא/$pathWithExt';
    }

    if (inferredFileName == null || inferredFileName.isEmpty) {
      return null;
    }

    final normalizedCategory = _normalizeCategoryPath(categoryPath);
    if (normalizedCategory == null || normalizedCategory.isEmpty) {
      return inferredFileName;
    }

    return 'אוצריא/$normalizedCategory/$inferredFileName';
  }

  String? _normalizeSeparators(String? path) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceAll('\\', '/');
  }

  String _ensureExtension(String value, String fileType) {
    if (value.contains('.') && !value.endsWith('.')) return value;
    final type = fileType.trim();
    if (type.isEmpty) return value;
    return '$value.$type';
  }

  String _ensurePathHasExtension(String path, String fileType) {
    final lastSlash = path.lastIndexOf('/');
    final fileName = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    final hasDot = fileName.contains('.');
    if (hasDot) return path;
    return _ensureExtension(path, fileType);
  }

  bool _isAbsolutePath(String path) {
    if (path.startsWith('/')) return true;
    if (path.length > 2 &&
        path[1] == ':' &&
        path[2] == Platform.pathSeparator) {
      return true;
    }
    return false;
  }

  String? _normalizeCategoryPath(String? rawCategoryPath) {
    if (rawCategoryPath == null) return null;
    final trimmed = rawCategoryPath.trim();
    if (trimmed.isEmpty) return null;

    final slashNormalized = trimmed
        .replaceAll('\\', '/')
        .replaceAll(', ', '/')
        .replaceAll(',', '/');
    final parts = slashNormalized
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return null;
    return parts.join('/');
  }
}
