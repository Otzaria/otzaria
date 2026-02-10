import 'dart:io';

import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/core/models/book.dart' as migration_models;
import 'package:otzaria/models/books.dart';

/// שירות מרכזי להפקת פרטי ספר לתצוגה/דיווח מתוך DB.
class BookDetailsService {
  static const String bookNotFoundText = 'לא ניתן למצוא את הספר';

  /// מחזיר פרטי ספר בפורמט אחיד:
  /// - שם הקובץ
  /// - נתיב הקובץ
  /// - תיקיית המקור
  Future<Map<String, String>> getBookDetails(Book book) async {
    final details = <String, String>{
      'שם הקובץ': bookNotFoundText,
      'נתיב הקובץ': bookNotFoundText,
      'תיקיית המקור': bookNotFoundText,
    };

    final dbBook = await _tryGetDbBook(book);
    final dbSource = await _tryGetDbSourceName(dbBook);

    final fileType = _resolveFileType(book, dbBook);
    final inferredName = _inferFileName(
      title: book.title,
      fileType: fileType,
      rawPath: dbBook?.filePath ?? book.filePath,
    );

    final resolvedPath = _resolveFilePath(
      rawPath: dbBook?.filePath ?? book.filePath,
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
    if (dbSource != null && dbSource.isNotEmpty) {
      details['תיקיית המקור'] = dbSource;
    }

    return details;
  }

  Future<migration_models.Book?> _tryGetDbBook(Book book) async {
    try {
      final provider = SqliteDataProvider.instance;
      await provider.initialize();
      final repo = provider.repository;
      if (repo == null) return null;
      return await repo.getBookByTitle(book.title);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryGetDbSourceName(migration_models.Book? dbBook) async {
    if (dbBook == null) return null;
    try {
      final provider = SqliteDataProvider.instance;
      final repo = provider.repository;
      if (repo == null) return null;
      final source = await repo.getSourceById(dbBook.sourceId);
      return source?.name.trim();
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
      final candidate =
          slash >= 0 ? normalizedRaw.substring(slash + 1) : normalizedRaw;
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
    if (path.length > 2 && path[1] == ':' && path[2] == Platform.pathSeparator) {
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
