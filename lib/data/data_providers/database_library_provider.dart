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
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/migration/models/toc_entry.dart' as db_models;
import 'package:otzaria/utils/file/file_hidden_utils.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/docx_cache.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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

        // New or changed book — parse TOC for TXT / DOCX.
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

        books.add(
          _DiscoveredBook(
            path: entity.path,
            title: title,
            fileType: fileType,
            fileSize: fileSize,
            lastModified: lastModified,
            categoryPath: categoryPath,
            tocEntries: rawToc,
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
    flat.add(
      _RawTocEntry(
        text: entry.text,
        level: entry.level,
        lineIndex: entry.index,
        parentIndex: parentIndex,
      ),
    );
    if (entry.children.isNotEmpty) {
      _flattenRawRecursive(entry.children, flat, myIndex);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────

/// טוען קישורי "מקור" (SOURCE וירטואלי) לספר כ-target: הופך source↔target כדי
/// שספר מפרש יציג את מקורו. ב-v3 הקישור נשמר בכיוון קנוני אחד בלבד.
/// שורות ה-anchors כוללות גם שורות מכוסות של קישורי-טווח (link_coverage,
/// side=1) — כך קישור שהצד התלוי שלו משתרע על כמה שורות מופיע בכל שורה בטווח.
List<Map<String, dynamic>> _loadInverseSourceRows(
  sqlite3.Database db,
  int bookId, {
  int? startLineIndex,
  int? endLineIndex,
}) {
  final types = LinkTypes.dependentTextTypes.toList();
  final typePlaceholders = List.filled(types.length, '?').join(', ');
  final hasRange = startLineIndex != null && endLineIndex != null;
  // בשאילתה ההפוכה השורה המוצגת היא צד היעד של הקישור השמור.
  final hasLinkAnchor = _hasLinkAnchorTable(db);
  final hasLinkRanges = _hasLinkRangeTables(db);
  final anchorSelect = _anchorSelectColumns(hasLinkAnchor);
  final anchorJoin = _anchorJoinClause(hasLinkAnchor, displayedSide: 1);
  // בפאנל של תצוגת המקור מוצג צד ה-source של הקישור (side=0).
  final rangeEndSelect = _rangeEndSelectColumns(hasLinkRanges);
  final rangeEndJoin = _rangeEndJoinClause(hasLinkRanges, panelSide: 0);

  if (hasRange) {
    // כשיש טווח: מוצאים תחילה את ה-line IDs בטווח דרך idx_line_book_index,
    // ואז מחפשים links לפי targetLineId דרך idx_link_target_line — הרבה יותר
    // יעיל מאשר לסרוק את כל ה-links של הספר (עשרות אלפים לספרי בסיס כגון
    // תורה / ש"ס) ולסנן לפי lineIndex בדיעבד.
    final coverageArm = hasLinkRanges
        ? '''
          UNION ALL
          SELECT lc.linkId, lc.lineId FROM link_coverage lc
          WHERE lc.side = 1 AND lc.lineId IN (
            SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
          )'''
        : '';
    final params = <Object?>[
      bookId,
      startLineIndex,
      endLineIndex,
      bookId,
      if (hasLinkRanges) ...[bookId, startLineIndex, endLineIndex],
      ...types,
    ];
    return db.select('''
        WITH anchors(linkId, anchorLineId) AS (
          SELECT l.id, l.targetLineId FROM link l
          WHERE l.targetLineId IN (
            SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
          )
            AND l.targetBookId = ?
          $coverageArm
        )
        SELECT
          tl.lineIndex as sourceLineIndex,
          sl.lineIndex as targetLineIndex,
          sl.heRef as targetLineHeRef,
          sb.title as targetBookTitle,
          sb.categoryId as targetCategoryId,
          NULL as targetFileType,
          $rangeEndSelect
          $anchorSelect
          'SOURCE' as connectionTypeName
        FROM anchors a
        JOIN link l ON l.id = a.linkId
        JOIN line tl ON tl.id = a.anchorLineId
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN book sb ON l.sourceBookId = sb.id
        JOIN connection_type ct ON l.connectionTypeId = ct.id
        $rangeEndJoin
        $anchorJoin
        WHERE ct.name IN ($typePlaceholders)
          AND l.sourceBookId != l.targetBookId
        ORDER BY tl.lineIndex
      ''', params).toMapList();
  }

  final coverageArm = hasLinkRanges
      ? '''
        UNION ALL
        SELECT lc.linkId, lc.lineId FROM link_coverage lc
        JOIN link cl ON cl.id = lc.linkId
        WHERE lc.side = 1 AND cl.targetBookId = ?'''
      : '';
  final params = <Object?>[
    bookId,
    if (hasLinkRanges) bookId,
    ...types,
  ];
  return db.select('''
      WITH anchors(linkId, anchorLineId) AS (
        SELECT id, targetLineId FROM link WHERE targetBookId = ?
        $coverageArm
      )
      SELECT
        tl.lineIndex as sourceLineIndex,
        sl.lineIndex as targetLineIndex,
        sl.heRef as targetLineHeRef,
        sb.title as targetBookTitle,
        sb.categoryId as targetCategoryId,
        NULL as targetFileType,
        $rangeEndSelect
        $anchorSelect
        'SOURCE' as connectionTypeName
      FROM anchors a
      JOIN link l ON l.id = a.linkId
      JOIN line tl ON tl.id = a.anchorLineId
      JOIN line sl ON l.sourceLineId = sl.id
      JOIN book sb ON l.sourceBookId = sb.id
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      $rangeEndJoin
      $anchorJoin
      WHERE ct.name IN ($typePlaceholders)
        AND l.sourceBookId != l.targetBookId
      ORDER BY tl.lineIndex
    ''', params).toMapList();
}

/// עוגני-מילה (link_anchor) — קיים רק במסדים חדשים; במסד ישן השאילתות חוזרות
/// לעמודות NULL. side=0 = העוגן יושב בשורת המקור של הקישור, side=1 = בשורת
/// היעד. `displayedSide` הוא הצד שהשורה שלו מוצגת בגוף הטקסט (הסמן/הטווח
/// מוזרקים אליה), והצד הנגדי הוא קטע-הפאנל (anchorLinked*).
bool _hasLinkAnchorTable(sqlite3.Database db) => db
    .select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='link_anchor' LIMIT 1",
    )
    .isNotEmpty;

/// קישורי-טווח (link_range/link_coverage) — קיימים רק במסדים חדשים; במסד ישן
/// השאילתות חוזרות לעמודות NULL ולשורת העוגן הראשונה בלבד. שתי הטבלאות
/// נשלחות יחד, לכן די בבדיקת link_coverage.
bool _hasLinkRangeTables(sqlite3.Database db) => db
    .select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='link_coverage' LIMIT 1",
    )
    .isNotEmpty;

/// מהדורות ספרים (book_version/version_line) — קיימות רק במסדים חדשים; במסד
/// ישן רשימת הגרסאות ריקה ופתיחת גרסה נכשלת בשקט. שתי הטבלאות נשלחות יחד,
/// לכן די בבדיקת book_version.
bool _hasBookVersionTables(sqlite3.Database db) => db
    .select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='book_version' LIMIT 1",
    )
    .isNotEmpty;

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
          FROM link_anchor WHERE side = $displayedSide GROUP BY linkId
        ) la ON la.linkId = l.id AND a.anchorLineId = $displayedSideLine
        LEFT JOIN (
          SELECT linkId, MIN(charStart) AS charStart, charEnd
          FROM link_anchor WHERE side = ${1 - displayedSide} GROUP BY linkId
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
      'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1',
      [title, categoryId],
    ).toMapList();

    if (bookResults.isEmpty) {
      return const [];
    }

    final bookId = bookResults.first['id'] as int;
    final hasLinkAnchor = _hasLinkAnchorTable(db);
    final hasLinkRanges = _hasLinkRangeTables(db);

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
        ORDER BY sl.lineIndex
      ''',
          [bookId, if (hasLinkRanges) bookId],
        )
        .toMapList();
    return [...forwardRows, ..._loadInverseSourceRows(db, bookId)];
  } finally {
    db?.close();
  }
}

/// Top-level worker לסיכום קישורי ספר לפי (ספר-יעד, סוג חיבור) — שאילתת
/// GROUP BY זולה במקום למשוך עשרות אלפי שורות קישורים לדארט.
({List<Map<String, dynamic>> rows, int? maxSourceLineIndex})
_loadBookLinkTargetsSummaryRowsInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);

    final bookResults = db.select(
      'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1',
      [title, categoryId],
    ).toMapList();
    if (bookResults.isEmpty) {
      return (rows: const [], maxSourceLineIndex: null);
    }

    final bookId = bookResults.first['id'] as int;
    final hasLinkRanges = _hasLinkRangeTables(db);

    // קישור-טווח נספר פעם לכל שורה מכוסה — כמו בטעינת הקישורים המלאה, כדי
    // שסיווג "מפרש נדיר" לפי הספירה יישאר שקול.
    final coverageArm = hasLinkRanges
        ? '''
          UNION ALL
          SELECT lc.linkId FROM link_coverage lc
          JOIN link cl ON cl.id = lc.linkId
          WHERE lc.side = 0 AND cl.sourceBookId = ?'''
        : '';
    final forwardRows = db
        .select(
          '''
        WITH anchors(linkId) AS (
          SELECT id FROM link WHERE sourceBookId = ?
          $coverageArm
        )
        SELECT tb.title as targetBookTitle,
               ct.name as connectionTypeName,
               COUNT(*) as linkCount
        FROM anchors a
        JOIN link l ON l.id = a.linkId
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        GROUP BY tb.title, ct.name
      ''',
          [bookId, if (hasLinkRanges) bookId],
        )
        .toMapList();

    // הזרוע ההפוכה — מפרשים ששמורים כקישור מהם אל הספר הזה (מוצגים כ-SOURCE),
    // כמו ב-_loadInverseSourceRows.
    final depTypes = LinkTypes.dependentTextTypes.toList();
    final typePlaceholders = List.filled(depTypes.length, '?').join(', ');
    final inverseRows = db
        .select(
          '''
        SELECT sb.title as targetBookTitle,
               'SOURCE' as connectionTypeName,
               COUNT(*) as linkCount
        FROM link l
        JOIN book sb ON l.sourceBookId = sb.id
        JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.targetBookId = ?
          AND ct.name IN ($typePlaceholders)
          AND l.sourceBookId != l.targetBookId
        GROUP BY sb.title
      ''',
          [bookId, ...depTypes],
        )
        .toMapList();

    final maxRows = db.select(
      'SELECT MAX(sl.lineIndex) as maxIdx FROM link l '
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

/// Top-level wrapper עבור סיכום קישורי ספר ב-isolate.
/// ראה ההסבר ב-[_runAlternativeStructuresInIsolate].
Future<({List<Map<String, dynamic>> rows, int? maxSourceLineIndex})>
_runBookLinkTargetsSummaryInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
}) {
  return Isolate.run(
    () => _loadBookLinkTargetsSummaryRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
    ),
  );
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
      'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1',
      [title, categoryId],
    ).toMapList();

    if (bookResults.isEmpty) {
      return const [];
    }

    final bookId = bookResults.first['id'] as int;
    final hasLinkAnchor = _hasLinkAnchorTable(db);
    final hasLinkRanges = _hasLinkRangeTables(db);

    final parameters = <Object?>[
      bookId,
      if (hasLinkRanges) ...[bookId, startLineIndex, endLineIndex],
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

    // שורות ה-anchors כוללות גם שורות מכוסות של קישורי-טווח (side=0). הזרוע
    // מסוננת לחלון כבר כאן דרך ה-PK של link_coverage (lineId ראשון) — שורות
    // coverage של side=0 הן תמיד שורות ספר-המקור עצמו, כך שסינון לפי שורות
    // הספר בחלון מייתר JOIN ל-link (ספרי בסיס גדולים נושאים מאות אלפי שורות
    // coverage, וסריקה מלאה שלהן בכל חלון גלילה יקרה מדי).
    final coverageArm = hasLinkRanges
        ? '''
          UNION ALL
          SELECT lc.linkId, lc.lineId FROM link_coverage lc
          WHERE lc.side = 0 AND lc.lineId IN (
            SELECT id FROM line WHERE bookId = ? AND lineIndex BETWEEN ? AND ?
          )'''
        : '';
    final rows = db.select('''
        WITH anchors(linkId, anchorLineId) AS (
          SELECT id, sourceLineId FROM link WHERE sourceBookId = ?
          $coverageArm
        )
        SELECT
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tl.heRef as targetLineHeRef,
          tb.title as targetBookTitle,
          tb.categoryId as targetCategoryId,
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
        WHERE sl.lineIndex BETWEEN ? AND ?
          $commentaryFilterClause
        ORDER BY sl.lineIndex, tb.orderIndex
      ''', parameters).toMapList();
    return [
      ...rows,
      ..._loadInverseSourceRows(
        db,
        bookId,
        startLineIndex: startLineIndex,
        endLineIndex: endLineIndex,
      ),
    ];
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

/// Top-level wrapper שמרכז את כל הלוגיקה של קריאת alt-structures בתוך
/// `Isolate.run`. חיוני שהקריאה ל-`Isolate.run` תיווצר *כאן* (בפונקציה
/// ברמת קובץ), ולא בתוך instance method של `DatabaseLibraryProvider` -
/// אחרת ה-closure של Dart עלול לתפוס את `this` (כולל ה-`FfiDatabase`
/// שאינו ניתן לשליחה ל-isolate) ולגרום לכשל
/// "Illegal argument in isolate message".
Future<List<Map<String, dynamic>>> _runAlternativeStructuresInIsolate({
  required String dbPath,
  required String bookTitle,
}) {
  return Isolate.run(
    () => _loadAlternativeStructuresRowsInIsolate(
      dbPath: dbPath,
      bookTitle: bookTitle,
    ),
  );
}

/// Top-level wrapper עבור טעינת קישורי ספר ב-isolate.
/// ראה ההסבר ב-[_runAlternativeStructuresInIsolate].
Future<List<Map<String, Object?>>> _runBookLinksInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
  required String fileType,
}) {
  return Isolate.run(
    () => _loadBookLinksRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    ),
  );
}

/// Top-level wrapper עבור טעינת קישורי טווח ב-isolate.
/// ראה ההסבר ב-[_runAlternativeStructuresInIsolate].
Future<List<Map<String, Object?>>> _runBookLinksInRangeInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLineIndex,
  required int endLineIndex,
  List<String>? targetBookTitles,
}) {
  return Isolate.run(
    () => _loadBookLinksRowsInRangeInIsolate(
      dbPath: dbPath,
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
/// מתבצע כאן כדי לא לחסום את ה-UI thread. ראה [_runAlternativeStructuresInIsolate].
({int startLine, int endLine, int totalLines, List<String> lines})?
_loadBookTextRangeRowsInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLine,
  required int endLine,
  String? versionTitle,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);

    final bookResults = db.select(
      'SELECT id, totalLines FROM book WHERE title = ? AND categoryId = ? LIMIT 1',
      [title, categoryId],
    ).toMapList();
    if (bookResults.isEmpty) {
      return null;
    }

    final totalLines = bookResults.first['totalLines'] as int;
    if (totalLines <= 0) {
      return null;
    }
    final bookId = bookResults.first['id'] as int;

    final normalizedStart = startLine.clamp(0, totalLines - 1);
    final normalizedEnd = endLine.clamp(normalizedStart, totalLines - 1);

    final List<Map<String, dynamic>> rows;
    if (versionTitle != null) {
      if (!_hasBookVersionTables(db)) return null;
      final versionRows = db.select(
        'SELECT id FROM book_version WHERE bookId = ? AND versionTitle = ? LIMIT 1',
        [bookId, versionTitle],
      ).toMapList();
      if (versionRows.isEmpty) return null;
      final versionId = versionRows.first['id'] as int;
      // מהדורה חלופית: שורות מבנה (heRef NULL — כותרות/מחברים) נשארות מהשלד;
      // שורת תוכן מקבלת את נוסח המהדורה, וסגמנט שחסר בה מוצג ריק — לעולם לא
      // נופלים בשקט לנוסח הממוזג.
      rows = db
          .select(
            '''
        SELECT CASE WHEN l.heRef IS NULL THEN l.content
                    ELSE COALESCE(vl.content, '') END AS content
        FROM line l
        LEFT JOIN version_line vl ON vl.versionId = ? AND vl.lineId = l.id
        WHERE l.bookId = ? AND l.lineIndex >= ? AND l.lineIndex <= ?
        ORDER BY l.lineIndex
      ''',
            [versionId, bookId, normalizedStart, normalizedEnd],
          )
          .toMapList();
    } else {
      rows = db.select(
        'SELECT content FROM line WHERE bookId = ? AND lineIndex >= ? AND lineIndex <= ? ORDER BY lineIndex',
        [bookId, normalizedStart, normalizedEnd],
      ).toMapList();
    }
    if (rows.isEmpty) {
      return null;
    }

    final text = rows.map((row) => row['content'] as String? ?? '').join('\n');
    return (
      startLine: normalizedStart,
      endLine: normalizedEnd,
      totalLines: totalLines,
      lines: text.split('\n'),
    );
  } finally {
    db?.close();
  }
}

/// Top-level wrapper עבור טעינת טווח תוכן ב-isolate.
/// ראה ההסבר ב-[_runAlternativeStructuresInIsolate].
Future<({int startLine, int endLine, int totalLines, List<String> lines})?>
_runBookTextRangeInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
  required String fileType,
  required int startLine,
  required int endLine,
  String? versionTitle,
}) {
  return Isolate.run(
    () => _loadBookTextRangeRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      startLine: startLine,
      endLine: endLine,
      versionTitle: versionTitle,
    ),
  );
}

/// Top-level worker לרשימת המהדורות (book_version) של ספר. רשימה ריקה כשה-DB
/// ישן (אין טבלה) או כשאין לספר מידע גרסאות.
List<Map<String, dynamic>> _loadBookVersionsRowsInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    if (!_hasBookVersionTables(db)) return const [];

    final bookResults = db.select(
      'SELECT id FROM book WHERE title = ? AND categoryId = ? LIMIT 1',
      [title, categoryId],
    ).toMapList();
    if (bookResults.isEmpty) return const [];
    final bookId = bookResults.first['id'] as int;

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
/// ראה ההסבר ב-[_runAlternativeStructuresInIsolate].
Future<List<Map<String, dynamic>>> _runBookVersionsInIsolate({
  required String dbPath,
  required String title,
  required int categoryId,
}) {
  return Isolate.run(
    () => _loadBookVersionsRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
    ),
  );
}

/// (title, categoryId) של ספרים שיש להם מהדורה לבחירה: 2+ גרסאות, או גרסה
/// יחידה עם טקסט שמור. גרסה יחידה מטא-דאטה בלבד = הנוסח המוצג עצמו, ואינה
/// נכללת. נטען פעם אחת ומשמש לקביעת הצגת תפריט 'גרסאות'.
List<Map<String, dynamic>> _loadSelectableVersionKeysInIsolate({
  required String dbPath,
}) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    if (!_hasBookVersionTables(db)) return const [];

    return db.select('''
      SELECT b.title, b.categoryId
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
  required String dbPath,
}) {
  return Isolate.run(
    () => _loadSelectableVersionKeysInIsolate(dbPath: dbPath),
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
class DatabaseLibraryProvider implements LibraryProvider {
  final SqliteDataProvider _sqliteProvider = SqliteDataProvider.instance;
  final Set<BookCompositeKey> _cachedKeys = {};
  final Map<int, String> _categoryIdToPath = {};
  final Map<int, db_models.Category> _categoriesById = {};
  bool _titlesCached = false;
  String? _bundledTalmudBavliPathCache;
  bool? _bundledTalmudBavliExistsCache;

  /// מפתחות "title categoryId" של ספרים שראוי להציג להם תפריט 'גרסאות'.
  /// ממוזמז — נטען פעם אחת ל-DB; מנוקה ב-[clearCache].
  Future<Set<String>>? _selectableVersionKeysFuture;

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

  @visibleForTesting
  static ({List<Map<String, dynamic>> rows, int? maxSourceLineIndex})
  loadBookLinkTargetsSummaryRowsForTesting({
    required String dbPath,
    required String title,
    required int categoryId,
  }) {
    return _loadBookLinkTargetsSummaryRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> loadBookVersionsRowsForTesting({
    required String dbPath,
    required String title,
    required int categoryId,
  }) {
    return _loadBookVersionsRowsInIsolate(
      dbPath: dbPath,
      title: title,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  static ({int startLine, int endLine, int totalLines, List<String> lines})?
  loadBookTextRangeRowsForTesting({
    required String dbPath,
    required String title,
    required int categoryId,
    required String fileType,
    required int startLine,
    required int endLine,
    String? versionTitle,
  }) {
    return _loadBookTextRangeRowsInIsolate(
      dbPath: dbPath,
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
      final dbBooks = await _sqliteProvider.repository!.getAllBooks();
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
    if (!_shouldUseUserBooks(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: false,
    )) {
      return false;
    }
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
          title,
          categoryId,
          fileType,
        );
        if (book == null) return null;
        if (book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          if (await file.exists()) {
            // DOCX הוא בינארי — חובה להמיר, לא readAsString (שמחזיר זבל/זורק).
            if ((book.fileType ?? '').toLowerCase() == 'docx' ||
                file.path.toLowerCase().endsWith('.docx')) {
              return await convertDocxWithCache(file, title);
            }
            // קבצים אישיים ישנים עשויים להיות ב-Windows-1255/UTF-16 ולא UTF-8.
            return await readTextFileSmart(file);
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
            if ((book.fileType ?? '').toLowerCase() == 'docx') {
              return await convertDocxWithCache(file, title);
            }
            return await readTextFileSmart(file);
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
          title,
          categoryId,
          fileType,
        );
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
    _selectableVersionKeysFuture = null;
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

    // NOTE: Sorting is now done during build (like Kotlin), no need for post-sort
    // _sortLibraryRecursive(library); // Removed - sorting happens in _buildCatalogCategoryRecursiveOptimized

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
      final defaultCategory = await repository.getCategoryByTitle(
        'ללא קטגוריה',
      );
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
      final existingCategory = await repository.getCategoryByTitleAndParent(
        categoryName,
        parentId,
      );

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
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(file.path);
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
  ) async {
    try {
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      if (!await File(dbPath).exists()) {
        return;
      }

      final repo = await UserBooksDatabaseHolder.instance.repository;

      late final List<Map<String, dynamic>> userBooks;
      late final List<Map<String, dynamic>> userCats;
      late final Map<int, String> userAuthors;

      // קריאת הנתונים מ-user_books.db מתבצעת *לפני* ניקוי הקאשים. אם
      // הקריאה נכשלת (למשל "database is locked" בזמן כתיבה מקבילית),
      // יוצאים דרך ה-catch בלי לגעת בקאשים או ב-library — והמצב הקודם
      // (ספרי המשתמש שכבר נטענו) נשמר עד הניסיון הבא, במקום להיעלם.
      final db = await repo.database.database;
      withTransaction(db, () {
        userBooks = repo.database.bookDao.getAllBooksMinimal(
          db,
          withFileColumns: true,
        );
        userCats = repo.database.categoryDao.getAllCategoryRows(db);
        userAuthors = repo.database.bookDao.getBookAuthorsMap(db);
      });

      // הקריאה הצליחה — עכשיו בטוח לנקות ולבנות מחדש. מכאן והלאה הבנייה
      // פועלת על נתונים שכבר בזיכרון ואינה ניגשת ל-DB, כך שאם תיכשל בכל
      // זאת, ה-library והקאשים יישארו חלקיים אך מסונכרנים זה עם זה.
      _userBooksCategoryIds.clear();
      _userBooksCachedKeys.clear();

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
      // (במקום להציג אותן תחת קטגוריית "ספרים אישיים" נפרדת).
      final mergeIntoLibraryRoot =
          Settings.getValue<bool>(
            SettingsRepository.keyMergeUserBooksIntoLibrary,
            defaultValue: false,
          ) ??
          false;

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

      if (mergeIntoLibraryRoot) {
        // במצב מיזוג: גם "ספרים אישיים" וגם שם התיקייה שהמשתמש בחר
        // (pickedFolder) לא יופיעו בעץ. הבנייה מתחילה מתת-התיקיות של
        // התיקייה הנבחרת, וקטגוריות מתמזגות בשורש הספרייה לפי שם.
        // ספרים שיושבים ישירות תחת "ספרים אישיים" או תחת תיקייה נבחרת
        // נכנסים לרשימת ספרי השורש של הספרייה (`library.books`).
        for (final dbBook in directBooksUnderRoot) {
          final book = _convertMinimalBookMapToBook(
            dbBook,
            library,
            metadata,
            authorFromDatabase: userAuthors[dbBook['id'] as int? ?? 0],
            isUserBook: true,
            idOverride: dbBook['id'] as int? ?? 0,
            categoryIdOverride: personalRootId,
          );
          if (book == null) continue;
          library.books.add(book);
          _userBooksCachedKeys.add(
            BookCompositeKey.create(
              title: book.title,
              categoryId: personalRootId,
              fileType: book.fileType,
              isUserBook: true,
            ),
          );
        }

        for (final pickedFolder in pickedFolders) {
          _userBooksCategoryIds.add(pickedFolder.id);

          // ספרים בתוך התיקייה הנבחרת עצמה — לשורש הספרייה.
          final booksInPickedFolder = (booksByCategory[pickedFolder.id] ?? [])
            ..sort((a, b) {
              final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
              final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
              return orderA.compareTo(orderB);
            });
          for (final dbBook in booksInPickedFolder) {
            final book = _convertMinimalBookMapToBook(
              dbBook,
              library,
              metadata,
              authorFromDatabase: userAuthors[dbBook['id'] as int? ?? 0],
              isUserBook: true,
              idOverride: dbBook['id'] as int? ?? 0,
              categoryIdOverride: pickedFolder.id,
            );
            if (book == null) continue;
            library.books.add(book);
            _userBooksCachedKeys.add(
              BookCompositeKey.create(
                title: book.title,
                categoryId: pickedFolder.id,
                fileType: book.fileType,
                isUserBook: true,
              ),
            );
          }

          // תת-תיקיות של התיקייה הנבחרת — מתמזגות בשורש הספרייה לפי שם.
          final grandchildren = [
            ...?categoriesByParent[pickedFolder.id],
          ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          for (final grandchild in grandchildren) {
            final existing = library.subCategories
                .where((c) => c.title == grandchild.title)
                .firstOrNull;
            if (existing == null) {
              final built = _buildUserBooksCatalogCategoryRecursive(
                grandchild,
                booksByCategory,
                categoriesByParent,
                userAuthors,
                library,
                metadata,
              );
              library.subCategories.add(built);
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
      } else {
        // הזרימה הקיימת — עוטף את כל ספרי המשתמש תחת "ספרים אישיים".
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

        for (final dbBook in directBooksUnderRoot) {
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
          _userBooksCachedKeys.add(
            BookCompositeKey.create(
              title: book.title,
              categoryId: personalRootId,
              fileType: book.fileType,
              isUserBook: true,
            ),
          );
        }

        for (final child in pickedFolders) {
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
        isUserBook: true,
        idOverride: dbBook['id'] as int? ?? 0,
        categoryIdOverride: nativeCategoryId,
      );
      if (book == null) continue;
      category.books.add(book);
      _userBooksCachedKeys.add(
        BookCompositeKey.create(
          title: book.title,
          categoryId: nativeCategoryId,
          fileType: book.fileType,
          isUserBook: true,
        ),
      );
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
  /// fileType, filePath, heShortDesc, heDesc, author.
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
    final heDesc = bookMap['heDesc'] as String?;
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
    final metaHeDesc = heDesc ?? bookMeta?['heDesc'] as String?;

    final normalizedFileType = (fileType ?? '').toLowerCase();

    // External catalog books (fileType='link') are no longer stored in seforim.db.
    // They are served from a separate database via ExternalCatalogRepository.
    if (normalizedFileType == 'link' || normalizedFileType == 'url') {
      return null;
    }

    if (filePath != null && fileType == 'pdf') {
      final resolvedFilePath = resolveMovedFileBookPath(filePath);
      return PdfBook(
        id: id,
        title: title,
        category: category,
        path: resolvedFilePath,
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
        isUserBook: isUserBook,
      );
    }

    if (filePath != null && fileType == 'docx') {
      final resolvedFilePath = resolveMovedFileBookPath(filePath);
      return DocxBook(
        id: id,
        title: title,
        category: category,
        path: resolvedFilePath,
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
        isUserBook: isUserBook,
      );
    }

    return TextBook(
      id: id,
      title: title,
      category: category,
      author: author,
      heShortDesc: metaHeShortDesc,
      heDesc: metaHeDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
      isUserBook: isUserBook,
    );
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
    String fileType,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return [];
    }

    // ראה הערה ב-_runAlternativeStructuresInIsolate: ה-Isolate.run עצמו
    // חייב להיווצר בתוך פונקציה ברמת קובץ, אחרת `this` עלול להיתפס.
    final dbPath = _sqliteProvider.dbPath;

    try {
      final result = await _runBookLinksInIsolate(
        dbPath: dbPath,
        title: title,
        categoryId: categoryId,
        fileType: fileType,
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
          anchorStart: row['anchorCharStart'] as int?,
          anchorEnd: row['anchorCharEnd'] as int?,
          anchorLabel: row['anchorLabel'] as String?,
          linkedAnchorStart: row['anchorLinkedCharStart'] as int?,
          linkedAnchorEnd: row['anchorLinkedCharEnd'] as int?,
          anchorSpans: _parseAnchorSpans(row['anchorSpans'] as String?),
          heRefEnd:
              (row['targetRangeEndHeRef'] as String?)?.trim().isNotEmpty == true
              ? (row['targetRangeEndHeRef'] as String).trim()
              : null,
          index2End: row['targetRangeEndLineIndex'] != null
              ? (row['targetRangeEndLineIndex'] as int) + 1
              : null,
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
    final normalizedTargetBookTitles =
        targetBookTitles
            ?.map((targetTitle) => targetTitle.trim())
            .where((targetTitle) => targetTitle.isNotEmpty)
            .toSet()
            .toList()
          ?..sort();
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return [];
    }

    // ראה הערה ב-_runAlternativeStructuresInIsolate.
    final dbPath = _sqliteProvider.dbPath;

    try {
      final result = await _runBookLinksInRangeInIsolate(
        dbPath: dbPath,
        title: title,
        categoryId: categoryId,
        fileType: fileType,
        startLineIndex: startLineIndex,
        endLineIndex: endLineIndex,
        targetBookTitles: normalizedTargetBookTitles,
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
          anchorStart: row['anchorCharStart'] as int?,
          anchorEnd: row['anchorCharEnd'] as int?,
          anchorLabel: row['anchorLabel'] as String?,
          linkedAnchorStart: row['anchorLinkedCharStart'] as int?,
          linkedAnchorEnd: row['anchorLinkedCharEnd'] as int?,
          anchorSpans: _parseAnchorSpans(row['anchorSpans'] as String?),
          heRefEnd:
              (row['targetRangeEndHeRef'] as String?)?.trim().isNotEmpty == true
              ? (row['targetRangeEndHeRef'] as String).trim()
              : null,
          index2End: row['targetRangeEndLineIndex'] != null
              ? (row['targetRangeEndLineIndex'] as int) + 1
              : null,
        );
      }).toList();
      return links;
    } catch (e) {
      debugPrint('⚠️ Error in getLinksForBookRange "$title": $e');
      return [];
    }
  }

  /// סיכום קישורי הספר לפי (ספר-יעד, סוג חיבור), בתוספת השורה הגבוהה ביותר
  /// שיש עליה קישור (1-based, כמו [Link.index1]; 0 אם אין קישורים).
  /// מיועד לבניית רשימת המפרשים של ספר בלי לטעון את כל הקישורים לזיכרון.
  /// מחזיר null אם המסד לא זמין או שהשאילתה נכשלה.
  Future<({List<LinkTargetSummary> targets, int maxSourceLine})?>
  getBookLinkTargetsSummary(String title, int categoryId) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return null;
    }

    // ראה הערה ב-_runAlternativeStructuresInIsolate.
    final dbPath = _sqliteProvider.dbPath;

    try {
      final result = await _runBookLinkTargetsSummaryInIsolate(
        dbPath: dbPath,
        title: title,
        categoryId: categoryId,
      );
      return (
        targets: [
          for (final row in result.rows)
            LinkTargetSummary(
              targetTitle: row['targetBookTitle'] as String,
              connectionType:
                  row['connectionTypeName'] as String? ?? 'reference',
              linkCount: (row['linkCount'] as int?) ?? 0,
            ),
        ],
        maxSourceLine: (result.maxSourceLineIndex ?? -1) + 1,
      );
    } catch (e) {
      debugPrint('⚠️ Error in getBookLinkTargetsSummary "$title": $e');
      return null;
    }
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
  }) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return null;
    }

    // ראה הערה ב-_runAlternativeStructuresInIsolate.
    final dbPath = _sqliteProvider.dbPath;

    try {
      return await _runBookTextRangeInIsolate(
        dbPath: dbPath,
        title: title,
        categoryId: categoryId,
        fileType: fileType,
        startLine: startLine,
        endLine: endLine,
        versionTitle: versionTitle,
      );
    } catch (e) {
      debugPrint('⚠️ Error in getBookTextRange "$title": $e');
      return null;
    }
  }

  /// רשימת המהדורות (book_version) של ספר, מהדורות עם טקסט מלא תחילה.
  /// רשימה ריקה כשה-DB ישן או כשאין לספר מידע גרסאות.
  Future<List<BookVersionInfo>> getBookVersions(
    String title,
    int categoryId,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return const [];
    }

    final dbPath = _sqliteProvider.dbPath;
    try {
      final rows = await _runBookVersionsInIsolate(
        dbPath: dbPath,
        title: title,
        categoryId: categoryId,
      );
      return rows.map(BookVersionInfo.fromDbRow).toList();
    } catch (e) {
      debugPrint('⚠️ Error in getBookVersions "$title": $e');
      return const [];
    }
  }

  /// האם להציג לספר תפריט 'גרסאות' — כלומר יש מהדורה לבחירה (2+ גרסאות, או
  /// גרסה יחידה עם טקסט). גרסה יחידה מטא-דאטה בלבד = הנוסח המוצג, ולכן false.
  Future<bool> hasSelectableBookVersions(String title, int categoryId) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return false;
    }
    final keys = await (_selectableVersionKeysFuture ??=
        _loadSelectableVersionKeys());
    return keys.contains('$title $categoryId');
  }

  Future<Set<String>> _loadSelectableVersionKeys() async {
    try {
      final rows = await _runSelectableVersionKeysInIsolate(
        dbPath: _sqliteProvider.dbPath,
      );
      return rows.map((r) => '${r['title']} ${r['categoryId']}').toSet();
    } catch (e) {
      debugPrint('⚠️ Error loading selectable version keys: $e');
      _selectableVersionKeysFuture = null; // אפשר ניסיון חוזר בטעינה הבאה
      return const <String>{};
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
        categoryId: link.targetCategoryId,
        fileType: link.targetFileType,
        preferUserBooks: link.targetIsUserBook,
      );
      if (resolvedBook == null) return 'שגיאה: הספר לא נמצא במסד הנתונים';

      // ספר file-backed (תיקייה שנוספה בלי "הוסף למסד הנתונים") — אין שורות
      // ב-DB, התוכן נקרא מהקובץ עצמו לפי אותו פיצול שורות של הסורק.
      final dbBook = resolvedBook.book;
      final dbBookFileType = (dbBook.fileType ?? 'txt').toLowerCase();
      if (dbBook.isFileBacked &&
          dbBook.filePath != null &&
          (dbBookFileType == 'txt' || dbBookFileType == 'docx')) {
        final file = File(dbBook.filePath!);
        if (!await file.exists()) return 'שגיאה: הקובץ לא נמצא';
        final text = dbBookFileType == 'docx'
            ? await convertDocxWithCache(file, dbBook.title)
            : await readTextFileSmart(file);
        final lines = text.split('\n');
        final start = link.index2 - 1;
        if (start >= lines.length) return 'שגיאה: אינדקס מחוץ לטווח';
        final end0 = ((link.index2End ?? link.index2) - 1).clamp(
          start,
          lines.length - 1,
        );
        return lines
            .sublist(start, end0 + 1)
            .map((l) => l.trimRight())
            .join('<br>');
      }

      // link.index2 is 1-based; lineIndex in DB is 0-based
      final line = await resolvedBook.repository.getLineByIndex(
        resolvedBook.book.id,
        link.index2 - 1,
      );
      if (line == null) return 'שגיאה: אינדקס מחוץ לטווח';

      // קישור-טווח: מצרפים את כל שורות הטווח עד index2End (1-based, כולל)
      // בשאילתת טווח אחת במקום שאילתה פר-שורה.
      final end0 = (link.index2End ?? link.index2) - 1;
      if (end0 <= link.index2 - 1) return line.content;
      final rangeLines = await resolvedBook.repository.getLines(
        resolvedBook.book.id,
        link.index2 - 1,
        end0,
      );
      if (rangeLines.isEmpty) return line.content;
      return rangeLines.map((l) => l.content).join('<br>');
    } catch (e) {
      debugPrint('⚠️ Error in getLinkContent: $e');
      return 'שגיאה בטעינת תוכן המפרש';
    }
  }

  /// Get all alternative TOC structures available in the database for a specific book
  Future<List<AltTocStructure>> getAlternativeStructuresForBook(
    String bookTitle,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return [];
    }

    // לא להעביר ל-Isolate.run closure שנוצר בתוך instance method הזה -
    // הקומפיילר של Dart עלול לתפוס את `this` בכל זאת (כולל ה-FfiDatabase
    // הלא-ניתן-לשליחה), והקריאה תיכשל עם "Illegal argument in isolate
    // message". במקום זאת אנו משתמשים ב-tear-off של פונקציה ברמת קובץ
    // ומעבירים את הפרמטרים כ-record של ערכים פרימיטיביים.
    final dbPath = _sqliteProvider.dbPath;

    try {
      final results = await _runAlternativeStructuresInIsolate(
        dbPath: dbPath,
        bookTitle: bookTitle,
      );

      return results.map((json) => AltTocStructure.fromJson(json)).toList();
    } catch (e) {
      debugPrint(
        '⚠️ Error in getAlternativeStructuresForBook "$bookTitle": $e',
      );
      return [];
    }
  }

  /// Get all alternative TOC structures available in the database
  Future<List<AltTocStructure>> getAlternativeStructures() async {
    return _dbOperation<List<AltTocStructure>>(
      (db) async {
        final results = db
            .select('SELECT * FROM alt_toc_structure')
            .toMapList();
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
    );
  }

  /// מחזיר רשימת (lineIndex, text) לכל ערכי כותרות משנה בעלי שורה מוגדרת
  Future<List<({int lineIndex, String text})>> getAltTocLineIndices(
    int structureId,
  ) async {
    return _dbOperation<List<({int lineIndex, String text})>>(
      (db) async {
        final results = db
            .select(
              '''
          SELECT l.lineIndex, t.text
          FROM alt_toc_entry e
          JOIN tocText t ON e.textId = t.id
          JOIN line l ON e.lineId = l.id
          WHERE e.structureId = ?
          ORDER BY l.lineIndex
        ''',
              [structureId],
            )
            .toMapList();

        return results
            .map(
              (r) => (
                lineIndex: r['lineIndex'] as int,
                text: r['text'] as String,
              ),
            )
            .toList();
      },
      [],
      'getAltTocLineIndices $structureId',
    );
  }

  /// מחזיר את ערכי מבנה ה-AltToc עם ה-lineIndex של כל ערך (או null לכותרות-אב
  /// ללא שורה), לצד id/parentId/level/text — כדי לבנות את העץ ולחשב index
  /// לכותרות. LEFT JOIN על line שומר גם ערכים חסרי שורה; הסדר לפי e.id
  /// כדי לשמר את סדר המסמך של ה-DB.
  Future<
    List<({int id, int? parentId, int level, int? lineIndex, String text})>
  >
  getAltTocEntriesWithLineIndex(int structureId) async {
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
    );
  }

  /// Get links (books/lines) associated with a specific alternative TOC entry
  Future<List<Link>> getLinksForAltTocEntry(
    int structureId,
    int altTocEntryId,
  ) async {
    return _dbOperation<List<Link>>(
      (db) async {
        // Join line_alt_toc -> line -> book
        final results = db
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
    String bookTitle,
    int lineIndex,
    int structureId,
  ) async {
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
    final updatedBookIds = <int>[];

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
        '📁 Isolate found ${discovered.length} books to process in $folderPath',
      );

      // Phase 2 (main isolate): only metadata updates + new-book inserts.
      // This is deliberately light: unchanged books were already filtered in
      // Phase 1, so no TOC parse or DB read happens here for them.
      //
      // ה-insert עצמו סינכרוני (sqlite3 חוסם את ה-thread), ולכן הוספה של
      // ספרים רבים בבת אחת תוקעת את ה-UI. כדי למנוע זאת אנו משחררים את
      // לולאת האירועים אחת לכמה ספרים — ה-UI ממשיך להגיב בלי לשנות את
      // לוגיקת ה-DB עצמה.
      var processedSinceYield = 0;
      // source פר-תיקייה (Personal::<נתיב>) — זהה לזה שמסלול הסנכרון/מחיקה
      // מצפה לו, כדי שה-prune והמחיקה יזהו את הספרים לפי שם ה-source.
      final folderSourceName = CustomFolderSource.nameForFolder(folderPath);
      int? scanSourceId;
      for (final book in discovered) {
        if (++processedSinceYield >= 8) {
          processedSinceYield = 0;
          await Future<void>.delayed(Duration.zero);
        }
        if (book.conversionError != null) {
          debugPrint(
            '⚠️ DOCX conversion failed for ${book.title}: ${book.conversionError}',
          );
          failedDetails.add((book.title, book.conversionError!));
          failed++;
          continue;
        }
        try {
          if (book.existingBookId != null) {
            // File changed since last scan — update metadata, and refresh the
            // TOC if it was re-parsed (so navigation matches the new content).
            await repository.updateExternalBookMetadata(
              book.existingBookId!,
              book.fileSize,
              book.lastModified,
            );
            if (book.tocEntries != null) {
              await repository.replaceExternalBookToc(
                book.existingBookId!,
                _rawTocToDbEntries(book.tocEntries!),
              );
            }
            debugPrint(
              '📁 Updated external book (metadata+TOC): ${book.title}',
            );
            updated++;
            updatedBookIds.add(book.existingBookId!);
            continue;
          }

          // New book: create category, parse PDF outline, insert.
          // Re-check authoritatively before inserting (guards against Phase-1
          // fallback duplicates and concurrent-scan races).
          if (await _recheckBeforeInsert(
            repository,
            book.path,
            book.fileSize,
            book.lastModified,
          )) {
            continue;
          }

          final categoryId = await _getOrCreateCategoryInDb(
            book.categoryPath,
            repository,
          );

          List<db_models.TocEntry>? tocEntries;
          if (book.tocEntries != null && book.tocEntries!.isNotEmpty) {
            // TXT / DOCX: already parsed inside the isolate.
            tocEntries = _rawTocToDbEntries(book.tocEntries!);
          } else if (book.fileType == 'pdf') {
            // PDF: parse outline here — pdfrx serializes everything through a
            // single global worker, so there is no gain in parallelizing.
            final pdfToc = await _parsePdfOutline(File(book.path));
            if (pdfToc.isNotEmpty) {
              final dbEntries = <db_models.TocEntry>[];
              _convertTocEntriesToDb(pdfToc, dbEntries, 0, null);
              tocEntries = dbEntries.isNotEmpty ? dbEntries : null;
            }
          }

          scanSourceId ??= await repository.insertSource(folderSourceName, -1);
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
            sourceId: scanSourceId,
          );
          debugPrint(
            '📁 Inserted external book to DB: ${book.title} (type: ${book.fileType})',
          );
          added++;
        } catch (e) {
          debugPrint('⚠️ Failed to process book: ${book.path} - $e');
          failed++;
        }
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
        alreadyInDb.id,
        fileSize,
        lastModified,
      );
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
