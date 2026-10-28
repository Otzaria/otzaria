import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/services/user_links_loader.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/repository/book_toc_loader.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/book_common/utils/commentator_group_builder.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart'
    show CommentatorIdentity;
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'dart:io';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';

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

/// מפרש של ספר כפי שהוא יושב בשאילתות הקישורים: השם, המחבר, מספר הקישורים
/// ושם האוסף (`book.collectiveTitleHe`).
class CommentatorInfo {
  final String title;
  final String? author;
  final int linkCount;
  final String? collectiveTitle;

  const CommentatorInfo({
    required this.title,
    this.author,
    this.linkCount = 0,
    this.collectiveTitle,
  });
}

/// מפרשי הספר, הנדירים שבהם, וזהות כל מפרש לפי כותרתו.
typedef CommentatorsWithRarity = ({
  List<String> all,
  Set<String> rare,
  Map<String, CommentatorIdentity> identities,
});

class TextBookRepository {
  final FileSystemData _fileSystem;
  final SqliteDataProvider _sqliteProvider;

  TextBookRepository({
    required this._fileSystem,
    SqliteDataProvider? sqliteProvider,
  }) : _sqliteProvider = sqliteProvider ?? SqliteDataProvider.instance;

  Future<bool> supportsContinuousReadingMode(TextBook book) =>
      FileSystemData.instance.supportsContinuousReadingMode(
        book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
      );

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
      preferSource: book.source,
    );
    if (providerText != null && providerText.isNotEmpty) {
      return providerText;
    }

    // Fallback: read directly from the database (doesn't require provider caches).
    final dbBook = await BookLocator.getBookFromDatabase(
      title,
      category: book.category,
      categoryId: book.categoryId,
      fileType: book.fileType,
      source: book.source,
    );
    if (dbBook != null) {
      // Best-effort enrichment for subsequent calls.
      book.fileType ??= dbBook.fileType;
      book.filePath ??= dbBook.filePath;

      if (dbBook.isFileBacked && dbBook.filePath != null) {
        final file = File(dbBook.filePath!);
        if (await file.exists()) {
          // PDF מוחזר '' — אין ממנו טקסט, והקוראים שלו בצנרת נפרדת.
          return await readFileBackedBookText(file, dbBook.fileType, title) ??
              '';
        }
      }

      final dbText = await _sqliteProvider.getBookTextFromDb(
        title,
        dbBook.categoryId,
        dbBook.fileType,
        book.source,
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

    // מסד ספרי המשתמש שומר את שורות מקור ה-Markdown בעוד שהקורא מציג HTML
    // מומר; טעינת טווח מהמסד תערבב שתי מפות אינדקסים ותשבור ניווט וקישורים.
    if (isMarkdownBook(fileType: fileType, filePath: book.filePath)) {
      return null;
    }

    // ספרי seforim.db ומסדים מצורפים: השאילתה וה-split רצים ב-isolate (כמו
    // הקישורים), כדי שלא יחסמו את ה-UI thread בזמן גלילה. ספרי משתמש נשארים
    // במסלול ה-drift, וכישלון נופל אליו (file-backed וכו').
    if (categoryId != null && !book.source.isUser) {
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
        source: book.source,
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
      preferSource: book.source,
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
      source: book.source,
      startLineIndex: normalizedStart,
      endLineIndex: normalizedEnd,
      targetBookTitles: normalizedTargetBookTitles,
    );
    final externalLinks = await ExternalLinkRepository.instance.linksInRange(
      title: book.title,
      categoryId: book.categoryId,
      source: book.source,
      startLineIndex: normalizedStart,
      endLineIndex: normalizedEnd,
      targetBookTitles: normalizedTargetBookTitles,
    );
    if (userLinks.isEmpty && externalLinks.isEmpty) return base;
    return mergeExtraLinks(base, [...userLinks, ...externalLinks]);
  }

  /// מוסיף ל-[base] את [extra] בלי כפילויות: קישור הדדי בין שני מסדים (A→B
  /// ו-B→A) או שורה כפולה ב-`external_link` מופיעים פעם אחת.
  @visibleForTesting
  static List<Link> mergeExtraLinks(List<Link> base, List<Link> extra) {
    final seen = {for (final link in base) linkIdentityKey(link)};
    return [
      ...base,
      for (final link in extra)
        if (seen.add(linkIdentityKey(link))) link,
    ];
  }

  /// מפרשים שמקורם בקישורים חוצי-מסדים (`external_link`), עם המסד של כל אחד —
  /// הדור של מפרש נקבע לפי המסד שלו ולא לפי המסד של הספר הנקרא.
  Future<Map<String, BookSource>> getExternalCommentatorSources(
    TextBook book,
  ) => ExternalLinkRepository.instance.commentatorSources(
    title: book.title,
    categoryId: book.categoryId,
    source: book.source,
  );

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

    // ספר ממסד מצורף: קישוריו במסד שלו בלבד — ספר בשם זהה ב-seforim.db
    // הוא ספר אחר.
    if (book.source.isAttached) {
      if (categoryId == null) return const [];
      return DatabaseLibraryProvider.instance.getLinksForBookRange(
        title,
        categoryId,
        fileType,
        startLineIndex: normalizedStart,
        endLineIndex: normalizedEnd,
        targetBookTitles: normalizedTargetBookTitles,
        source: book.source,
      );
    }

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
          .where((link) => link.overlapsSourceLines(rangeStart, rangeEnd))
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

  ({TextBook book, int generation, List<TocEntry> toc})? _lastToc;

  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    final manager = LibraryProviderManager.instance;
    final provider = manager.getProviderForBook(
      book.title,
      categoryId: book.categoryId,
      fileType: book.fileType,
    );
    final cache = BooksCache.instance;
    final entry = book.id == null ? null : cache.getBookById(book.id!);
    // רק תוכן שמאומת בקטלוג הרשמי נשמר; קבצים ומקורות חיצוניים עשויים להשתנות.
    if (!manager.isInitialized ||
        provider is! DatabaseLibraryProvider ||
        provider.resolvedSourceForBook(book)?.isOfficial != true ||
        !book.source.isOfficial ||
        book.filePath != null ||
        entry == null ||
        entry.filePath != null ||
        entry.title != book.title ||
        entry.categoryId != book.categoryId ||
        entry.fileType != (book.fileType ?? 'txt')) {
      return loadBookToc(book, sqliteProvider: _sqliteProvider);
    }
    final generation = cache.generation;
    final last = _lastToc;
    if (last != null &&
        identical(last.book, book) &&
        last.generation == generation) {
      return last.toc;
    }
    final toc = await manager.getBookToc(
      book.title,
      categoryId: book.categoryId,
      fileType: book.fileType ?? 'txt',
      preferSource: book.source,
    );
    if (toc == null || toc.isEmpty) {
      return loadBookTocFallback(book, sqliteProvider: _sqliteProvider);
    }
    // טעינה שחפפה לעדכון ספרייה או מקור אינה נשמרת.
    if (generation == cache.generation &&
        provider.resolvedSourceForBook(book)?.isOfficial == true &&
        book.filePath == null) {
      _lastToc = (book: book, generation: generation, toc: toc);
    }
    return toc;
  }

  /// מחזיר רשימת פרשנים זמינים לספר מה-DB
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    return (await getCommentatorsWithRarity(book)).all;
  }

  /// מחזיר את מפרשי הספר ([all]) יחד עם קבוצת המפרשים ה"נדירים" ([rare]) שיש
  /// להסתיר מרשימת הבחירה הכללית (בספרים גדולים בלבד). ראה
  /// [computeRareCommentators].
  Future<CommentatorsWithRarity> getCommentatorsWithRarity(
    TextBook book,
  ) async {
    final detailed = await getCommentatorsDetailed(book);
    return (
      all: [for (final c in detailed.commentators) c.title],
      rare: detailed.rare,
      identities: {
        for (final c in detailed.commentators)
          c.title: CommentatorIdentity(
            collectiveTitle: c.collectiveTitle,
            linkCount: c.linkCount,
          ),
      },
    );
  }

  /// אותם מפרשים של [getCommentatorsWithRarity], בלי לאבד את המחבר ומספר
  /// הקישורים שהשאילתה כבר מחזירה. ממוין לפי שם.
  Future<({List<CommentatorInfo> commentators, Set<String> rare})>
  getCommentatorsDetailed(TextBook book) async {
    // מפרשים מקישורי-משתמש ומקישורים חוצי-מסדים — נוספים לרשימה של כל ספר;
    // מפרש כזה לעולם אינו "נדיר" (נוסף במכוון).
    final userCommentators = {
      ...await loadUserCommentatorTitles(
        bookTitle: book.title,
        bookCategoryId: book.categoryId,
        source: book.source,
      ),
      ...(await getExternalCommentatorSources(book)).keys,
    };
    userOnly() => (
      commentators: [
        for (final title in userCommentators.toList()..sort())
          CommentatorInfo(title: title),
      ],
      rare: const <String>{},
    );

    // קישורי המפרשים במסד של הספר בלבד; ספר אישי — רק מקישורי-משתמש.
    final repository = await _linksRepositoryFor(book.source);
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
    final commentatorsData = await _selectCommentatorsByBook(
      repository,
      book.source,
      dbBook.id,
    );

    // מפרש עשוי להופיע בכמה שורות (מחבר לכל שורה) עם אותו linkCount; לוקחים
    // את הערך המרבי כמספר הקישורים לספר.
    final linkCountByTitle = <String, int>{};
    final authorByTitle = <String, String>{};
    final collectiveByTitle = <String, String>{};
    for (final row in commentatorsData) {
      final title = row['targetBookTitle'] as String;
      final count = (row['linkCount'] as int?) ?? 0;
      if (count > (linkCountByTitle[title] ?? 0)) {
        linkCountByTitle[title] = count;
      }
      final author = row['author'] as String?;
      if (author != null && author.isNotEmpty) {
        authorByTitle.putIfAbsent(title, () => author);
      }
      final collective = row['collectiveTitleHe'] as String?;
      if (collective != null) collectiveByTitle[title] = collective;
    }

    final all = {...linkCountByTitle.keys, ...userCommentators}.toList()
      ..sort((a, b) => a.compareTo(b));
    final rare = computeRareCommentators(
      bookTotalLines: dbBook.totalLines,
      linkCountByCommentator: linkCountByTitle,
    ).difference(userCommentators);
    return (
      commentators: [
        for (final title in all)
          CommentatorInfo(
            title: title,
            author: authorByTitle[title],
            linkCount: linkCountByTitle[title] ?? 0,
            collectiveTitle: collectiveByTitle[title],
          ),
      ],
      rare: rare,
    );
  }

  /// מפרשי הספר על טווח שורות המקור [startLine]–[endLine] (0-based, כולל) —
  /// חיווט של `selectCommentatorsByLineRange` ששימשה עד כה רק את FindRef.
  Future<List<CommentatorInfo>> getCommentatorsInLineRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final byTitle = <String, CommentatorInfo>{};
    final externalCounts = <String, int>{};
    for (final link in await ExternalLinkRepository.instance.linksInRange(
      title: book.title,
      categoryId: book.categoryId,
      source: book.source,
      startLineIndex: startLine,
      endLineIndex: endLine,
    )) {
      if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
      externalCounts[link.path2] = (externalCounts[link.path2] ?? 0) + 1;
    }
    for (final MapEntry(key: title, value: count) in externalCounts.entries) {
      byTitle[title] = CommentatorInfo(title: title, linkCount: count);
    }
    List<CommentatorInfo> sorted() =>
        byTitle.values.toList()..sort((a, b) => a.title.compareTo(b.title));

    final repository = await _linksRepositoryFor(book.source);
    if (repository == null) return sorted();

    final dbBook = book.categoryId != null
        ? await repository.getBookByTitleAndCategory(
            book.title,
            book.categoryId!,
          )
        : await repository.getBookByTitle(book.title);
    if (dbBook == null) return sorted();

    // הגבול העליון בשאילתה בלעדי, בעוד ש-[endLine] כולל את שורת הסיום.
    final rows = await repository.database.linkDao
        .selectCommentatorsByLineRange(
          dbBook.id,
          startLine,
          endLine + 1,
        );

    for (final row in rows) {
      final title = row['targetBookTitle'] as String;
      final count = (row['linkCount'] as int?) ?? 0;
      final existing = byTitle[title];
      if (existing == null || count > existing.linkCount) {
        byTitle[title] = CommentatorInfo(
          title: title,
          author: row['author'] as String?,
          linkCount: count,
        );
      }
    }
    return sorted();
  }

  /// מפרשים נוספים על קטע המקור; [requireExactLine] מוותר על קישורי הקטע
  /// כשאין למפרש קישור לשורת המקור המדויקת.
  Future<List<Link>> getSiblingCommentaries({
    required String sourceBookTitle,
    required int? sourceCategoryId,
    required int sourceLineIndex,
    required String currentBookTitle,
    required int? currentCategoryId,
    BookSource sourceBookSource = BookSource.official,
    BookSource currentBookSource = BookSource.official,
    bool requireExactLine = false,
  }) async {
    // מפרשים ממסדים אחרים על אותה שורת מקור, דרך `external_link`.
    final external = [
      for (final link in await ExternalLinkRepository.instance.linksInRange(
        title: sourceBookTitle,
        categoryId: sourceCategoryId,
        source: sourceBookSource,
        startLineIndex: sourceLineIndex,
        endLineIndex: sourceLineIndex,
      ))
        if (LinkTypes.isDependentTextLink(link.connectionType) &&
            !(link.path2 == currentBookTitle &&
                link.targetSource == currentBookSource))
          link,
    ];

    // קישורי המפרשים במסד של ספר המקור; ספר ממקור אחר בשם זהה אינו אותו ספר.
    final repository = await _linksRepositoryFor(sourceBookSource);
    if (repository == null) return CommentaryService.sortLinksByEra(external);

    final sourceBook = sourceCategoryId != null
        ? await repository.getBookByTitleAndCategory(
            sourceBookTitle,
            sourceCategoryId,
          )
        : await repository.getBookByTitle(sourceBookTitle);
    if (sourceBook == null) return CommentaryService.sortLinksByEra(external);

    final currentBook = currentBookSource != sourceBookSource
        ? null
        : currentCategoryId != null
        ? await repository.getBookByTitleAndCategory(
            currentBookTitle,
            currentCategoryId,
          )
        : await repository.getBookByTitle(currentBookTitle);

    final rows = await _siblingCommentaryRows(
      repository,
      sourceBookSource,
      bookId: sourceBook.id,
      bookTitle: sourceBookTitle,
      lineIndex: sourceLineIndex,
      excludeBookId: currentBook?.id ?? -1,
    );

    final matchedRows = requireExactLine
        ? rows.where((row) => row['exactTargetLineIndex'] != null)
        : rows;
    final links = matchedRows.map((row) {
      final exact = row['exactTargetLineIndex'] as int?;
      final first = exact ?? row['minTargetLineIndex'] as int;
      var last = exact ?? row['maxTargetLineIndex'] as int;
      if (exact != null) {
        // קטעי השורה ברצף מהראשון: עד שתי שורות הפרדה, שאינן קטע של שורת מקור
        // אחרת — כדי שהתצוגה לא תגלוש לס"ק של סעיף אחר.
        late final others = _lineIndexes(row['otherTargetLineIndexes']).toSet();
        for (final next in _lineIndexes(row['exactTargetLineIndexes'])) {
          final gap = next - last - 1;
          if (gap < 0) continue;
          if (gap > 2 ||
              gap > 0 &&
                  (others.contains(last + 1) || others.contains(next - 1))) {
            break;
          }
          last = next;
        }
      }
      return Link(
        heRef: row['targetBookTitle'] as String,
        index1: sourceLineIndex + 1,
        path2: row['targetBookTitle'] as String,
        index2: first + 1,
        index2End: last > first ? last + 1 : null,
        connectionType: row['connectionType'] as String? ?? 'commentary',
        targetCategoryId: row['targetCategoryId'] as int?,
        targetBookId: row['targetBookId'] as int?,
        targetFileType: row['targetFileType'] as String?,
        targetSource: sourceBookSource,
      );
    }).toList();

    // מיון לפי דורות (ראשונים→אחרונים→…) לצורך פסי ההפרדה בתת-התפריט.
    return CommentaryService.sortLinksByEra(mergeExtraLinks(links, external));
  }

  static Iterable<int> _lineIndexes(Object? csv) =>
      csv == null ? const [] : (csv as String).split(',').map(int.parse);

  /// ב-seforim.db השאילתה סורקת את כל קישורי הספר (עד 124ms בבראשית),
  /// ולכן רצה ב-worker ולא על ה-UI isolate.
  Future<List<Map<String, dynamic>>> _selectCommentatorsByBook(
    SeforimRepository repository,
    BookSource source,
    int bookId,
  ) async {
    final dbPath = _sqliteProvider.dbPath;
    if (source.isOfficial && dbPath.isNotEmpty) {
      try {
        return (await DbReadWorker.request('commentatorsByBook', {
                  'dbPath': dbPath,
                  'bookId': bookId,
                })
                as List)
            .cast<Map<String, dynamic>>();
      } on DbReadWorkerUnavailable {
        // נופלים לשאילתה הישירה, כמו שאר הקריאות כשה-worker אינו זמין.
      }
    }
    return repository.database.linkDao.selectCommentatorsByBook(bookId);
  }

  /// בפנייה הראשונה לספר נבנה תוכן העניינים שלו (עד 115ms בבית יוסף), ולכן
  /// ב-seforim.db השאילתה רצה ב-worker ולא על ה-UI isolate.
  Future<List<Map<String, dynamic>>> _siblingCommentaryRows(
    SeforimRepository repository,
    BookSource source, {
    required int bookId,
    required String bookTitle,
    required int lineIndex,
    required int excludeBookId,
  }) async {
    final dbPath = _sqliteProvider.dbPath;
    if (source.isOfficial && dbPath.isNotEmpty) {
      try {
        return (await DbReadWorker.request('siblingCommentaryRows', {
                  'dbPath': dbPath,
                  'bookId': bookId,
                  'bookTitle': bookTitle,
                  'lineIndex': lineIndex,
                  'excludeBookId': excludeBookId,
                })
                as List)
            .cast<Map<String, dynamic>>();
      } on DbReadWorkerUnavailable {
        // נופלים לשאילתה הישירה, כמו שאר הקריאות כשה-worker אינו זמין.
      }
    }
    return repository.getSiblingCommentaryLinkRowsForLine(
      bookId: bookId,
      bookTitle: bookTitle,
      lineIndex: lineIndex,
      excludeBookId: excludeBookId,
    );
  }

  /// המאגר שבו יושבים קישורי [source]: seforim.db או המסד המצורף. לספר
  /// אישי — null (קישוריו ב-user_link).
  Future<SeforimRepository?> _linksRepositoryFor(BookSource source) =>
      switch (source) {
        OfficialBookSource() => _officialRepository(),
        UserBookSource() => Future.value(),
        AttachedBookSource(:final slug) =>
          AttachedLibraryRegistry.instance.repositoryFor(slug),
      };

  /// פותח מחדש חיבור שנסגר; חיבור שמעולם לא נפתח שייך לאתחול האפליקציה.
  Future<SeforimRepository?> _officialRepository() async {
    final provider = _sqliteProvider;
    if (!provider.isInitialized && provider.canReopenAfterClose) {
      await provider.initialize();
    }
    return provider.repository;
  }

  /// האם חיבור הספרייה הרשמית פתוח — לרישום כשל בטעינת המפרשים.
  bool get isLibraryConnectionOpen => _sqliteProvider.isInitialized;

  Future<void> saveBookContent(TextBook book, String content) async {
    await _fileSystem.saveBookText(book.title, content);
  }
}
