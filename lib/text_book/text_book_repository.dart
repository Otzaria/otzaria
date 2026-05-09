import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'dart:io';
import 'dart:isolate';

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
      categoryId: book.categoryId,
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
          if (ext == 'pdf') return '';
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

  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    final normalizedStart = startIndex < 0 ? 0 : startIndex;
    final normalizedEnd =
        endIndex < normalizedStart ? normalizedStart : endIndex;
    final normalizedTargetBookTitles = targetBookTitles
        ?.map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList()
      ?..sort();

    final title = book.title;
    final categoryId = book.categoryId;
    final fileType = book.fileType ?? 'txt';

    final provider = LibraryProviderManager.instance.getProviderForBook(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );

    if (provider is DatabaseLibraryProvider && categoryId != null) {
      return await provider.getLinksForBookRange(
        title,
        categoryId,
        fileType,
        startLineIndex: normalizedStart,
        endLineIndex: normalizedEnd,
        targetBookTitles: normalizedTargetBookTitles,
      );
    }

    final providerLinks = await book.links;
    if (providerLinks.isNotEmpty) {
      final rangeStart = normalizedStart + 1;
      final rangeEnd = normalizedEnd + 1;
      final targetBookTitlesSet = normalizedTargetBookTitles?.toSet();
      final filteredLinks = providerLinks
          .where((link) => link.index1 >= rangeStart && link.index1 <= rangeEnd)
          .where((link) {
        if (targetBookTitlesSet == null) {
          return true;
        }
        // Non-commentary links (cross-references, sources, etc.) always pass through
        final type = link.connectionType.toUpperCase();
        if (type != 'COMMENTARY' && type != 'TARGUM') {
          return true;
        }
        return targetBookTitlesSet.contains(utils.getTitleFromPath(link.path2));
      }).toList();
      return filteredLinks;
    }

    final dbBook = await BookLocator.getBookFromDatabase(
      book.title,
      category: book.category,
      categoryId: book.categoryId,
    );

    if (dbBook != null && _sqliteProvider.repository != null) {
      return await DatabaseLibraryProvider.instance.getLinksForBookRange(
        title,
        dbBook.categoryId,
        dbBook.fileType ?? fileType,
        startLineIndex: normalizedStart,
        endLineIndex: normalizedEnd,
        targetBookTitles: normalizedTargetBookTitles,
      );
    }

    return const [];
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
      categoryId: book.categoryId,
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
          } else if (ext == 'pdf') {
            content = '';
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
      categoryId: book.categoryId,
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
