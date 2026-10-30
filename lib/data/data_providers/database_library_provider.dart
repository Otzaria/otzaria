import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting, compute;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/attached_libraries/utils/attached_file_path.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/models/toc_entry.dart' as migration;
import 'package:otzaria/migration/database/daos/category_dao.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/user_content_import/repository/user_alt_toc_repository.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_book_versions.dart';
import 'package:otzaria/user_content_import/services/user_sidecar_sync.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;

import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    show bookNoteMarkers;
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/migration/services/external_book_import.dart';
import 'package:otzaria/utils/file/file_hidden_utils.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'link_visibility_sql.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;

/// שם השורש שמרכז את ספרי מסד שאין בו טבלת קטגוריות.
const kUncategorizedCategoryTitle = 'ללא קטגוריה';

const _kPersonalRootTitle = 'ספרים אישיים';

/// מסדים מצורפים ממוינים תחת "ספרים אישיים" אחרי תיקיות הספרים האישיים.
const _kAttachedRootOrder = 1000;

/// במיזוג, ספרי מסד מצורף וקטגוריותיו אחרי הרשמיים והאישיים, לפי עדיפות המסד.
const _kAttachedMergedOrderBase = 1000000;
const _kAttachedMergedOrderStride = 100000;

/// הנתונים של מסד מצורף אחד בזמן בניית העץ.
class _AttachedCatalogBuild {
  _AttachedCatalogBuild({
    required this.library,
    required this.source,
    required this.rows,
    required this.categoryRows,
    required this.authors,
    required this.metadata,
  });

  final AttachedLibrary library;
  final AttachedBookSource source;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> categoryRows;
  final Map<int, String> authors;
  final Map<String, Map<String, dynamic>> metadata;
  final Map<int, List<Map<String, dynamic>>> booksByCategory = {};
  final Map<int?, List<db_models.Category>> categoriesByParent = {};

  /// הסדר בעץ של [orderIndex] מהמסד: במיזוג — אחרי כל התוכן הקיים.
  int order(num? orderIndex) {
    final own = orderIndex?.toInt() ?? 999;
    if (library.placement != AttachedLibraryPlacement.mergeIntoLibrary) {
      return own;
    }
    return _kAttachedMergedOrderBase +
        library.priority * _kAttachedMergedOrderStride +
        own.clamp(0, _kAttachedMergedOrderStride - 1);
  }
}

/// קטלוג מסד מצורף כפי שנקרא ב-isolate. [missing] — הקובץ אינו קיים.
typedef AttachedCatalogRows = ({
  bool missing,
  List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> categories,
  Map<int, String> authors,
});

/// קורא את הקטלוג של מסד מצורף על חיבור מוקשח משלו — רץ ב-isolate, כך
/// שקובץ איטי או כונן רשת מת אינם חוסמים את בניית העץ.
AttachedCatalogRows readAttachedCatalogSync(ReadOnlyDbTarget target) {
  if (!File(target.path).existsSync()) {
    return (missing: true, books: const [], categories: const [], authors: {});
  }
  final db = openReadOnlyTarget(target);
  try {
    final capabilities = DbCapabilities.probe(db);
    late final List<Map<String, dynamic>> books;
    late final List<Map<String, dynamic>> categories;
    late final Map<int, String> authors;
    withTransaction(db, () {
      books = [
        for (final row in BookDao.selectBooksMinimal(
          db,
          capabilities,
          withFileColumns: true,
        ))
          {...row, 'resolvedFilePath': _existingAttachedFile(target, row)},
      ];
      categories = CategoryDao.selectCategoryRows(db, capabilities);
      authors = BookDao.selectBookAuthorsMap(db, capabilities);
    });
    return (
      missing: false,
      books: books,
      categories: categories,
      authors: authors,
    );
  } finally {
    db.close();
  }
}

/// הקובץ של ספר מבוסס-קובץ במסד מצורף, כשהנתיב מותר והקובץ קיים.
String? _existingAttachedFile(
  ReadOnlyDbTarget target,
  Map<String, dynamic> row,
) {
  final resolved = resolveAttachedBookFilePath(
    target.path,
    row['filePath'] as String?,
  );
  return resolved != null && File(resolved).existsSync() ? resolved : null;
}

/// שורות הקטלוג של seforim.db על חיבור משלו; null כשאין נתיב למסד.
/// ביטול חייב להתפשט כדי לא לפתוח חיבור ראשי ששוחרר לכתיבה חיצונית.
Future<CatalogRows?> _officialCatalogInIsolate(String dbPath) async {
  if (dbPath.isEmpty) return null;
  return DbReadWorker.runOnFreshIsolate(
    () => readOfficialCatalogSync(dbPath),
  );
}

typedef CatalogRows = ({
  List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> categories,
  Map<int, String> authors,
});

@visibleForTesting
CatalogRows readOfficialCatalogSync(String dbPath) {
  final db = openReadOnlyTarget((
    path: dbPath,
    untrusted: false,
    immutable: false,
  ));
  try {
    return _readCatalogRows(db, DbCapabilities.probe(db));
  } finally {
    db.close();
  }
}

/// בטרנזקציה אחת, כדי שסנכרון רקע לא ינעל את המסד בין השאילתות.
CatalogRows _readCatalogRows(
  sqlite3.Database db,
  DbCapabilities capabilities,
) {
  late final CatalogRows rows;
  withTransaction(db, () {
    rows = (
      books: BookDao.selectBooksMinimal(db, capabilities),
      categories: CategoryDao.selectCategoryRows(db, capabilities),
      authors: BookDao.selectBookAuthorsMap(db, capabilities),
    );
  });
  return rows;
}

Future<AttachedCatalogRows> _readAttachedCatalogInIsolate(
  ReadOnlyDbTarget target,
) => Isolate.run(() => readAttachedCatalogSync(target));

typedef _UserBooksCatalogRows = ({
  List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> categories,
  Map<int, String> authors,
  List<Map<String, dynamic>> versions,
});

/// בטרנזקציה אחת — תמונת מצב עקבית של כל טבלאות הקטלוג של user_books.db.
_UserBooksCatalogRows _selectUserBooksCatalog(
  sqlite3.Database db,
  DbCapabilities capabilities,
) {
  late final _UserBooksCatalogRows rows;
  withTransaction(db, () {
    rows = (
      books: BookDao.selectBooksMinimal(
        db,
        capabilities,
        withFileColumns: true,
      ),
      categories: CategoryDao.selectCategoryRows(db, capabilities),
      authors: BookDao.selectBookAuthorsMap(db, capabilities),
      versions: db
          .select(
            'SELECT versionBookId, primaryBookId, primarySource, primaryTitle, '
            'primaryCategoryPath, versionTitle, versionNotes, priority '
            'FROM user_book_version',
          )
          .toMapList(),
    );
  });
  return rows;
}

/// קטלוג user_books.db ופתרון נתיבי הקבצים, על חיבור read-only ב-isolate:
/// פענוח עשרות אלפי שורות על ה-UI isolate תקע את הממשק (#3515).
Future<_UserBooksCatalogRows> _readUserBooksCatalogInIsolate(
  String dbPath,
  String libraryPath,
) => Isolate.run(() {
  final db = openReadOnlyTarget(trustedDbTarget(dbPath));
  try {
    db.execute('PRAGMA busy_timeout=5000');
    final rows = _selectUserBooksCatalog(db, DbCapabilities.probe(db));
    return (
      books: [
        for (final row in rows.books)
          if (row['filePath'] case final String path)
            {
              ...row,
              'filePath': resolveMovedFileBookPath(
                path,
                activeLibraryPath: libraryPath,
              ),
            }
          else
            row,
      ],
      categories: rows.categories,
      authors: rows.authors,
      versions: rows.versions,
    );
  } finally {
    db.close();
  }
}, debugName: 'readUserBooksCatalog');

/// קריאת קטלוג של מסד מצורף שעדיין רצה, כולל אחרי שבניית העץ ויתרה עליה.
class _PendingAttachedCatalog {
  _PendingAttachedCatalog(this.future) {
    future.then((_) => done = true, onError: (_) => done = true);
  }

  final Future<AttachedCatalogRows> future;
  bool done = false;
  bool timedOut = false;
}

typedef _ExternalWriteBatch = ({
  String dbPath,
  List<_DiscoveredBook> books,
  Map<String, List<migration.TocEntry>> pdfTocs,
  Map<String, Map<String, String>> queries,
  String source,
});

Future<ScanResult> _writeDiscoveredBooks(_ExternalWriteBatch args) async {
  QueryLoader.seedCache(args.queries);
  final database = MyDatabase.withPath(args.dbPath);
  final repository = SeforimRepository(database);
  var added = 0;
  var updated = 0;
  var failed = 0;
  final failedDetails = <(String, String)>[];
  final updatedBookIds = <int>[];
  final discovered = args.books;
  final folderSourceName = args.source;
  try {
    await repository.ensureInitialized();
    int? scanSourceId;
    for (final discoveredBook in discovered) {
      final book = discoveredBook.book;
      if (discoveredBook.conversionError != null) {
        failedDetails.add((book.title, discoveredBook.conversionError!));
        failed++;
        continue;
      }
      try {
        if (discoveredBook.existingBookId != null) {
          await book.update(repository, discoveredBook.existingBookId!);
          updated++;
          updatedBookIds.add(discoveredBook.existingBookId!);
          continue;
        }
        if (await DatabaseLibraryProvider._recheckBeforeInsert(
          repository,
          book.filePath,
          book.fileSize,
          book.lastModified,
        )) {
          continue;
        }
        final category = await findOrCreateBookCategoryChain(
          repository,
          discoveredBook.categoryPath,
        );
        final pdfToc = args.pdfTocs[book.filePath];
        scanSourceId ??= await repository.insertSource(folderSourceName, -1);
        await book.insert(
          repository,
          categoryId: category.categoryId,
          sourceId: scanSourceId,
          isPersonal: true,
          pdfTocEntries: pdfToc,
        );
        added++;
      } catch (e) {
        debugPrint('⚠️ Failed to process book: ${book.filePath} - $e');
        failed++;
      }
    }

    return ScanResult(
      addedBooks: added,
      updatedBooks: updated,
      failedBooks: failed,
      failedDetails: failedDetails,
      updatedBookIds: updatedBookIds,
    );
  } finally {
    database.close();
  }
}

class _DiscoveredBook {
  const _DiscoveredBook({
    required this.book,
    required this.categoryPath,
    this.existingBookId,
    this.conversionError,
  });

  final PreparedExternalBook book;
  final List<String> categoryPath;
  final int? existingBookId;
  final String? conversionError;
}

/// מסננת קבצים ללא שינוי ומכינה כותרות טקסטואליות מחוץ ל-UI isolate.
Future<List<_DiscoveredBook>> _scanExternalFolderInIsolate(
  (String folderPath, String folderName, String dbPath) args,
) async {
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
        final format = documentFormatFromExtension(name);
        if (format == null || !format.isProductionSupported) continue;
        // .xml ו-.wbk נאספים רק אם תוכנם אכן מסמך — אותו שער בדיוק שבסורק
        // הסנכרון וב-generator. בלעדיו כל קובץ XML שיושב בתיקיית ספרים היה
        // מדווח למשתמש ככשל המרה.
        if (format.needsContentSniffing &&
            !await isSupportedBookFileByContent(entity.path)) {
          continue;
        }
        final fileType = format.extension;

        final stat = await entity.stat();
        final title = getTitleFromPath(entity.path);
        final fileSize = stat.size;
        final lastModified = stat.modified.millisecondsSinceEpoch;

        // ── DB existence check ─────────────────────────────────────────────
        // Perform BEFORE any expensive IO (TOC parse) so unchanged books are
        // skipped entirely without reading file content. A *changed* file
        // falls through to re-parse its TOC (so the navigation stays in sync
        // with the edited content), keeping its existing book id.
        int? existingBookId;
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
            existingBookId = row['id'] as int; // changed — re-parse TOC below
          }
        }
        // ──────────────────────────────────────────────────────────────────

        var book = PreparedExternalBook(
          filePath: entity.path,
          title: title,
          fileType: fileType,
          fileSize: fileSize,
          lastModified: lastModified,
        );
        String? conversionError;
        try {
          book = PreparedExternalBook.prepare(entity.path, stat, format);
        } catch (e) {
          conversionError = e.toString();
        }
        books.add(
          _DiscoveredBook(
            book: book,
            categoryPath: categoryPath,
            conversionError: conversionError,
            existingBookId: existingBookId,
          ),
        );
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
  String folderPath,
  String folderName,
  String dbPath,
) async {
  final result = await _scanExternalFolderInIsolate((
    folderPath,
    folderName,
    dbPath,
  ));
  return result
      .map((b) => {'path': b.book.filePath, 'existingBookId': b.existingBookId})
      .toList();
}

// ──────────────────────────────────────────────────────────────────────────

/// חלון הקישורים ההפוך ל-seforim.db הרשמי בלבד: IN על idx_link_target_line.
/// פרמטרים: (bookId, start, end).
@visibleForTesting
const officialInverseWindowLinksSql = '''SELECT l.id, l.targetLineId FROM link l
          WHERE l.targetLineId IN (
            SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
          )''';

/// win+anchors הישירים ל-seforim.db הרשמי בלבד: CROSS JOIN מקבע את win כחיצוני על
/// idx_link_source_line או idx_link_source_targetorder; ה-+ על sourceBookId מונע בחירת idx_link_source_book (אין sqlite_stat1).
@visibleForTesting
const officialForwardWindowSql = '''win(id, bookId) AS (
          SELECT id, bookId FROM line
          WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
        ),
        anchors(linkId, anchorLineId) AS (
          SELECT l.id, l.sourceLineId FROM win w
          CROSS JOIN link l
            ON l.sourceLineId = w.id AND +l.sourceBookId = w.bookId''';

/// טוען קישורי "מקור" (SOURCE וירטואלי) לספר כ-target: הופך source↔target כדי
/// שספר מפרש יציג את מקורו. ב-v3 הקישור נשמר בכיוון קנוני אחד בלבד.
/// שורות ה-anchors כוללות גם שורות מכוסות של קישורי-טווח (link_coverage,
/// side=1) — כך קישור שהצד התלוי שלו משתרע על כמה שורות מופיע בכל שורה בטווח.
List<Map<String, dynamic>> _loadInverseSourceRows(
  sqlite3.Database db,
  DbCapabilities capabilities,
  int bookId, {
  int? startLineIndex,
  int? endLineIndex,
  bool official = false,
}) {
  final hasSuppressedSide = capabilities.hasLinkSuppressedSide;
  final dependentTypes = LinkTypes.dependentTextTypes.toList();
  // קישורי הפניה דו-כיווניים רק בסכמה שמספקת verdict נפרד לכל צד.
  final types = LinkTypes.inverseQueryTypes(bidirectional: hasSuppressedSide);
  final typePlaceholders = List.filled(types.length, '?').join(', ');
  final connectionTypeExpr = inverseConnectionTypeExpr(dependentTypes);
  final hasRange = startLineIndex != null && endLineIndex != null;
  // בשאילתה ההפוכה השורה המוצגת היא צד היעד של הקישור השמור.
  final suppressedFilter = suppressedSideFilter(
    hasSuppressedSide,
    displayedSide: 1,
  );
  final hasLinkAnchor = capabilities.hasLinkAnchors;
  final hasLinkRanges = capabilities.hasLinkRanges;
  final referenceTypes = LinkTypes.referenceTypes
      .map((type) => "'$type'")
      .join(', ');
  final inverseBookFilter = hasSuppressedSide
      ? '''
        AND (l.sourceBookId != l.targetBookId OR (
          ct.name IN ($referenceTypes)
          AND (
            EXISTS (SELECT 1 FROM link_suppressed_side sourceSuppressed
                    WHERE sourceSuppressed.linkId = l.id AND sourceSuppressed.side = 0)
            OR (
              a.anchorLineId != l.sourceLineId
              ${hasLinkRanges ? 'AND NOT EXISTS (SELECT 1 FROM link_coverage sourceCoverage WHERE sourceCoverage.linkId = l.id AND sourceCoverage.side = 0 AND sourceCoverage.lineId = a.anchorLineId)' : ''}
            )
          )
        ))'''
      : 'AND l.sourceBookId != l.targetBookId';
  final anchorSelect = _anchorSelectColumns(hasLinkAnchor);
  final anchorJoin = _anchorJoinClause(hasLinkAnchor, displayedSide: 1);
  final provenanceSelect = capabilities.hasLinkBaseProvenance
      ? 'l.baseProvenance as baseProvenance,'
      : '0 as baseProvenance,';
  // בפאנל של תצוגת המקור מוצג צד ה-source של הקישור (side=0).
  final rangeEndSelect = _rangeEndSelectColumns(hasLinkRanges);
  final rangeEndJoin = _rangeEndJoinClause(hasLinkRanges, panelSide: 0);

  final String windowLinksArm;
  final String coverageArm;
  final List<Object?> params;
  if (hasRange) {
    // מסד שאינו הרשמי נשאר בדיוק עם השאילתה המקורית (ראו officialForwardWindowSql).
    windowLinksArm = official
        ? officialInverseWindowLinksSql
        : '''SELECT l.id, l.targetLineId FROM link l
          WHERE l.targetLineId IN (
            SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
          )
            AND l.targetBookId = ?''';
    coverageArm = hasLinkRanges
        ? '''
          UNION ALL
          SELECT lc.linkId, lc.lineId FROM link_coverage lc
          WHERE lc.side = 1 AND lc.lineId IN (
            SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
          )'''
        : '';
    params = [
      bookId,
      startLineIndex,
      endLineIndex,
      if (!official) bookId,
      if (hasLinkRanges) ...[bookId, startLineIndex, endLineIndex],
      ...types,
    ];
  } else {
    windowLinksArm = 'SELECT id, targetLineId FROM link WHERE targetBookId = ?';
    coverageArm = hasLinkRanges
        ? '''
        UNION ALL
        SELECT lc.linkId, lc.lineId FROM link_coverage lc
        JOIN link cl ON cl.id = lc.linkId
        WHERE lc.side = 1 AND cl.targetBookId = ?'''
        : '';
    params = [bookId, if (hasLinkRanges) bookId, ...types];
  }
  return db.select('''
      WITH anchors(linkId, anchorLineId) AS (
        $windowLinksArm
        $coverageArm
      )
      SELECT
        tl.lineIndex as sourceLineIndex,
        sl.lineIndex as targetLineIndex,
        sl.heRef as targetLineHeRef,
        sb.title as targetBookTitle,
        sb.categoryId as targetCategoryId,
        sb.id as targetBookId,
        NULL as targetFileType,
        $rangeEndSelect
        $anchorSelect
        $provenanceSelect
        $connectionTypeExpr as connectionTypeName
      FROM anchors a
      ${hasRange && official ? 'CROSS JOIN' : 'JOIN'} link l ON l.id = a.linkId
      JOIN line tl ON tl.id = a.anchorLineId
      JOIN line sl ON l.sourceLineId = sl.id
      JOIN book sb ON l.sourceBookId = sb.id
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      $rangeEndJoin
      $anchorJoin
      WHERE ct.name IN ($typePlaceholders)
        $inverseBookFilter
        $suppressedFilter
      ORDER BY tl.lineIndex
    ''', params).toMapList();
}

/// מזהה הספר [title] — בקטגוריה [categoryId] כשהמסד מכיר קטגוריות — או null.
/// במסד בלי עמודת קטגוריה כל הספרים יושבים תחת שורש אחד, וההתאמה לפי כותרת.
int? _selectBookId(
  sqlite3.Database db,
  DbCapabilities capabilities,
  String title, {
  int? categoryId,
}) {
  if (!capabilities.hasBooks) return null;
  final byCategory = categoryId != null && capabilities.hasBookCategories;
  final rows = db.select(
    byCategory
        ? 'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1'
        : 'SELECT id FROM book WHERE title = ? LIMIT 1',
    [title, if (byCategory) categoryId],
  );
  return rows.isEmpty ? null : rows.first['id'] as int;
}

/// עמודות קצה-הטווח של צד-הפאנל: heRef של השורה האחרונה בטווח + האינדקס שלה
/// (0-based), או NULL כשאין טווח / כשהמסד ישן.
String _rangeEndSelectColumns(bool hasLinkRanges) => hasLinkRanges
    ? '''rl.heRef as targetRangeEndHeRef,
          lr.endLineIndex as targetRangeEndLineIndex,'''
    : '''NULL as targetRangeEndHeRef,
          NULL as targetRangeEndLineIndex,''';

/// JOIN לקצה-הטווח של צד-הפאנל (`panelSide`: 0 = צד המקור השמור, 1 = היעד).
String _rangeEndJoinClause(bool hasLinkRanges, {required int panelSide}) =>
    hasLinkRanges
    ? '''LEFT JOIN link_range lr ON lr.linkId = l.id AND lr.side = $panelSide
        LEFT JOIN line rl ON rl.id = lr.endLineId'''
    : '';

String _anchorSelectColumns(bool hasLinkAnchor) => hasLinkAnchor
    ? '''la.charStart as anchorCharStart,
          la.charEnd as anchorCharEnd,
          la.label as anchorLabel,
          la.spans as anchorSpans,
          lal.charStart as anchorLinkedCharStart,
          lal.charEnd as anchorLinkedCharEnd,'''
    : '''NULL as anchorCharStart,
          NULL as anchorCharEnd,
          NULL as anchorLabel,
          NULL as anchorSpans,
          NULL as anchorLinkedCharStart,
          NULL as anchorLinkedCharEnd,''';

/// עוגני הקישור מקובצים לשורה אחת לכל קישור וצד: העוגן הראשון (MIN) לאות
/// שבפאנל, ו-spans מקודד את כולם ("start:end:label;...", ראו
/// [_parseAnchorSpans]) כך שקישור עם כמה עוגנים באותה שורה מציג את כולם.
/// דטרמיניזם: charEnd/label הלא-אגרגטיביים מגיעים לפי חוזה SQLite משורת
/// ה-MIN, ושורת ה-MIN יחידה — (linkId, side, charStart) הוא ה-PK של
/// link_anchor, כך שאין שני עוגנים לאותו קישור/צד עם אותו charStart.
/// ה-la מוצמד רק לשורת העוגן המקורית של הקישור (a.anchorLineId = שורת הצד
/// המוצג): אופסטי העוגן חושבו מול הטקסט של אותה שורה, ובקישור-טווח אסור
/// שידלפו לשורות coverage. ה-lal (הצד המקושר, קטע-הפאנל) נשאר לפי linkId —
/// שורת הפאנל היא תמיד שורת ההתחלה של הקישור.
String _anchorJoinClause(bool hasLinkAnchor, {required int displayedSide}) {
  if (!hasLinkAnchor) return '';
  final displayedSideLine = displayedSide == 0
      ? 'l.sourceLineId'
      : 'l.targetLineId';
  return '''LEFT JOIN (
          SELECT linkId, MIN(charStart) AS charStart, charEnd, label,
                 GROUP_CONCAT(charStart || ':' || COALESCE(charEnd, '') || ':' || COALESCE(label, ''), ';') AS spans
          FROM link_anchor
          WHERE side = $displayedSide AND linkId IN (SELECT linkId FROM anchors)
          GROUP BY linkId
        ) la ON la.linkId = l.id AND a.anchorLineId = $displayedSideLine
        LEFT JOIN (
          SELECT linkId, MIN(charStart) AS charStart, charEnd
          FROM link_anchor
          WHERE side = ${1 - displayedSide} AND linkId IN (SELECT linkId FROM anchors)
          GROUP BY linkId
        ) lal ON lal.linkId = l.id''';
}

/// מפענח את מחרוזת ה-spans מהשאילתה לרשימת עוגנים ממוינת לפי מיקום.
List<LinkAnchorSpan> _parseAnchorSpans(String? spans) {
  if (spans == null || spans.isEmpty) return const [];
  final result = <LinkAnchorSpan>[];
  for (final part in spans.split(';')) {
    final fields = part.split(':');
    final start = int.tryParse(fields.first);
    if (start == null) continue;
    final end = fields.length > 1 ? int.tryParse(fields[1]) : null;
    final label = fields.length > 2 ? fields.sublist(2).join(':') : '';
    result.add(
      LinkAnchorSpan(
        start: start,
        end: end,
        label: label.isEmpty ? null : label,
      ),
    );
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

/// שורת קישור מהשאילתה (אינדקסים 0-based) → [Link] (אינדקסים 1-based).
Link _linkFromRow(Map<String, Object?> row, BookSource source) {
  final targetTitle = row['targetBookTitle'] as String;
  final targetLineHeRef = row['targetLineHeRef'] as String?;
  final connectionType = row['connectionTypeName'] as String? ?? 'reference';

  return Link(
    heRef: targetLineHeRef?.trim().isNotEmpty == true
        ? targetLineHeRef!.trim()
        : targetTitle,
    index1: (row['sourceLineIndex'] as int) + 1,
    path2: targetTitle,
    index2: (row['targetLineIndex'] as int) + 1,
    connectionType: connectionType,
    targetCategoryId: row['targetCategoryId'] as int?,
    targetBookId: row['targetBookId'] as int?,
    targetFileType: row['targetFileType'] as String?,
    anchorStart: row['anchorCharStart'] as int?,
    anchorEnd: row['anchorCharEnd'] as int?,
    anchorLabel: row['anchorLabel'] as String?,
    linkedAnchorStart: row['anchorLinkedCharStart'] as int?,
    linkedAnchorEnd: row['anchorLinkedCharEnd'] as int?,
    anchorSpans: _parseAnchorSpans(row['anchorSpans'] as String?),
    heRefEnd: (row['targetRangeEndHeRef'] as String?)?.trim().isNotEmpty == true
        ? (row['targetRangeEndHeRef'] as String).trim()
        : null,
    index2End: row['targetRangeEndLineIndex'] != null
        ? (row['targetRangeEndLineIndex'] as int) + 1
        : null,
    baseProvenance: row['baseProvenance'] as int? ?? 0,
    targetSource: source,
  );
}

List<Map<String, dynamic>> _loadBookLinksRowsInIsolate({
  required ReadOnlyDbTarget target,
  required String title,
  required int categoryId,
  required String fileType,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasLinks) return const [];

    final bookId = _selectBookId(
      db,
      capabilities,
      title,
      categoryId: categoryId,
    );
    if (bookId == null) return const [];

    final hasLinkAnchor = capabilities.hasLinkAnchors;
    final hasLinkRanges = capabilities.hasLinkRanges;
    // בשאילתה הקדמית השורה המוצגת היא צד המקור השמור.
    final suppressedFilter = suppressedSideFilter(
      capabilities.hasLinkSuppressedSide,
      displayedSide: 0,
    );

    // שורות ה-anchors כוללות גם שורות מכוסות של קישורי-טווח (side=0), כך
    // שקישור שהמקור שלו משתרע על כמה שורות מופיע בכל שורה שהוא מכסה.
    final coverageArm = hasLinkRanges
        ? '''
          UNION ALL
          SELECT lc.linkId, lc.lineId FROM link_coverage lc
          JOIN link cl ON cl.id = lc.linkId
          WHERE lc.side = 0 AND cl.sourceBookId = ?'''
        : '';
    final forwardRows = db
        .select(
          '''
        WITH anchors(linkId, anchorLineId) AS (
          SELECT id, sourceLineId FROM link WHERE sourceBookId = ?
          $coverageArm
        )
        SELECT
          l.sourceLineId,
          l.targetLineId,
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tl.heRef as targetLineHeRef,
          tb.title as targetBookTitle,
          tb.categoryId as targetCategoryId,
          tb.id as targetBookId,
          NULL as targetFileType,
          ${_rangeEndSelectColumns(hasLinkRanges)}
          ${_anchorSelectColumns(hasLinkAnchor)}
          ct.name as connectionTypeName
        FROM anchors a
        JOIN link l ON l.id = a.linkId
        JOIN line sl ON sl.id = a.anchorLineId
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        ${_rangeEndJoinClause(hasLinkRanges, panelSide: 1)}
        ${_anchorJoinClause(hasLinkAnchor, displayedSide: 0)}
        WHERE 1=1
          $suppressedFilter
        ORDER BY sl.lineIndex
      ''',
          [bookId, if (hasLinkRanges) bookId],
        )
        .toMapList();
    return [
      ...forwardRows,
      ..._loadInverseSourceRows(db, capabilities, bookId),
    ];
  } finally {
    db?.close();
  }
}

/// השאילתה הקדמית של [_loadBookLinkTargetsSummaryRowsInIsolate]: מספר
/// הקישורים לפי (שם ספר-יעד, שם סוג חיבור).
@visibleForTesting
String bookLinkTargetsForwardSql({
  required bool hasLinkRanges,
  required String suppressedFilter,
}) {
  // קישור-טווח נספר פעם לכל שורה מכוסה — כמו בטעינת הקישורים המלאה, כדי
  // שסיווג "מפרש נדיר" לפי הספירה יישאר שקול.
  final coverageArm = hasLinkRanges
      ? '''
          UNION ALL
          SELECT lc.linkId FROM link_coverage lc
          JOIN link cl ON cl.id = lc.linkId
          WHERE lc.side = 0 AND cl.sourceBookId = ?'''
      : '';
  return '''
        WITH anchors(linkId) AS (
          SELECT id FROM link WHERE sourceBookId = ?
          $coverageArm
        ),
        -- ספירה לפי מזהים לפני ה-JOIN לשמות: שליפת ספר ושם סוג לכל קישור
        -- (עשרות אלפים בספר גדול) היא רוב זמן השאילתה.
        counts AS (
          SELECT l.targetBookId, l.connectionTypeId, COUNT(*) AS n
          FROM anchors a
          JOIN link l ON l.id = a.linkId
          WHERE 1=1
            $suppressedFilter
          GROUP BY l.targetBookId, l.connectionTypeId
        )
        SELECT tb.title as targetBookTitle,
               ct.name as connectionTypeName,
               SUM(c.n) as linkCount
        FROM counts c
        JOIN book tb ON c.targetBookId = tb.id
        LEFT JOIN connection_type ct ON c.connectionTypeId = ct.id
        GROUP BY tb.title, ct.name
      ''';
}

/// Top-level worker לסיכום קישורי ספר לפי (ספר-יעד, סוג חיבור) — שאילתת
/// GROUP BY זולה במקום למשוך עשרות אלפי שורות קישורים לדארט.
({List<Map<String, dynamic>> rows, int? maxSourceLineIndex})
_loadBookLinkTargetsSummaryRowsInIsolate({
  required ReadOnlyDbTarget target,
  required bool official,
  required String title,
  required int categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    const empty = (rows: <Map<String, dynamic>>[], maxSourceLineIndex: null);
    if (!capabilities.hasLinks) return empty;

    final bookId = _selectBookId(
      db,
      capabilities,
      title,
      categoryId: categoryId,
    );
    if (bookId == null) return empty;

    final hasLinkRanges = capabilities.hasLinkRanges;
    final hasSuppressedSide = capabilities.hasLinkSuppressedSide;
    final forwardSuppressed = suppressedSideFilter(
      hasSuppressedSide,
      displayedSide: 0,
    );

    final forwardRows = db.select(
      bookLinkTargetsForwardSql(
        hasLinkRanges: hasLinkRanges,
        suppressedFilter: forwardSuppressed,
      ),
      [bookId, if (hasLinkRanges) bookId],
    ).toMapList();

    // הזרוע ההפוכה — סופרת שורות link בלבד, בלי זרוע ה-coverage שיש
    // ל-_loadInverseSourceRows, ולכן היא נמוכה ממנה. הצרכן היחיד
    // (aggregateLinkTargetsFromSummary) סופר רק תלויי-טקסט, ושורות הפוכות
    // אינן כאלה — הן נכנסות ל-nonCommentaryTitles שבו הספירה נזרקת.
    final depTypes = LinkTypes.dependentTextTypes.toList();
    final inverseTypes = LinkTypes.inverseQueryTypes(
      bidirectional: hasSuppressedSide,
    );
    final typePlaceholders = List.filled(inverseTypes.length, '?').join(', ');
    final inverseTypeExpr = inverseConnectionTypeExpr(depTypes);
    final inverseSuppressed = suppressedSideFilter(
      hasSuppressedSide,
      displayedSide: 1,
    );
    final referenceTypes = LinkTypes.referenceTypes
        .map((type) => "'$type'")
        .join(', ');
    final hasNonOverlappingSameBookTarget = hasLinkRanges
        ? '''
          EXISTS (
            SELECT 1 FROM (
              SELECT l.targetLineId AS lineId
              UNION
              SELECT targetCoverage.lineId FROM link_coverage targetCoverage
              WHERE targetCoverage.linkId = l.id AND targetCoverage.side = 1
            ) targetAnchor
            WHERE targetAnchor.lineId != l.sourceLineId
              AND NOT EXISTS (
                SELECT 1 FROM link_coverage sourceCoverage
                WHERE sourceCoverage.linkId = l.id
                  AND sourceCoverage.side = 0
                  AND sourceCoverage.lineId = targetAnchor.lineId
              )
          )'''
        : 'l.targetLineId != l.sourceLineId';
    final inverseBookFilter = hasSuppressedSide
        ? '''
          AND (l.sourceBookId != l.targetBookId OR (
            ct.name IN ($referenceTypes)
            AND (
              EXISTS (SELECT 1 FROM link_suppressed_side sourceSuppressed
                      WHERE sourceSuppressed.linkId = l.id AND sourceSuppressed.side = 0)
              OR $hasNonOverlappingSameBookTarget
            )
          ))'''
        : 'AND l.sourceBookId != l.targetBookId';
    final inverseRows = db
        .select(
          '''
        SELECT sb.title as targetBookTitle,
               $inverseTypeExpr as connectionTypeName,
               COUNT(*) as linkCount
        FROM link l
        JOIN book sb ON l.sourceBookId = sb.id
        JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.targetBookId = ?
          AND ct.name IN ($typePlaceholders)
          $inverseBookFilter
          $inverseSuppressed
        GROUP BY sb.title, connectionTypeName
      ''',
          [bookId, ...inverseTypes],
        )
        .toMapList();

    // בספר דל קישורים, סריקה מסוף השורות עלולה לעבור זנב ארוך ללא קישור.
    // בדיקת צפיפות מוגבלת עוצרת אחרי 256 קישורים באינדקס sourceBookId.
    // בספר דל מתחילים מ-link; בספר עתיר קישורים מתחילים מסוף line.
    final useReverseMax = official && _hasManySourceLinks(db, bookId);
    final maxRows = db.select(
      official
          ? useReverseMax
                ? 'SELECT (SELECT sl.lineIndex FROM line sl WHERE sl.bookId = ? '
                      'AND EXISTS (SELECT 1 FROM link l WHERE l.sourceLineId = sl.id '
                      'AND +l.sourceBookId = sl.bookId) '
                      'ORDER BY sl.lineIndex DESC LIMIT 1) as maxIdx'
                : 'SELECT MAX(sl.lineIndex) as maxIdx FROM link l '
                      'CROSS JOIN line sl ON sl.id = l.sourceLineId '
                      'WHERE l.sourceBookId = ?'
          : 'SELECT MAX(sl.lineIndex) as maxIdx FROM link l '
                'JOIN line sl ON sl.id = l.sourceLineId WHERE l.sourceBookId = ?',
      [bookId],
    ).toMapList();
    final maxSourceLineIndex = maxRows.isEmpty
        ? null
        : maxRows.first['maxIdx'] as int?;

    return (
      rows: [...forwardRows, ...inverseRows],
      maxSourceLineIndex: maxSourceLineIndex,
    );
  } finally {
    db?.close();
  }
}

bool _hasManySourceLinks(sqlite3.Database db, int bookId) => db.select(
  'SELECT 1 FROM link WHERE sourceBookId = ? LIMIT 1 OFFSET 255',
  [bookId],
).isNotEmpty;

/// Top-level wrapper עבור סיכום קישורי ספר ב-isolate.
/// ראה ההסבר ב-[_runBookLoadInIsolate].
Future<({List<Map<String, dynamic>> rows, int? maxSourceLineIndex})>
_runBookLinkTargetsSummaryInIsolate({
  required ReadOnlyDbTarget target,
  required bool official,
  required String title,
  required int categoryId,
}) {
  return Isolate.run(
    () => _loadBookLinkTargetsSummaryRowsInIsolate(
      target: target,
      official: official,
      title: title,
      categoryId: categoryId,
    ),
  );
}

List<Map<String, dynamic>> _loadBookLinksRowsInRangeInIsolate({
  required ReadOnlyDbTarget target,
  required bool official,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLineIndex,
  required int endLineIndex,
  required List<String>? targetBookTitles,
  ReadOnlyConnection? connection,
}) {
  sqlite3.Database? db;
  try {
    db = connection?.db ?? openReadOnlyTarget(target);
    // מסד בלי טבלאות קישורים הוא תשובה ריקה תקפה, לא כשל שדורש ניסיון חוזר.
    final capabilities = connection?.capabilities ?? DbCapabilities.probe(db);
    if (!capabilities.hasLinks) return const [];

    final bookId = _selectBookId(
      db,
      capabilities,
      title,
      categoryId: categoryId,
    );
    if (bookId == null) return const [];

    final hasLinkAnchor = capabilities.hasLinkAnchors;
    final hasLinkRanges = capabilities.hasLinkRanges;
    final suppressedFilter = suppressedSideFilter(
      capabilities.hasLinkSuppressedSide,
      displayedSide: 0,
    );

    final parameters = <Object?>[bookId, startLineIndex, endLineIndex];
    // כשהפילטר ריק (אין מפרשים נבחרים) — עדיין מחזירים קישורי REFERENCE
    final hasCommentaryFilter =
        targetBookTitles != null && targetBookTitles.isNotEmpty;
    final targetBookPlaceholders = hasCommentaryFilter
        ? List.filled(targetBookTitles.length, '?').join(', ')
        : '';
    if (hasCommentaryFilter) {
      parameters.addAll(targetBookTitles);
    }

    // תנאי הפילטר ("מפרש" = אחד מסוגי הטקסט התלויים, כולל SUPER_COMMENTARY/
    // MIDRASH וכו', לא רק COMMENTARY/TARGUM):
    // null     → ללא פילטר (כל הקישורים)
    // ריק      → רק קישורים שאינם מפרשים (REFERENCE וכד׳)
    // לא ריק   → קישורים שאינם מפרשים + המפרשים הנבחרים
    final depTypesIn = LinkTypes.dependentTextTypes
        .map((t) => "'$t'")
        .join(', ');
    final commentaryFilterClause = targetBookTitles == null
        ? ''
        : hasCommentaryFilter
        ? 'AND (ct.name IS NULL OR ct.name NOT IN ($depTypesIn) OR tb.title IN ($targetBookPlaceholders))'
        : 'AND (ct.name IS NULL OR ct.name NOT IN ($depTypesIn))';

    // שורות ה-anchors כוללות גם שורות מכוסות של קישורי-טווח (side=0); הן תמיד
    // שורות ספר-המקור עצמו, ולכן די בסינון מול win.
    final coverageArm = hasLinkRanges
        ? '''
          UNION ALL
          SELECT lc.linkId, lc.lineId FROM link_coverage lc
          WHERE lc.side = 0 AND lc.lineId IN (SELECT id FROM win)'''
        : '';
    final windowSql = official
        ? officialForwardWindowSql
        : '''win(id) AS (
          SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
        ),
        anchors(linkId, anchorLineId) AS (
          SELECT l.id, l.sourceLineId FROM link l
          WHERE l.sourceLineId IN (SELECT id FROM win)''';
    final rows = db.select('''
        WITH $windowSql
          $coverageArm
        )
        SELECT
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tl.heRef as targetLineHeRef,
          tb.title as targetBookTitle,
          tb.categoryId as targetCategoryId,
          tb.id as targetBookId,
          NULL as targetFileType,
          ${_rangeEndSelectColumns(hasLinkRanges)}
          ${_anchorSelectColumns(hasLinkAnchor)}
          ct.name as connectionTypeName
        FROM anchors a
        JOIN link l ON l.id = a.linkId
        JOIN line sl ON sl.id = a.anchorLineId
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        ${_rangeEndJoinClause(hasLinkRanges, panelSide: 1)}
        ${_anchorJoinClause(hasLinkAnchor, displayedSide: 0)}
        WHERE 1=1
          $commentaryFilterClause
          $suppressedFilter
        ORDER BY sl.lineIndex, tb.orderIndex
      ''', parameters).toMapList();
    return [
      ...rows,
      ..._loadInverseSourceRows(
        db,
        capabilities,
        bookId,
        startLineIndex: startLineIndex,
        endLineIndex: endLineIndex,
        official: official,
      ),
    ];
  } finally {
    if (connection == null) db?.close();
  }
}

List<Map<String, dynamic>> _loadAlternativeStructuresRowsInIsolate({
  required ReadOnlyDbTarget target,
  required String bookTitle,
  int? categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasAltTocStructures) return const [];

    final bookId = _selectBookId(
      db,
      capabilities,
      bookTitle,
      categoryId: categoryId,
    );
    if (bookId == null) return const [];

    return db.select(
      'SELECT * FROM alt_toc_structure WHERE bookId = ? ORDER BY id',
      [bookId],
    ).toMapList();
  } finally {
    db?.close();
  }
}

/// Top-level wrapper שמריץ את [load] (טעינת נתוני ספר לפי שם וקטגוריה) בתוך
/// `Isolate.run`. חיוני שהקריאה ל-`Isolate.run` תיווצר *כאן* (בפונקציה
/// ברמת קובץ), ולא בתוך instance method של `DatabaseLibraryProvider` -
/// אחרת ה-closure של Dart עלול לתפוס את `this` (כולל ה-`FfiDatabase`
/// שאינו ניתן לשליחה ל-isolate) ולגרום לכשל
/// "Illegal argument in isolate message".
Future<T> _runBookLoadInIsolate<T>(
  T Function({
    required ReadOnlyDbTarget target,
    required String bookTitle,
    int? categoryId,
  })
  load, {
  required ReadOnlyDbTarget target,
  required String bookTitle,
  int? categoryId,
}) => Isolate.run(
  () => load(target: target, bookTitle: bookTitle, categoryId: categoryId),
);

/// סמני חלוקה וכותרות נושא בגוף הטקסט של ספר, ממופתחים לפי `lineIndex`.
/// [markers] — עלי `Simanim` (אותיות פסקה במדרש רבה, "א") ו-`Seifim`
/// (סעיפים בנושאי-כלים, "סעיף ג"; מגרסת ספרייה 24).
/// [headings] — רשומות `Topic` ("הלכות ציצית") ושמות פרשה (`Parasha` ברמה 0,
/// בלי העליות), רק כשאינם כבר גלויים בטקסט.
InlineSectionMarks _loadInlineSectionMarksInIsolate({
  required ReadOnlyDbTarget target,
  required String bookTitle,
  int? categoryId,
  ReadOnlyConnection? connection,
}) {
  sqlite3.Database? db;
  try {
    db = connection?.db ?? openReadOnlyTarget(target);
    final capabilities = connection?.capabilities ?? DbCapabilities.probe(db);
    if (!capabilities.hasAltToc) return (markers: const {}, headings: const {});

    final bookId = _selectBookId(
      db,
      capabilities,
      bookTitle,
      categoryId: categoryId,
    );
    if (bookId == null) return (markers: const {}, headings: const {});

    // hasChildren = 0 — רק העלים. רשומות הביניים של המבנה משכפלות
    // כותרות פרשה/פרק/סימן שכבר גלויות בטקסט (ובקוהלת רבה המבנה
    // תלת-רמתי: פרשה → פרק → סימן).
    final markerRows = db
        .select(
          '''
      SELECT l.lineIndex AS lineIndex, t.text AS label
      FROM alt_toc_structure s
      JOIN alt_toc_entry e ON e.structureId = s.id
      JOIN tocText t ON t.id = e.textId
      JOIN line l ON l.id = e.lineId
      WHERE s.bookId = ? AND s.key IN ('Simanim', 'Seifim')
        AND e.hasChildren = 0
      ''',
          [bookId],
        )
        .toMapList();

    final markers = <int, String>{};
    for (final row in markerRows) {
      final lineIndex = row['lineIndex'];
      final label = row['label'];
      if (lineIndex is int && label is String && label.isNotEmpty) {
        markers[lineIndex] = label;
      }
    }

    // כל הרמות, לא רק עלים: בערוך השולחן "הלכות X" החסרה היא צומת ביניים,
    // והעלה ("סימן א") נופל בבדיקת הנראוּת.
    final headingRows = db.select(
      capabilities.hasSplitLineContent
          ? '''
      SELECT s.key AS structureKey, l.lineIndex AS lineIndex, t.text AS label,
        lc.content AS line0,
        (SELECT pc.content FROM line p JOIN line_content pc ON pc.id = p.id
          WHERE p.bookId = l.bookId AND p.lineIndex = l.lineIndex - 1) AS line1,
        (SELECT pc.content FROM line p JOIN line_content pc ON pc.id = p.id
          WHERE p.bookId = l.bookId AND p.lineIndex = l.lineIndex - 2) AS line2
      FROM alt_toc_structure s
      JOIN alt_toc_entry e ON e.structureId = s.id
      JOIN tocText t ON t.id = e.textId
      JOIN line l ON l.id = e.lineId
      LEFT JOIN line_content lc ON lc.id = l.id
      WHERE s.bookId = ?
        AND (s.key = 'Topic' OR (s.key = 'Parasha' AND e.level = 0))
      ORDER BY l.lineIndex, e.level
      '''
          : '''
      SELECT s.key AS structureKey, l.lineIndex AS lineIndex, t.text AS label,
        l.content AS line0,
        (SELECT p.content FROM line p
          WHERE p.bookId = l.bookId AND p.lineIndex = l.lineIndex - 1) AS line1,
        (SELECT p.content FROM line p
          WHERE p.bookId = l.bookId AND p.lineIndex = l.lineIndex - 2) AS line2
      FROM alt_toc_structure s
      JOIN alt_toc_entry e ON e.structureId = s.id
      JOIN tocText t ON t.id = e.textId
      JOIN line l ON l.id = e.lineId
      WHERE s.bookId = ?
        AND (s.key = 'Topic' OR (s.key = 'Parasha' AND e.level = 0))
      ORDER BY l.lineIndex, e.level
      ''',
      [bookId],
    ).toMapList();

    // השאילתה מביאה לכל כותרת את שורתה ושתיים שלפניה — חלון הבדיקה כולו.
    // שורה מפוענחת רק כשבדיקת הנראוּת מגיעה אליה, ופעם אחת.
    final rawByIndex = <int, Object?>{};
    final rows = <({int lineIndex, String label})>[];
    for (final row in headingRows) {
      final lineIndex = row['lineIndex'];
      final rawLabel = row['label'];
      if (lineIndex is! int || rawLabel is! String) continue;
      final label = row['structureKey'] == 'Parasha'
          ? parashaHeadingLabel(rawLabel)
          : rawLabel;
      if (label == null) continue;
      rawByIndex[lineIndex] = row['line0'];
      rawByIndex[lineIndex - 1] ??= row['line1'];
      rawByIndex[lineIndex - 2] ??= row['line2'];
      rows.add((lineIndex: lineIndex, label: label));
    }
    final codec = LineContentCodec.of(db);
    final linesByIndex = <int, String?>{};
    final headings = buildSectionHeadings(
      rows,
      (i) => linesByIndex.containsKey(i)
          ? linesByIndex[i]
          : linesByIndex[i] = codec.text(rawByIndex[i]),
    );
    return (markers: markers, headings: headings);
  } finally {
    if (connection == null) db?.close();
  }
}

/// סמני חלוקה ([markers]) וכותרות נושא ([headings]) לפי `lineIndex`.
typedef InlineSectionMarks = ({
  Map<int, String> markers,
  Map<int, List<String>> headings,
});

/// דיבורי-המתחיל של ספר, ממופתחים לפי `lineIndex` — הצורה המודפסת
/// (`dhDisplay`) מטבלת `line_dh`. מסד ישן, בלי הטבלה או בלי העמודה, נותן
/// מפה ריקה.
Map<int, String> _loadDibburHamatchilInIsolate({
  required ReadOnlyDbTarget target,
  required String bookTitle,
  int? categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasLineDhDisplay) return const {};

    final bookId = _selectBookId(
      db,
      capabilities,
      bookTitle,
      categoryId: categoryId,
    );
    if (bookId == null) return const {};

    final rows = db.select(
      'SELECT lineIndex, dhDisplay FROM line_dh WHERE bookId = ? '
      'ORDER BY lineIndex',
      [bookId],
    ).toMapList();
    final dibburim = <int, String>{};
    for (final row in rows) {
      final lineIndex = row['lineIndex'];
      final display = row['dhDisplay'];
      if (lineIndex is int && display is String && display.isNotEmpty) {
        dibburim[lineIndex] = display;
      }
    }
    return dibburim;
  } finally {
    db?.close();
  }
}

/// תא שלם בשורת שם קודש; ערך אחר — FormatException, כמו span פגום.
int _divineNameInt(sqlite3.Row row, String column) {
  final value = row[column];
  if (value is! int) {
    throw FormatException('divine-name $column is not an integer: $value');
  }
  return value;
}

/// מופעי שמות הקודש של ספר (`line_divine_name`) לפי `lineIndex`, בשאילתה
/// אחת. מסד ישן, בלי הטבלה, נותן [DivineNameSpans.empty].
DivineNameSpans _loadDivineNamesInIsolate({
  required ReadOnlyDbTarget target,
  required String bookTitle,
  int? categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasDivineNames) return DivineNameSpans.empty;

    final bookId = _selectBookId(
      db,
      capabilities,
      bookTitle,
      categoryId: categoryId,
    );
    if (bookId == null) return DivineNameSpans.empty;

    final builder = DivineNameSpansBuilder();
    final rows = db.select(
      'SELECT l.lineIndex AS lineIndex, d.charStart AS charStart, '
      'd.span AS span '
      'FROM line l JOIN line_divine_name d ON d.lineId = l.id '
      'WHERE l.bookId = ? ORDER BY l.lineIndex, d.charStart',
      [bookId],
    );
    for (final row in rows) {
      final lineIndex = _divineNameInt(row, 'lineIndex');
      final start = _divineNameInt(row, 'charStart');
      final name = decodeDivineNameSpan(start, _divineNameInt(row, 'span'));
      builder.add(lineIndex, start, name.end, name.kind);
    }
    return builder.build();
  } finally {
    db?.close();
  }
}

/// הערות השוליים של ספר (`line_note`) לפי `lineIndex`, בשאילתה אחת. מסד בלי
/// הטבלה (סכמה 6, מצורף, אישי) נותן [BookNotes.empty]. גוף ההערה מפוענח כמו
/// טקסט שורה ([LineContentCodec]).
BookNotes _loadBookNotesInIsolate({
  required ReadOnlyDbTarget target,
  required String bookTitle,
  int? categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasBookNotes) return BookNotes.empty;

    final bookId = _selectBookId(
      db,
      capabilities,
      bookTitle,
      categoryId: categoryId,
    );
    if (bookId == null) return BookNotes.empty;

    final builder = BookNotesBuilder();
    final codec = LineContentCodec.of(db);
    // הסימן לא נשמר: ה-<sup> ה-k-י שבשורה הוא הסימן של ההערה ה-k-ית שיש לה hasMarker.
    final split = capabilities.hasSplitLineContent;
    final markersByLine = <int, List<String>>{
      for (final row in db.select(
        'SELECT l.id AS lineId, ${split ? 'lc.content' : 'l.content'} AS content '
        'FROM line l ${split ? 'LEFT JOIN line_content lc ON lc.id = l.id ' : ''}'
        'WHERE l.bookId = ? AND EXISTS (SELECT 1 FROM line_note n '
        'WHERE n.lineId = l.id AND n.hasMarker = 1)',
        [bookId],
      ))
        row['lineId'] as int: bookNoteMarkers(codec.text(row['content']) ?? ''),
    };
    final markersTaken = <int, int>{};
    final rows = db.select(
      'SELECT l.id AS lineId, l.lineIndex AS lineIndex, n.noteIndex AS noteIndex, '
      'n.charPos AS charPos, n.hasMarker AS hasMarker, n.body AS body '
      'FROM line l JOIN line_note n ON n.lineId = l.id '
      'WHERE l.bookId = ? ORDER BY l.lineIndex, n.noteIndex',
      [bookId],
    );
    for (final row in rows) {
      final lineId = row['lineId'] as int;
      final lineIndex = row['lineIndex'];
      final noteIndex = row['noteIndex'];
      final charPos = row['charPos'];
      final String? marker;
      switch (row['hasMarker']) {
        case 0:
          marker = null;
        case 1:
          final markers = markersByLine[lineId]!;
          final taken = markersTaken[lineId] ?? 0;
          if (taken == markers.length) {
            throw FormatException('בשורה $lineId יש פחות סימני הערה מהערות');
          }
          marker = markers[taken];
          markersTaken[lineId] = taken + 1;
        case final other:
          throw FormatException(
            'line_note.hasMarker של שורה $lineId הוא $other',
          );
      }
      final body = codec.text(row['body']);
      if (lineIndex is int && noteIndex is int && body is String) {
        builder.add(
          lineIndex,
          noteIndex,
          marker,
          body,
          charPos: charPos is int ? charPos : -1,
        );
      }
    }
    for (final MapEntry(key: lineId, value: markers) in markersByLine.entries) {
      if (markersTaken[lineId] != markers.length) {
        throw FormatException('בשורה $lineId יש יותר סימני הערה מהערות');
      }
    }
    if (capabilities.hasBookNoteDivineNames) {
      // שכבת השמות נכשלת לבדה: גוף ההערות נשאר, בלי אף שם (לא חלקית).
      try {
        final names =
            <({int lineIndex, int noteIndex, int start, int end, int kind})>[];
        for (final row in db.select(
          'SELECT l.lineIndex AS lineIndex, d.noteIndex AS noteIndex, '
          'd.charStart AS charStart, d.span AS span '
          'FROM line l JOIN line_note_divine_name d ON d.lineId = l.id '
          'WHERE l.bookId = ? ORDER BY l.lineIndex, d.noteIndex, d.charStart',
          [bookId],
        )) {
          final start = _divineNameInt(row, 'charStart');
          final name = decodeDivineNameSpan(start, _divineNameInt(row, 'span'));
          names.add((
            lineIndex: _divineNameInt(row, 'lineIndex'),
            noteIndex: _divineNameInt(row, 'noteIndex'),
            start: start,
            end: name.end,
            kind: name.kind,
          ));
        }
        for (final n in names) {
          builder.addDivineName(
            n.lineIndex,
            n.noteIndex,
            n.start,
            n.end,
            n.kind,
          );
        }
      } on Exception catch (e) {
        debugPrint('⚠️ Error in getBookNotes divine names "$bookTitle": $e');
      }
    }
    return builder.build();
  } finally {
    db?.close();
  }
}

/// Top-level wrapper עבור טעינת קישורי ספר ב-isolate.
/// ראה ההסבר ב-[_runBookLoadInIsolate].
Future<List<Map<String, Object?>>> _runBookLinksInIsolate({
  required ReadOnlyDbTarget target,
  required String title,
  required int categoryId,
  required String fileType,
}) {
  return Isolate.run(
    () => _loadBookLinksRowsInIsolate(
      target: target,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    ),
  );
}

/// Top-level wrapper עבור טעינת קישורי טווח ב-isolate.
/// ראה ההסבר ב-[_runBookLoadInIsolate].
Future<List<Map<String, Object?>>> _runBookLinksInRangeInIsolate({
  required ReadOnlyDbTarget target,
  required bool official,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLineIndex,
  required int endLineIndex,
  List<String>? targetBookTitles,
}) {
  return Isolate.run(
    () => _loadBookLinksRowsInRangeInIsolate(
      target: target,
      official: official,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      startLineIndex: startLineIndex,
      endLineIndex: endLineIndex,
      targetBookTitles: targetBookTitles,
    ),
  );
}

/// Top-level worker לטעינת טווח שורות על חיבור RO חדש ב-isolate; ה-join+split
/// מתבצע כאן כדי לא לחסום את ה-UI thread. ראה [_runBookLoadInIsolate].
({int startLine, int endLine, int totalLines, List<String> lines})?
_loadBookTextRangeRowsInIsolate({
  required ReadOnlyDbTarget target,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLine,
  required int endLine,
  String? versionTitle,
  ReadOnlyConnection? connection,
}) {
  sqlite3.Database? db;
  try {
    db = connection?.db ?? openReadOnlyTarget(target);
    final capabilities = connection?.capabilities ?? DbCapabilities.probe(db);
    if (!capabilities.hasLines) return null;

    final bookId = _selectBookId(
      db,
      capabilities,
      title,
      categoryId: categoryId,
    );
    if (bookId == null) return null;
    final totalLinesQuery = capabilities.hasColumn('book', 'totalLines')
        ? 'SELECT totalLines FROM book WHERE id = ?'
        : 'SELECT COUNT(*) FROM line WHERE bookId = ?';
    final totalLines = firstIntValue(db.select(totalLinesQuery, [bookId])) ?? 0;
    if (totalLines <= 0) {
      return null;
    }

    final normalizedStart = startLine.clamp(0, totalLines - 1);
    final normalizedEnd = endLine.clamp(normalizedStart, totalLines - 1);

    final List<Map<String, dynamic>> rows;
    if (versionTitle != null) {
      if (!capabilities.hasBookVersions) return null;
      final versionRows = db.select(
        'SELECT id FROM book_version WHERE bookId = ? AND versionTitle = ? LIMIT 1',
        [bookId, versionTitle],
      ).toMapList();
      if (versionRows.isEmpty) return null;
      final versionId = versionRows.first['id'] as int;
      // מהדורה חלופית: שורות מבנה (heRef NULL — כותרות/מחברים) נשארות מהשלד;
      // שורת תוכן מקבלת את נוסח המהדורה, וסגמנט שחסר בה מוצג ריק — לעולם לא
      // נופלים בשקט לנוסח הממוזג.
      rows = db.select(
        capabilities.hasSplitLineContent
            // סכמה 6: vl.content NULL = זהה לבסיס; שורה חסרה עדיין ריקה.
            ? '''
        SELECT CASE WHEN l.heRef IS NULL THEN lc.content
                    WHEN vl.lineId IS NULL THEN ''
                    ELSE COALESCE(vl.content, lc.content, '') END AS content
        FROM line l
        LEFT JOIN line_content lc ON lc.id = l.id
        LEFT JOIN version_line vl ON vl.versionId = ? AND vl.lineId = l.id
        WHERE l.bookId = ? AND l.lineIndex >= ? AND l.lineIndex <= ?
        ORDER BY l.lineIndex
      '''
            : '''
        SELECT CASE WHEN l.heRef IS NULL THEN l.content
                    ELSE COALESCE(vl.content, '') END AS content
        FROM line l
        LEFT JOIN version_line vl ON vl.versionId = ? AND vl.lineId = l.id
        WHERE l.bookId = ? AND l.lineIndex >= ? AND l.lineIndex <= ?
        ORDER BY l.lineIndex
      ''',
        [versionId, bookId, normalizedStart, normalizedEnd],
      ).toMapList();
    } else {
      rows = db.select(
        capabilities.hasSplitLineContent
            ? 'SELECT lc.content AS content FROM line l '
                  'LEFT JOIN line_content lc ON lc.id = l.id '
                  'WHERE l.bookId = ? AND l.lineIndex >= ? AND l.lineIndex <= ? '
                  'ORDER BY l.lineIndex'
            : 'SELECT content FROM line WHERE bookId = ? AND lineIndex >= ? AND lineIndex <= ? ORDER BY lineIndex',
        [bookId, normalizedStart, normalizedEnd],
      ).toMapList();
    }
    if (rows.isEmpty) {
      return null;
    }

    final codec = LineContentCodec.of(db);
    final text = rows.map((row) => codec.text(row['content']) ?? '').join('\n');
    return (
      startLine: normalizedStart,
      endLine: normalizedEnd,
      totalLines: totalLines,
      lines: text.split('\n'),
    );
  } finally {
    if (connection == null) db?.close();
  }
}

/// Top-level wrapper עבור טעינת טווח תוכן ב-isolate.
/// ראה ההסבר ב-[_runBookLoadInIsolate].
Future<({int startLine, int endLine, int totalLines, List<String> lines})?>
_runBookTextRangeInIsolate({
  required ReadOnlyDbTarget target,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLine,
  required int endLine,
  String? versionTitle,
}) {
  return Isolate.run(
    () => _loadBookTextRangeRowsInIsolate(
      target: target,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      startLine: startLine,
      endLine: endLine,
      versionTitle: versionTitle,
    ),
  );
}

/// טעינות הטווח של [DbReadWorker] על החיבור הקבוע שלו — אותן פונקציות של
/// מסלול ה-`Isolate.run`, בלי פתיחת חיבור ו-probe בכל בקשה.
Object? runRangeRequestOnConnection(
  String method,
  Map<String, Object?> args,
  ReadOnlyConnection connection,
) {
  final target = trustedDbTarget(args['dbPath'] as String);
  return switch (method) {
    'textRange' => _loadBookTextRangeRowsInIsolate(
      target: target,
      title: args['title'] as String,
      categoryId: args['categoryId'] as int,
      fileType: args['fileType'] as String,
      startLine: args['startLine'] as int,
      endLine: args['endLine'] as int,
      versionTitle: args['versionTitle'] as String?,
      connection: connection,
    ),
    'linksRange' => _loadBookLinksRowsInRangeInIsolate(
      target: target,
      official: true,
      title: args['title'] as String,
      categoryId: args['categoryId'] as int,
      fileType: args['fileType'] as String,
      startLineIndex: args['startLineIndex'] as int,
      endLineIndex: args['endLineIndex'] as int,
      targetBookTitles: (args['targetBookTitles'] as List?)?.cast<String>(),
      connection: connection,
    ),
    'inlineSectionMarks' => _loadInlineSectionMarksInIsolate(
      target: target,
      bookTitle: args['bookTitle'] as String,
      categoryId: args['categoryId'] as int?,
      connection: connection,
    ),
    _ => throw StateError('Unknown DbReadWorker method: $method'),
  };
}

/// seforim.db נקרא ב-[DbReadWorker]; מסד מצורף, או worker שאינו זמין,
/// נשארים במסלול [isolateRun] (חיבור חדש לכל בקשה).
Future<T> _loadOnReadWorker<T>(
  ReadOnlyDbTarget target,
  String method,
  Map<String, Object?> args,
  Future<T> Function() isolateRun,
) async {
  if (target.untrusted) return isolateRun();
  try {
    return await DbReadWorker.request(method, {
          ...args,
          'dbPath': target.path,
        })
        as T;
  } on DbReadWorkerUnavailable {
    return DbReadWorker.trackTemporaryRead(isolateRun);
  }
}

/// Top-level worker לרשימת המהדורות (book_version) של ספר. רשימה ריקה כשה-DB
/// ישן (אין טבלה) או כשאין לספר מידע גרסאות.
List<Map<String, dynamic>> _loadBookVersionsRowsInIsolate({
  required ReadOnlyDbTarget target,
  required String title,
  required int categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasBookVersions) return const [];

    final bookId = _selectBookId(
      db,
      capabilities,
      title,
      categoryId: categoryId,
    );
    if (bookId == null) return const [];

    return db
        .select(
          '''
      SELECT versionTitle, heVersionTitle, versionSource, priority, license,
             versionNotes, heVersionNotes, hasContent
      FROM book_version
      WHERE bookId = ?
      ORDER BY hasContent DESC, priority DESC, versionTitle
    ''',
          [bookId],
        )
        .toMapList();
  } finally {
    db?.close();
  }
}

/// Top-level wrapper עבור רשימת מהדורות ב-isolate.
/// ראה ההסבר ב-[_runBookLoadInIsolate].
Future<List<Map<String, dynamic>>> _runBookVersionsInIsolate({
  required ReadOnlyDbTarget target,
  required String title,
  required int categoryId,
}) {
  return Isolate.run(
    () => _loadBookVersionsRowsInIsolate(
      target: target,
      title: title,
      categoryId: categoryId,
    ),
  );
}

/// (title, categoryId) של ספרים שיש להם מהדורה לבחירה: 2+ גרסאות, או גרסה
/// יחידה עם טקסט שמור. גרסה יחידה מטא-דאטה בלבד = הנוסח המוצג עצמו, ואינה
/// נכללת. נטען פעם אחת ומשמש לקביעת הצגת תפריט 'גרסאות'.
List<Map<String, dynamic>> _loadSelectableVersionKeysInIsolate({
  required ReadOnlyDbTarget target,
}) {
  sqlite3.Database? db;
  try {
    db = openReadOnlyTarget(target);
    final capabilities = DbCapabilities.probe(db);
    if (!capabilities.hasBookVersions) return const [];

    return db.select('''
      SELECT b.title, ${capabilities.hasBookCategories ? 'b.categoryId' : '0 AS categoryId'}
      FROM book b
      WHERE b.id IN (
        SELECT bookId FROM book_version
        GROUP BY bookId
        HAVING COUNT(*) >= 2 OR MAX(hasContent) = 1
      )
    ''').toMapList();
  } finally {
    db?.close();
  }
}

Future<List<Map<String, dynamic>>> _runSelectableVersionKeysInIsolate({
  required ReadOnlyDbTarget target,
}) {
  return Isolate.run(
    () => _loadSelectableVersionKeysInIsolate(target: target),
  );
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

  /// מזהי ספרים (ב-user_books.db) שקובצם השתנה מאז הסריקה הקודמת —
  /// דורשים אינדוקס מחדש בחיפוש.
  final List<int> updatedBookIds;

  const ScanResult({
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.failedBooks = 0,
    this.fatalError,
    this.failedDetails = const [],
    this.updatedBookIds = const [],
  });

  bool get isSuccess => fatalError == null;
  bool get hasPartialFailure => fatalError == null && failedBooks > 0;
  bool get hasChanges => addedBooks > 0 || updatedBooks > 0;
}

/// Library provider that loads books from the SQLite database.
class DatabaseLibraryProvider implements LibraryProvider, LinkLinesProvider {
  final SqliteDataProvider _sqliteProvider = SqliteDataProvider.instance;
  final Set<BookCompositeKey> _cachedKeys = {};
  final Map<int, String> _categoryIdToPath = {};
  final Map<int, db_models.Category> _categoriesById = {};
  bool _titlesCached = false;
  String? _bundledTalmudBavliPathCache;
  bool? _bundledTalmudBavliExistsCache;

  /// מפתחות "title\u0000categoryId" של ספרים שראוי להציג להם תפריט 'גרסאות',
  /// לפי `BookSource.wireKey`. נטען פעם אחת לכל מסד; מנוקה ב-[clearCache].
  final Map<String, Future<Set<String>>> _selectableVersionKeysFutures = {};

  /// IDs **טבעיים** (native AUTOINCREMENT) של קטגוריות ב-`user_books.db`
  /// שצורפו ל-Library. שימושי כדי לדעת לאיזה DB לפנות בקריאות
  /// `getBookText`/`getBookToc`/`hasBook` כשרק `categoryId` ידוע (בלי
  /// `preferSource`).
  ///
  /// שים לב: יכולה להיות חפיפה עם IDs של seforim — אם שני ה-DBs קצו 1,2,3…
  /// אז 5 יכול להיות בשניהם. לכן הסט הזה רק *רומז* על user_books, וההכרעה
  /// הסופית נופלת על ה-cache (`_userBooksCachedKeys`) שמשתמש במפתח עם
  /// `source: BookSource.user`.
  final Set<int> _userBooksCategoryIds = {};

  /// מיפוי `(title, categoryId, fileType) → BookCompositeKey` עבור ספרים
  /// שמקורם ב-`user_books.db`. נפרד מ-`_cachedKeys` כדי שהמטמון של seforim
  /// לא ייפגע. כל המפתחות כאן עם `source: BookSource.user`.
  final Set<BookCompositeKey> _userBooksCachedKeys = {};

  /// ספרים אישיים לפי מזהה ב-user_books.db — כולל גרסאות שאינן בעץ.
  final Map<int, Book> _userBooksById = {};

  /// גרסאות שאינן ראשיות: נפתחות רק מתפריט 'גרסאות', ולכן אינן בעץ.
  final Set<int> _hiddenUserVersionBookIds = {};

  List<UserBookVersionRecord> _userBookVersions = const [];

  /// הספר הרשמי/המצורף שכל גרסה אישית שלו נפתרה אליו, לפי מזהה ספר הגרסה.
  final Map<int, Book> _catalogVersionPrimaries = {};

  /// מפתחות ספרי המסדים המצורפים. מזהי הקטגוריות טבעיים לכל מסד, ולכן המקור
  /// (slug) הוא חלק מהמפתח ומנתיבי הקטגוריות.
  final Set<BookCompositeKey> _attachedCachedKeys = {};
  final Map<String, Map<int, String>> _attachedCategoryPaths = {};
  final Map<String, _PendingAttachedCatalog> _pendingAttachedCatalogs = {};

  /// זמן ההמתנה לקטלוג של מסד מצורף אחד. מסד שלא ענה בזמן מסומן לא-זמין,
  /// והעץ נבנה בלעדיו; כשהקריאה מסתיימת המסד חוזר והעץ מתרענן.
  @visibleForTesting
  static Duration attachedCatalogTimeout = const Duration(seconds: 5);

  @visibleForTesting
  static Future<AttachedCatalogRows> Function(ReadOnlyDbTarget target)
  attachedCatalogReader = _readAttachedCatalogInIsolate;

  BookCompositeKey? _attachedKeyFor(
    String title,
    int categoryId,
    String fileType,
  ) {
    final normalized = BookCompositeKey.normalizeFileType(fileType);
    return _attachedCachedKeys
        .where(
          (key) =>
              key.title == title &&
              key.categoryId == categoryId &&
              key.fileType == normalized,
        )
        .firstOrNull;
  }

  void _registerUserBook(Book book, Category category) {
    final id = book.id;
    if (id != null) _userBooksById[id] = book;
    if (id == null || !_hiddenUserVersionBookIds.contains(id)) {
      category.books.add(book);
    }
  }

  Book? _userBookInCatalog(Book book) {
    final id = book.id;
    final byId = id == null ? null : _userBooksById[id];
    if (byId != null) return byId;
    return _userBooksById.values
        .where(
          (b) =>
              b.title == book.title &&
              b.categoryId == book.categoryId &&
              (book.fileType == null || b.fileType == book.fileType),
        )
        .firstOrNull;
  }

  /// הגרסאות של ספר אישי — הראשית תחילה, ואחריה לפי עדיפות ושם. ריק כשהספר
  /// אינו חלק מקבוצת גרסאות.
  List<BookVersionInfo> getUserBookVersions(Book book) {
    if (!book.isUserBook) return const [];
    final id = _userBookInCatalog(book)?.id;
    if (id == null) return const [];
    return buildUserBookVersions(
      bookId: id,
      records: _userBookVersions,
      booksById: _userBooksById,
      catalogPrimaries: _catalogVersionPrimaries,
    );
  }

  /// הגרסאות האישיות שהוצהרו על ספר רשמי או ממסד מצורף [book].
  List<BookVersionInfo> getPersonalVersionsOf(Book book) {
    if (book.isUserBook || _catalogVersionPrimaries.isEmpty) return const [];
    return buildPersonalVersionsOfCatalogBook(
      primary: book,
      records: _userBookVersions,
      booksById: _userBooksById,
      catalogPrimaries: _catalogVersionPrimaries,
    );
  }

  static UserBookVersionRecord? _userBookVersionFromRow(
    Map<String, dynamic> row,
  ) {
    final versionBookId = row['versionBookId'] as int;
    final versionTitle = row['versionTitle'] as String;
    final versionNotes = row['versionNotes'] as String?;
    final priority = (row['priority'] as num?)?.toDouble();
    final source =
        BookSource.tryParse(row['primarySource'] as String?) ?? BookSource.user;
    if (source.isUser) {
      final primaryId = row['primaryBookId'] as int?;
      if (primaryId == null) return null;
      return UserBookVersionRecord(
        versionBookId: versionBookId,
        primaryBookId: primaryId,
        versionTitle: versionTitle,
        versionNotes: versionNotes,
        priority: priority,
      );
    }
    final primaryTitle = row['primaryTitle'] as String?;
    if (primaryTitle == null || primaryTitle.trim().isEmpty) return null;
    return UserBookVersionRecord.ofCatalogBook(
      versionBookId: versionBookId,
      primarySource: source,
      primaryTitle: primaryTitle,
      primaryCategoryPath: row['primaryCategoryPath'] as String?,
      versionTitle: versionTitle,
      versionNotes: versionNotes,
      priority: priority,
    );
  }

  /// קושר גרסאות אישיות לספרים רשמיים/מצורפים לפי כותרת (ולא לפי מזהה, שמשתנה
  /// בעדכון ספרייה). גרסה שהראשי שלה לא נמצא נשארת ספר אישי רגיל בעץ.
  void _attachCatalogBookVersions(Library library) {
    _catalogVersionPrimaries.clear();
    _resolveCatalogVersionPrimaries(library);
    library.offTreeBooks = [
      for (final id in _hiddenUserVersionBookIds) ?_userBooksById[id],
    ];
  }

  void _resolveCatalogVersionPrimaries(Library library) {
    final pending = _userBookVersions.where((v) => v.hasCatalogPrimary);
    if (pending.isEmpty) return;

    final catalogByTitle = <String, List<Book>>{};
    for (final book in library.getAllBooks()) {
      if (book.isUserBook) continue;
      catalogByTitle
          .putIfAbsent(normalizeVersionTitle(book.title), () => [])
          .add(book);
    }
    for (final record in pending) {
      final version = _userBooksById[record.versionBookId];
      if (version == null) continue;
      final primary = resolveCatalogPrimary(record, catalogByTitle);
      if (primary == null) {
        debugPrint(
          '⚠️ [UserBookVersions] primary not found for book '
          '${record.versionBookId} (${record.primarySource.wireKey})',
        );
        continue;
      }
      _catalogVersionPrimaries[record.versionBookId] = primary;
      _hiddenUserVersionBookIds.add(record.versionBookId);
      version.category?.books.remove(version);
    }
  }

  bool _isUserBooksCategoryId(int categoryId) =>
      _userBooksCategoryIds.contains(categoryId);

  /// מקור הקריאה בפועל לפי אותו ניתוב שמשמש את הטקסט ותוכן העניינים.
  BookSource? resolvedSourceForBook(TextBook book) => book.categoryId == null
      ? null
      : _resolveSource(
          title: book.title,
          categoryId: book.categoryId!,
          fileType: book.fileType ?? 'txt',
          preferSource: book.source,
        );

  /// המסד שממנו לקרוא ספר שידוע רק לפי כותרת+קטגוריה+סוג: [preferSource]
  /// כשאינו רשמי, אחרת אישי רק כשהמטמון או הקטגוריה מעידים על כך.
  BookSource _resolveSource({
    required String title,
    required int categoryId,
    required String fileType,
    required BookSource preferSource,
  }) {
    if (!preferSource.isOfficial) return preferSource;
    final key = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      source: BookSource.user,
    );
    if (_userBooksCachedKeys.contains(key)) return BookSource.user;
    // שני המסדים מונים קטגוריות מ-1, ולכן מזהה קטגוריה לבדו אינו מכריע:
    // ספר שמוכר ל-seforim באותה קטגוריה נשאר רשמי.
    final seforimKey = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (_cachedKeys.contains(seforimKey)) return BookSource.official;
    final attachedKey = _attachedKeyFor(title, categoryId, fileType);
    if (attachedKey != null) return attachedKey.source;
    return _isUserBooksCategoryId(categoryId)
        ? BookSource.user
        : BookSource.official;
  }

  /// המסד שממנו קוראים ב-isolate נתוני ספר מ-[source]: seforim.db, או מסד
  /// מצורף (נפתח מוקשח). null — אין מסד כזה (ספר אישי, מסד שאינו תקין).
  ReadOnlyDbTarget? _isolateTargetFor(BookSource source) => switch (source) {
    OfficialBookSource() =>
      _sqliteProvider.isInitialized && _sqliteProvider.repository != null
          ? trustedDbTarget(_sqliteProvider.dbPath)
          : null,
    UserBookSource() => null,
    AttachedBookSource(:final slug) => switch (AttachedLibraryRegistry.instance
        .libraryFor(slug)) {
      final library? => (
        path: library.path,
        untrusted: true,
        immutable: library.immutable,
      ),
      null => null,
    },
  };

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
  static Future<T> loadOnReadWorkerForTesting<T>(
    ReadOnlyDbTarget target,
    String method,
    Map<String, Object?> args,
    Future<T> Function() fallback,
  ) => _loadOnReadWorker(target, method, args, fallback);

  @visibleForTesting
  static List<Map<String, dynamic>> loadBookLinksRowsForTesting({
    required String dbPath,
    bool untrusted = false,
    required String title,
    required int categoryId,
    required String fileType,
  }) {
    return _loadBookLinksRowsInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadAlternativeStructuresRowsForTesting({
    required String dbPath,
    bool untrusted = false,
    required String bookTitle,
    int? categoryId,
  }) {
    return _loadAlternativeStructuresRowsInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      bookTitle: bookTitle,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static BookNotes loadBookNotesForTesting({
    required String dbPath,
    bool untrusted = false,
    required String bookTitle,
    int? categoryId,
  }) {
    return _loadBookNotesInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      bookTitle: bookTitle,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static DivineNameSpans loadDivineNamesForTesting({
    required String dbPath,
    bool untrusted = false,
    required String bookTitle,
    int? categoryId,
  }) {
    return _loadDivineNamesInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      bookTitle: bookTitle,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static Map<int, String> loadDibburHamatchilForTesting({
    required String dbPath,
    bool untrusted = false,
    required String bookTitle,
    int? categoryId,
  }) {
    return _loadDibburHamatchilInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      bookTitle: bookTitle,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static InlineSectionMarks loadInlineSectionMarksForTesting({
    required String dbPath,
    bool untrusted = false,
    required String bookTitle,
    int? categoryId,
  }) {
    return _loadInlineSectionMarksInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      bookTitle: bookTitle,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadSelectableVersionKeysForTesting({
    required String dbPath,
    bool untrusted = false,
  }) {
    return _loadSelectableVersionKeysInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadBookLinksRowsInRangeForTesting({
    required String dbPath,
    bool untrusted = false,
    bool official = false,
    required String title,
    required int categoryId,
    required String fileType,
    required int startLineIndex,
    required int endLineIndex,
    List<String>? targetBookTitles,
  }) {
    return _loadBookLinksRowsInRangeInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      official: official,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      startLineIndex: startLineIndex,
      endLineIndex: endLineIndex,
      targetBookTitles: targetBookTitles,
    );
  }

  @visibleForTesting
  static ({List<Map<String, dynamic>> rows, int? maxSourceLineIndex})
  loadBookLinkTargetsSummaryRowsForTesting({
    required String dbPath,
    bool untrusted = false,
    bool official = false,
    required String title,
    required int categoryId,
  }) {
    return _loadBookLinkTargetsSummaryRowsInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      official: official,
      title: title,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static bool usesReverseMaxSourceLineQueryForTesting({
    required String dbPath,
    required int bookId,
  }) {
    final db = openReadOnlyTarget((
      path: dbPath,
      untrusted: false,
      immutable: false,
    ));
    try {
      return _hasManySourceLinks(db, bookId);
    } finally {
      db.close();
    }
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadBookVersionsRowsForTesting({
    required String dbPath,
    bool untrusted = false,
    required String title,
    required int categoryId,
  }) {
    return _loadBookVersionsRowsInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      title: title,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static ({int startLine, int endLine, int totalLines, List<String> lines})?
  loadBookTextRangeRowsForTesting({
    required String dbPath,
    bool untrusted = false,
    required String title,
    required int categoryId,
    required String fileType,
    required int startLine,
    required int endLine,
    String? versionTitle,
  }) {
    return _loadBookTextRangeRowsInIsolate(
      target: (path: dbPath, untrusted: untrusted, immutable: false),
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      startLine: startLine,
      endLine: endLine,
      versionTitle: versionTitle,
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
      // חילוץ שנקטע משאיר תיקייה עם PDF חלקי וסימון-ביניים; מתעלמים ממנה עד
      // שההתקנה תושלם, אחרת הספרייה תציג מסכתות עם קבצים חסרים.
      if (exists &&
          !DatabaseConstants.isTalmudBavliInstallInProgress(candidatePath)) {
        _bundledTalmudBavliPathCache = candidatePath;
        _bundledTalmudBavliExistsCache = true;
        return true;
      }
    }

    _bundledTalmudBavliPathCache = candidatePaths.first;
    _bundledTalmudBavliExistsCache = false;
    return false;
  }

  /// מסכתות PDF בלי טקסט בבלי תואם: הסדר שלהן והמסכת שאחריה הן מוצגות.
  static const _talmudBavliPdfSederPlacement = {
    'שקלים': (seder: 'סדר מועד', after: 'פסחים'),
    'עדיות': (seder: 'סדר נזיקין', after: 'שבועות'),
  };

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

      final placement = titleToSubCategory.containsKey(title)
          ? null
          : _talmudBavliPdfSederPlacement[title];
      final placementSeder = placement == null
          ? null
          : category.subCategories
                .where((c) => c.title == placement.seder)
                .firstOrNull;

      // Place PDF in the sub-category of its matching TextBook.
      // Orphans (no matching TextBook) go into a dedicated sub-category
      // appended after "סדר טהרות" so they don't float to the top.
      if (orphanCategory == null &&
          placementSeder == null &&
          !titleToSubCategory.containsKey(title)) {
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
          titleToSubCategory[title] ??
          placementSeder ??
          orphanCategory ??
          category;
      final targetCategoryId = titleToSubCategory.containsKey(title)
          ? targetCategory.title.hashCode
          : DatabaseConstants.talmudBavliFolderName.hashCode;

      final bookMeta = metadata[title];
      final matchingTextBook = targetCategory.books
          .where((b) => b is TextBook && b.title == title)
          .firstOrNull;
      final pdfBook = PdfBook(
        id: matchingTextBook?.id,
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          title,
        ),
        title: title,
        category: targetCategory,
        path: entity.path,
        filePath: entity.path,
        author: bookMeta?['author'] as String?,
        heShortDesc: bookMeta?['heShortDesc'] as String?,
        pubDate: bookMeta?['pubDate'] as String?,
        pubPlace: bookMeta?['pubPlace'] as String?,
        order:
            matchingTextBook?.order ??
            placementSeder?.books
                .where((b) => b.title == placement!.after)
                .firstOrNull
                ?.order ??
            bookMeta?['order'] as int? ??
            999,
        topics: DatabaseConstants.talmudBavliFolderName,
        categoryPath: DatabaseConstants.talmudBavliFolderName,
        categoryId: targetCategoryId,
      );

      targetCategory.books.add(pdfBook);
      existingPdfTitles.add(title);
      modifiedCategories.add(targetCategory);
      _cachedKeys.add(
        BookCompositeKey.create(
          title: title,
          categoryId: targetCategoryId,
          fileType: 'pdf',
        ),
      );
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
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    final Map<String, List<Book>> booksByCategory = {};

    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty');
      return booksByCategory;
    }

    try {
      final hasTalmudBavliDirectory =
          await _bundledTalmudBavliDirectoryExists();
      // נצפה *לפני* השליפה: clear() שיקרה במהלכה פוסל את הזריעה.
      final booksCacheGeneration = BooksCache.instance.generation;
      final dbBooks = await _sqliteProvider.repository!.getAllBooks();
      // אותן שורות שהקאש המשותף צריך — זריעה כאן חוסכת סריקה שנייה של
      // טבלת `book` (7,300+ ספרים).
      BooksCache.instance.seedFromBooks(
        dbBooks,
        generation: booksCacheGeneration,
      );
      final categories = await _sqliteProvider.repository!.getAllCategories();
      debugPrint('💾 Database found ${dbBooks.length} books');

      // Build category paths and caches
      final Map<int, db_models.Category> categoryMap = {
        for (var c in categories) c.id: c,
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
        _cachedKeys.add(
          BookCompositeKey.create(
            title: dbBook.title,
            categoryId: dbBook.categoryId,
            fileType: dbBook.fileType,
          ),
        );

        final categoryName = dbBook.topics.isNotEmpty
            ? dbBook.topics.first.name
            : 'ללא קטגוריה';

        final topics = _buildTopics(dbBook, categoryPath);

        final book = TextBook(
          id: dbBook.id,
          title: dbBook.title,
          author: dbBook.authors.isNotEmpty ? dbBook.authors.first.name : null,
          heShortDesc: dbBook.heShortDesc,
          pubDate: dbBook.pubDates.isNotEmpty
              ? dbBook.pubDates.first.date
              : null,
          pubPlace: dbBook.pubPlaces.isNotEmpty
              ? dbBook.pubPlaces.first.name
              : null,
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
        '💾 Database loaded ${dbBooks.length} books into ${booksByCategory.length} categories',
      );
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
      source: BookSource.user,
    );
    if (_userBooksCachedKeys.contains(userBookKey)) {
      return true;
    }
    if (_attachedKeyFor(title, categoryId, fileType) != null) return true;

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

    // seforim.db v3 אינו מכיל fileType — איתור לפי כותרת+קטגוריה בלבד.
    final book = await repository.getBookByTitleAndCategory(title, categoryId);
    return book != null;
  }

  /// מחזיר האם ספר משתמש (מ-`user_books.db`) הוא "עותק עצמאי"
  /// (content-in-db) — כלומר תוכנו שמור בתוכנה ואינו תלוי בקובץ שבדיסק.
  ///
  /// משמש את מסך הספרייה כדי לאפשר מחיקה **רק** לספרי "עותק עצמאי": ספר
  /// "קריאה מהקבצים" נמחק רק ע"י מחיקת הקובץ מהדיסק.
  ///
  /// fail-closed: מחזיר `false` אם הספר אינו ספר משתמש, אם לא נמצא, או אם
  /// ה-lookup נכשל — כדי שלא תיחשף מחיקה לספר שאינו ודאי "עותק עצמאי".
  Future<bool> isUserBookContentInDb(
    String title,
    int categoryId,
    String fileType,
  ) async {
    final source = _resolveSource(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferSource: BookSource.official,
    );
    if (!source.isUser) return false;
    try {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final book = await repo.getBookByTitleCategoryAndFileType(
        title,
        categoryId,
        fileType,
      );
      if (book == null) return false;
      return !book.isFileBacked;
    } catch (e) {
      debugPrint('⚠️ isUserBookContentInDb error: $e');
      return false;
    }
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

      final attachedSource = matchedKey?.source;
      if (attachedSource is AttachedBookSource) {
        return _attachedCategoryPaths[attachedSource.slug]?[matchedKey!
            .categoryId];
      }
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
        preferSource: categoryId != null && _isUserBooksCategoryId(categoryId)
            ? BookSource.user
            : BookSource.official,
      );
      if (resolvedBook == null) return null;
      // categoryId טבעי לשני הסוגים, ההבחנה נעשית דרך המקור.
      final path = await _getPathForCategoryId(
        resolvedBook.book.categoryId,
        fromUserBooks: resolvedBook.source.isUser,
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
          repository,
          categoryId,
        );
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
          source: BookSource.user,
        );
        if (_userBooksCachedKeys.contains(userBookKey)) {
          return userBookKey;
        }
      }
    }

    final candidateSets = <Set<BookCompositeKey>>[
      _cachedKeys,
      if (includeUserBooks) ...[_userBooksCachedKeys, _attachedCachedKeys],
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
    BookSource preferSource = BookSource.official,
  }) async {
    final source = _resolveSource(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferSource: preferSource,
    );
    if (source is AttachedBookSource) {
      return _readAttachedBookText(title, categoryId, source);
    }
    // ספרים מתיקיות מותאמות אישית: לקרוא מ-user_books.db (תוכן מהקובץ
    // עצמו אם isFileBacked, אחרת משורות ה-line).
    if (source.isUser) {
      try {
        final repo = await UserBooksDatabaseHolder.instance.repository;
        final book = await repo.getBookByTitleCategoryAndFileType(
          title,
          categoryId,
          fileType,
        );
        if (book == null) return null;
        if (book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          if (await file.exists()) {
            // PDF מוחזר null — הקוראים שלו עוברים בצנרת נפרדת. פורמט בינארי
            // (ZIP/OLE) לעולם אינו נקרא כטקסט אלא מומר.
            return await readFileBackedBookText(file, book.fileType, title);
          }
        }
        // נופל לטעינה מתוך ה-DB עצמו (טבלת `line`).
        return await _readBookTextFromUserBooksDb(
          repo,
          book.id,
          book.totalLines,
        );
      } catch (e) {
        debugPrint('⚠️ Error reading user book text: $e');
        return null;
      }
    }

    if (_sqliteProvider.repository != null) {
      try {
        // seforim.db v3 אינו מכיל fileType — איתור לפי כותרת+קטגוריה בלבד.
        final book = await _sqliteProvider.repository!
            .getBookByTitleAndCategory(title, categoryId);
        if (book != null && book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          if (await file.exists()) {
            return await readFileBackedBookText(file, book.fileType, title);
          }
        }
        // If not external or file not found, try DB text
        if (book != null) {
          return await _sqliteProvider.getBookTextFromDb(
            title,
            categoryId,
            fileType,
            preferSource,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Error reading external book text: $e');
      }
    }
    return null;
  }

  /// ספר ממסד מצורף נקרא תמיד משורות ה-`line` שלו — נתיב קובץ שבמסד אינו
  /// נפתח (מסד שאינו בשליטת התוכנה).
  Future<String?> _readAttachedBookText(
    String title,
    int categoryId,
    AttachedBookSource source,
  ) async {
    try {
      final record = await BookDatabaseResolver.resolveBook(
        title: title,
        categoryId: categoryId,
        preferSource: source,
      );
      if (record == null || record.source != source) return null;
      final text = await BookTextReader.text(record.repository, record.book);
      if (text != null) return text;
      // ספר מבוסס-קובץ: filePath כבר נפתר בתוך תיקיית המסד (או null).
      final file = record.book.filePath;
      if (file == null || !await File(file).exists()) return null;
      return await readFileBackedBookText(
        File(file),
        record.book.fileType,
        title,
      );
    } catch (e) {
      debugPrint('⚠️ Error reading attached book text: $e');
      return null;
    }
  }

  Future<List<TocEntry>?> _readAttachedBookToc(
    String title,
    int categoryId,
    AttachedBookSource source,
  ) async {
    try {
      final record = await BookDatabaseResolver.resolveBook(
        title: title,
        categoryId: categoryId,
        preferSource: source,
      );
      if (record == null || record.source != source) return null;
      return await _loadTocFromUserBooksRepo(
        record.repository,
        record.book.id,
      );
    } catch (e) {
      debugPrint('⚠️ Error reading attached book TOC: $e');
      return null;
    }
  }

  /// קורא את תוכן הספר משורות ה-`line` של `user_books.db` ומחזיר טקסט מאוחד.
  Future<String?> _readBookTextFromUserBooksDb(
    SeforimRepository repo,
    int bookId,
    int totalLines,
  ) async {
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
    BookSource preferSource = BookSource.official,
  }) async {
    final source = _resolveSource(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferSource: preferSource,
    );
    if (source is AttachedBookSource) {
      return _readAttachedBookToc(title, categoryId, source);
    }
    if (source.isUser) {
      try {
        final repo = await UserBooksDatabaseHolder.instance.repository;
        final book = await repo.getBookByTitleCategoryAndFileType(
          title,
          categoryId,
          fileType,
        );
        if (book == null) return null;
        // פורמט שדורש המרה: ה-TOC נגזר מהתוכן המומר (במטמון) ולא משורות ה-DB —
        // רשומות ה-DB נבנות בסריקה ומתיישנות כשגרסת הממיר עולה (אינדקסי
        // השורות זזים ותוכן העניינים המוטמע לא היה נלקח בחשבון).
        if (book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          final format = documentFormatOf(
            fileType: book.fileType,
            path: file.path,
          );
          if (format != null &&
              format.requiresConversion &&
              await file.exists()) {
            final content = await convertDocumentForIndex(file, title, format);
            if (content.isNotEmpty) {
              final toc = await Isolate.run(
                () => TocParser.parseEntriesFromContent(content),
              );
              if (toc.isNotEmpty) return toc;
            }
          }
        }
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
      preferSource,
    );
  }

  /// טוען TOC של ספר ממסד שאינו הרשמי (`user_books.db` או מסד מצורף) ומחזיר
  /// עץ TocEntry של מודל ה-app.
  Future<List<TocEntry>?> _loadTocFromUserBooksRepo(
    SeforimRepository repo,
    int bookId,
  ) async {
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
    if (_userBooksCachedKeys.isEmpty && _attachedCachedKeys.isEmpty) {
      return base;
    }
    return {
      ...base,
      ..._userBooksCachedKeys.map((key) => key.toStorageKey()),
      ..._attachedCachedKeys.map((key) => key.toStorageKey()),
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
      // Only base fields are needed; loading every relation again doubles the
      // catalog cost.
      final (:books, :categories) = await _bookCatalog(repository);

      _cachedKeys.clear();
      _categoriesById
        ..clear()
        ..addEntries(
          categories.map((category) => MapEntry(category.id, category)),
        );

      for (final book in books) {
        if (!shouldIncludeBookByPath(
          book.filePath,
          hasTalmudBavliDirectory: hasTalmudBavliDirectory,
          talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
        )) {
          continue;
        }

        _cachedKeys.add(
          BookCompositeKey.create(
            title: book.title,
            categoryId: book.categoryId,
            fileType: book.fileType,
          ),
        );

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

  /// כל ספרי seforim.db וקטגוריותיו: על ה-UI isolate זו חסימה של כ-90ms,
  /// ולכן הם נקראים ב-worker.
  Future<({List<db_models.Book> books, List<db_models.Category> categories})>
  _bookCatalog(SeforimRepository repository) async {
    final dbPath = _sqliteProvider.dbPath;
    if (dbPath.isNotEmpty) {
      try {
        return await DbReadWorker.request('bookCatalog', {'dbPath': dbPath})
            as ({
              List<db_models.Book> books,
              List<db_models.Category> categories,
            });
      } on DbReadWorkerUnavailable {
        // נופלים לשאילתה הישירה, כמו שאר הקריאות כשה-worker אינו זמין.
      }
    }
    return (
      books: await repository.getAllBooksLean(),
      categories: await repository.getAllCategories(),
    );
  }

  /// Clears the cached titles (call when database changes)
  void clearCache() {
    Link.clearContentCache();
    BookNotesRepository.instance.clear();
    DivineNamesRepository.instance.clear();
    _cachedKeys.clear();
    _categoryIdToPath.clear();
    _categoriesById.clear();
    _userBooksCachedKeys.clear();
    _userBooksCategoryIds.clear();
    _attachedCachedKeys.clear();
    _attachedCategoryPaths.clear();
    _titlesCached = false;
    _bundledTalmudBavliPathCache = null;
    _bundledTalmudBavliExistsCache = null;
    _selectableVersionKeysFutures.clear();
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

  /// Gets the underlying SQLite provider for advanced operations
  SqliteDataProvider get sqliteProvider => _sqliteProvider;

  /// Private helper for database operations to reduce boilerplate
  /// [requires] — היכולת שבלעדיה המסד אינו מכיל את המידע ומוחזר [defaultValue].
  Future<T> _dbOperation<T>(
    Future<T> Function(sqlite3.Database db) operation,
    T defaultValue,
    String errorContext, {
    bool Function(DbCapabilities capabilities)? requires,
    BookSource source = BookSource.official,
  }) async {
    try {
      final repository = source is AttachedBookSource
          ? await AttachedLibraryRegistry.instance.repositoryFor(source.slug)
          : _sqliteProvider.isInitialized
          ? _sqliteProvider.repository
          : null;
      if (repository == null) return defaultValue;
      final database = repository.database;
      if (requires != null && !requires(await database.capabilities)) {
        return defaultValue;
      }
      final db = await database.database;
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

    final catalogRows =
        await _officialCatalogInIsolate(_sqliteProvider.dbPath) ??
        _readCatalogRows(
          await repository.database.database,
          await repository.database.capabilities,
        );
    final allDbBooks = catalogRows.books;
    var allCatRows = catalogRows.categories;
    final authorsByBookId = catalogRows.authors;
    // מסד בלי קטגוריות: כל ספריו (categoryId = 0) תחת שורש יחיד.
    if (allCatRows.isEmpty && allDbBooks.isNotEmpty) {
      allCatRows = const [
        {'id': 0, 'parentId': null, 'title': kUncategorizedCategoryTitle},
      ];
    }

    debugPrint(
      '⏱️ Transaction (books+categories): ${DateTime.now().difference(tQuery).inMilliseconds}ms (${allDbBooks.length} books, ${allCatRows.length} categories)',
    );

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
      '⏱️ Category tree build: ${DateTime.now().difference(tTree).inMilliseconds}ms',
    );

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
    await _appendAttachedLibraries(library, metadata);
    _attachCatalogBookVersions(library);

    // NOTE: Sorting is now done during build (like Kotlin), no need for post-sort

    // Mark titles as cached
    _titlesCached = true;

    debugPrint(
      '💾 Database catalog built with $totalCategories categories and ${allDbBooks.length} books from DB',
    );

    // NOTE: Library is now built ONLY from the database.
    // Files that are not in the DB will not appear in the library browser.
    // This is intentional - all book/file information should be in the DB.

    return library;
  }

  /// קוראת outline ב-isolate הראשי, שבו PDFium זמין.
  Future<List<TocEntry>> _parsePdfOutline(File file) async {
    PdfDocument? document;
    try {
      // progressive: בלעדיו pdfium מפענח כל עמוד לפני ה-outline (שניות בסריקה).
      document = await PdfDocument.openFile(
        file.path,
        useProgressiveLoading: true,
      );
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
    } finally {
      // סגירת המסמך משחררת את ה-pdfrx worker היחיד (אחרת נשאר פתוח עד GC).
      await document?.dispose();
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
      description: dbCategory.heDesc ?? '',
      shortDescription: dbCategory.heShortDesc ?? '',
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
  ) => UserBooksDatabaseHolder.instance.trackRead(() async {
    try {
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      if (!await File(dbPath).exists()) {
        return;
      }

      final repo = await UserBooksDatabaseHolder.instance.repository;

      // קריאת הנתונים מ-user_books.db מתבצעת *לפני* ניקוי הקאשים. אם
      // הקריאה נכשלת (למשל "database is locked" בזמן כתיבה מקבילית),
      // יוצאים דרך ה-catch בלי לגעת בקאשים או ב-library — והמצב הקודם
      // (ספרי המשתמש שכבר נטענו) נשמר עד הניסיון הבא, במקום להיעלם.
      _UserBooksCatalogRows rows;
      try {
        rows = await _readUserBooksCatalogInIsolate(
          repo.database.path,
          Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '',
        );
      } catch (e) {
        debugPrint('⚠️ readUserBooksCatalog failed, reading directly: $e');
        final db = await repo.database.database;
        final direct = _selectUserBooksCatalog(
          db,
          DbCapabilities.forDatabase(repo.database.path, db),
        );
        rows = (
          books: await resolveMovedFilePathsInBackground(direct.books),
          categories: direct.categories,
          authors: direct.authors,
          versions: direct.versions,
        );
      }
      final userBooks = rows.books;
      final userCats = rows.categories;
      final userAuthors = rows.authors;
      final userVersions = [
        for (final row in rows.versions) ?_userBookVersionFromRow(row),
      ];

      // הקריאה הצליחה — עכשיו בטוח לנקות ולבנות מחדש. מכאן והלאה הבנייה
      // פועלת על נתונים שכבר בזיכרון ואינה ניגשת ל-DB, כך שאם תיכשל בכל
      // זאת, ה-library והקאשים יישארו חלקיים אך מסונכרנים זה עם זה.
      _userBooksCategoryIds.clear();
      _userBooksCachedKeys.clear();
      _userBooksById.clear();
      _userBookVersions = userVersions;
      _catalogVersionPrimaries.clear();
      // גרסה של ספר רשמי/מצורף מוסתרת רק אחרי שהראשי נמצא בקטלוג.
      _hiddenUserVersionBookIds
        ..clear()
        ..addAll([
          for (final v in userVersions)
            if (!v.hasCatalogPrimary && v.versionBookId != v.primaryBookId)
              v.versionBookId,
        ]);

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
      final allUserCategories = userCats
          .map((row) => db_models.Category.fromJson(row))
          .toList();
      final categoriesByParent = <int?, List<db_models.Category>>{};
      for (final cat in allUserCategories) {
        categoriesByParent.putIfAbsent(cat.parentId, () => []).add(cat);
      }

      // חיפוש קטגוריית "ספרים אישיים" ברמת השורש של user_books.db.
      final rootCats = categoriesByParent[null] ?? [];
      final personalRootInUserDb = rootCats
          .where((c) => c.title == 'ספרים אישיים')
          .firstOrNull;
      if (personalRootInUserDb == null) {
        return;
      }

      // ID טבעי (לא offset) של "ספרים אישיים" מ-user_books.db.
      final personalRootId = personalRootInUserDb.id;
      _userBooksCategoryIds.add(personalRootId);

      // הגדרה: האם למזג תיקיות מותאמות אישית ישירות לעץ הראשי לפי שם
      // (במקום להציג אותן תחת קטגוריית "ספרים אישיים" נפרדת). זו ברירת
      // המחדל — תיקייה בודדת יכולה לדרוס אותה.
      final mergeDefault =
          Settings.getValue<bool>(
            SettingsRepository.keyMergeUserBooksIntoLibrary,
            defaultValue: false,
          ) ??
          false;
      final configuredFolders = CustomFoldersManager.loadFolders(
        Settings.getValue<String>(SettingsRepository.keyCustomFolders),
      );
      final mergeOverridesByFolderName = _mergeOverridesByFolderName(
        configuredFolders,
        mergeDefault,
      );
      final hiddenFolderNames = CustomFoldersManager.hiddenFolderNames(
        configuredFolders,
      );

      // ילדים ישירים של "ספרים אישיים" — אלו התיקיות שהמשתמש בחר בדיאלוג
      // הוספת תיקייה (למשל "מסמכים", "הורדות"). השם שלהן כשלעצמו אינו
      // מהווה קטגוריה מבחינת המשתמש — הוא רק מצביע על מיקום בדיסק.
      final pickedFolders = [
        ...?categoriesByParent[personalRootInUserDb.id],
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      // ספרים שיושבים ישירות תחת "ספרים אישיים" (בד"כ אין כאלה — תיקיות
      // הן רמה אחת מתחת — אבל מטפלים ליתר ביטחון).
      final directBooksUnderRoot =
          (booksByCategory[personalRootInUserDb.id] ?? [])..sort((a, b) {
            final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
            final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
            return orderA.compareTo(orderB);
          });

      // "ספרים אישיים" נוצרת רק אם יש לה תוכן: תיקייה שאינה ממוזגת, או
      // ספרים בודדים שאין להם תת-תיקייה להתמזג אליה.
      Category? personalCategoryInLibrary;
      Category ensurePersonalCategory() {
        return personalCategoryInLibrary ??=
            library.subCategories
                .where((c) => c.title == 'ספרים אישיים')
                .firstOrNull ??
            () {
              final created = Category(
                title: 'ספרים אישיים',
                description: metadata['ספרים אישיים']?['heDesc'] ?? '',
                shortDescription:
                    metadata['ספרים אישיים']?['heShortDesc'] ?? '',
                order: personalRootInUserDb.orderIndex,
                subCategories: [],
                books: [],
                parent: library,
              );
              library.subCategories.add(created);
              return created;
            }();
      }

      // ספר בודד אינו קטגוריה שאפשר למזג לפי שם. גם במיזוג מלא הוא מקבל
      // בית תחת "ספרים אישיים" ולא מתפזר בשורש הספרייה.
      for (final dbBook in directBooksUnderRoot) {
        final directBooksParent = ensurePersonalCategory();
        final book = _convertMinimalBookMapToBook(
          dbBook,
          directBooksParent,
          metadata,
          authorFromDatabase: userAuthors[dbBook['id'] as int? ?? 0],
          source: BookSource.user,
          idOverride: dbBook['id'] as int? ?? 0,
          categoryIdOverride: personalRootId,
          remapMovedPath: false,
        );
        if (book == null) continue;
        _registerUserBook(book, directBooksParent);
        _userBooksCachedKeys.add(
          BookCompositeKey.create(
            title: book.title,
            categoryId: personalRootId,
            fileType: book.fileType,
            source: BookSource.user,
          ),
        );
      }

      for (final pickedFolder in pickedFolders) {
        if (hiddenFolderNames.contains(pickedFolder.title)) continue;
        final merged =
            mergeOverridesByFolderName[pickedFolder.title] ?? mergeDefault;

        if (!merged) {
          // התיקייה הנבחרת מוצגת כקטגוריה תחת "ספרים אישיים", עם שמה.
          final personal = ensurePersonalCategory();
          final existing = personal.subCategories
              .where((c) => c.title == pickedFolder.title)
              .firstOrNull;
          if (existing == null) {
            personal.subCategories.add(
              _buildUserBooksCatalogCategoryRecursive(
                pickedFolder,
                booksByCategory,
                categoriesByParent,
                userAuthors,
                personal,
                metadata,
              ),
            );
          } else {
            existing.parent = personal;
            _appendUserBooksContentToCategoryRecursive(
              existing,
              pickedFolder,
              booksByCategory,
              categoriesByParent,
              userAuthors,
              metadata,
            );
          }
          continue;
        }

        // במצב מיזוג: גם "ספרים אישיים" וגם שם התיקייה שהמשתמש בחר
        // (pickedFolder) לא יופיעו בעץ. הבנייה מתחילה מתת-התיקיות של
        // התיקייה הנבחרת, וקטגוריות מתמזגות בשורש הספרייה לפי שם.
        // הקטגוריה עצמה נדלגת ולכן ה-id שלה נרשם כאן ולא ע"י הבנייה
        // הרקורסיבית.
        _userBooksCategoryIds.add(pickedFolder.id);

        // ספרים בתוך התיקייה הנבחרת עצמה — אין להם תת-תיקייה להתמזג
        // אליה, ולכן הם מצטרפים ל"ספרים אישיים".
        final booksInPickedFolder = (booksByCategory[pickedFolder.id] ?? [])
          ..sort((a, b) {
            final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
            final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
            return orderA.compareTo(orderB);
          });
        for (final dbBook in booksInPickedFolder) {
          final looseBooksParent = ensurePersonalCategory();
          final book = _convertMinimalBookMapToBook(
            dbBook,
            looseBooksParent,
            metadata,
            authorFromDatabase: userAuthors[dbBook['id'] as int? ?? 0],
            source: BookSource.user,
            idOverride: dbBook['id'] as int? ?? 0,
            categoryIdOverride: pickedFolder.id,
            remapMovedPath: false,
          );
          if (book == null) continue;
          looseBooksParent.books.add(book);
          _userBooksCachedKeys.add(
            BookCompositeKey.create(
              title: book.title,
              categoryId: pickedFolder.id,
              fileType: book.fileType,
              source: BookSource.user,
            ),
          );
        }

        // תת-תיקיות של התיקייה הנבחרת — מתמזגות בשורש הספרייה לפי שם.
        final grandchildren = [
          ...?categoriesByParent[pickedFolder.id],
        ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        for (final grandchild in grandchildren) {
          final existing = _findMergeTarget(
            library.subCategories,
            grandchild.title,
          );
          if (existing == null) {
            library.subCategories.add(
              _buildUserBooksCatalogCategoryRecursive(
                grandchild,
                booksByCategory,
                categoriesByParent,
                userAuthors,
                library,
                metadata,
              ),
            );
          } else {
            existing.parent = library;
            _appendUserBooksContentToCategoryRecursive(
              existing,
              grandchild,
              booksByCategory,
              categoriesByParent,
              userAuthors,
              metadata,
            );
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ Error appending user books to library: $e');
      // הספרייה תיטען בלי הספרים האישיים — דווח כדי שלא נחמיץ DB
      // שבור או הרשאות חסרות.
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
    }
  });

  /// מצרף לעץ את ספרי המסדים המצורפים הגלויים, לפי סדר העדיפות: תחת
  /// `ספרים אישיים/<שם המסד>`, או ממוזגים לקטגוריות הספרייה לפי שם. מסד שאינו
  /// נגיש מדולג; כשל במסד אחד אינו פוגע באחרים.
  Future<void> _appendAttachedLibraries(
    Library library,
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    _attachedCachedKeys.clear();
    _attachedCategoryPaths.clear();
    final attachedLibraries = [
      for (final attached in AttachedLibraryRegistry.instance.visibleLibraries)
        if (attached.source != null) attached,
    ];
    // כל המסדים נקראים במקביל, וכל אחד מוגבל בזמן בנפרד.
    final catalogs = await Future.wait(
      attachedLibraries.map(_readAttachedCatalog),
    );
    for (var i = 0; i < attachedLibraries.length; i++) {
      final attached = attachedLibraries[i];
      final rows = catalogs[i];
      if (rows == null) continue;
      try {
        _addAttachedLibraryToCatalog(
          library,
          _AttachedCatalogBuild(
            library: attached,
            source: attached.source!,
            rows: rows.books,
            categoryRows: rows.categories,
            authors: rows.authors,
            metadata: metadata,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('⚠️ Error appending attached library ${attached.slug}: $e');
        unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      }
    }
  }

  /// הקטלוג של [attached], או null כשאינו זמין כרגע. קובץ שנעלם, וקריאה
  /// שלא הסתיימה ב-[attachedCatalogTimeout], מסמנים את המסד לא-זמין.
  Future<AttachedCatalogRows?> _readAttachedCatalog(
    AttachedLibrary attached,
  ) async {
    final path = attached.path;
    final attachedRepository = AttachedLibrariesRepository.instance;
    final pending = _pendingAttachedCatalogs.putIfAbsent(path, () {
      attachedRepository.setLoading(path, loading: true);
      return _PendingAttachedCatalog(
        attachedCatalogReader((
          path: path,
          untrusted: true,
          immutable: attached.immutable,
        )),
      );
    });
    try {
      final rows = pending.done
          ? await pending.future
          : await pending.future.timeout(
              pending.timedOut ? Duration.zero : attachedCatalogTimeout,
            );
      _pendingAttachedCatalogs.remove(path);
      attachedRepository.setLoading(path, loading: false);
      if (rows.missing) {
        unawaited(_reportAttachedReachability(path, reachable: false));
        return null;
      }
      return rows;
    } on TimeoutException {
      if (!pending.timedOut) {
        pending.timedOut = true;
        unawaited(_reportAttachedReachability(path, reachable: false));
        unawaited(
          pending.future
              .then(
                (rows) async {
                  if (!rows.missing) {
                    await _reportAttachedReachability(path, reachable: true);
                  }
                },
                onError: (Object _) {},
              )
              .whenComplete(
                () => attachedRepository.setLoading(path, loading: false),
              ),
        );
      }
      return null;
    } catch (e, stackTrace) {
      _pendingAttachedCatalogs.remove(path);
      attachedRepository.setLoading(path, loading: false);
      debugPrint('⚠️ Error reading attached library ${attached.slug}: $e');
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      return null;
    }
  }

  Future<void> _reportAttachedReachability(
    String path, {
    required bool reachable,
  }) => AttachedLibrariesRepository.instance
      .setReachable(path, reachable: reachable)
      .catchError((Object e) {
        debugPrint('⚠️ Could not update attached library $path: $e');
      });

  void _addAttachedLibraryToCatalog(
    Library library,
    _AttachedCatalogBuild build,
  ) {
    final categories = [
      for (final row in build.categoryRows) db_models.Category.fromJson(row),
    ];
    final knownIds = {for (final category in categories) category.id};
    for (final category in categories) {
      // הורה שאינו במסד — הקטגוריה נחשבת שורש, במקום להיעלם מהעץ.
      final parentId = knownIds.contains(category.parentId)
          ? category.parentId
          : null;
      build.categoriesByParent.putIfAbsent(parentId, () => []).add(category);
    }
    final looseBooks = <Map<String, dynamic>>[];
    for (final row in build.rows) {
      if (!_isAttachedDisplayableRow(row)) continue;
      final categoryId = row['categoryId'] as int? ?? 0;
      if (knownIds.contains(categoryId)) {
        build.booksByCategory.putIfAbsent(categoryId, () => []).add(row);
      } else {
        looseBooks.add(row);
      }
    }

    Category? libraryRoot;
    Category ensureLibraryRoot() {
      final existing = libraryRoot;
      if (existing != null) return existing;
      final personal = _personalRootFor(library, build.metadata);
      final created = Category(
        title: build.library.displayName,
        description: '',
        shortDescription: '',
        order: _kAttachedRootOrder + build.library.priority,
        subCategories: [],
        books: [],
        parent: personal,
      );
      personal.subCategories.add(created);
      return libraryRoot = created;
    }

    final roots = [...?build.categoriesByParent[null]]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final merge =
        build.library.placement == AttachedLibraryPlacement.mergeIntoLibrary;
    for (final root in roots) {
      if (!merge) {
        final parent = ensureLibraryRoot();
        parent.subCategories.add(_buildAttachedCategory(root, parent, build));
        continue;
      }
      final existing = _findMergeTarget(library.subCategories, root.title);
      if (existing == null) {
        library.subCategories.add(_buildAttachedCategory(root, library, build));
      } else {
        _appendAttachedContent(existing, root, build);
      }
    }

    // ספרים בלי קטגוריה (מסד בלי טבלת קטגוריות) יושבים תחת שם המסד.
    if (looseBooks.isNotEmpty) {
      _addAttachedBooks(
        ensureLibraryRoot(),
        0,
        _sortedByOrder(looseBooks),
        build,
      );
    }
  }

  Category _buildAttachedCategory(
    db_models.Category dbCategory,
    Category parent,
    _AttachedCatalogBuild build,
  ) {
    final category = Category(
      title: dbCategory.title,
      description: dbCategory.heDesc ?? '',
      shortDescription: dbCategory.heShortDesc ?? '',
      order: build.order(dbCategory.orderIndex),
      subCategories: [],
      books: [],
      parent: parent,
    );
    _appendAttachedContent(category, dbCategory, build);
    return category;
  }

  void _appendAttachedContent(
    Category category,
    db_models.Category dbCategory,
    _AttachedCatalogBuild build,
  ) {
    _addAttachedBooks(
      category,
      dbCategory.id,
      _sortedByOrder([...?build.booksByCategory[dbCategory.id]]),
      build,
    );
    final children = [...?build.categoriesByParent[dbCategory.id]]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    for (final child in children) {
      final existing = _findMergeTarget(category.subCategories, child.title);
      if (existing == null) {
        category.subCategories.add(
          _buildAttachedCategory(child, category, build),
        );
      } else {
        _appendAttachedContent(existing, child, build);
      }
    }
  }

  void _addAttachedBooks(
    Category category,
    int categoryId,
    List<Map<String, dynamic>> rows,
    _AttachedCatalogBuild build,
  ) {
    final slug = build.source.slug;
    // כל הספרים כאן באותה קטגוריה — הנתיב מחושב פעם אחת ולא לכל ספר.
    final categoryPathInfo = _categoryPathInfo(category);
    for (final row in rows) {
      final id = row['id'] as int? ?? 0;
      final book = _convertMinimalBookMapToBook(
        // נתיב הקובץ נפתר מראש יחסית לתיקיית המסד; נתיב אחר אינו נפתח.
        {
          ...row,
          'filePath': row['resolvedFilePath'],
          'orderIndex': build.order(_orderOf(row)),
        },
        category,
        build.metadata,
        authorFromDatabase: build.authors[id],
        source: build.source,
        idOverride: id,
        categoryIdOverride: categoryId,
        remapMovedPath: false,
        categoryPathInfo: categoryPathInfo,
      );
      if (book == null) continue;
      category.books.add(book);
      _attachedCachedKeys.add(
        BookCompositeKey.create(
          title: book.title,
          categoryId: categoryId,
          fileType: book.fileType,
          source: build.source,
        ),
      );
      final path = book.categoryPath;
      if (path != null && path.isNotEmpty) {
        _attachedCategoryPaths.putIfAbsent(slug, () => {})[categoryId] = path;
      }
    }
  }

  /// ספר שתוכנו בשורות ה-DB, או ספר מבוסס-קובץ (PDF, Word…) שהקובץ שלו נמצא
  /// בתיקיית המסד. קובץ שנתיבו אסור או חסר — הספר אינו מוצג.
  static bool _isAttachedDisplayableRow(Map<String, dynamic> row) {
    final fileType = (row['fileType'] as String?)?.trim().toLowerCase() ?? '';
    if (fileType.isEmpty || fileType == 'txt') return true;
    return row['resolvedFilePath'] != null &&
        documentFormatOf(fileType: fileType) != null;
  }

  static num? _orderOf(Map<String, dynamic> row) =>
      row['orderIndex'] is num ? row['orderIndex'] as num : null;

  static List<Map<String, dynamic>> _sortedByOrder(
    List<Map<String, dynamic>> rows,
  ) => rows
    ..sort((a, b) {
      final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
      final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
      return orderA.compareTo(orderB);
    });

  /// שורש "ספרים אישיים" בעץ — קיים (מהספרים האישיים) או חדש בסוף הספרייה.
  Category _personalRootFor(
    Library library,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    final existing = library.subCategories
        .where((c) => c.title == _kPersonalRootTitle)
        .firstOrNull;
    if (existing != null) return existing;
    final created = Category(
      title: _kPersonalRootTitle,
      description: metadata[_kPersonalRootTitle]?['heDesc'] ?? '',
      shortDescription: metadata[_kPersonalRootTitle]?['heShortDesc'] ?? '',
      order: 999,
      subCategories: [],
      books: [],
      parent: library,
    );
    library.subCategories.add(created);
    return created;
  }

  /// קטגוריית היעד למיזוג תיקייה אישית, בהשוואה שמתעלמת מגרשיים וגרש:
  /// שם תיקייה ב-Windows לא יכול להכיל `"`, ולכן "תנך" חייב להתאים ל"תנ״ך".
  Category? _findMergeTarget(List<Category> candidates, String folderTitle) {
    final key = _mergeTitleKey(folderTitle);
    return candidates.where((c) => _mergeTitleKey(c.title) == key).firstOrNull;
  }

  static String _mergeTitleKey(String title) =>
      title.replaceAll(RegExp('''['"״׳’”“`]'''), '').trim();

  /// מצב המיזוג לפי קטגוריית-השורש. תיקיות בעלות אותו שם חולקות קטגוריה,
  /// ולכן כשמצביהן האפקטיביים חלוקים חוזרים לברירת המחדל הגלובלית.
  Map<String, bool> _mergeOverridesByFolderName(
    List<CustomFolder> folders,
    bool mergeDefault,
  ) {
    final result = <String, bool>{};
    final conflicting = <String>{};
    for (final folder in folders) {
      final value = folder.resolveMergeIntoLibrary(mergeDefault);
      if (result.containsKey(folder.name) && result[folder.name] != value) {
        conflicting.add(folder.name);
      }
      result[folder.name] = value;
    }
    for (final name in conflicting) {
      result.remove(name);
    }
    return result;
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
    // `_userBooksCategoryIds` ו-`source: BookSource.user` במפתח.
    final nativeCategoryId = dbCategory.id;
    _userBooksCategoryIds.add(nativeCategoryId);

    final dbBooks =
        [
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
        source: BookSource.user,
        idOverride: dbBook['id'] as int? ?? 0,
        categoryIdOverride: nativeCategoryId,
        remapMovedPath: false,
      );
      if (book == null) continue;
      _registerUserBook(book, category);
      _userBooksCachedKeys.add(
        BookCompositeKey.create(
          title: book.title,
          categoryId: nativeCategoryId,
          fileType: book.fileType,
          source: BookSource.user,
        ),
      );
    }

    final children = [
      ...?categoriesByParent[dbCategory.id],
    ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    for (final child in children) {
      final existingSubCategory = _findMergeTarget(
        category.subCategories,
        child.title,
      );
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
  /// fileType, filePath, heShortDesc, heDesc, author.
  /// Falls back to metadata when the minimal row does not include a field.
  Book? _convertMinimalBookMapToBook(
    Map<String, dynamic> bookMap,
    Category category,
    Map<String, Map<String, dynamic>> metadata, {
    String? authorFromDatabase,
    BookSource source = BookSource.official,
    int? idOverride,
    int? categoryIdOverride,
    bool remapMovedPath = true,
    ({String categoryPath, String topics})? categoryPathInfo,
  }) {
    final title = bookMap['title'] as String;
    final id = idOverride ?? (bookMap['id'] as int? ?? 0);
    final filePath = bookMap['filePath'] as String?;
    final fileType = bookMap['fileType'] as String?;
    final heShortDesc = bookMap['heShortDesc'] as String?;
    final heDesc = bookMap['heDesc'] as String?;
    final orderDouble = (bookMap['orderIndex'] as num?)?.toDouble() ?? 999.0;
    final order = orderDouble.toInt();
    final categoryId =
        categoryIdOverride ?? (bookMap['categoryId'] as int? ?? 0);

    final bookMeta = metadata[title];
    final (:categoryPath, :topics) =
        categoryPathInfo ?? _categoryPathInfo(category);

    final author = authorFromDatabase ?? (bookMeta?['author'] as String?);
    final pubDate = bookMeta?['pubDate'] as String?;
    final pubPlace = bookMeta?['pubPlace'] as String?;
    final metaHeShortDesc = heShortDesc ?? bookMeta?['heShortDesc'] as String?;
    final metaHeDesc = heDesc ?? bookMeta?['heDesc'] as String?;

    final normalizedFileType = (fileType ?? '').toLowerCase();

    // External catalog books (fileType='link') are no longer stored in seforim.db.
    // They are served from a separate database via ExternalCatalogRepository.
    if (normalizedFileType == 'link' || normalizedFileType == 'url') {
      return null;
    }

    final resolvedFilePath = filePath == null || !remapMovedPath
        ? filePath
        : resolveMovedFileBookPath(filePath);

    return buildBookForFileType(
      fileType: normalizedFileType,
      id: id,
      title: title,
      category: category,
      path: resolvedFilePath ?? title,
      filePath: resolvedFilePath,
      author: author,
      heShortDesc: metaHeShortDesc,
      heDesc: metaHeDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
      source: source,
    );
  }

  static ({String categoryPath, String topics}) _categoryPathInfo(
    Category? category,
  ) {
    final List<String> path = [];
    final Set<Category> visited = {};
    while (category != null && !visited.contains(category)) {
      if (category.title == 'ספריית אוצריא') break;
      visited.add(category);
      path.insert(0, category.title);
      category = category.parent;
    }
    final categoryPath = path.join(', ');

    // Use metadata for topics (no junction table data available)
    String topics = '';
    if (categoryPath.isNotEmpty) {
      topics = categoryPath
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(', ');
    }
    return (categoryPath: categoryPath, topics: topics);
  }

  /// [resolveMovedFileBookPath] לכל שורה, ב-isolate: בדיקת קובץ סינכרונית לכל
  /// ספר אישי חסמה את ה-UI בבניית העץ (#3380). בכשל — השורות כמות שהן.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> resolveMovedFilePathsInBackground(
    List<Map<String, dynamic>> rows,
  ) async {
    final paths = [
      for (final row in rows)
        if (row['filePath'] case final String path) path,
    ];
    if (paths.isEmpty) return rows;
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
    final List<String> resolved;
    try {
      resolved = await Isolate.run(
        () => [
          for (final path in paths)
            resolveMovedFileBookPath(path, activeLibraryPath: libraryPath),
        ],
        debugName: 'resolveMovedFilePaths',
      );
    } catch (e) {
      debugPrint('⚠️ resolveMovedFilePaths failed: $e');
      return rows;
    }
    var next = 0;
    return [
      for (final row in rows)
        if (row['filePath'] is String)
          {...row, 'filePath': resolved[next++]}
        else
          row,
    ];
  }

  @visibleForTesting
  String resolveFileBookPathForTesting(String filePath) =>
      resolveMovedFileBookPath(filePath);

  /// Counts the total number of categories in the tree.
  int _countCategories(Category category) {
    return 1 +
        category.subCategories.fold(
          0,
          (sum, sub) => sum + _countCategories(sub),
        );
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType, {
    BookSource source = BookSource.official,
  }) async {
    // ראה הערה ב-_runBookLoadInIsolate: ה-Isolate.run עצמו
    // חייב להיווצר בתוך פונקציה ברמת קובץ, אחרת `this` עלול להיתפס.
    return _readTarget(source, [], 'getAllLinksForBook "$title"', (
      target,
    ) async {
      final result = await _runBookLinksInIsolate(
        target: target,
        title: title,
        categoryId: categoryId,
        fileType: fileType,
      );
      final links = [for (final row in result) _linkFromRow(row, source)];
      debugPrint('💾 Found ${links.length} links for book "$title"');
      return links;
    });
  }

  Future<List<Link>> getLinksForBookRange(
    String title,
    int categoryId,
    String fileType, {
    required int startLineIndex,
    required int endLineIndex,
    Iterable<String>? targetBookTitles,
    BookSource source = BookSource.official,
  }) async {
    final normalizedTargetBookTitles =
        targetBookTitles
            ?.map((targetTitle) => targetTitle.trim())
            .where((targetTitle) => targetTitle.isNotEmpty)
            .toSet()
            .toList()
          ?..sort();
    // כשל או מסד סגור זורקים ולא מחזירים ריק: הקורא שומר תוצאה ריקה כחלון
    // "מכוסה" ולא ינסה שוב, והמפרשים נעלמים עד גלילה רחוקה.
    final target = _isolateTargetFor(source);
    if (target == null) {
      throw StateError('המסד של "$title" אינו פתוח — הקישורים לא נטענו');
    }

    // ראה הערה ב-_runBookLoadInIsolate.
    final result = await _loadOnReadWorker(
      target,
      'linksRange',
      {
        'title': title,
        'categoryId': categoryId,
        'fileType': fileType,
        'startLineIndex': startLineIndex,
        'endLineIndex': endLineIndex,
        'targetBookTitles': normalizedTargetBookTitles,
      },
      () => _runBookLinksInRangeInIsolate(
        target: target,
        official: source is OfficialBookSource,
        title: title,
        categoryId: categoryId,
        fileType: fileType,
        startLineIndex: startLineIndex,
        endLineIndex: endLineIndex,
        targetBookTitles: normalizedTargetBookTitles,
      ),
    );

    return [for (final row in result) _linkFromRow(row, source)];
  }

  /// סיכום קישורי הספר לפי (ספר-יעד, סוג חיבור), בתוספת השורה הגבוהה ביותר
  /// שיש עליה קישור (1-based, כמו [Link.index1]; 0 אם אין קישורים).
  /// מיועד לבניית רשימת המפרשים של ספר בלי לטעון את כל הקישורים לזיכרון.
  /// מחזיר null אם המסד לא זמין או שהשאילתה נכשלה.
  Future<({List<LinkTargetSummary> targets, int maxSourceLine})?>
  getBookLinkTargetsSummary(
    String title,
    int categoryId, {
    BookSource source = BookSource.official,
  }) async {
    // ראה הערה ב-_runBookLoadInIsolate.
    return _readTarget(source, null, 'getBookLinkTargetsSummary "$title"', (
      target,
    ) async {
      final result = await _runBookLinkTargetsSummaryInIsolate(
        target: target,
        official: source is OfficialBookSource,
        title: title,
        categoryId: categoryId,
      );
      final external = await ExternalLinkRepository.instance.targetsSummary(
        title: title,
        categoryId: categoryId,
        source: source,
      );
      final maxSourceLine = (result.maxSourceLineIndex ?? -1) + 1;
      return (
        targets: [
          for (final row in result.rows)
            LinkTargetSummary(
              targetTitle: row['targetBookTitle'] as String,
              connectionType:
                  row['connectionTypeName'] as String? ?? 'reference',
              linkCount: (row['linkCount'] as int?) ?? 0,
            ),
          ...external.targets,
        ],
        maxSourceLine: external.maxSourceLine > maxSourceLine
            ? external.maxSourceLine
            : maxSourceLine,
      );
    });
  }

  /// טוען טווח שורות תוכן ב-isolate נפרד (כמו [getLinksForBookRange]), כדי
  /// שהשאילתה וה-split לא יחסמו את ה-UI thread בזמן גלילה. כש-[versionTitle]
  /// לא null נטען נוסח המהדורה הזו (version_line) על שלד שורות הספר.
  Future<({int startLine, int endLine, int totalLines, List<String> lines})?>
  getBookTextRange(
    String title,
    int categoryId,
    String fileType, {
    required int startLine,
    required int endLine,
    String? versionTitle,
    BookSource source = BookSource.official,
  }) async {
    // ראה הערה ב-_runBookLoadInIsolate.
    return _readTarget(
      source,
      null,
      'getBookTextRange "$title"',
      (target) => _loadOnReadWorker(
        target,
        'textRange',
        {
          'title': title,
          'categoryId': categoryId,
          'fileType': fileType,
          'startLine': startLine,
          'endLine': endLine,
          'versionTitle': versionTitle,
        },
        () => _runBookTextRangeInIsolate(
          target: target,
          title: title,
          categoryId: categoryId,
          fileType: fileType,
          startLine: startLine,
          endLine: endLine,
          versionTitle: versionTitle,
        ),
      ),
    );
  }

  /// רשימת המהדורות (book_version) של ספר, מהדורות עם טקסט מלא תחילה.
  /// רשימה ריקה כשה-DB ישן או כשאין לספר מידע גרסאות.
  Future<List<BookVersionInfo>> getBookVersions(
    String title,
    int categoryId, {
    BookSource source = BookSource.official,
  }) async {
    return _readTarget(source, const [], 'getBookVersions "$title"', (
      target,
    ) async {
      final rows = await _runBookVersionsInIsolate(
        target: target,
        title: title,
        categoryId: categoryId,
      );
      return rows.map(BookVersionInfo.fromDbRow).toList();
    });
  }

  /// האם להציג לספר תפריט 'גרסאות' — כלומר יש מהדורה לבחירה (2+ גרסאות, או
  /// גרסה יחידה עם טקסט). גרסה יחידה מטא-דאטה בלבד = הנוסח המוצג, ולכן false.
  Future<bool> hasSelectableBookVersions(
    String title,
    int categoryId, {
    BookSource source = BookSource.official,
  }) async {
    final target = _isolateTargetFor(source);
    if (target == null) return false;
    final sourceKey = source.wireKey;
    final keys = await (_selectableVersionKeysFutures[sourceKey] ??=
        _loadSelectableVersionKeys(sourceKey, target));
    return keys.contains('$title\u0000$categoryId');
  }

  Future<Set<String>> _loadSelectableVersionKeys(
    String sourceKey,
    ReadOnlyDbTarget target,
  ) async {
    try {
      final rows = await _runSelectableVersionKeysInIsolate(target: target);
      return rows.map((r) => '${r['title']}\u0000${r['categoryId']}').toSet();
    } catch (e) {
      debugPrint('⚠️ Error loading selectable version keys: $e');
      // אפשר ניסיון חוזר בטעינה הבאה
      _selectableVersionKeysFutures.remove(sourceKey);
      return const <String>{};
    }
  }

  @override
  Future<String> getLinkContent(Link link) async => (await getLinkContentLines(
    link,
  )).map((line) => line.content).join('<br>');

  @override
  Future<List<LinkContentLine>> getLinkContentLines(Link link) async {
    if (link.path2.isEmpty) {
      return [(lineIndex: link.index2 - 1, content: 'שגיאה: נתיב ריק')];
    }
    if (link.index2 <= 0) {
      return [(lineIndex: link.index2 - 1, content: 'שגיאה: אינדקס לא תקין')];
    }

    final normalizedTitle = _bookTitleFromLinkPath(link.path2);
    // כותרת ללא תיקייה עשויה להסתיים בסיומת אמיתית; נסה אותה לפני שם הקובץ.
    final targetTitles = [
      if (!link.path2.contains('/') && link.path2 != normalizedTitle)
        link.path2,
      normalizedTitle,
    ];

    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return [(lineIndex: link.index2 - 1, content: 'שגיאה: מאגר לא מאותחל')];
    }

    for (final title in targetTitles) {
      final fromWorker = await _officialLinkContentOnWorker(link, title);
      if (fromWorker != null) return fromWorker;
    }

    try {
      ResolvedDbBookRecord? resolvedBook;
      findBook:
      for (final candidate
          in await BookDatabaseResolver.loadRepositoryCandidates(
            preferSource: link.targetSource,
          )) {
        for (final title in targetTitles) {
          resolvedBook = await BookDatabaseResolver.resolveBookInCandidates(
            title: title,
            candidates: [candidate],
            categoryId: link.targetCategoryId,
            fileType: link.targetFileType,
          );
          if (resolvedBook != null) break findBook;
        }
      }
      if (resolvedBook == null) {
        return [
          (
            lineIndex: link.index2 - 1,
            content: 'שגיאה: הספר לא נמצא במסד הנתונים',
          ),
        ];
      }

      // ספר file-backed (תיקייה שנוספה בלי "הוסף למסד הנתונים") — אין שורות
      // ב-DB, התוכן נקרא מהקובץ עצמו לפי אותו פיצול שורות של הסורק.
      final dbBook = resolvedBook.book;
      final dbBookFormat = documentFormatOf(
        fileType: dbBook.fileType,
        path: dbBook.filePath,
      );
      if (dbBook.isFileBacked &&
          dbBook.filePath != null &&
          (dbBookFormat?.isTextual ?? false)) {
        final file = File(dbBook.filePath!);
        if (!await file.exists()) {
          return [
            (lineIndex: link.index2 - 1, content: 'שגיאה: הקובץ לא נמצא'),
          ];
        }
        // הווריאנט המלא כבר במטמון הקורא; וריאנט נפרד מכפיל את הטקסט
        // ב-cache.db ומחליף את תמונת המפרש בתג תמונה ריק.
        final text =
            await readFileBackedBookText(file, dbBook.fileType, dbBook.title) ??
            '';
        final lines = text.split('\n');
        final start = link.index2 - 1;
        if (start >= lines.length) {
          return [
            (lineIndex: link.index2 - 1, content: 'שגיאה: אינדקס מחוץ לטווח'),
          ];
        }
        final end0 = ((link.index2End ?? link.index2) - 1).clamp(
          start,
          lines.length - 1,
        );
        return lines
            .sublist(start, end0 + 1)
            .indexed
            .map(
              (entry) =>
                  (lineIndex: start + entry.$1, content: entry.$2.trimRight()),
            )
            .toList(growable: false);
      }

      return await linkSourceLinesFromDb(
        resolvedBook.repository,
        resolvedBook.book.id,
        link.index2,
        link.index2End,
      );
    } catch (e) {
      debugPrint('⚠️ Error in getLinkContent: $e');
      return [(lineIndex: link.index2 - 1, content: 'שגיאה בטעינת תוכן המפרש')];
    }
  }

  /// תוכן קישור לספר ב-seforim.db, מה-[DbReadWorker] במקום על ה-UI isolate.
  /// null — הספר אינו שם או שהוא ספר קבצים: המסלול הישיר ממשיך.
  Future<List<LinkContentLine>?> _officialLinkContentOnWorker(
    Link link,
    String targetTitle,
  ) async {
    final dbPath = _sqliteProvider.dbPath;
    if (!link.targetSource.isOfficial || dbPath.isEmpty) return null;
    try {
      final result =
          await DbReadWorker.batched('linkContent', {
                'dbPath': dbPath,
                'title': targetTitle,
                'categoryId': link.targetCategoryId,
                'index2': link.index2,
                'index2End': link.index2End,
                'includeLines': true,
              })
              as Map;
      return (result['lines'] as List?)?.cast<LinkContentLine>();
    } on DbReadWorkerSuspended {
      return [(lineIndex: link.index2 - 1, content: 'שגיאה: מאגר לא מאותחל')];
    } catch (e) {
      debugPrint('⚠️ getLinkContent worker and fallback failed: $e');
      return [(lineIndex: link.index2 - 1, content: 'שגיאה בטעינת תוכן המפרש')];
    }
  }

  static String _bookTitleFromLinkPath(String value) {
    final name = value.split('/').last;
    final extension = p.extension(name).toLowerCase();
    if (extension == '.txt' || extension == '.text') {
      return name.substring(0, name.length - extension.length);
    }
    return name;
  }

  /// מבני ה-AltToc של [book] מהמסד שלו. ספר ממקור אחר בשם זהה ממוספר אחרת,
  /// ולכן לעולם אינו מקבל את מבניו; כל מבנה נושא את [AltTocStructure.source].
  Future<List<AltTocStructure>> getAlternativeStructuresForBook(
    TextBook book,
  ) async {
    if (book.isUserBook) {
      return _userAltTocOperation(
        (repo) async {
          final bookId = await repo.bookId(
            title: book.title,
            categoryId: book.categoryId,
            filePath: book.filePath,
          );
          return bookId == null ? [] : repo.structures(bookId);
        },
        const [],
        'getAlternativeStructuresForBook (user) "${book.title}"',
      );
    }
    final bookTitle = book.title;

    // לא להעביר ל-Isolate.run closure שנוצר בתוך instance method הזה -
    // הקומפיילר של Dart עלול לתפוס את `this` בכל זאת (כולל ה-FfiDatabase
    // הלא-ניתן-לשליחה), והקריאה תיכשל עם "Illegal argument in isolate
    // message". במקום זאת אנו משתמשים ב-tear-off של פונקציה ברמת קובץ
    // ומעבירים את הפרמטרים כ-record של ערכים פרימיטיביים.
    return _readTarget(
      book.source,
      [],
      'getAlternativeStructuresForBook "$bookTitle"',
      (target) async {
        final results = await _runBookLoadInIsolate(
          _loadAlternativeStructuresRowsInIsolate,
          target: target,
          bookTitle: bookTitle,
          categoryId: book.categoryId,
        );

        return [
          for (final json in results)
            AltTocStructure.fromJson(json, source: book.source),
        ];
      },
    );
  }

  /// כמו [getInlineSectionMarksByLineIndex], לספר אישי. התוכן אינו במסד,
  /// ולכן בדיקת הנראוּת של כותרת נושא נעשית מול [lineAt] — שורות הספר הטעון.
  Future<InlineSectionMarks> getUserInlineSectionMarks(
    TextBook book,
    String? Function(int lineIndex) lineAt,
  ) {
    return _userAltTocOperation<InlineSectionMarks>(
      (repo) async {
        final bookId = await repo.bookId(
          title: book.title,
          categoryId: book.categoryId,
          filePath: book.filePath,
        );
        if (bookId == null) {
          return (markers: <int, String>{}, headings: <int, List<String>>{});
        }
        final rows = await repo.inlineSectionRows(bookId);
        return (
          markers: rows.markers,
          headings: buildSectionHeadings(rows.headings, lineAt),
        );
      },
      (markers: <int, String>{}, headings: <int, List<String>>{}),
      'getUserInlineSectionMarks "${book.title}"',
    );
  }

  /// מריץ קריאה על כותרות הספרים האישיים; כשל מחזיר את [fallback].
  Future<T> _userAltTocOperation<T>(
    Future<T> Function(UserAltTocRepository repo) operation,
    T fallback,
    String errorContext,
  ) async {
    try {
      final userRepo = await UserBooksDatabaseHolder.instance.repository;
      return await operation(UserAltTocRepository(userRepo.database));
    } catch (e) {
      debugPrint('⚠️ Error in $errorContext: $e');
      return fallback;
    }
  }

  /// מריץ [read] על מסד [source]; מסד שאינו פתוח או כשל מחזירים את [fallback].
  Future<T> _readTarget<T>(
    BookSource source,
    T fallback,
    String errorContext,
    Future<T> Function(ReadOnlyDbTarget target) read,
  ) async {
    final target = _isolateTargetFor(source);
    if (target == null) return fallback;
    try {
      return await read(target);
    } catch (e) {
      debugPrint('⚠️ Error in $errorContext: $e');
      return fallback;
    }
  }

  /// סמני חלוקה וכותרות נושא להצגה בגוף הטקסט, לפי `lineIndex` של שורת
  /// התוכן (issues #773, #1121). לספר בלי מבנים כאלה — מפות ריקות.
  Future<InlineSectionMarks> getInlineSectionMarksByLineIndex(
    String bookTitle, {
    int? categoryId,
    BookSource source = BookSource.official,
  }) async {
    const empty = (markers: <int, String>{}, headings: <int, List<String>>{});
    // ב-worker הקבוע: מפענח השורות נטען פעם אחת לחיבור, לא בכל פתיחת ספר.
    return _readTarget(
      source,
      empty,
      'getInlineSectionMarksByLineIndex "$bookTitle"',
      (target) => _loadOnReadWorker(
        target,
        'inlineSectionMarks',
        {'bookTitle': bookTitle, 'categoryId': categoryId},
        () => _runBookLoadInIsolate(
          _loadInlineSectionMarksInIsolate,
          target: target,
          bookTitle: bookTitle,
          categoryId: categoryId,
        ),
      ),
    );
  }

  /// דיבורי-המתחיל של ספר (`line_dh`, מגרסת ספרייה 25), ממופתחים לפי
  /// `lineIndex` של שורת הפירוש: הצורה המודפסת של הדיבור, לתצוגה כתת-כותרת
  /// בעץ הניווט. לספר בלי אינדקס, או במסד ישן, מוחזרת מפה ריקה.
  Future<Map<int, String>> getDibburHamatchilByLineIndex(
    String bookTitle, {
    int? categoryId,
    BookSource source = BookSource.official,
  }) async {
    return _readTarget(
      source,
      const {},
      'getDibburHamatchilByLineIndex "$bookTitle"',
      (target) => _runBookLoadInIsolate(
        _loadDibburHamatchilInIsolate,
        target: target,
        bookTitle: bookTitle,
        categoryId: categoryId,
      ),
    );
  }

  /// מופעי שמות הקודש של ספר (`line_divine_name`), לפי `lineIndex`. במסד
  /// ישן, או לספר בלי מופעים, מוחזר [DivineNameSpans.empty].
  Future<DivineNameSpans> getDivineNameSpans(
    String bookTitle, {
    int? categoryId,
    BookSource source = BookSource.official,
  }) async {
    return _readTarget(
      source,
      DivineNameSpans.empty,
      'getDivineNameSpans "$bookTitle"',
      (target) => _runBookLoadInIsolate(
        _loadDivineNamesInIsolate,
        target: target,
        bookTitle: bookTitle,
        categoryId: categoryId,
      ),
    );
  }

  /// הערות השוליים של ספר (`line_note`), לפי `lineIndex`. במסד בלי הטבלה,
  /// או לספר בלי הערות, מוחזר [BookNotes.empty]. כשל נזרק: הגופים הם חלק
  /// מטקסט הספר, ועוגני הקישורים נמדדים עליהם.
  Future<BookNotes> getBookNotes(
    String bookTitle, {
    int? categoryId,
    BookSource source = BookSource.official,
  }) async {
    final target = _isolateTargetFor(source);
    if (target == null) return BookNotes.empty;
    return _runBookLoadInIsolate(
      _loadBookNotesInIsolate,
      target: target,
      bookTitle: bookTitle,
      categoryId: categoryId,
    );
  }

  /// Get all alternative TOC entries for a specific structure
  Future<List<AltTocEntry>> getAllAlternativeEntries(
    int structureId, {
    BookSource source = BookSource.official,
  }) async {
    if (source.isUser) {
      return _userAltTocOperation(
        (repo) => repo.entries(structureId),
        const [],
        'getAllAlternativeEntries (user) $structureId',
      );
    }
    return _dbOperation<List<AltTocEntry>>(
      (db) async {
        // We join with tocText to get the actual text
        // Order by ID to ensure consistent order (or maybe level/parentId)
        final results = db
            .select(
              '''
          SELECT e.*, t.text
          FROM alt_toc_entry e
          JOIN tocText t ON e.textId = t.id
          WHERE e.structureId = ?
          ORDER BY e.id
        ''',
              [structureId],
            )
            .toMapList();

        return results.map((json) => AltTocEntry.fromJson(json)).toList();
      },
      [],
      'getAllAlternativeEntries $structureId',
      requires: (c) => c.hasAltToc,
      source: source,
    );
  }

  /// מחזיר ערכי AltToc בסדר המזהים, עם נתוני ההיררכיה ושורת הכותרת.
  /// LEFT JOIN משמר כותרות-אב שאין להן שורה.
  Future<
    List<({int id, int? parentId, int level, int? lineIndex, String text})>
  >
  getAltTocEntriesWithLineIndex(
    int structureId, {
    BookSource source = BookSource.official,
  }) async {
    if (source.isUser) {
      return _userAltTocOperation(
        (repo) => repo.entriesWithLineIndex(structureId),
        const [],
        'getAltTocEntriesWithLineIndex (user) $structureId',
      );
    }
    return _dbOperation<
      List<({int id, int? parentId, int level, int? lineIndex, String text})>
    >(
      (db) async {
        final results = db
            .select(
              '''
          SELECT e.id, e.parentId, e.level, l.lineIndex, t.text
          FROM alt_toc_entry e
          JOIN tocText t ON e.textId = t.id
          LEFT JOIN line l ON e.lineId = l.id
          WHERE e.structureId = ?
          ORDER BY e.id
        ''',
              [structureId],
            )
            .toMapList();

        return results
            .map(
              (r) => (
                id: r['id'] as int,
                parentId: r['parentId'] as int?,
                level: r['level'] as int,
                lineIndex: r['lineIndex'] as int?,
                text: r['text'] as String,
              ),
            )
            .toList();
      },
      [],
      'getAltTocEntriesWithLineIndex $structureId',
      requires: (c) => c.hasAltToc,
      source: source,
    );
  }

  /// Get links (books/lines) associated with a specific alternative TOC entry
  Future<List<Link>> getLinksForAltTocEntry(
    int structureId,
    int altTocEntryId, {
    BookSource source = BookSource.official,
  }) async {
    if (source.isUser) {
      return _userAltTocOperation(
        (repo) => repo.linksForEntry(structureId, altTocEntryId),
        const [],
        'getLinksForAltTocEntry (user) $structureId',
      );
    }
    return _dbOperation<List<Link>>(
      (db) async {
        // Join line_alt_toc -> line -> book
        var results = db
            .select(
              '''
          SELECT
            b.title as bookTitle,
            l.lineIndex,
            l.heRef
          FROM line_alt_toc lat
          JOIN line l ON lat.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE lat.structureId = ? AND lat.altTocEntryId = ?
          ORDER BY b.title, l.lineIndex
        ''',
              [structureId, altTocEntryId],
            )
            .toMapList();
        // עלה שאחיו הבא נפתח באותה שורה (דפים בפסקה אחת) אינו ממופה ב-line_alt_toc.
        if (results.isEmpty) {
          results = db
              .select(
                '''
          SELECT b.title as bookTitle, l.lineIndex, l.heRef
          FROM alt_toc_entry e
          JOIN line l ON e.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE e.structureId = ? AND e.id = ? AND e.hasChildren = 0
        ''',
                [structureId, altTocEntryId],
              )
              .toMapList();
        }

        return results.map((row) {
          final bookTitle = row['bookTitle'] as String;
          final lineIndex = row['lineIndex'] as int;

          return Link(
            heRef: row['heRef'] as String? ?? '$bookTitle ${lineIndex + 1}',
            index1: 0, // Not relevant here
            path2: bookTitle,
            index2: lineIndex + 1, // 1-based index for UI
            connectionType: 'alt_toc',
            targetSource: source,
          );
        }).toList();
      },
      [],
      'getLinksForAltTocEntry',
      requires: (c) => c.hasLineAltToc,
      source: source,
    );
  }

  /// Get the alternative TOC entry associated with a specific book line
  Future<int?> getAltTocEntryForLine(
    String bookTitle,
    int lineIndex,
    int structureId, {
    BookSource source = BookSource.official,
  }) async {
    if (source.isUser) {
      return _userAltTocOperation(
        (repo) => repo.entryForLine(structureId, lineIndex),
        null,
        'getAltTocEntryForLine (user) $structureId',
      );
    }
    return _dbOperation<int?>(
      (db) async {
        final results = db
            .select(
              '''
          SELECT lat.altTocEntryId
          FROM line_alt_toc lat
          JOIN line l ON lat.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE b.title = ? AND l.lineIndex = ? AND lat.structureId = ?
          LIMIT 1
  ''',
              [bookTitle, lineIndex, structureId],
            )
            .toMapList();

        if (results.isNotEmpty) {
          return results.first['altTocEntryId'] as int;
        }
        return null;
      },
      null,
      'getAltTocEntryForLine',
      requires: (c) => c.hasLineAltToc,
      source: source,
    );
  }

  /// מכינה ספרים ברקע ומחילה את השינויים בתור הכתיבה לספרים האישיים.
  Future<ScanResult> scanAndAddExternalBooksFromFolder(
    String folderPath,
    String folderName,
    SeforimRepository repository,
  ) {
    // _doScan never throws; operationQueue handles busyCount and serialization.
    return operationQueue.enqueue(
      () => _doScan(folderPath, folderName, repository),
    );
  }

  Future<ScanResult> _doScan(
    String folderPath,
    String folderName,
    SeforimRepository repository,
  ) async {
    debugPrint('📁 Scanning custom folder for external books: $folderPath');

    int added = 0;
    int updated = 0;
    int failed = 0;
    final failedDetails = <(String, String)>[];
    final updatedBookIds = <int>[];

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        debugPrint('⚠️ Folder does not exist: $folderPath');
        return const ScanResult(fatalError: 'התיקייה לא נמצאה');
      }

      // הוספת תיקייה משווה רק ל-user_books.db; האוסף כולו רץ ברקע.
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      final discovered = await Isolate.run(
        () => _scanExternalFolderInIsolate((folderPath, folderName, dbPath)),
      );
      debugPrint(
        '📁 Isolate found ${discovered.length} books to process in $folderPath',
      );

      final pdfTocs = <String, List<migration.TocEntry>>{};
      for (var i = 0; i < discovered.length; i++) {
        final item = discovered[i];
        if (item.book.fileType != 'pdf' || item.existingBookId != null) {
          continue;
        }
        try {
          pdfTocs[item.book.filePath] = externalBookTocEntries(
            await _parsePdfOutline(File(item.book.filePath)),
          );
        } catch (error) {
          discovered[i] = _DiscoveredBook(
            book: item.book,
            categoryPath: item.categoryPath,
            conversionError: error.toString(),
          );
        }
      }
      await QueryLoader.initialize();
      late final ScanResult written;
      try {
        written = await compute(_writeDiscoveredBooks, (
          dbPath: repository.database.path,
          books: discovered,
          pdfTocs: pdfTocs,
          queries: QueryLoader.cacheSnapshot,
          source: CustomFolderSource.nameForFolder(folderPath),
        ));
      } finally {
        for (final item in discovered) {
          if (item.existingBookId case final id?) {
            repository.invalidateExternalBookToc(id);
          }
        }
      }
      added = written.addedBooks;
      updated = written.updatedBooks;
      failed = written.failedBooks;
      failedDetails.addAll(written.failedDetails);
      updatedBookIds.addAll(written.updatedBookIds);

      // קובצי הכותרות והגרסאות שבתיקייה נקלטים אחרי הספרים — הם מזוהים
      // לפי נתיב הקובץ, שקיים ב-DB רק מכאן ואילך.
      for (final error in await UserSidecarSync.applyForFolder(
        userDb: repository.database,
        folderPath: folderPath,
        officialRepository: _sqliteProvider.repository,
      )) {
        failedDetails.add((folderName, error));
      }

      debugPrint(
        '📁 Finished scanning custom folder: $folderPath '
        '(added=$added, updated=$updated, failed=$failed)',
      );
      return ScanResult(
        addedBooks: added,
        updatedBooks: updated,
        failedBooks: failed,
        failedDetails: failedDetails,
        updatedBookIds: updatedBookIds,
      );
    } catch (e) {
      debugPrint('⚠️ Scan failed for $folderPath: $e');
      return ScanResult(fatalError: e);
    }
  }

  /// בדיקה חוזרת מול המסד הכותב מונעת הוספה כפולה לאחר סריקת הרקע.
  static Future<bool> _recheckBeforeInsert(
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
        alreadyInDb.id,
        fileSize,
        lastModified,
      );
      debugPrint('📁 Updated metadata (recheck): $filePath');
    }
    return true;
  }

  /// בדיקת הקיום נפרדת כדי לאמת את גיבוי הסריקה גם ללא מסד פתוח.
  @visibleForTesting
  static Future<bool> recheckBeforeInsertForTest({
    required dynamic repository,
    required String filePath,
    required int fileSize,
    required int lastModified,
  }) {
    return DatabaseLibraryProvider._recheckBeforeInsert(
      repository,
      filePath,
      fileSize,
      lastModified,
    );
  }
}
