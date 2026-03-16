import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/utils/docx_to_otzaria.dart';
import 'package:otzaria/utils/toc_parser.dart';
import 'dart:io';
import 'dart:isolate';
import 'package:otzaria/migration/dao/sqflite/sqlite3_utils.dart';

class TextBookRepository {
  final FileSystemData _fileSystem;
  final SqliteDataProvider _sqliteProvider;

  TextBookRepository({
    required FileSystemData fileSystem,
    SqliteDataProvider? sqliteProvider,
  })  : _fileSystem = fileSystem,
        _sqliteProvider = sqliteProvider ?? SqliteDataProvider.instance;

  Future<String> getBookContent(TextBook book) async {
    // Primary path: go through the provider manager (handles file system + DB).
    // This can fail early in app startup because some providers require catalog caching.
    final title = book.title;
    final categoryId = book.categoryId;
    final fileType = book.fileType ?? 'txt';

    final providerText = await LibraryProviderManager.instance.getBookText(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (providerText != null && providerText.isNotEmpty) {
      return providerText;
    }

    // Fallback: read directly from the database (doesn't require provider caches).
    final dbBook = await BookLocator.getBookFromDatabase(
      title,
      category: book.category,
    );
    if (dbBook != null) {
      // Best-effort enrichment for subsequent calls.
      book.fileType ??= dbBook.fileType;
      book.filePath ??= dbBook.filePath;

      if (dbBook.isFileBacked && dbBook.filePath != null) {
        final file = File(dbBook.filePath!);
        if (await file.exists()) {
          final ext = (dbBook.fileType ?? '').toLowerCase();
          if (ext == 'docx') {
            final bytes = await file.readAsBytes();
            return await Isolate.run(() => docxToText(bytes, title));
          }
          return await file.readAsString();
        }
      }

      final dbText = await _sqliteProvider.getBookTextFromDb(
        title,
        dbBook.categoryId,
        dbBook.fileType,
      );
      if (dbText != null && dbText.isNotEmpty) {
        return dbText;
      }
    }

    // Last resort: keep existing behavior.
    return '';
  }

  Future<List<Link>> getBookLinks(TextBook book) async {
    // Primary path: via provider manager routing.
    // This can fail early in startup if the provider mapping cache isn't ready yet.
    final providerLinks = await book.links;
    if (providerLinks.isNotEmpty) {
      return providerLinks;
    }

    // Fallback: query links directly from the DB without relying on provider caches.
    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return const [];
    }

    final dbBook = await BookLocator.getBookFromDatabase(
      book.title,
      category: book.category,
    );
    if (dbBook == null) {
      return const [];
    }

    try {
      final db = await repository.database.database;

      final result = db.select('''
        SELECT 
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tb.title as targetBookTitle,
          ct.name as connectionTypeName
        FROM link l
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.sourceBookId = ?
        ORDER BY sl.lineIndex, tb.orderIndex
      ''', [dbBook.id]).toMapList();

      return result.map((row) {
        final targetTitle = row['targetBookTitle'] as String;
        final connectionType =
            row['connectionTypeName'] as String? ?? 'reference';

        return Link(
          // Historically this value came from CSV; for DB we keep a stable, non-empty label.
          heRef: targetTitle,
          index1: (row['sourceLineIndex'] as int) + 1,
          path2: targetTitle,
          index2: (row['targetLineIndex'] as int) + 1,
          connectionType: connectionType,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    final title = book.title;
    final categoryId = book.categoryId;
    final fileType = book.fileType ?? 'txt';

    final providerToc = await LibraryProviderManager.instance.getBookToc(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (providerToc != null && providerToc.isNotEmpty) {
      return providerToc;
    }

    // Fallback: fetch TOC directly from DB or parse it for external books.
    final dbBook = await BookLocator.getBookFromDatabase(
      title,
      category: book.category,
    );
    if (dbBook != null) {
      book.fileType ??= dbBook.fileType;
      book.filePath ??= dbBook.filePath;

      if (dbBook.isFileBacked && dbBook.filePath != null) {
        final file = File(dbBook.filePath!);
        if (await file.exists()) {
          final ext = (dbBook.fileType ?? '').toLowerCase();
          final String content;
          if (ext == 'docx') {
            final bytes = await file.readAsBytes();
            content = await Isolate.run(() => docxToText(bytes, title));
          } else {
            content = await file.readAsString();
          }
          if (content.isNotEmpty) {
            return await Isolate.run(
                () => TocParser.parseEntriesFromContent(content));
          }
        }
      }

      final dbToc = await _sqliteProvider.getBookTocFromDb(
        title,
        dbBook.categoryId,
        dbBook.fileType,
      );
      if (dbToc != null && dbToc.isNotEmpty) {
        return dbToc;
      }
    }

    return [];
  }

  /// מחזיר רשימת פרשנים זמינים לספר מה-DB
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return [];
    }

    // מקבל את ה-book מה-DB לפי שם וקטגוריה
    final dbBook = await BookLocator.getBookFromDatabase(
      book.title,
      category: book.category,
    );
    if (dbBook == null) {
      return [];
    }

    // שולף את הפרשנים ישירות מה-DB
    final commentatorsData =
        await repository.database.linkDao.selectCommentatorsByBook(dbBook.id);

    // ממפה לרשימת שמות ייחודיים
    final commentatorTitles = commentatorsData
        .map((row) => row['targetBookTitle'] as String)
        .toSet()
        .toList();

    commentatorTitles.sort((a, b) => a.compareTo(b));
    return commentatorTitles;
  }

  Future<bool> bookExists(String title) async {
    return await _fileSystem.bookExists(title);
  }

  Future<void> saveBookContent(TextBook book, String content) async {
    await _fileSystem.saveBookText(book.title, content);
  }
}
