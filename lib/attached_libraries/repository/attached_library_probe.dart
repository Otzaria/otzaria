import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:path/path.dart' as p;

/// תוצאת בדיקת קובץ מסד. [problem] null — המסד תקין.
class AttachedLibraryProbeResult {
  final AttachedLibraryProblem? problem;
  final String slug;
  final String displayName;
  final int bookCount;
  final Set<AttachedLibraryCapability> capabilities;
  final AttachedLibraryFingerprint? fingerprint;
  final bool immutable;

  const AttachedLibraryProbeResult({
    this.problem,
    this.slug = '',
    this.displayName = '',
    this.bookCount = 0,
    this.capabilities = const {},
    this.fingerprint,
    this.immutable = false,
  });

  const AttachedLibraryProbeResult.failure(AttachedLibraryProblem this.problem)
    : slug = '',
      displayName = '',
      bookCount = 0,
      capabilities = const {},
      fingerprint = null,
      immutable = false;

  bool get isOk => problem == null;
}

/// בודק קובץ מסד לפני צירוף: כותרת SQLite, יומן תלוי, פתיחה מוקשחת
/// ומפת היכולות. נקראות רק טבלאות מוכרות (`kKnownSeforimTables`); טבלאות
/// אחרות — למשל של תוספים — אינן נקראות כלל.
abstract final class AttachedLibraryProbe {
  /// הבדיקה רצה ב-isolate: פתיחת מסד גדול וספירת ספרים חוסמות.
  static Future<AttachedLibraryProbeResult> probe(String path) =>
      Isolate.run(() => probeSync(path));

  static AttachedLibraryProbeResult probeSync(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return const AttachedLibraryProbeResult.failure(
        AttachedLibraryProblem.notFound,
      );
    }
    final FileStat stat;
    final SqliteHeaderInfo header;
    try {
      stat = file.statSync();
      header = readSqliteHeaderSync(path);
    } on FileSystemException {
      return const AttachedLibraryProbeResult.failure(
        AttachedLibraryProblem.openFailed,
      );
    }
    if (!header.isSqlite) {
      return const AttachedLibraryProbeResult.failure(
        AttachedLibraryProblem.notSqlite,
      );
    }
    if (hasPendingJournalSync(path)) {
      return const AttachedLibraryProbeResult.failure(
        AttachedLibraryProblem.pendingJournal,
      );
    }

    // מסד WAL נקרא בלי קובצי-צד רק כ-immutable; תיקייה שאין בה הרשאה נכשלת
    // בפתיחה הרגילה ונפתחת גם היא כך.
    var immutable = header.isWal;
    Database? db = _tryOpen(path, immutable: immutable);
    if (db == null && !immutable) {
      immutable = true;
      db = _tryOpen(path, immutable: true);
    }
    if (db == null) {
      return const AttachedLibraryProbeResult.failure(
        AttachedLibraryProblem.openFailed,
      );
    }

    try {
      final capabilities = DbCapabilities.probe(db);
      if (!capabilities.hasBooks) {
        return const AttachedLibraryProbeResult.failure(
          AttachedLibraryProblem.noBooks,
        );
      }
      final meta = _readSchemaMeta(db, capabilities);
      final bookCount =
          firstIntValue(db.select('SELECT COUNT(*) FROM book')) ?? 0;
      final baseName = p.basenameWithoutExtension(path);
      return AttachedLibraryProbeResult(
        slug: slugFor(libraryId: meta['library_id'], fileName: baseName),
        displayName: _nonEmpty(meta['library_name']) ?? baseName,
        bookCount: bookCount,
        capabilities: capabilitiesOf(capabilities),
        fingerprint: AttachedLibraryFingerprint(
          size: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
          dbVersion: _nonEmpty(meta['db_version']),
        ),
        immutable: immutable,
      );
    } on SqliteException {
      return const AttachedLibraryProbeResult.failure(
        AttachedLibraryProblem.openFailed,
      );
    } finally {
      db.close();
    }
  }

  static Database? _tryOpen(String path, {required bool immutable}) {
    Database? db;
    try {
      db = openUntrustedReadOnlyDatabase(path, immutable: immutable);
      // הפתיחה עצלה: רק שאילתה ראשונה קוראת את הכותרת ואת הסכמה.
      db.select('PRAGMA schema_version');
      return db;
    } on SqliteException {
      db?.close();
      return null;
    }
  }

  static Map<String, String> _readSchemaMeta(
    Database db,
    DbCapabilities capabilities,
  ) {
    if (!capabilities.hasColumn('schema_meta', 'key') ||
        !capabilities.hasColumn('schema_meta', 'value')) {
      return const {};
    }
    final rows = db.select(
      'SELECT key, value FROM schema_meta '
      "WHERE key IN ('library_id', 'library_name', 'db_version')",
    );
    return {
      for (final row in rows)
        if (row['key'] is String && row['value'] != null)
          row['key'] as String: row['value'].toString(),
    };
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// ה-slug של מסד: `schema_meta.library_id` כשקיים, אחרת שם הקובץ — שניהם
  /// מנוקים לצורה ש-[BookSource.isValidSlug] מקבל.
  static String slugFor({String? libraryId, required String fileName}) {
    final fromId = _nonEmpty(libraryId);
    if (fromId != null) {
      final slug = sanitizeSlug(fromId);
      if (slug.isNotEmpty) return slug;
    }
    final slug = sanitizeSlug(fileName);
    return slug.isEmpty ? 'db' : slug;
  }

  /// אותיות קטנות, ניקוד מוסר, כל רצף תווים אסורים הופך ל-`-`. מחרוזת ריקה
  /// כשלא נותר תו חוקי.
  static String sanitizeSlug(String raw) {
    var slug = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\p{M}', unicode: true), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}._-]+', unicode: true), '-')
        .replaceAll(RegExp('-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    if (slug.runes.length > 64) {
      slug = String.fromCharCodes(slug.runes.take(64));
    }
    return BookSource.isValidSlug(slug) ? slug : '';
  }

  static Set<AttachedLibraryCapability> capabilitiesOf(DbCapabilities c) => {
    if (c.hasBookCategories) AttachedLibraryCapability.categories,
    if (c.hasToc) AttachedLibraryCapability.toc,
    if (c.hasLinks) AttachedLibraryCapability.links,
    if (c.hasAltToc) AttachedLibraryCapability.altToc,
    if (c.hasBookVersions) AttachedLibraryCapability.versions,
    if (c.hasAuthors) AttachedLibraryCapability.authors,
    if (c.hasGenerations) AttachedLibraryCapability.generations,
    if (c.hasAcronyms) AttachedLibraryCapability.acronyms,
    if (c.hasLineRef) AttachedLibraryCapability.lineRef,
    if (c.hasDefaultCommentators) AttachedLibraryCapability.defaultCommentators,
    if (c.hasExternalLinks) AttachedLibraryCapability.externalLinks,
  };
}
