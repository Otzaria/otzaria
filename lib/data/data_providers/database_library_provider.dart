import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/migration/models/toc_entry.dart' as db_models;
import 'package:otzaria/utils/file/file_hidden_utils.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:pdfrx/pdfrx.dart';

// ──────────────────────────────────────────────────────────────────────────
// Isolate helpers for scanning external-book folders.
// All types must be sendable across isolate ports (no native handles,
// no platform-channel objects, no closures with non-sendable captures).
// ──────────────────────────────────────────────────────────────────────────

/// Sendable flat representation of a single TOC entry.
/// Parent/child references use 0-based indices into the flat list.
class _RawTocEntry {
  final String text;
  final int level;
  final int lineIndex;

  /// 0-based index of the parent entry; null for root entries.
  final int? parentIndex;

  const _RawTocEntry({
    required this.text,
    required this.level,
    required this.lineIndex,
    this.parentIndex,
  });
}

/// Sendable description of a discovered book file, returned from the
/// background isolate to the main isolate.
class _DiscoveredBook {
  final String path;
  final String title;
  final String fileType; // 'txt' | 'docx' | 'pdf'
  final int fileSize;
  final int lastModified;
  final List<String> categoryPath;

  /// Pre-parsed TOC for TXT / DOCX files (parsed inside the isolate).
  /// null for PDF (platform channel) or for metadata-update-only books.
  final List<_RawTocEntry>? tocEntries;

  /// Non-null when the book already exists in the DB but its file metadata
  /// (size or mtime) changed. Phase 2 only updates metadata; no insert needed.
  final int? existingBookId;

  /// Non-null when DOCX conversion failed (e.g. unsupported encoding).
  /// Books with this field set are counted as failures and not inserted.
  final String? conversionError;

  const _DiscoveredBook({
    required this.path,
    required this.title,
    required this.fileType,
    required this.fileSize,
    required this.lastModified,
    required this.categoryPath,
    this.tocEntries,
    this.existingBookId,
    this.conversionError,
  });
}

/// Entry point for [Isolate.run]: scans [folderPath] recursively,
/// filters out already-indexed unchanged books via a direct sqlite3 read,
/// and parses TXT / DOCX TOC for genuinely NEW books.
/// PDF TOC is intentionally skipped here (pdfrx uses platform channels).
Future<List<_DiscoveredBook>> _scanExternalFolderInIsolate(
    (String folderPath, String folderName, String dbPath) args) async {
  // Open a read-only sqlite3 connection to check existing books without
  // going through the Drift/sqflite layer (which requires platform channels).
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(args.$3, mode: sqlite3.OpenMode.readOnly);
  } catch (_) {
    // If the DB cannot be opened (first run, locked, etc.) fall through
    // and treat every file as new.
  }

  final books = <_DiscoveredBook>[];
  await _collectBookFilesRecursive(
    Directory(args.$1),
    ['ספרים אישיים', args.$2],
    books,
    db,
  );
  db?.close();
  return books;
}

Future<void> _collectBookFilesRecursive(
  Directory dir,
  List<String> categoryPath,
  List<_DiscoveredBook> books,
  sqlite3.Database? db,
) async {
  await for (final entity in dir.list()) {
    try {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (isHiddenOrSystem(entity.path)) continue;

      if (entity is Directory) {
        await _collectBookFilesRecursive(
          entity,
          [...categoryPath, name],
          books,
          db,
        );
      } else if (entity is File) {
        final lower = name.toLowerCase();
        String fileType;
        if (lower.endsWith('.txt')) {
          fileType = 'txt';
        } else if (lower.endsWith('.docx')) {
          fileType = 'docx';
        } else if (lower.endsWith('.pdf')) {
          fileType = 'pdf';
        } else {
          continue;
        }

        final stat = await entity.stat();
        final title = getTitleFromPath(entity.path);
        final fileSize = stat.size;
        final lastModified = stat.modified.millisecondsSinceEpoch;

        // ── DB existence check ─────────────────────────────────────────────
        // Perform BEFORE any expensive IO (TOC parse) so unchanged books are
        // skipped entirely without reading file content.
        if (db != null) {
          final rows = db.select(
            'SELECT id, fileSize, lastModified FROM book WHERE filePath = ? LIMIT 1',
            [entity.path],
          ).toMapList();
          if (rows.isNotEmpty) {
            final row = rows.first;
            final storedSize = row['fileSize'] as int? ?? -1;
            final storedMtime = row['lastModified'] as int? ?? -1;
            if (storedSize == fileSize && storedMtime == lastModified) {
              // Unchanged — skip entirely, no work needed.
              continue;
            }
            // File has changed — report for metadata-only update.
            books.add(_DiscoveredBook(
              path: entity.path,
              title: title,
              fileType: fileType,
              fileSize: fileSize,
              lastModified: lastModified,
              categoryPath: categoryPath,
              tocEntries: null, // no re-parse on metadata update
              existingBookId: row['id'] as int,
            ));
            continue;
          }
        }
        // ──────────────────────────────────────────────────────────────────

        // Genuinely new book — parse TOC for TXT / DOCX.
        List<_RawTocEntry>? rawToc;
        String? conversionError;
        if (fileType == 'txt') {
          try {
            final content = await entity.readAsString();
            // Synchronous call — we are already in a background isolate.
            final parsed = TocParser.parseEntriesFromContent(content);
            rawToc = _flattenTocToRaw(parsed);
          } catch (_) {
            // TOC parse failure is non-fatal.
          }
        } else if (fileType == 'docx') {
          try {
            final bytes = await entity.readAsBytes();
            final content = docxToText(bytes, title);
            try {
              final parsed = TocParser.parseEntriesFromContent(content);
              rawToc = _flattenTocToRaw(parsed);
            } catch (_) {
              // TOC parse failure is non-fatal — book still inserted without TOC.
            }
          } catch (e) {
            conversionError = e.toString();
          }
        }
        // PDF: rawToc stays null — parsed on the main isolate.

        books.add(_DiscoveredBook(
          path: entity.path,
          title: title,
          fileType: fileType,
          fileSize: fileSize,
          lastModified: lastModified,
          categoryPath: categoryPath,
          tocEntries: rawToc,
          conversionError: conversionError,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Skipping inaccessible entity: ${entity.path}: $e');
    }
  }
}

/// Exposed for unit-testing only.
///
/// Returns a list of maps with keys: `path`, `existingBookId` (nullable).
/// Unchanged books (already in DB with matching metadata) are absent from
/// the list.
@visibleForTesting
Future<List<Map<String, Object?>>> scanExternalFolderForTest(
    String folderPath, String folderName, String dbPath) async {
  final result =
      await _scanExternalFolderInIsolate((folderPath, folderName, dbPath));
  return result
      .map((b) => {'path': b.path, 'existingBookId': b.existingBookId})
      .toList();
}

/// Converts a hierarchical [TocEntry] tree into a flat, sendable list.
/// Uses pre-order (depth-first) traversal so each parent precedes its children.
List<_RawTocEntry> _flattenTocToRaw(List<TocEntry> roots) {
  final flat = <_RawTocEntry>[];
  _flattenRawRecursive(roots, flat, null);
  return flat;
}

void _flattenRawRecursive(
  List<TocEntry> entries,
  List<_RawTocEntry> flat,
  int? parentIndex,
) {
  for (final entry in entries) {
    final myIndex = flat.length;
    flat.add(_RawTocEntry(
      text: entry.text,
      level: entry.level,
      lineIndex: entry.index,
      parentIndex: parentIndex,
    ));
    if (entry.children.isNotEmpty) {
      _flattenRawRecursive(entry.children, flat, myIndex);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _loadBookLinksRowsInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
  required String fileType,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);

    final bookResults = db.select(
      'SELECT id FROM book WHERE title = ? AND categoryId = ? AND fileType = ? LIMIT 1',
      [title, categoryId, fileType],
    ).toMapList();

    if (bookResults.isEmpty) {
      return const [];
    }

    final bookId = bookResults.first['id'] as int;

    return db.select('''
        SELECT 
          l.sourceLineId,
          l.targetLineId,
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tl.heRef as targetLineHeRef,
          tb.title as targetBookTitle,
          tb.categoryId as targetCategoryId,
          tb.fileType as targetFileType,
          ct.name as connectionTypeName
        FROM link l
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.sourceBookId = ?
        ORDER BY sl.lineIndex
      ''', [bookId]).toMapList();
  } finally {
    db?.close();
  }
}

List<Map<String, dynamic>> _loadBookLinksRowsInRangeInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLineIndex,
  required int endLineIndex,
  required List<String>? targetBookTitles,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);

    final bookResults = db.select(
      'SELECT id FROM book WHERE title = ? AND categoryId = ? AND fileType = ? LIMIT 1',
      [title, categoryId, fileType],
    ).toMapList();

    if (bookResults.isEmpty) {
      return const [];
    }

    final bookId = bookResults.first['id'] as int;

    final parameters = <Object?>[
      bookId,
      startLineIndex,
      endLineIndex,
    ];
    // כשהפילטר ריק (אין מפרשים נבחרים) — עדיין מחזירים קישורי REFERENCE
    final hasCommentaryFilter =
        targetBookTitles != null && targetBookTitles.isNotEmpty;
    final targetBookPlaceholders = hasCommentaryFilter
        ? List.filled(targetBookTitles.length, '?').join(', ')
        : '';
    if (hasCommentaryFilter) {
      parameters.addAll(targetBookTitles);
    }

    // תנאי הפילטר:
    // null     → ללא פילטר (כל הקישורים)
    // ריק      → רק קישורי non-commentary (REFERENCE וכד׳)
    // לא ריק   → קישורי non-commentary + המפרשים הנבחרים
    final commentaryFilterClause = targetBookTitles == null
        ? ''
        : hasCommentaryFilter
            ? 'AND (ct.name IS NULL OR ct.name NOT IN (\'COMMENTARY\', \'TARGUM\') OR tb.title IN ($targetBookPlaceholders))'
            : 'AND (ct.name IS NULL OR ct.name NOT IN (\'COMMENTARY\', \'TARGUM\'))';

    final rows = db.select('''
        SELECT
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tl.heRef as targetLineHeRef,
          tb.title as targetBookTitle,
          tb.categoryId as targetCategoryId,
          tb.fileType as targetFileType,
          ct.name as connectionTypeName
        FROM link l
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.sourceBookId = ?
          AND sl.lineIndex BETWEEN ? AND ?
          $commentaryFilterClause
        ORDER BY sl.lineIndex, tb.orderIndex
      ''', parameters).toMapList();
    return rows;
  } catch (error) {
    rethrow;
  } finally {
    db?.close();
  }
}

List<Map<String, dynamic>> _loadAlternativeStructuresRowsInIsolate({
  required String dbPath,
  required String bookTitle,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);

    final bookResults = db.select(
      'SELECT id FROM book WHERE title = ? LIMIT 1',
      [bookTitle],
    ).toMapList();

    if (bookResults.isEmpty) {
      return const [];
    }

    final bookId = bookResults.first['id'] as int;

    return db.select(
      'SELECT * FROM alt_toc_structure WHERE bookId = ? ORDER BY id',
      [bookId],
    ).toMapList();
  } finally {
    db?.close();
  }
}

/// מתאם כל פעולות הכתיבה לספרים האישיים: add-folder scan, rescan, toggle, remove.
///
/// תור סריאלי יחיד עם ספירת עסוקות נצפית.
/// ה-singleton חי על [DatabaseLibraryProvider] ולכן שורד פירוק ויצירה של widgets.
class PersonalBooksOperationQueue {
  Future<void> _tail = Future.value();

  /// מספר הפעולות הממתינות או הרצות כרגע.
  /// עולה ב-1 מיד כשמוסיפים לתור (לא רק כשמתחיל הביצוע),
  /// כך שה-UI מציג מצב עסוק גם בזמן ההמתנה בתור.
  final ValueNotifier<int> busyCount = ValueNotifier(0);

  bool get isBusy => busyCount.value > 0;

  /// מוסיף [operation] לתור הסריאלי ומחזיר את תוצאתה.
  ///
  /// פעולות מבוצעות בסדר הוספה בלבד, לעולם לא במקביל.
  Future<T> enqueue<T>(Future<T> Function() operation) {
    busyCount.value++; // עולה מיד, עוד לפני הביצוע
    final result = _tail.then<T>((_) async {
      try {
        return await operation();
      } finally {
        busyCount.value--;
      }
    });
    // _tail לעולם לא נדחית; אחרת שרשרת ה-then תיקלע לדד-לוק.
    _tail = result.then<void>((_) {}).catchError((_) {});
    return result;
  }
}

/// תוצאת סריקת תיקייה חיצונית.
///
/// [addedBooks]  - מספר הספרים שנוספו ל-DB בהצלחה.
/// [updatedBooks] - מספר הספרים שעודכנו (שינוי metadata).
/// [failedBooks]  - מספר הספרים שנכשלו בעיבוד (שגיאה חלקית).
/// [fatalError]   - שגיאה קטלנית שמנעה את הסריקה כולה (Isolate נפל וכד׳).
///                  כאשר שגיאה זו קיימת, ספירות הספרים הן 0.
class ScanResult {
  final int addedBooks;
  final int updatedBooks;
  final int failedBooks;
  final Object? fatalError;
  final List<(String title, String reason)> failedDetails;

  const ScanResult({
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.failedBooks = 0,
    this.fatalError,
    this.failedDetails = const [],
  });

  bool get isSuccess => fatalError == null;
  bool get hasPartialFailure => fatalError == null && failedBooks > 0;
  bool get hasChanges => addedBooks > 0 || updatedBooks > 0;
}

/// Library provider that loads books from the SQLite database.
class DatabaseLibraryProvider implements LibraryProvider {
  final SqliteDataProvider _sqliteProvider = SqliteDataProvider.instance;
  final Set<BookCompositeKey> _cachedKeys = {};
  final Map<int, String> _categoryIdToPath = {};
  final Map<int, db_models.Category> _categoriesById = {};
  bool _titlesCached = false;
  String? _bundledTalmudBavliPathCache;
  bool? _bundledTalmudBavliExistsCache;

  /// IDs **טבעיים** (native AUTOINCREMENT) של קטגוריות ב-`user_books.db`
  /// שצורפו ל-Library. שימושי כדי לדעת לאיזה DB לפנות בקריאות
  /// `getBookText`/`getBookToc`/`hasBook` כשרק `categoryId` ידוע (בלי דגל
  /// `preferUserBooks`).
  ///
  /// שים לב: יכולה להיות חפיפה עם IDs של seforim — אם שני ה-DBs קצו 1,2,3…
  /// אז 5 יכול להיות בשניהם. לכן הסט הזה רק *רומז* על user_books, וההכרעה
  /// הסופית נופלת על ה-cache (`_userBooksCachedKeys`) שמשתמש במפתח עם
  /// `isUserBook: true`.
  final Set<int> _userBooksCategoryIds = {};

  /// מיפוי `(title, categoryId, fileType) → BookCompositeKey` עבור ספרים
  /// שמקורם ב-`user_books.db`. נפרד מ-`_cachedKeys` כדי שהמטמון של seforim
  /// לא ייפגע. כל המפתחות כאן עם `isUserBook: true`.
  final Set<BookCompositeKey> _userBooksCachedKeys = {};

  bool _isUserBooksCategoryId(int categoryId) =>
      _userBooksCategoryIds.contains(categoryId);

  bool _shouldUseUserBooks({
    required String title,
    required int categoryId,
    required String fileType,
    required bool preferUserBooks,
  }) {
    if (preferUserBooks) return true;
    // המפתח של user_books תמיד עם `isUserBook: true` — לכן יש להרכיב
    // מפתח-בדיקה תואם.
    final key = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      isUserBook: true,
    );
    if (_userBooksCachedKeys.contains(key)) return true;
    // נפילה לסיגנל החלש יותר — קטגוריה רשומה כקטגוריית user_books, ואין
    // כבר מפתח חזק יותר שאומר ההפך.
    return _isUserBooksCategoryId(categoryId);
  }

  /// תור פעולות יחיד לכל כתיבות ה-DB של ספרים אישיים.
  /// ה-static מאפשר גישה ישירה ב-DatabaseLibraryProvider.operationQueue
  /// גם ממסכים אחרים, בלי להצמד ל-instance.
  static final PersonalBooksOperationQueue operationQueue =
      PersonalBooksOperationQueue();

  /// Singleton instance
  static DatabaseLibraryProvider? _instance;

  DatabaseLibraryProvider._();

  static DatabaseLibraryProvider get instance {
    _instance ??= DatabaseLibraryProvider._();
    return _instance!;
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadBookLinksRowsForTesting({
    required String dbPath,
    required String title,
    required int categoryId,
    required String fileType,
  }) {
    return _loadBookLinksRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadAlternativeStructuresRowsForTesting({
    required String dbPath,
    required String bookTitle,
  }) {
    return _loadAlternativeStructuresRowsInIsolate(
      dbPath: dbPath,
      bookTitle: bookTitle,
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadBookLinksRowsInRangeForTesting({
    required String dbPath,
    required String title,
    required int categoryId,
    required String fileType,
    required int startLineIndex,
    required int endLineIndex,
    List<String>? targetBookTitles,
  }) {
    return _loadBookLinksRowsInRangeInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      startLineIndex: startLineIndex,
      endLineIndex: endLineIndex,
      targetBookTitles: targetBookTitles,
    );
  }

  Future<bool> _bundledTalmudBavliDirectoryExists() async {
    final candidatePaths = DatabaseConstants.getTalmudBavliDirectoryPaths();
    if (_bundledTalmudBavliExistsCache != null &&
        _bundledTalmudBavliPathCache != null &&
        candidatePaths.contains(_bundledTalmudBavliPathCache)) {
      return _bundledTalmudBavliExistsCache!;
    }

    for (final candidatePath in candidatePaths) {
      final exists = await Directory(candidatePath).exists();
      if (exists) {
        _bundledTalmudBavliPathCache = candidatePath;
        _bundledTalmudBavliExistsCache = true;
        return true;
      }
    }

    _bundledTalmudBavliPathCache = candidatePaths.first;
    _bundledTalmudBavliExistsCache = false;
    return false;
  }

  Future<void> _addBundledTalmudBavliPdfBooksToCategory(
    Category category,
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    final bundledPath = _bundledTalmudBavliPathCache;
    if (bundledPath == null || !await _bundledTalmudBavliDirectoryExists()) {
      return;
    }

    final bundledDir = Directory(bundledPath);

    // Build a map: title → sub-category that contains a TextBook with that title.
    // This lets us place each PDF next to its matching text book.
    final Map<String, Category> titleToSubCategory = {};
    for (final sub in category.getAllCategories()) {
      for (final book in sub.books) {
        if (book is TextBook) {
          titleToSubCategory[book.title] = sub;
        }
      }
    }

    // Collect all existing PDF titles across the entire tree to avoid duplicates.
    final existingPdfTitles = <String>{};
    for (final book in category.getAllBooks()) {
      if (book is PdfBook) existingPdfTitles.add(book.title);
    }

    final modifiedCategories = <Category>{};
    Category? orphanCategory;

    await for (final entity in bundledDir.list()) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.pdf')) continue;

      final title = getTitleFromPath(entity.path);
      if (existingPdfTitles.contains(title)) continue;

      // Place PDF in the sub-category of its matching TextBook.
      // Orphans (no matching TextBook) go into a dedicated sub-category
      // appended after "סדר טהרות" so they don't float to the top.
      if (orphanCategory == null && !titleToSubCategory.containsKey(title)) {
        // Place right after "סדר טהרות" (order 30 in DB) → use 31.
        final tohorotOrder = category.subCategories
            .where((c) => c.title == 'סדר טהרות')
            .firstOrNull
            ?.order;
        final orphanOrder = tohorotOrder != null ? tohorotOrder + 1 : 31;
        orphanCategory = Category(
          title: 'מסכתות נוספות',
          description: '',
          shortDescription: '',
          subCategories: [],
          books: [],
          parent: category,
          order: orphanOrder,
        );
        category.subCategories.add(orphanCategory);
        category.subCategories.sort((a, b) => a.order.compareTo(b.order));
      }
      final targetCategory =
          titleToSubCategory[title] ?? orphanCategory ?? category;
      final targetCategoryId = titleToSubCategory.containsKey(title)
          ? targetCategory.title.hashCode
          : DatabaseConstants.talmudBavliFolderName.hashCode;

      final bookMeta = metadata[title];
      final matchingTextBook = targetCategory.books
          .where((b) => b is TextBook && b.title == title)
          .firstOrNull;
      final pdfBook = PdfBook(
        id: matchingTextBook?.id,
        title: title,
        category: targetCategory,
        path: entity.path,
        filePath: entity.path,
        author: bookMeta?['author'] as String?,
        heShortDesc: bookMeta?['heShortDesc'] as String?,
        pubDate: bookMeta?['pubDate'] as String?,
        pubPlace: bookMeta?['pubPlace'] as String?,
        order: matchingTextBook?.order ?? bookMeta?['order'] as int? ?? 999,
        topics: DatabaseConstants.talmudBavliFolderName,
        categoryPath: DatabaseConstants.talmudBavliFolderName,
        categoryId: targetCategoryId,
      );

      targetCategory.books.add(pdfBook);
      existingPdfTitles.add(title);
      modifiedCategories.add(targetCategory);
      _cachedKeys.add(BookCompositeKey.create(
        title: title,
        categoryId: targetCategoryId,
        fileType: 'pdf',
      ));
      _categoryIdToPath[targetCategoryId] =
          DatabaseConstants.talmudBavliFolderName;
    }

    // Re-sort only the categories that were modified.
    for (final cat in modifiedCategories) {
      cat.books.sort((a, b) => a.order.compareTo(b.order));
    }
  }

  @visibleForTesting
  static bool shouldIncludeBookByPath(
    String? filePath, {
    required bool hasTalmudBavliDirectory,
    String? talmudBavliDirectoryPath,
  }) {
    if (hasTalmudBavliDirectory) {
      return true;
    }

    return !DatabaseConstants.isTalmudBavliFilePath(
      filePath,
      talmudBavliDirectoryPath: talmudBavliDirectoryPath,
    );
  }

  /// Helper method to build topics string from database book and category path
  String _buildTopics(db_models.Book dbBook, String categoryPath) {
    String topics = dbBook.topics.map((t) => t.name).join(', ');
    if (topics.isEmpty && categoryPath.isNotEmpty) {
      topics = categoryPath
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(', ');
    }
    return topics;
  }

  @override
  String get providerId => 'database';

  @override
  String get displayName => 'מסד נתונים';

  @override
  String get sourceIndicator => 'DB';

  @override
  int get priority => 1; // Higher priority than file system

  @override
  bool get isInitialized => _sqliteProvider.isInitialized;

  @override
  Future<void> initialize() async {
    await _sqliteProvider.initialize();
    debugPrint('💾 DatabaseLibraryProvider initialized');
  }

  @override
  Future<Map<String, List<Book>>> loadBooks(
      Map<String, Map<String, dynamic>> metadata) async {
    final Map<String, List<Book>> booksByCategory = {};

    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty');
      return booksByCategory;
    }

    try {
      final hasTalmudBavliDirectory =
          await _bundledTalmudBavliDirectoryExists();
      final dbBooks = await _sqliteProvider.repository!.getAllBooks();
      final categories = await _sqliteProvider.repository!.getAllCategories();
      debugPrint('💾 Database found ${dbBooks.length} books');

      // Build category paths and caches
      final Map<int, db_models.Category> categoryMap = {
        for (var c in categories) c.id: c
      };
      final Map<int, String> categoryPaths = {};

      String getPath(int? categoryId) {
        if (categoryId == null) return '';
        if (categoryPaths.containsKey(categoryId)) {
          return categoryPaths[categoryId]!;
        }

        final List<String> path = [];
        var currentId = categoryId;
        // Prevent infinite loops with a max depth check or visited set if needed,
        // but assuming DAG/Tree structure here.
        while (categoryMap.containsKey(currentId)) {
          final category = categoryMap[currentId]!;
          path.insert(0, category.title);
          if (category.parentId == null) break;
          currentId = category.parentId!;
        }
        final pathStr = path.join(', ');
        categoryPaths[categoryId] = pathStr;
        return pathStr;
      }

      // Cache titles for quick lookup
      _cachedKeys.clear();
      _categoryIdToPath.clear();
      _categoriesById
        ..clear()
        ..addAll(categoryMap);

      for (final dbBook in dbBooks) {
        if (!shouldIncludeBookByPath(
          dbBook.filePath,
          hasTalmudBavliDirectory: hasTalmudBavliDirectory,
          talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
        )) {
          continue;
        }

        final categoryPath = getPath(dbBook.categoryId);
        _categoryIdToPath[dbBook.categoryId] = categoryPath;
        _cachedKeys.add(BookCompositeKey.create(
          title: dbBook.title,
          categoryId: dbBook.categoryId,
          fileType: dbBook.fileType,
        ));

        final categoryName =
            dbBook.topics.isNotEmpty ? dbBook.topics.first.name : 'ללא קטגוריה';

        final topics = _buildTopics(dbBook, categoryPath);

        final book = TextBook(
          id: dbBook.id,
          title: dbBook.title,
          author: dbBook.authors.isNotEmpty ? dbBook.authors.first.name : null,
          heShortDesc: dbBook.heShortDesc,
          pubDate:
              dbBook.pubDates.isNotEmpty ? dbBook.pubDates.first.date : null,
          pubPlace:
              dbBook.pubPlaces.isNotEmpty ? dbBook.pubPlaces.first.name : null,
          order: dbBook.order.toInt(),
          topics: topics,
          fileType: dbBook.fileType,
          categoryPath: categoryPath,
          categoryId: dbBook.categoryId,
          externalLibraryId: dbBook.externalLibraryId,
        );

        booksByCategory.putIfAbsent(categoryName, () => []);
        booksByCategory[categoryName]!.add(book);
      }

      _titlesCached = true;
      debugPrint(
          '💾 Database loaded ${dbBooks.length} books into ${booksByCategory.length} categories');
    } catch (e) {
      debugPrint('⚠️ Error loading books from database: $e');
    }

    return booksByCategory;
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    final seforimKey = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (_cachedKeys.contains(seforimKey)) {
      return true;
    }
    final userBookKey = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      isUserBook: true,
    );
    if (_userBooksCachedKeys.contains(userBookKey)) {
      return true;
    }

    // אם ה-categoryId רשום כקטגוריית user_books, נבדוק בקובץ הזה.
    if (_isUserBooksCategoryId(categoryId)) {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final book = await repo.getBookByTitleCategoryAndFileType(
        title,
        categoryId,
        userBookKey.fileType,
      );
      return book != null;
    }

    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return false;
    }

    final book = await repository.getBookByTitleCategoryAndFileType(
      title,
      categoryId,
      seforimKey.fileType,
    );
    return book != null;
  }

  /// Finds the category path for a given book title.
  /// Returns null if the book is not found in the database.
  Future<String?> findCategoryPathForBook(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    final normalizedFileType = BookCompositeKey.normalizeFileType(fileType);

    if (_titlesCached) {
      final matchedKey = _findMatchingCachedKey(
        title,
        categoryId: categoryId,
        normalizedFileType: normalizedFileType,
        includeUserBooks: true,
      );

      if (matchedKey != null) {
        final path = await _getPathForCategoryId(
          matchedKey.categoryId,
          fromUserBooks: matchedKey.isUserBook,
        );
        return path.isEmpty ? null : path;
      }
    }

    try {
      final resolvedBook = await BookDatabaseResolver.resolveBook(
        title: title,
        categoryId: categoryId,
        fileType: normalizedFileType,
        preferUserBooks:
            categoryId != null && _isUserBooksCategoryId(categoryId),
      );
      if (resolvedBook == null) return null;
      // categoryId טבעי לשני הסוגים, ההבחנה נעשית דרך `isUserBooks`.
      final path = await _getPathForCategoryId(
        resolvedBook.book.categoryId,
        fromUserBooks: resolvedBook.isUserBooks,
      );
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// Helper to get full path for a category ID from DB
  ///
  /// [fromUserBooks] קובע מאיזה DB לקרוא — חשוב כי `categoryId` כבר טבעי
  /// ויכול להתקיים בשניהם.
  Future<String> _getPathForCategoryId(
    int categoryId, {
    bool fromUserBooks = false,
  }) async {
    final cachedPath = _categoryIdToPath[categoryId];
    if (cachedPath != null && !fromUserBooks) return cachedPath;

    if (fromUserBooks || _isUserBooksCategoryId(categoryId)) {
      try {
        final repository = await UserBooksDatabaseHolder.instance.repository;
        final categoryPath = await BookDatabaseResolver.buildCategoryPath(
            repository, categoryId);
        if (categoryPath.isNotEmpty && !fromUserBooks) {
          _categoryIdToPath[categoryId] = categoryPath;
        }
        return categoryPath;
      } catch (_) {
        return '';
      }
    }

    final repository = _sqliteProvider.repository;
    if (repository == null) return '';

    if (_categoriesById.isEmpty) {
      final categories = await repository.getAllCategories();
      for (final category in categories) {
        _categoriesById[category.id] = category;
      }
    }

    final pathParts = <String>[];
    final visited = <int>{};
    int? currentId = categoryId;

    while (currentId != null && visited.add(currentId)) {
      var category = _categoriesById[currentId];
      category ??= await repository.getCategory(currentId);
      if (category == null) {
        break;
      }
      _categoriesById[category.id] = category;
      pathParts.insert(0, category.title);
      currentId = category.parentId;
    }

    final categoryPath = pathParts.join(', ');
    if (categoryPath.isNotEmpty) {
      _categoryIdToPath[categoryId] = categoryPath;
    }
    return categoryPath;
  }

  /// Checks if any book with the given title exists in the database.
  Future<bool> hasBookWithTitle(String title) async {
    if (!_titlesCached) {
      await getDatabaseOnlyBookTitles();
    }

    for (final key in _cachedKeys) {
      if (key.matchesTitle(title)) return true;
    }
    for (final key in _userBooksCachedKeys) {
      if (key.matchesTitle(title)) return true;
    }
    return false;
  }

  BookCompositeKey? _findMatchingCachedKey(
    String title, {
    int? categoryId,
    required String normalizedFileType,
    required bool includeUserBooks,
  }) {
    if (categoryId != null) {
      // seforim קודם (priority גבוה), אז user_books — כי categoryId יכול
      // להתקיים בשני ה-DBs.
      final seforimKey = BookCompositeKey.create(
        title: title,
        categoryId: categoryId,
        fileType: normalizedFileType,
      );
      if (_cachedKeys.contains(seforimKey)) {
        return seforimKey;
      }
      if (includeUserBooks) {
        final userBookKey = BookCompositeKey.create(
          title: title,
          categoryId: categoryId,
          fileType: normalizedFileType,
          isUserBook: true,
        );
        if (_userBooksCachedKeys.contains(userBookKey)) {
          return userBookKey;
        }
      }
    }

    final candidateSets = <Set<BookCompositeKey>>[
      _cachedKeys,
      if (includeUserBooks) _userBooksCachedKeys,
    ];
    for (final candidateSet in candidateSets) {
      for (final key in candidateSet) {
        if (!key.matchesTitle(title)) continue;
        if (normalizedFileType.isNotEmpty &&
            key.fileType != normalizedFileType) {
          continue;
        }
        return key;
      }
    }

    return null;
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    // ספרים מתיקיות מותאמות אישית: לקרוא מ-user_books.db (תוכן מהקובץ
    // עצמו אם isFileBacked, אחרת משורות ה-line).
    if (_shouldUseUserBooks(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    )) {
      try {
        final repo = await UserBooksDatabaseHolder.instance.repository;
        final book = await repo.getBookByTitleCategoryAndFileType(
            title, categoryId, fileType);
        if (book == null) return null;
        if (book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          if (await file.exists()) {
            return await file.readAsString();
          }
        }
        // נופל לטעינה מתוך ה-DB עצמו (טבלת `line`).
        return await _readBookTextFromUserBooksDb(
            repo, book.id, book.totalLines);
      } catch (e) {
        debugPrint('⚠️ Error reading user book text: $e');
        return null;
      }
    }

    if (_sqliteProvider.repository != null) {
      try {
        final book = await _sqliteProvider.repository!
            .getBookByTitleCategoryAndFileType(title, categoryId, fileType);
        if (book != null && book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          if (await file.exists()) {
            if ((book.fileType ?? '').toLowerCase() == 'docx') {
              final bytes = await file.readAsBytes();
              final t = title;
              return await Isolate.run(() => docxToText(bytes, t));
            }
            return await file.readAsString();
          }
        }
        // If not external or file not found, try DB text
        if (book != null) {
          return await _sqliteProvider.getBookTextFromDb(
            title,
            categoryId,
            fileType,
            preferUserBooks,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Error reading external book text: $e');
      }
    }
    return null;
  }

  /// קורא את תוכן הספר משורות ה-`line` של `user_books.db` ומחזיר טקסט מאוחד.
  Future<String?> _readBookTextFromUserBooksDb(
      SeforimRepository repo, int bookId, int totalLines) async {
    try {
      if (totalLines <= 0) return null;
      final lines = await repo.getLines(bookId, 0, totalLines - 1);
      if (lines.isEmpty) return null;
      return lines.map((l) => l.content).join('\n');
    } catch (e) {
      debugPrint('⚠️ Error loading user_books lines for book $bookId: $e');
      return null;
    }
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    if (_shouldUseUserBooks(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    )) {
      try {
        final repo = await UserBooksDatabaseHolder.instance.repository;
        final book = await repo.getBookByTitleCategoryAndFileType(
            title, categoryId, fileType);
        if (book == null) return null;
        return await _loadTocFromUserBooksRepo(repo, book.id);
      } catch (e) {
        debugPrint('⚠️ Error reading user book TOC: $e');
        return null;
      }
    }
    return await _sqliteProvider.getBookTocFromDb(
      title,
      categoryId,
      fileType,
      preferUserBooks,
    );
  }

  /// טוען TOC של ספר מ-`user_books.db` ומחזיר עץ TocEntry של מודל ה-app.
  /// משתמש ב-`getBookTocs` של ה-repository (שכבר עושה JOIN ל-tocText
  /// ומחזיר רשומות migration עם `text` מאוכלס).
  Future<List<TocEntry>?> _loadTocFromUserBooksRepo(
      SeforimRepository repo, int bookId) async {
    final tocEntries = await repo.getBookTocs(bookId);
    if (tocEntries.isEmpty) return null;
    final idToEntry = <int, TocEntry>{};
    final roots = <TocEntry>[];
    for (final migrationToc in tocEntries) {
      final parent = migrationToc.parentId != null
          ? idToEntry[migrationToc.parentId]
          : null;
      final entry = TocEntry(
        text: migrationToc.text,
        index: migrationToc.lineIndex ?? 0,
        level: migrationToc.level,
        parent: parent,
      );
      idToEntry[migrationToc.id] = entry;
      if (parent != null) {
        parent.children.add(entry);
      } else {
        roots.add(entry);
      }
    }
    return roots;
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    // Return only books that are actually in the database
    final base = await getDatabaseOnlyBookTitles();
    if (_userBooksCachedKeys.isEmpty) return base;
    return {
      ...base,
      ..._userBooksCachedKeys.map((key) => key.toStorageKey()),
    };
  }

  /// Gets book titles that are ONLY in the database
  Future<Set<String>> getDatabaseOnlyBookTitles() async {
    if (_titlesCached) {
      return _cachedKeys.map((key) => key.toStorageKey()).toSet();
    }

    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return {};
    }

    try {
      final hasTalmudBavliDirectory =
          await _bundledTalmudBavliDirectoryExists();
      final books = await repository.getAllBooks();
      final categories = await repository.getAllCategories();

      _cachedKeys.clear();
      _categoriesById
        ..clear()
        ..addEntries(
            categories.map((category) => MapEntry(category.id, category)));

      for (final book in books) {
        if (!shouldIncludeBookByPath(
          book.filePath,
          hasTalmudBavliDirectory: hasTalmudBavliDirectory,
          talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
        )) {
          continue;
        }

        _cachedKeys.add(BookCompositeKey.create(
          title: book.title,
          categoryId: book.categoryId,
          fileType: book.fileType,
        ));

        if (!_categoryIdToPath.containsKey(book.categoryId)) {
          final categoryPath = await _getPathForCategoryId(book.categoryId);
          if (categoryPath.isNotEmpty) {
            _categoryIdToPath[book.categoryId] = categoryPath;
          }
        }
      }

      _titlesCached = true;
      return _cachedKeys.map((key) => key.toStorageKey()).toSet();
    } catch (e) {
      debugPrint('⚠️ Error building DB key cache: $e');
      return {};
    }
  }

  /// Clears the cached titles (call when database changes)
  void clearCache() {
    _cachedKeys.clear();
    _categoryIdToPath.clear();
    _categoriesById.clear();
    _userBooksCachedKeys.clear();
    _userBooksCategoryIds.clear();
    _titlesCached = false;
    _bundledTalmudBavliPathCache = null;
    _bundledTalmudBavliExistsCache = null;
    debugPrint('💾 Database cache cleared');
  }

  @visibleForTesting
  void seedCacheForTesting({
    required Iterable<BookCompositeKey> keys,
    Map<int, String>? categoryIdToPath,
    bool titlesCached = true,
  }) {
    _cachedKeys
      ..clear()
      ..addAll(keys);
    _categoryIdToPath
      ..clear()
      ..addAll(categoryIdToPath ?? const {});
    _titlesCached = titlesCached;
  }

  /// Gets database statistics
  Future<Map<String, int>> getStats() async {
    return await _sqliteProvider.getDatabaseStats();
  }

  /// Gets the underlying SQLite provider for advanced operations
  SqliteDataProvider get sqliteProvider => _sqliteProvider;

  /// Private helper for database operations to reduce boilerplate
  Future<T> _dbOperation<T>(
    Future<T> Function(sqlite3.Database db) operation,
    T defaultValue,
    String errorContext,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return defaultValue;
    }

    try {
      final db = await _sqliteProvider.repository!.database.database;
      return await operation(db);
    } catch (e) {
      debugPrint('⚠️ Error in $errorContext: $e');
      return defaultValue;
    }
  }

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty library');
      return Library(categories: []);
    }

    debugPrint('💾 Building library catalog from database...');

    // CRITICAL: Clear cache before rebuilding to ensure fresh data
    _titlesCached = false;
    _cachedKeys.clear();
    _categoryIdToPath.clear();
    _categoriesById.clear();

    final repository = _sqliteProvider.repository!;

    final hasTalmudBavliDirectory = await _bundledTalmudBavliDirectoryExists();

    // OPTIMIZATION: Load minimal book data first, then load authors in one
    // batch query inside the same transaction to avoid per-book DB work.
    // full book data with relations (25+ columns + 4 junction table queries).
    // Both queries run inside a single transaction to prevent BackgroundSync
    // from locking the DB between them (which caused 17s delays).
    final tQuery = DateTime.now();

    late final List<Map<String, dynamic>> allDbBooks;
    late final List<Map<String, dynamic>> allCatRows;
    late final Map<int, String> authorsByBookId;

    final db = await repository.database.database;
    withTransaction(db, () {
      allDbBooks = repository.database.bookDao.getAllBooksMinimal(db);
      allCatRows = repository.database.categoryDao.getAllCategoryRows(db);
      authorsByBookId = repository.database.bookDao.getBookAuthorsMap(db);
    });

    debugPrint(
        '⏱️ Transaction (books+categories): ${DateTime.now().difference(tQuery).inMilliseconds}ms (${allDbBooks.length} books, ${allCatRows.length} categories)');

    final booksByCategory = <int, List<Map<String, dynamic>>>{};
    for (final bookData in allDbBooks) {
      if (!shouldIncludeBookByPath(
        bookData['filePath'] as String?,
        hasTalmudBavliDirectory: hasTalmudBavliDirectory,
        talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
      )) {
        continue;
      }

      // Use null-safe cast: corrupt data (null categoryId) should not crash the
      // entire library load. Books with no category are silently skipped.
      final catId = bookData['categoryId'] as int?;
      if (catId == null) continue;
      booksByCategory.putIfAbsent(catId, () => []);
      booksByCategory[catId]!.add(bookData);
    }

    // Parse category rows into model objects (filtering debug-only categories)
    final allCategories = allCatRows
        .map((row) => db_models.Category.fromJson(row))
        .where((cat) => cat.title != 'אודות התוכנה')
        .toList();
    _categoriesById
      ..clear()
      ..addEntries(allCategories.map((cat) => MapEntry(cat.id, cat)));

    final categoriesByParent = <int?, List<db_models.Category>>{};
    for (final cat in allCategories) {
      categoriesByParent.putIfAbsent(cat.parentId, () => []);
      categoriesByParent[cat.parentId]!.add(cat);
    }

    debugPrint('💾 Loaded ${allCategories.length} categories');

    // Build catalog tree starting from root categories (parentId = null)
    // Sort root categories by orderIndex (like Kotlin: sortedBy { it.order })
    final rootCategories = (categoriesByParent[null] ?? [])
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final Library library = Library(categories: []);

    debugPrint('💾 Found ${rootCategories.length} root categories');

    final tTree = DateTime.now();
    int totalCategories = 0;
    for (final rootCategory in rootCategories) {
      final catalogCategory = _buildCatalogCategoryRecursiveOptimized(
        rootCategory,
        booksByCategory,
        categoriesByParent,
        authorsByBookId,
        library,
        metadata,
      );
      library.subCategories.add(catalogCategory);
      totalCategories += _countCategories(catalogCategory);
    }
    debugPrint(
        '⏱️ Category tree build: ${DateTime.now().difference(tTree).inMilliseconds}ms');

    final talmudBavliCategory = library.subCategories.where((category) {
      return category.title == DatabaseConstants.talmudBavliFolderName;
    }).firstOrNull;
    if (talmudBavliCategory != null) {
      await _addBundledTalmudBavliPdfBooksToCategory(
        talmudBavliCategory,
        metadata,
      );
    }

    // צירוף ספרים מתיקיות מותאמות אישית מ-user_books.db תחת קטגוריית
    // "ספרים אישיים" באותו עץ.
    await _appendUserBooksToLibrary(library, metadata);

    // NOTE: Sorting is now done during build (like Kotlin), no need for post-sort
    // _sortLibraryRecursive(library); // Removed - sorting happens in _buildCatalogCategoryRecursiveOptimized

    // Mark titles as cached
    _titlesCached = true;

    debugPrint(
        '💾 Database catalog built with $totalCategories categories and ${allDbBooks.length} books from DB');

    // NOTE: Library is now built ONLY from the database.
    // Files that are not in the DB will not appear in the library browser.
    // This is intentional - all book/file information should be in the DB.

    return library;
  }

  /// Gets or creates a category in the database for the given path.
  /// Returns the category ID.
  /// Implements the logic from CATEGORY_SYNC_PLAN.md - Step 3
  ///
  /// [repository] — ה-repository שאליו רושמים את הקטגוריות (יכול להיות
  /// user_books או seforim, תלוי בזרימה הקוראת).
  Future<int> _getOrCreateCategoryInDb(
    List<String> categoryPath,
    SeforimRepository repository,
  ) async {
    if (categoryPath.isEmpty) {
      // Return default category
      final defaultCategory =
          await repository.getCategoryByTitle('ללא קטגוריה');
      if (defaultCategory != null) {
        return defaultCategory.id;
      }
      // Create default category if it doesn't exist
      return await repository.insertCategory(
        db_models.Category(
          id: 0,
          title: 'ללא קטגוריה',
          parentId: null,
          level: 0,
        ),
      );
    }

    // Start from root (parentId = null)
    int? parentId;
    int currentLevel = 0;

    // Walk through each level of the category hierarchy
    for (final categoryName in categoryPath) {
      // Try to find existing category with this name under the current parent
      final existingCategory =
          await repository.getCategoryByTitleAndParent(categoryName, parentId);

      if (existingCategory != null) {
        // Category exists - use it as parent for next level
        parentId = existingCategory.id;
        currentLevel = existingCategory.level + 1;
      } else {
        // Category doesn't exist - create it
        final newCategoryId = await repository.insertCategory(
          db_models.Category(
            id: 0, // Will be auto-generated
            title: categoryName,
            parentId: parentId,
            level: currentLevel,
          ),
        );

        // Use the new category as parent for next level
        parentId = newCategoryId;
        currentLevel++;
      }
    }

    // Return the ID of the final (deepest) category
    return parentId!;
  }

  /// Parses PDF outline and converts to TocEntry format.
  Future<List<TocEntry>> _parsePdfOutline(File file) async {
    try {
      final document = await PdfDocument.openFile(file.path);
      final outline = await document.loadOutline();

      if (outline.isEmpty) {
        return [];
      }

      final entries = <TocEntry>[];
      _convertPdfOutlineToTocEntries(outline, entries, level: 1);

      return entries;
    } catch (e) {
      debugPrint('⚠️ Failed to parse PDF outline: $e');
      return [];
    }
  }

  /// Recursively converts PDF outline nodes to TocEntry format.
  void _convertPdfOutlineToTocEntries(
    List<PdfOutlineNode> nodes,
    List<TocEntry> entries, {
    required int level,
    TocEntry? parent,
  }) {
    for (final node in nodes) {
      final pageNumber = node.dest?.pageNumber ?? 0;

      final entry = TocEntry(
        text: node.title,
        index: pageNumber,
        level: level,
        parent: parent,
      );

      // Process children recursively
      if (node.children.isNotEmpty) {
        _convertPdfOutlineToTocEntries(
          node.children,
          entry.children,
          level: level + 1,
          parent: entry,
        );
      }

      entries.add(entry);
    }
  }

  /// Recursively converts TocEntry objects to DB format.
  void _convertTocEntriesToDb(
    List<TocEntry> entries,
    List<db_models.TocEntry> dbEntries,
    int bookId,
    int? parentId,
  ) {
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isLastChild = i == entries.length - 1;
      final hasChildren = entry.children.isNotEmpty;
      final localEntryId = dbEntries.length + 1;

      final dbEntry = db_models.TocEntry(
        id: localEntryId,
        bookId: bookId,
        parentId: parentId,
        text: entry.text,
        level: entry.level,
        lineId: null, // No line table entry for external books
        lineIndex: entry.index, // Store the index directly for external books
        isLastChild: isLastChild,
        hasChildren: hasChildren,
      );

      dbEntries.add(dbEntry);

      if (hasChildren) {
        _convertTocEntriesToDb(
          entry.children,
          dbEntries,
          bookId,
          localEntryId,
        );
      }
    }
  }

  /// Recursively builds a catalog category with its subcategories and books (OPTIMIZED - no async).
  /// Mirrors the Kotlin buildCatalogCategoryRecursive logic:
  /// - Books are sorted by order
  /// - Subcategories are sorted by orderIndex
  Category _buildCatalogCategoryRecursiveOptimized(
    db_models.Category dbCategory,
    Map<int, List<Map<String, dynamic>>> booksByCategory,
    Map<int?, List<db_models.Category>> categoriesByParent,
    Map<int, String> authorsByBookId,
    Category parent,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    // Create the category using orderIndex from DB (like Kotlin uses category.order)
    final category = Category(
      title: dbCategory.title,
      description: metadata[dbCategory.title]?['heDesc'] ?? '',
      shortDescription: metadata[dbCategory.title]?['heShortDesc'] ?? '',
      order: dbCategory.orderIndex,
      subCategories: [],
      books: [],
      parent: parent,
    );

    // Get books for this category and sort by order (like Kotlin: sortedBy { it.order })
    final dbBooks = (booksByCategory[dbCategory.id] ?? [])
      ..sort((a, b) {
        final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
        final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
        return orderA.compareTo(orderB);
      });
    for (final dbBook in dbBooks) {
      final book = _convertMinimalBookMapToBook(
        dbBook,
        category,
        metadata,
        authorFromDatabase: authorsByBookId[dbBook['id'] as int? ?? 0],
      );
      if (book == null) continue;
      category.books.add(book);

      // Cache the book key for provider mapping
      final key = BookCompositeKey.create(
        title: book.title,
        categoryId: dbCategory.id,
        fileType: book.fileType,
      );
      _cachedKeys.add(key);
      if (book.categoryPath != null && book.categoryPath!.isNotEmpty) {
        _categoryIdToPath[dbCategory.id] = book.categoryPath!;
      }
    }

    // Get subcategories sorted by orderIndex (like Kotlin: sortedBy { it.order })
    final children = (categoriesByParent[dbCategory.id] ?? [])
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    for (final child in children) {
      final subCategory = _buildCatalogCategoryRecursiveOptimized(
        child,
        booksByCategory,
        categoriesByParent,
        authorsByBookId,
        category,
        metadata,
      );
      category.subCategories.add(subCategory);
    }

    return category;
  }

  /// מצרף את עץ הקטגוריות והספרים מ-`user_books.db` אל תוך [library]
  /// תחת הקטגוריה "ספרים אישיים". אם הקטגוריה כבר קיימת ב-[library]
  /// (למשל מ-seforim.db legacy שלא נוקה עדיין), היא מתמזגת תוכן הספרים
  /// וה-subCategories.
  Future<void> _appendUserBooksToLibrary(
    Library library,
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    try {
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      if (!await File(dbPath).exists()) {
        return;
      }

      // ניקוי הקאשים מבוצע רק אחרי שווידאנו שיש user_books.db לטעון.
      // ככה אם הקובץ נמחק בין קריאות לא נאבד את המצב הקודם בלי החלפה.
      _userBooksCategoryIds.clear();
      _userBooksCachedKeys.clear();

      final repo = await UserBooksDatabaseHolder.instance.repository;

      late final List<Map<String, dynamic>> userBooks;
      late final List<Map<String, dynamic>> userCats;
      late final Map<int, String> userAuthors;

      final db = await repo.database.database;
      withTransaction(db, () {
        userBooks = repo.database.bookDao.getAllBooksMinimal(db);
        userCats = repo.database.categoryDao.getAllCategoryRows(db);
        userAuthors = repo.database.bookDao.getBookAuthorsMap(db);
      });

      if (userBooks.isEmpty && userCats.isEmpty) {
        return;
      }

      // קיבוץ ספרים לפי categoryId.
      final booksByCategory = <int, List<Map<String, dynamic>>>{};
      for (final bookData in userBooks) {
        final catId = bookData['categoryId'] as int?;
        if (catId == null) continue;
        booksByCategory.putIfAbsent(catId, () => []).add(bookData);
      }

      // קיבוץ קטגוריות לפי parentId.
      final allUserCategories =
          userCats.map((row) => db_models.Category.fromJson(row)).toList();
      final categoriesByParent = <int?, List<db_models.Category>>{};
      for (final cat in allUserCategories) {
        categoriesByParent.putIfAbsent(cat.parentId, () => []).add(cat);
      }

      // חיפוש קטגוריית "ספרים אישיים" ברמת השורש של user_books.db.
      final rootCats = categoriesByParent[null] ?? [];
      final personalRootInUserDb =
          rootCats.where((c) => c.title == 'ספרים אישיים').firstOrNull;
      if (personalRootInUserDb == null) {
        return;
      }

      // איתור / יצירה של קטגוריית "ספרים אישיים" ב-Library.
      Category? personalCategoryInLibrary = library.subCategories
          .where((c) => c.title == 'ספרים אישיים')
          .firstOrNull;
      personalCategoryInLibrary ??= () {
        final created = Category(
          title: 'ספרים אישיים',
          description: metadata['ספרים אישיים']?['heDesc'] ?? '',
          shortDescription: metadata['ספרים אישיים']?['heShortDesc'] ?? '',
          order: personalRootInUserDb.orderIndex,
          subCategories: [],
          books: [],
          parent: library,
        );
        library.subCategories.add(created);
        return created;
      }();

      // ID טבעי (לא offset) של "ספרים אישיים" מ-user_books.db.
      final personalRootId = personalRootInUserDb.id;
      _userBooksCategoryIds.add(personalRootId);

      // ספרים שיושבים ישירות תחת "ספרים אישיים" (בד"כ אין כאלה — תיקיות
      // הן רמה אחת מתחת — אבל מטפלים ליתר ביטחון).
      final directBooks = (booksByCategory[personalRootInUserDb.id] ?? [])
        ..sort((a, b) {
          final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
          final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
          return orderA.compareTo(orderB);
        });
      for (final dbBook in directBooks) {
        final book = _convertMinimalBookMapToBook(
          dbBook,
          personalCategoryInLibrary,
          metadata,
          authorFromDatabase: userAuthors[dbBook['id'] as int? ?? 0],
          isUserBook: true,
          idOverride: dbBook['id'] as int? ?? 0,
          categoryIdOverride: personalRootId,
        );
        if (book == null) continue;
        personalCategoryInLibrary.books.add(book);
        _userBooksCachedKeys.add(BookCompositeKey.create(
          title: book.title,
          categoryId: personalRootId,
          fileType: book.fileType,
          isUserBook: true,
        ));
      }

      // תתי-קטגוריות (תיקייה לכל folder מותאם אישית).
      final children = [
        ...?categoriesByParent[personalRootInUserDb.id],
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final child in children) {
        final existing = personalCategoryInLibrary.subCategories
            .where((c) => c.title == child.title)
            .firstOrNull;
        if (existing == null) {
          final builtSubCategory = _buildUserBooksCatalogCategoryRecursive(
            child,
            booksByCategory,
            categoriesByParent,
            userAuthors,
            personalCategoryInLibrary,
            metadata,
          );
          personalCategoryInLibrary.subCategories.add(builtSubCategory);
        } else {
          existing.parent = personalCategoryInLibrary;
          _appendUserBooksContentToCategoryRecursive(
            existing,
            child,
            booksByCategory,
            categoriesByParent,
            userAuthors,
            metadata,
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ Error appending user books to library: $e');
      // הספרייה תיטען בלי הספרים האישיים — דווח כדי שלא נחמיץ DB
      // שבור או הרשאות חסרות.
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
    }
  }

  @visibleForTesting
  void populateUserBooksCategoryForTesting({
    required Category targetCategory,
    required db_models.Category dbCategory,
    required Map<int, List<Map<String, dynamic>>> booksByCategory,
    required Map<int?, List<db_models.Category>> categoriesByParent,
    required Map<int, String> authorsByBookId,
    required Map<String, Map<String, dynamic>> metadata,
  }) {
    _appendUserBooksContentToCategoryRecursive(
      targetCategory,
      dbCategory,
      booksByCategory,
      categoriesByParent,
      authorsByBookId,
      metadata,
    );
  }

  /// וריאנט של [_buildCatalogCategoryRecursiveOptimized] שכותב את ה-IDs
  /// של הקטגוריות והספרים ל-_userBooksCategoryIds/_userBooksCachedKeys
  /// במקום ל-_categoriesById/_cachedKeys של seforim.
  Category _buildUserBooksCatalogCategoryRecursive(
    db_models.Category dbCategory,
    Map<int, List<Map<String, dynamic>>> booksByCategory,
    Map<int?, List<db_models.Category>> categoriesByParent,
    Map<int, String> authorsByBookId,
    Category parent,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    final category = Category(
      title: dbCategory.title,
      description: metadata[dbCategory.title]?['heDesc'] ?? '',
      shortDescription: metadata[dbCategory.title]?['heShortDesc'] ?? '',
      order: dbCategory.orderIndex,
      subCategories: [],
      books: [],
      parent: parent,
    );

    _appendUserBooksContentToCategoryRecursive(
      category,
      dbCategory,
      booksByCategory,
      categoriesByParent,
      authorsByBookId,
      metadata,
    );

    return category;
  }

  void _appendUserBooksContentToCategoryRecursive(
    Category category,
    db_models.Category dbCategory,
    Map<int, List<Map<String, dynamic>>> booksByCategory,
    Map<int?, List<db_models.Category>> categoriesByParent,
    Map<int, String> authorsByBookId,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    // categoryId טבעי מ-user_books.db (בלי offset). הבידול נעשה דרך
    // `_userBooksCategoryIds` ו-`isUserBook: true` במפתח.
    final nativeCategoryId = dbCategory.id;
    _userBooksCategoryIds.add(nativeCategoryId);

    final dbBooks = [
      ...?booksByCategory[dbCategory.id],
    ]..sort((a, b) {
        final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
        final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
        return orderA.compareTo(orderB);
      });
    for (final dbBook in dbBooks) {
      final book = _convertMinimalBookMapToBook(
        dbBook,
        category,
        metadata,
        authorFromDatabase: authorsByBookId[dbBook['id'] as int? ?? 0],
        isUserBook: true,
        idOverride: dbBook['id'] as int? ?? 0,
        categoryIdOverride: nativeCategoryId,
      );
      if (book == null) continue;
      category.books.add(book);
      _userBooksCachedKeys.add(BookCompositeKey.create(
        title: book.title,
        categoryId: nativeCategoryId,
        fileType: book.fileType,
        isUserBook: true,
      ));
    }

    final children = [
      ...?categoriesByParent[dbCategory.id],
    ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    for (final child in children) {
      final existingSubCategory = category.subCategories
          .where((subCategory) => subCategory.title == child.title)
          .firstOrNull;
      if (existingSubCategory == null) {
        final subCategory = _buildUserBooksCatalogCategoryRecursive(
          child,
          booksByCategory,
          categoriesByParent,
          authorsByBookId,
          category,
          metadata,
        );
        category.subCategories.add(subCategory);
      } else {
        existingSubCategory.parent = category;
        _appendUserBooksContentToCategoryRecursive(
          existingSubCategory,
          child,
          booksByCategory,
          categoriesByParent,
          authorsByBookId,
          metadata,
        );
      }
    }
  }

  /// Converts a minimal book map (from getAllBooksMinimal) to the app's Book model.
  /// Uses only the columns available: id, title, categoryId, orderIndex,
  /// fileType, filePath, heShortDesc, author.
  /// Falls back to metadata when the minimal row does not include a field.
  Book? _convertMinimalBookMapToBook(
    Map<String, dynamic> bookMap,
    Category category,
    Map<String, Map<String, dynamic>> metadata, {
    String? authorFromDatabase,
    bool isUserBook = false,
    int? idOverride,
    int? categoryIdOverride,
  }) {
    final title = bookMap['title'] as String;
    final id = idOverride ?? (bookMap['id'] as int? ?? 0);
    final filePath = bookMap['filePath'] as String?;
    final fileType = bookMap['fileType'] as String?;
    final heShortDesc = bookMap['heShortDesc'] as String?;
    final orderDouble = (bookMap['orderIndex'] as num?)?.toDouble() ?? 999.0;
    final order = orderDouble.toInt();
    final categoryId =
        categoryIdOverride ?? (bookMap['categoryId'] as int? ?? 0);

    final bookMeta = metadata[title];

    // Build category path from the Category object
    String getCategoryPath(Category? cat) {
      final List<String> path = [];
      final Set<Category> visited = {};
      while (cat != null && !visited.contains(cat)) {
        if (cat.title == 'ספריית אוצריא') break;
        visited.add(cat);
        path.insert(0, cat.title);
        cat = cat.parent;
      }
      return path.join(', ');
    }

    final categoryPath = getCategoryPath(category);

    // Use metadata for topics (no junction table data available)
    String topics = '';
    if (categoryPath.isNotEmpty) {
      topics = categoryPath
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(', ');
    }

    final author = authorFromDatabase ?? (bookMeta?['author'] as String?);
    final pubDate = bookMeta?['pubDate'] as String?;
    final pubPlace = bookMeta?['pubPlace'] as String?;
    final metaHeShortDesc = heShortDesc ?? bookMeta?['heShortDesc'] as String?;

    final normalizedFileType = (fileType ?? '').toLowerCase();

    // External catalog books (fileType='link') are no longer stored in seforim.db.
    // They are served from a separate database via ExternalCatalogRepository.
    if (normalizedFileType == 'link' || normalizedFileType == 'url') {
      return null;
    }

    if (filePath != null && fileType == 'pdf') {
      return PdfBook(
        id: id,
        title: title,
        category: category,
        path: filePath,
        author: author,
        heShortDesc: metaHeShortDesc,
        pubDate: pubDate,
        pubPlace: pubPlace,
        order: order,
        topics: topics,
        categoryPath: categoryPath,
        categoryId: categoryId,
        isUserBook: isUserBook,
      );
    }

    if (filePath != null && fileType == 'docx') {
      return DocxBook(
        id: id,
        title: title,
        category: category,
        path: filePath,
        author: author,
        heShortDesc: metaHeShortDesc,
        pubDate: pubDate,
        pubPlace: pubPlace,
        order: order,
        topics: topics,
        categoryPath: categoryPath,
        categoryId: categoryId,
        isUserBook: isUserBook,
      );
    }

    return TextBook(
      id: id,
      title: title,
      category: category,
      author: author,
      heShortDesc: metaHeShortDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
      isUserBook: isUserBook,
    );
  }

  /// Counts the total number of categories in the tree.
  int _countCategories(Category category) {
    return 1 +
        category.subCategories
            .fold(0, (sum, sub) => sum + _countCategories(sub));
  }

  @override
  Future<List<Link>> getAllLinksForBook(
      String title, int categoryId, String fileType) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return [];
    }

    try {
      final result = await Isolate.run(
        () => _loadBookLinksRowsInIsolate(
          dbPath: _sqliteProvider.dbPath,
          title: title,
          categoryId: categoryId,
          fileType: fileType,
        ),
      );

      final links = result.map((row) {
        final targetTitle = row['targetBookTitle'] as String;
        final targetLineHeRef = row['targetLineHeRef'] as String?;
        final connectionType =
            row['connectionTypeName'] as String? ?? 'reference';

        return Link(
          heRef: targetLineHeRef?.trim().isNotEmpty == true
              ? targetLineHeRef!.trim()
              : targetTitle,
          index1: (row['sourceLineIndex'] as int) + 1,
          path2: targetTitle,
          index2: (row['targetLineIndex'] as int) + 1,
          connectionType: connectionType,
          targetCategoryId: row['targetCategoryId'] as int?,
          targetFileType: row['targetFileType'] as String?,
        );
      }).toList();

      debugPrint('💾 Found ${links.length} links for book "$title"');
      return links;
    } catch (e) {
      debugPrint('⚠️ Error in getAllLinksForBook "$title": $e');
      return [];
    }
  }

  Future<List<Link>> getLinksForBookRange(
    String title,
    int categoryId,
    String fileType, {
    required int startLineIndex,
    required int endLineIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    final normalizedTargetBookTitles = targetBookTitles
        ?.map((targetTitle) => targetTitle.trim())
        .where((targetTitle) => targetTitle.isNotEmpty)
        .toSet()
        .toList()
      ?..sort();
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return [];
    }

    try {
      final result = await Isolate.run(
        () => _loadBookLinksRowsInRangeInIsolate(
          dbPath: _sqliteProvider.dbPath,
          title: title,
          categoryId: categoryId,
          fileType: fileType,
          startLineIndex: startLineIndex,
          endLineIndex: endLineIndex,
          targetBookTitles: normalizedTargetBookTitles,
        ),
      );

      final links = result.map((row) {
        final targetTitle = row['targetBookTitle'] as String;
        final targetLineHeRef = row['targetLineHeRef'] as String?;
        final connectionType =
            row['connectionTypeName'] as String? ?? 'reference';

        return Link(
          heRef: targetLineHeRef?.trim().isNotEmpty == true
              ? targetLineHeRef!.trim()
              : targetTitle,
          index1: (row['sourceLineIndex'] as int) + 1,
          path2: targetTitle,
          index2: (row['targetLineIndex'] as int) + 1,
          connectionType: connectionType,
          targetCategoryId: row['targetCategoryId'] as int?,
          targetFileType: row['targetFileType'] as String?,
        );
      }).toList();
      return links;
    } catch (e) {
      debugPrint('⚠️ Error in getLinksForBookRange "$title": $e');
      return [];
    }
  }

  @override
  Future<String> getLinkContent(Link link) async {
    if (link.path2.isEmpty) return 'שגיאה: נתיב ריק';
    if (link.index2 <= 0) return 'שגיאה: אינדקס לא תקין';

    final targetTitle = link.path2.contains('/')
        ? link.path2.split('/').last.replaceAll('.txt', '')
        : link.path2;

    final repository = _sqliteProvider.repository;
    if (repository == null) return 'שגיאה: מאגר לא מאותחל';

    try {
      final resolvedBook = await BookDatabaseResolver.resolveBook(
        title: targetTitle,
      );
      if (resolvedBook == null) return 'שגיאה: הספר לא נמצא במסד הנתונים';

      // link.index2 is 1-based; lineIndex in DB is 0-based
      final line = await resolvedBook.repository
          .getLineByIndex(resolvedBook.book.id, link.index2 - 1);
      if (line == null) return 'שגיאה: אינדקס מחוץ לטווח';

      return line.content;
    } catch (e) {
      debugPrint('⚠️ Error in getLinkContent: $e');
      return 'שגיאה בטעינת תוכן המפרש';
    }
  }

  /// Get all alternative TOC structures available in the database for a specific book
  Future<List<AltTocStructure>> getAlternativeStructuresForBook(
      String bookTitle) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return [];
    }

    try {
      final results = await Isolate.run(
        () => _loadAlternativeStructuresRowsInIsolate(
          dbPath: _sqliteProvider.dbPath,
          bookTitle: bookTitle,
        ),
      );

      return results.map((json) => AltTocStructure.fromJson(json)).toList();
    } catch (e) {
      debugPrint(
          '⚠️ Error in getAlternativeStructuresForBook "$bookTitle": $e');
      return [];
    }
  }

  /// Get all alternative TOC structures available in the database
  Future<List<AltTocStructure>> getAlternativeStructures() async {
    return _dbOperation<List<AltTocStructure>>(
      (db) async {
        final results =
            db.select('SELECT * FROM alt_toc_structure').toMapList();
        return results.map((json) => AltTocStructure.fromJson(json)).toList();
      },
      [],
      'getAlternativeStructures',
    );
  }

  /// Get all alternative TOC entries for a specific structure
  Future<List<AltTocEntry>> getAllAlternativeEntries(int structureId) async {
    return _dbOperation<List<AltTocEntry>>(
      (db) async {
        // We join with tocText to get the actual text
        // Order by ID to ensure consistent order (or maybe level/parentId)
        final results = db.select('''
          SELECT e.*, t.text
          FROM alt_toc_entry e
          JOIN tocText t ON e.textId = t.id
          WHERE e.structureId = ?
          ORDER BY e.id
        ''', [structureId]).toMapList();

        return results.map((json) => AltTocEntry.fromJson(json)).toList();
      },
      [],
      'getAllAlternativeEntries $structureId',
    );
  }

  /// מחזיר רשימת (lineIndex, text) לכל ערכי כותרות משנה בעלי שורה מוגדרת
  Future<List<({int lineIndex, String text})>> getAltTocLineIndices(
      int structureId) async {
    return _dbOperation<List<({int lineIndex, String text})>>(
      (db) async {
        final results = db.select('''
          SELECT l.lineIndex, t.text
          FROM alt_toc_entry e
          JOIN tocText t ON e.textId = t.id
          JOIN line l ON e.lineId = l.id
          WHERE e.structureId = ?
          ORDER BY l.lineIndex
        ''', [structureId]).toMapList();

        return results
            .map((r) => (
                  lineIndex: r['lineIndex'] as int,
                  text: r['text'] as String,
                ))
            .toList();
      },
      [],
      'getAltTocLineIndices $structureId',
    );
  }

  /// Get links (books/lines) associated with a specific alternative TOC entry
  Future<List<Link>> getLinksForAltTocEntry(
      int structureId, int altTocEntryId) async {
    return _dbOperation<List<Link>>(
      (db) async {
        // Join line_alt_toc -> line -> book
        final results = db.select('''
          SELECT 
            b.title as bookTitle,
            l.lineIndex,
            l.heRef
          FROM line_alt_toc lat
          JOIN line l ON lat.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE lat.structureId = ? AND lat.altTocEntryId = ?
          ORDER BY b.title, l.lineIndex
        ''', [structureId, altTocEntryId]).toMapList();

        return results.map((row) {
          final bookTitle = row['bookTitle'] as String;
          final lineIndex = row['lineIndex'] as int;

          return Link(
            heRef: row['heRef'] as String? ?? '$bookTitle ${lineIndex + 1}',
            index1: 0, // Not relevant here
            path2: bookTitle,
            index2: lineIndex + 1, // 1-based index for UI
            connectionType: 'alt_toc',
          );
        }).toList();
      },
      [],
      'getLinksForAltTocEntry',
    );
  }

  /// Get the alternative TOC entry associated with a specific book line
  Future<int?> getAltTocEntryForLine(
      String bookTitle, int lineIndex, int structureId) async {
    return _dbOperation<int?>(
      (db) async {
        final results = db.select('''
          SELECT lat.altTocEntryId
          FROM line_alt_toc lat
          JOIN line l ON lat.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE b.title = ? AND l.lineIndex = ? AND lat.structureId = ?
          LIMIT 1
  ''', [bookTitle, lineIndex, structureId]).toMapList();

        if (results.isNotEmpty) {
          return results.first['altTocEntryId'] as int;
        }
        return null;
      },
      null,
      'getAltTocEntryForLine',
    );
  }

  /// This is called when a new custom folder is added.
  ///
  /// Fires the scan in the background and returns immediately.
  /// סורקת תיקייה חיצונית ומוסיפה ספרים ל-DB.
  ///
  /// מחזירה [Future<ScanResult>] עם ספירות ותוצאה. הסריקות מסודרות בתור
  /// פנימי — סריקה חדשה מתחילה רק אחרי שהקודמת מסיימת, כך שאין
  /// כתיבות מקביליות ל-DB גם אם ה-UI לא חוסם.
  ///
  /// [folderPath] - הנתיב המלא לתיקייה לסריקה
  /// [folderName] - שם התצוגה של התיקייה
  /// [repository] - ה-repository לפעולות DB
  Future<ScanResult> scanAndAddExternalBooksFromFolder(
    String folderPath,
    String folderName,
    dynamic repository,
  ) {
    // _doScan never throws; operationQueue handles busyCount and serialization.
    return operationQueue.enqueue(
      () => _doScan(folderPath, folderName, repository),
    );
  }

  Future<ScanResult> _doScan(
    String folderPath,
    String folderName,
    dynamic repository,
  ) async {
    debugPrint('📁 Scanning custom folder for external books: $folderPath');

    int added = 0;
    int updated = 0;
    int failed = 0;
    final failedDetails = <(String, String)>[];

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        debugPrint('⚠️ Folder does not exist: $folderPath');
        return const ScanResult(fatalError: 'התיקייה לא נמצאה');
      }

      // Phase 1 (background isolate): scan directory, check DB existence via a
      // direct sqlite3 read-only connection, and parse TXT/DOCX TOC only for
      // genuinely new books. Unchanged books are filtered out here.
      //
      // ה-DB שאליו משווים בסריקה הוא `user_books.db` (לא `seforim.db`),
      // כי הסריקה הזו טוענת ספרים מתיקיות מותאמות אישית בלבד.
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      final discovered = await Isolate.run(
        () => _scanExternalFolderInIsolate((folderPath, folderName, dbPath)),
      );
      debugPrint(
          '📁 Isolate found ${discovered.length} books to process in $folderPath');

      // Phase 2 (main isolate): only metadata updates + new-book inserts.
      // This is deliberately light: unchanged books were already filtered in
      // Phase 1, so no TOC parse or DB read happens here for them.
      for (final book in discovered) {
        if (book.conversionError != null) {
          debugPrint('⚠️ DOCX conversion failed for ${book.title}: ${book.conversionError}');
          failedDetails.add((book.title, book.conversionError!));
          failed++;
          continue;
        }
        try {
          if (book.existingBookId != null) {
            // Metadata-only update (file changed since last scan).
            await repository.updateExternalBookMetadata(
              book.existingBookId!,
              book.fileSize,
              book.lastModified,
            );
            debugPrint('📁 Updated external book metadata: ${book.title}');
            updated++;
            continue;
          }

          // New book: create category, parse PDF outline, insert.
          // Re-check authoritatively before inserting (guards against Phase-1
          // fallback duplicates and concurrent-scan races).
          if (await _recheckBeforeInsert(
              repository, book.path, book.fileSize, book.lastModified)) {
            continue;
          }

          final categoryId =
              await _getOrCreateCategoryInDb(book.categoryPath, repository);

          List<db_models.TocEntry>? tocEntries;
          if (book.tocEntries != null && book.tocEntries!.isNotEmpty) {
            // TXT / DOCX: already parsed inside the isolate.
            tocEntries = _rawTocToDbEntries(book.tocEntries!);
          } else if (book.fileType == 'pdf') {
            // PDF: parse outline here — pdfrx requires platform channels.
            final pdfToc = await _parsePdfOutline(File(book.path));
            if (pdfToc.isNotEmpty) {
              final dbEntries = <db_models.TocEntry>[];
              _convertTocEntriesToDb(pdfToc, dbEntries, 0, null);
              tocEntries = dbEntries.isNotEmpty ? dbEntries : null;
            }
          }

          await repository.insertExternalContentBook(
            categoryId: categoryId,
            title: book.title,
            filePath: book.path,
            fileType: book.fileType,
            fileSize: book.fileSize,
            lastModified: book.lastModified,
            heShortDesc: null,
            orderIndex: 999.0,
            isPersonal: true,
            tocEntries: tocEntries,
          );
          debugPrint(
              '📁 Inserted external book to DB: ${book.title} (type: ${book.fileType})');
          added++;
        } catch (e) {
          debugPrint('⚠️ Failed to process book: ${book.path} - $e');
          failed++;
        }
      }

      debugPrint('📁 Finished scanning custom folder: $folderPath '
          '(added=$added, updated=$updated, failed=$failed)');
      return ScanResult(
          addedBooks: added,
          updatedBooks: updated,
          failedBooks: failed,
          failedDetails: failedDetails);
    } catch (e) {
      debugPrint('⚠️ Scan failed for $folderPath: $e');
      return ScanResult(fatalError: e);
    }
  }

  /// Authoritative pre-insert recheck.
  ///
  /// Returns `true` if [filePath] is already in the DB — the caller must skip
  /// the insert. Returns `false` if the file is genuinely new.
  /// When found and metadata has changed, the DB row is updated in-place.
  Future<bool> _recheckBeforeInsert(
    dynamic repository,
    String filePath,
    int fileSize,
    int lastModified,
  ) async {
    final alreadyInDb = await repository.getExternalBookByFilePath(filePath);
    if (alreadyInDb == null) return false;
    if (alreadyInDb.fileSize != fileSize ||
        alreadyInDb.lastModified != lastModified) {
      await repository.updateExternalBookMetadata(
          alreadyInDb.id, fileSize, lastModified);
      debugPrint('📁 Updated metadata (recheck): $filePath');
    }
    return true;
  }

  /// Exposes [_recheckBeforeInsert] for unit tests via a duck-typed [repository].
  ///
  /// The [repository] only needs to implement:
  ///   - `Future<T?> getExternalBookByFilePath(String path)`
  ///   - `Future<void> updateExternalBookMetadata(int id, int size, int mtime)`
  @visibleForTesting
  static Future<bool> recheckBeforeInsertForTest({
    required dynamic repository,
    required String filePath,
    required int fileSize,
    required int lastModified,
  }) {
    return DatabaseLibraryProvider.instance._recheckBeforeInsert(
      repository,
      filePath,
      fileSize,
      lastModified,
    );
  }

  /// Converts a flat [_RawTocEntry] list (produced by the background isolate)
  /// into [db_models.TocEntry] objects ready for DB insertion.
  ///
  /// The flat list uses 0-based [_RawTocEntry.parentIndex]; the DB model uses
  /// 1-based local IDs that are resolved by [SeforimRepository._insertTocEntriesForExternalBook].
  List<db_models.TocEntry> _rawTocToDbEntries(List<_RawTocEntry> raw) {
    // For each parentIndex value, record the last entry that has it so we can
    // flag isLastChild correctly.
    final lastChildOf = <int?, int>{};
    for (int i = 0; i < raw.length; i++) {
      lastChildOf[raw[i].parentIndex] = i;
    }

    return List.generate(raw.length, (i) {
      final r = raw[i];
      // In pre-order traversal a node has children iff its immediate successor
      // has this node's index as its parentIndex.
      final hasChildren = (i + 1 < raw.length) && (raw[i + 1].parentIndex == i);
      return db_models.TocEntry(
        id: i + 1, // 1-based local ID; resolved during insertion
        bookId:
            0, // placeholder; overridden in _insertTocEntriesForExternalBook
        parentId: r.parentIndex != null ? r.parentIndex! + 1 : null,
        text: r.text,
        level: r.level,
        lineId: null,
        lineIndex: r.lineIndex,
        isLastChild: lastChildOf[r.parentIndex] == i,
        hasChildren: hasChildren,
      );
    });
  }
}
