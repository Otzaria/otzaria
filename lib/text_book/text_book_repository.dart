import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/services/user_links_loader.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/utils/file/docx_cache.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'dart:io';
import 'dart:isolate';

class BookContentRange {
  final int startLine;
  final int endLine;
  final int totalLines;
  final List<String> lines;

  const BookContentRange({
    required this.startLine,
    required this.endLine,
    required this.totalLines,
    required this.lines,
  });
}

class TextBookRepository {
  final FileSystemData _fileSystem;
  final SqliteDataProvider _sqliteProvider;

  TextBookRepository({
    required this._fileSystem,
    SqliteDataProvider? sqliteProvider,
  }) : _sqliteProvider = sqliteProvider ?? SqliteDataProvider.instance;

  Future<String> getBookContent(TextBook book) async {
    // מהדורה חלופית: נטענת אך ורק משאילתת ה-overlay של version_line — בלי
    // ליפול בשקט לנוסח הממוזג (שהיה מוצג בשם המהדורה). כישלון = טקסט ריק.
    if (book.versionTitle != null) {
      final range = await getBookContentRange(
        book,
        startLine: 0,
        endLine: 1 << 30,
      );
      return range?.lines.join('\n') ?? '';
    }

    // Primary path: go through the provider manager (handles file system + DB).
    // This can fail early in app startup because some providers require catalog caching.
    final title = book.title;
    final categoryId = book.categoryId;
    final fileType = book.fileType ?? 'txt';

    final providerText = await LibraryProviderManager.instance.getBookText(
      title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: book.isUserBook,
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
            return await convertDocxWithCache(file, title);
          }
          if (ext == 'epub') {
            return await convertEpubWithCache(file, title);
          }
          if (ext == 'pdf') return '';
          return await readTextFileSmart(file);
        }
      }

      final dbText = await _sqliteProvider.getBookTextFromDb(
        title,
        dbBook.categoryId,
        dbBook.fileType,
        book.isUserBook,
      );
      if (dbText != null && dbText.isNotEmpty) {
        return dbText;
      }
    }

    // Last resort: keep existing behavior.
    return '';
  }

  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final categoryId = book.categoryId;
    final fileType = book.fileType ?? 'txt';

    // ספרי seforim.db בלבד: השאילתה וה-split רצים ב-isolate (כמו הקישורים),
    // כדי שלא יחסמו את ה-UI thread בזמן גלילה. ה-isolate פותח רק את seforim.db,
    // לכן ספרי משתמש נשארים במסלול ה-drift, וכישלון נופל אליו (file-backed וכו').
    if (categoryId != null && !book.isUserBook) {
      // getProviderForBook מסתכל רק ב-_bookToProvider שמתמלא אחרי buildLibraryCatalog.
      // בסטרטאפ (לפני buildLibraryCatalog) הוא מחזיר null — ולכן פונים ישירות
      // ל-DatabaseLibraryProvider שיכול לפתוח seforim.db ב-isolate גם בלי catalog.
      final dbProvider = DatabaseLibraryProvider.instance;
      final provider = LibraryProviderManager.instance.getProviderForBook(
        book.title,
        categoryId: categoryId,
        fileType: fileType,
      );
      final resolvedProvider = (provider is DatabaseLibraryProvider)
          ? provider
          : dbProvider;
      final range = await resolvedProvider.getBookTextRange(
        book.title,
        categoryId,
        fileType,
        startLine: startLine,
        endLine: endLine,
        versionTitle: book.versionTitle,
      );
      if (range != null && range.lines.isNotEmpty) {
        return BookContentRange(
          startLine: range.startLine,
          endLine: range.endLine,
          totalLines: range.totalLines,
          lines: range.lines,
        );
      }
      // מהדורה חלופית שלא נמצאה (DB ישן / שם שהשתנה): אין ליפול לנוסח
      // הממוזג בשם המהדורה — מחזירים null והטאב יציג ריק.
      if (book.versionTitle != null) {
        return null;
      }
    }

    if (book.versionTitle != null) {
      return null;
    }

    final range = await _sqliteProvider.getBookTextRangeFromDb(
      book.title,
      startLine: startLine,
      endLine: endLine,
      categoryId: book.categoryId,
      fileType: book.fileType ?? 'txt',
      preferUserBooks: book.isUserBook,
    );
    if (range == null || range.text.isEmpty) {
      return null;
    }

    return BookContentRange(
      startLine: range.startLine,
      endLine: range.endLine,
      totalLines: range.totalLines,
      lines: range.text.split('\n'),
    );
  }

  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    final normalizedStart = startIndex < 0 ? 0 : startIndex;
    final normalizedEnd = endIndex < normalizedStart
        ? normalizedStart
        : endIndex;
    final normalizedTargetBookTitles =
        targetBookTitles
            ?.map((title) => title.trim())
            .where((title) => title.isNotEmpty)
            .toSet()
            .toList()
          ?..sort();

    final base = await _loadBaseLinks(
      book,
      normalizedStart,
      normalizedEnd,
      normalizedTargetBookTitles,
    );

    // מיזוג קישורי-משתמש (מ-user_books.db) — forward (כשקוראים ספר אישי)
    // ו-inverse (מפרש-משתמש שמצביע אל הספר הזה, גם אם הוא רשמי).
    final userLinks = await loadUserLinksForBook(
      bookTitle: book.title,
      bookCategoryId: book.categoryId,
      isUserBook: book.isUserBook,
      startLineIndex: normalizedStart,
      endLineIndex: normalizedEnd,
      targetBookTitles: normalizedTargetBookTitles,
    );
    if (userLinks.isEmpty) return base;
    return [...base, ...userLinks];
  }

  /// טוען את קישורי המאגר (seforim.db / קובץ) בלבד — בלי קישורי-משתמש.
  Future<List<Link>> _loadBaseLinks(
    TextBook book,
    int normalizedStart,
    int normalizedEnd,
    List<String>? normalizedTargetBookTitles,
  ) async {
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
            if (!LinkTypes.isDependentTextLink(link.connectionType)) {
              return true;
            }
            return targetBookTitlesSet.contains(
              utils.getTitleFromPath(link.path2),
            );
          })
          .toList();
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
      preferUserBooks: book.isUserBook,
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
            content = await convertDocxWithCache(file, title);
          } else if (ext == 'epub') {
            content = await convertEpubWithCache(file, title);
          } else if (ext == 'pdf') {
            content = '';
          } else {
            content = await readTextFileSmart(file);
          }
          if (content.isNotEmpty) {
            return await Isolate.run(
              () => TocParser.parseEntriesFromContent(content),
            );
          }
        }
      }

      final dbToc = await _sqliteProvider.getBookTocFromDb(
        title,
        dbBook.categoryId,
        dbBook.fileType,
        book.isUserBook,
      );
      if (dbToc != null && dbToc.isNotEmpty) {
        return dbToc;
      }
    }

    return [];
  }

  /// מחזיר רשימת פרשנים זמינים לספר מה-DB
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    return (await getCommentatorsWithRarity(book)).all;
  }

  /// מחזיר את מפרשי הספר ([all]) יחד עם קבוצת המפרשים ה"נדירים" ([rare]) שיש
  /// להסתיר מרשימת הבחירה הכללית (בספרים גדולים בלבד). ראה
  /// [computeRareCommentators].
  Future<({List<String> all, Set<String> rare})> getCommentatorsWithRarity(
    TextBook book,
  ) async {
    // מפרשים מקישורי-משתמש (user_books.db) — נוספים לרשימת המפרשים של כל
    // ספר; מפרש מיובא לעולם אינו "נדיר" (יובא במכוון).
    final userCommentators = (await loadUserCommentatorTitles(
      bookTitle: book.title,
      bookCategoryId: book.categoryId,
      isUserBook: book.isUserBook,
    )).toSet();
    userOnly() =>
        (all: userCommentators.toList()..sort(), rare: const <String>{});

    // ספרים אישיים אינם כוללים קישורי מפרשים במסד הנתונים הרשמי.
    // חיפוש לפי book.id ב-seforim.db יחזיר מפרשים של ספר רשמי עם אותו ID.
    if (book.isUserBook) return userOnly();

    final repository = _sqliteProvider.repository;
    if (repository == null) return userOnly();

    // מקבל את ה-book ישירות מה-repository (אותו DB שממנו נשלוף את המפרשים)
    final dbBook = book.categoryId != null
        ? await repository.getBookByTitleAndCategory(
            book.title,
            book.categoryId!,
          )
        : await repository.getBookByTitle(book.title);
    if (dbBook == null) return userOnly();

    // שולף את הפרשנים ישירות מה-DB, כולל מספר הקישורים של כל מפרש
    final commentatorsData = await repository.database.linkDao
        .selectCommentatorsByBook(dbBook.id);

    // מפרש עשוי להופיע בכמה שורות (מחבר לכל שורה) עם אותו linkCount; לוקחים
    // את הערך המרבי כמספר הקישורים לספר.
    final linkCountByTitle = <String, int>{};
    for (final row in commentatorsData) {
      final title = row['targetBookTitle'] as String;
      final count = (row['linkCount'] as int?) ?? 0;
      if (count > (linkCountByTitle[title] ?? 0)) {
        linkCountByTitle[title] = count;
      }
    }

    final all = {...linkCountByTitle.keys, ...userCommentators}.toList()
      ..sort((a, b) => a.compareTo(b));
    final rare = computeRareCommentators(
      bookTotalLines: dbBook.totalLines,
      linkCountByCommentator: linkCountByTitle,
    ).difference(userCommentators);
    return (all: all, rare: rare);
  }

  /// מחזיר את "המפרשים הנוספים" על הקטע שבו יושבת שורת המקור [sourceLineIndex]
  /// בספר [sourceBookTitle] — כלומר שאר המפרשים על אותו עמוד/סוגיה, פרט לספר
  /// המפרש הפתוח כרגע ([currentBookTitle]). כל [Link] מוחזר בפורמט זהה לקישור
  /// מפרש רגיל, כך שהתצוגה המקדימה והניווט פועלים דרך התשתית הקיימת.
  ///
  /// מיועד לפיצ'ר תפריט ההקשר בספרי מפרש: בהינתן שורה במפרש, הקישור ההפוך
  /// (SOURCE) כבר נותן את שורת המקור; מכאן נאספים שאר מפרשי אותו קטע.
  Future<List<Link>> getSiblingCommentaries({
    required String sourceBookTitle,
    required int? sourceCategoryId,
    required int sourceLineIndex,
    required String currentBookTitle,
    required int? currentCategoryId,
  }) async {
    final repository = _sqliteProvider.repository;
    if (repository == null) return [];

    final sourceBook = sourceCategoryId != null
        ? await repository.getBookByTitleAndCategory(
            sourceBookTitle,
            sourceCategoryId,
          )
        : await repository.getBookByTitle(sourceBookTitle);
    if (sourceBook == null) return [];

    final currentBook = currentCategoryId != null
        ? await repository.getBookByTitleAndCategory(
            currentBookTitle,
            currentCategoryId,
          )
        : await repository.getBookByTitle(currentBookTitle);

    final rows = await repository.getSiblingCommentaryLinkRowsForLine(
      bookId: sourceBook.id,
      bookTitle: sourceBookTitle,
      lineIndex: sourceLineIndex,
      excludeBookId: currentBook?.id ?? -1,
    );

    final links = rows.map((row) {
      final exact = row['exactTargetLineIndex'] as int?;
      final minIdx = row['minTargetLineIndex'] as int;
      final maxIdx = row['maxTargetLineIndex'] as int;
      // התאמה מדויקת לשורת המקור → תצוגה מקדימה של אותו קטע בלבד. אחרת →
      // טווח כל הקישורים של המפרש בקטע (תוכן המפרש על העמוד).
      final int index2;
      final int? index2End;
      if (exact != null) {
        index2 = exact + 1;
        index2End = null;
      } else {
        index2 = minIdx + 1;
        index2End = maxIdx > minIdx ? maxIdx + 1 : null;
      }
      return Link(
        heRef: row['targetBookTitle'] as String,
        index1: sourceLineIndex + 1,
        path2: row['targetBookTitle'] as String,
        index2: index2,
        index2End: index2End,
        connectionType: row['connectionType'] as String? ?? 'commentary',
        targetCategoryId: row['targetCategoryId'] as int?,
        targetFileType: row['targetFileType'] as String?,
      );
    }).toList();

    // מיון לפי דורות (ראשונים→אחרונים→…) לצורך פסי ההפרדה בתת-התפריט.
    return CommentaryService.sortLinksByEra(links);
  }

  Future<bool> bookExists(String title) async {
    return await _fileSystem.bookExists(title);
  }

  Future<void> saveBookContent(TextBook book, String content) async {
    await _fileSystem.saveBookText(book.title, content);
  }
}
