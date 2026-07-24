import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';

/// תוצאת העשרה — ערכים חדשים בלבד, ללא מוטציה ב-TextBook.
typedef EnrichedBookData = ({
  int? resolvedId,
  String? heCategories,
  String? author,
  String? heEra,
});

/// מעשיר מידע קטגוריה לספר ברקע משלוש מקורות: DB, metadata, ונתיב.
/// מחזיר [EnrichedBookData] עם הערכים החדשים — לא משנה את ה-book.
Future<EnrichedBookData> enrichHeCategories(TextBook book) async {
  if (book.heCategories != null && book.heCategories!.isNotEmpty) {
    // heCategories קיים — משלימים רק id ומחבר חסרים מה-DB
    return _tryGetIdAndAuthorFromDatabase(book);
  }

  try {
    final fromDb = await _tryLoadFromDatabase(book);
    if (fromDb != null) return fromDb;
    final fromMeta = await _tryLoadFromMetadata(book);
    if (fromMeta != null) return fromMeta;
    final fromPath = await _tryLoadFromPath(book);
    if (fromPath != null) return fromPath;
  } catch (e) {
    debugPrint('⚠️ Failed to enrich heCategories in background: $e');
  }
  return (resolvedId: null, heCategories: null, author: null, heEra: null);
}

Future<EnrichedBookData?> _tryLoadFromDatabase(TextBook book) async {
  final sqliteProvider = SqliteDataProvider.instance;
  if (!await sqliteProvider.databaseExists() && !book.isUserBook) {
    return null;
  }

  final resolvedBook = await BookDatabaseResolver.resolveBook(
    title: book.title,
    categoryId: book.categoryId,
    fileType: book.fileType,
    filePath: book.filePath,
    preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
      isUserBook: book.isUserBook,
      categoryPath: book.categoryPath,
    ),
  );
  if (resolvedBook == null) return null;

  final heCategories = await BookDatabaseResolver.buildCategoryPath(
    resolvedBook.repository,
    resolvedBook.book.categoryId,
  );
  final dbAuthors = resolvedBook.book.authors;
  return (
    resolvedId: resolvedBook.book.id,
    heCategories: heCategories,
    author: book.author == null && dbAuthors.isNotEmpty
        ? dbAuthors.first.name
        : null,
    heEra: null,
  );
}

/// משלים מה-DB רק id ומחבר חסרים, מבלי לשנות heCategories (כשהוא כבר קיים).
Future<EnrichedBookData> _tryGetIdAndAuthorFromDatabase(TextBook book) async {
  const EnrichedBookData empty = (
    resolvedId: null,
    heCategories: null,
    author: null,
    heEra: null,
  );
  if (book.id != null && book.author != null) return empty;
  final sqliteProvider = SqliteDataProvider.instance;
  if (!await sqliteProvider.databaseExists() && !book.isUserBook) {
    return empty;
  }
  try {
    final resolvedBook = await BookDatabaseResolver.resolveBook(
      title: book.title,
      categoryId: book.categoryId,
      fileType: book.fileType,
      filePath: book.filePath,
      preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
        isUserBook: book.isUserBook,
        categoryPath: book.categoryPath,
      ),
    );
    if (resolvedBook == null) return empty;
    final dbAuthors = resolvedBook.book.authors;
    return (
      resolvedId: book.id == null ? resolvedBook.book.id : null,
      heCategories: null,
      author: book.author == null && dbAuthors.isNotEmpty
          ? dbAuthors.first.name
          : null,
      heEra: null,
    );
  } catch (e) {
    debugPrint('⚠️ Failed to get book id/author from DB: $e');
    return empty;
  }
}

Future<EnrichedBookData?> _tryLoadFromMetadata(TextBook book) async {
  final metadata = await FileSystemData.instance.metadata;
  final bookMetadata = metadata[book.title];
  if (bookMetadata == null) return null;

  final heCategories = bookMetadata['heCategories'] as String?;
  final author = bookMetadata['author'] as String?;
  final heEra = bookMetadata['heEra'] as String?;

  if (heCategories != null && heCategories.isNotEmpty) {
    return (
      resolvedId: null,
      heCategories: heCategories,
      author: author,
      heEra: heEra,
    );
  }
  return null;
}

Future<EnrichedBookData?> _tryLoadFromPath(TextBook book) async {
  final titleToPath = await FileSystemData.instance.titleToPath;
  final bookPath = titleToPath[book.title];
  if (bookPath == null) return null;

  String? heCategories;
  if (bookPath.contains(Platform.pathSeparator)) {
    final pathParts = bookPath.split(Platform.pathSeparator);
    final otzariaIndex = pathParts.indexOf('אוצריא');
    if (otzariaIndex >= 0 && otzariaIndex < pathParts.length - 2) {
      heCategories = pathParts
          .sublist(otzariaIndex + 1, pathParts.length - 1)
          .join(', ');
    }
  } else {
    final normalized = bookPath
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join(', ');
    if (normalized.isNotEmpty) {
      heCategories = normalized;
    }
  }

  if (heCategories == null) return null;
  return (
    resolvedId: null,
    heCategories: heCategories,
    author: null,
    heEra: null,
  );
}
