// בודק מסד ספרים אישי (בפורמט seforim.db) כפי שהתוכנה תראה אותו בצירוף.
// אינו תלוי ב-Flutter: רץ ב-`dart run`. הכללים משוכפלים מ-lib, ו-
// test/tool/validate_personal_db_test.dart מוודא שלא סטו מהמקור.

import 'dart:io';

import 'package:otzaria/attached_libraries/utils/attached_file_path.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// עותק של `kKnownSeforimTables` (lib/migration/database/db_capabilities.dart).
const Set<String> kValidatorKnownTables = {
  'category',
  'category_closure',
  'book',
  'source',
  'author',
  'book_author',
  'topic',
  'book_topic',
  'pub_place',
  'book_pub_place',
  'pub_date',
  'book_pub_date',
  'generation',
  'book_generation',
  'book_base_text',
  'line',
  'line_ref',
  'line_dh',
  'tocText',
  'tocEntry',
  'line_toc',
  'connection_type',
  'link',
  'link_anchor',
  'link_range',
  'link_coverage',
  'link_suppressed_side',
  'book_has_links',
  'book_acronym',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'default_commentator',
  'default_targum',
  'book_version',
  'version_line',
  'schema_meta',
  'db_meta',
  'external_link',
};

/// עותקים של `kMaxExternalLinkRows` / `kMaxExternalTextLength`.
const int kValidatorMaxExternalLinkRows = 500000;
const int kValidatorMaxExternalTextLength = 512;

/// העמודות שהתוכנה קוראת בלי חלופה, לכל טבלה. חסרה אחת — הפיצ'ר נכשל או ריק.
const Map<String, List<String>> kValidatorCoreColumns = {
  'book': ['id', 'title'],
  'line': ['id', 'bookId', 'lineIndex', 'content'],
  'category': ['id', 'parentId', 'title', 'level'],
  'tocText': ['id', 'text'],
  'tocEntry': ['id', 'bookId', 'parentId', 'textId', 'level', 'lineId'],
  'connection_type': ['id', 'name'],
  'link': [
    'sourceBookId',
    'targetBookId',
    'sourceLineId',
    'targetLineId',
    'connectionTypeId',
  ],
  'line_ref': ['bookId', 'lineIndex', 'refKeyHash'],
  'schema_meta': ['key', 'value'],
  'external_link': ['sourceBookId', 'sourceLineIndex', 'targetTitle'],
};

enum Severity { error, warning, info }

class ValidationIssue {
  const ValidationIssue(this.severity, this.code, this.message);

  final Severity severity;

  /// מזהה יציב לבדיקות ולסקריפטים.
  final String code;
  final String message;

  @override
  String toString() => '[${severity.name}] $code: $message';
}

/// תוצאת הבדיקה. [capabilities] ממופתח בשמות ה-getters של `DbCapabilities`.
class PersonalDbReport {
  PersonalDbReport(this.path);

  final String path;
  final List<ValidationIssue> issues = [];
  String? slug;
  String? libraryId;
  String? displayName;
  String? dbVersion;
  bool isWal = false;
  bool pendingJournal = false;
  bool openedImmutable = false;
  int? bookCount;
  int? externalLinkRows;
  final Set<String> knownTables = {};
  final Set<String> ignoredTables = {};
  final Set<String> impostors = {};
  final Map<String, bool> capabilities = {};

  bool get hasErrors => issues.any((i) => i.severity == Severity.error);

  void _add(Severity severity, String code, String message) =>
      issues.add(ValidationIssue(severity, code, message));
}

class _Caps {
  _Caps(this.tables, this.columns, this.indexes);

  final Set<String> tables;
  final Map<String, Set<String>> columns;
  final Set<String> indexes;

  bool has(String t) => tables.contains(t.toLowerCase());
  bool col(String t, String c) =>
      columns[t.toLowerCase()]?.contains(c.toLowerCase()) ?? false;

  // אותם כללים כמו ב-DbCapabilities.
  Map<String, bool> flags() {
    final books = has('book');
    final lines = books && has('line');
    final categories = has('category');
    final toc = lines && has('tocEntry') && has('tocText');
    final altToc =
        lines &&
        has('alt_toc_structure') &&
        has('alt_toc_entry') &&
        has('tocText');
    final links = lines && has('link') && has('connection_type');
    return {
      'hasBooks': books,
      'hasLines': lines,
      'hasCategories': categories,
      'hasBookCategories': categories && col('book', 'categoryId'),
      'hasToc': toc,
      'hasLineToc': toc && has('line_toc'),
      'hasAltTocStructures': books && has('alt_toc_structure'),
      'hasAltToc': altToc,
      'hasLineAltToc': altToc && has('line_alt_toc'),
      'hasLinks': links,
      'hasLinkAnchors': links && has('link_anchor'),
      'hasLinkRanges': links && has('link_range') && has('link_coverage'),
      'hasLinkSuppressedSide': links && has('link_suppressed_side'),
      'hasBookVersions': books && has('book_version') && has('version_line'),
      'hasLineRef': lines && has('line_ref'),
      'hasLineDhDisplay': books && col('line_dh', 'dhDisplay'),
      'hasLineBookIndex': indexes.contains('idx_line_book_index'),
      'hasAuthors': books && has('author') && has('book_author'),
      'hasTopics': books && has('topic') && has('book_topic'),
      'hasPubPlaces': books && has('pub_place') && has('book_pub_place'),
      'hasPubDates': books && has('pub_date') && has('book_pub_date'),
      'hasGenerations': books && has('generation') && has('book_generation'),
      'hasAcronyms': books && has('book_acronym'),
      'hasDefaultCommentators': books && has('default_commentator'),
      'hasDefaultTargums': books && has('default_targum'),
      'hasCategoryClosure': categories && has('category_closure'),
      'hasExternalLinks':
          books &&
          col('external_link', 'sourceBookId') &&
          col('external_link', 'sourceLineIndex') &&
          col('external_link', 'targetTitle'),
    };
  }
}

/// פיצ'רים שדורשים כמה טבלאות יחד: (שם, טבלאות שמעידות על כוונה, דגל).
const List<(String, List<String>, List<String>, String)> _featureGroups = [
  ('lines', ['line'], ['book', 'line'], 'hasLines'),
  ('toc', ['tocEntry'], ['line', 'tocEntry', 'tocText'], 'hasToc'),
  ('line_toc', ['line_toc'], ['tocEntry', 'tocText'], 'hasLineToc'),
  (
    'alt toc',
    ['alt_toc_entry'],
    ['line', 'alt_toc_structure', 'alt_toc_entry', 'tocText'],
    'hasAltToc',
  ),
  ('line_alt_toc', ['line_alt_toc'], ['alt_toc_entry'], 'hasLineAltToc'),
  (
    'links',
    ['link', 'connection_type'],
    ['line', 'link', 'connection_type'],
    'hasLinks',
  ),
  ('link anchors', ['link_anchor'], ['link'], 'hasLinkAnchors'),
  (
    'link ranges',
    ['link_range', 'link_coverage'],
    ['link', 'link_range', 'link_coverage'],
    'hasLinkRanges',
  ),
  (
    'link suppressed side',
    ['link_suppressed_side'],
    ['link'],
    'hasLinkSuppressedSide',
  ),
  (
    'versions',
    ['book_version', 'version_line'],
    ['book_version', 'version_line'],
    'hasBookVersions',
  ),
  ('line_ref', ['line_ref'], ['line'], 'hasLineRef'),
  (
    'authors',
    ['author', 'book_author'],
    ['author', 'book_author'],
    'hasAuthors',
  ),
  ('topics', ['topic', 'book_topic'], ['topic', 'book_topic'], 'hasTopics'),
  (
    'publication places',
    ['pub_place', 'book_pub_place'],
    ['pub_place', 'book_pub_place'],
    'hasPubPlaces',
  ),
  (
    'publication dates',
    ['pub_date', 'book_pub_date'],
    ['pub_date', 'book_pub_date'],
    'hasPubDates',
  ),
  (
    'generations',
    ['generation', 'book_generation'],
    ['generation', 'book_generation'],
    'hasGenerations',
  ),
  (
    'category closure',
    ['category_closure'],
    ['category'],
    'hasCategoryClosure',
  ),
];

/// עותק של `AttachedLibraryProbe.sanitizeSlug`.
String validatorSanitizeSlug(String raw) {
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

/// עותק של `AttachedLibraryProbe.slugFor`.
String validatorSlugFor({String? libraryId, required String fileName}) {
  final fromId = libraryId?.trim();
  if (fromId != null && fromId.isNotEmpty) {
    final slug = validatorSanitizeSlug(fromId);
    if (slug.isNotEmpty) return slug;
  }
  final slug = validatorSanitizeSlug(fileName);
  return slug.isEmpty ? 'db' : slug;
}

/// בודק את [path] בלי לכתוב אליו. [checkFiles] — בודק גם שקובצי
/// `book.filePath` קיימים בדיסק.
PersonalDbReport validatePersonalDb(String path, {bool checkFiles = true}) {
  final report = PersonalDbReport(path);
  final file = File(path);
  if (!file.existsSync()) {
    report._add(Severity.error, 'not_found', 'File not found.');
    return report;
  }

  final header = _readHeader(path);
  if (header == null) {
    report._add(Severity.error, 'not_sqlite', 'Not an SQLite 3 database.');
    return report;
  }
  report.isWal = header;
  report.pendingJournal = _pendingJournal(path);
  if (report.pendingJournal) {
    report._add(
      Severity.error,
      'pending_journal',
      'A non-empty -wal or -journal file sits next to the database. '
          'Linking will be refused. Close every program that writes to it, '
          'or run "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;".',
    );
  } else if (report.isWal) {
    report._add(
      Severity.warning,
      'wal_mode',
      'The database is in WAL mode. It will be opened immutable (no locking; '
          'the file must not change while attached). Prefer '
          '"PRAGMA journal_mode=DELETE;" before distributing.',
    );
  }

  var immutable = report.isWal;
  var db = _tryOpen(path, immutable: immutable);
  if (db == null && !immutable) {
    immutable = true;
    db = _tryOpen(path, immutable: true);
  }
  if (db == null) {
    report._add(Severity.error, 'open_failed', 'Could not open read-only.');
    return report;
  }
  report.openedImmutable = immutable;

  try {
    final caps = _probe(db, report);
    report.capabilities.addAll(caps.flags());
    _checkColumns(caps, report);
    _checkGroups(caps, report);
    if (!caps.has('book')) {
      report._add(
        Severity.error,
        'no_books',
        'No real "book" table — the database will be rejected.',
      );
      return report;
    }
    _readMeta(db, caps, report);
    report.bookCount = _count(db, 'SELECT COUNT(*) FROM book');
    if (report.bookCount == 0) {
      report._add(Severity.warning, 'empty', 'The "book" table is empty.');
    }
    if (caps.has('line') && !caps.indexes.contains('idx_line_book_index')) {
      report._add(
        Severity.warning,
        'missing_line_index',
        'Missing index idx_line_book_index ON line(bookId, lineIndex): '
            'reading and search will be slow.',
      );
    }
    _checkFilePaths(db, caps, report, checkFiles: checkFiles);
    _checkExternalLinks(db, caps, report);
  } on SqliteException catch (e) {
    report._add(Severity.error, 'sqlite_error', e.message);
  } finally {
    db.close();
  }
  return report;
}

/// null — אינו SQLite; אחרת האם הכותרת מסמנת WAL.
bool? _readHeader(String path) {
  const magic = 'SQLite format 3';
  final raf = File(path).openSync();
  try {
    final bytes = raf.readSync(100);
    if (bytes.length < 100) return null;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) return null;
    }
    if (bytes[magic.length] != 0) return null;
    return bytes[18] == 2 || bytes[19] == 2;
  } finally {
    raf.closeSync();
  }
}

bool _pendingJournal(String path) {
  bool nonEmpty(String side) {
    final f = File(side);
    return f.existsSync() && f.lengthSync() > 0;
  }

  return nonEmpty('$path-wal') || nonEmpty('$path-journal');
}

// אותה הקשחה כמו openUntrustedReadOnlyDatabase.
Database? _tryOpen(String path, {required bool immutable}) {
  Database? db;
  try {
    db = immutable
        ? sqlite3.open(
            Uri.file(path)
                .replace(
                  queryParameters: {'mode': 'ro', 'immutable': '1'},
                )
                .toString(),
            mode: OpenMode.readOnly,
            uri: true,
          )
        : sqlite3.open(path, mode: OpenMode.readOnly);
    for (final (key, value) in const [(1010, 1), (1017, 0), (1005, 0)]) {
      try {
        db.config.setIntConfig(key, value);
      } on Object {
        // גרסת SQLite שאינה מכירה את האפשרות.
      }
    }
    db.execute('PRAGMA trusted_schema=OFF');
    db.execute('PRAGMA query_only=ON');
    db.execute('PRAGMA mmap_size=0');
    db.select('PRAGMA schema_version');
    return db;
  } on SqliteException {
    db?.close();
    return null;
  }
}

_Caps _probe(Database db, PersonalDbReport report) {
  final known = {for (final t in kValidatorKnownTables) t.toLowerCase()};
  final tables = <String>{};
  final indexes = <String>{};
  final rows = db.select(
    "SELECT type, name, sql FROM sqlite_master "
    "WHERE type IN ('table', 'index', 'view')",
  );
  for (final row in rows) {
    final name = row['name'] as String?;
    if (name == null) continue;
    final lower = name.toLowerCase();
    final type = row['type'] as String?;
    if (type == 'index') {
      indexes.add(lower);
      continue;
    }
    final sql = (row['sql'] as String?)?.trimLeft().toUpperCase() ?? '';
    final isImpostor = type == 'view' || sql.startsWith('CREATE VIRTUAL');
    if (!known.contains(lower)) {
      if (!lower.startsWith('sqlite_')) report.ignoredTables.add(name);
      continue;
    }
    if (isImpostor) {
      report.impostors.add(name);
      continue;
    }
    tables.add(lower);
    report.knownTables.add(name);
  }
  for (final name in report.impostors) {
    report._add(
      Severity.warning,
      'impostor',
      '"$name" is a VIEW or virtual table and is ignored — '
          'create it as a real table.',
    );
  }

  final columns = <String, Set<String>>{};
  for (final t in tables) {
    for (final row in db.select('SELECT name FROM pragma_table_info(?)', [t])) {
      final name = row['name'] as String?;
      if (name == null) continue;
      columns.putIfAbsent(t, () => {}).add(name.toLowerCase());
    }
  }
  return _Caps(tables, columns, indexes);
}

void _checkColumns(_Caps caps, PersonalDbReport report) {
  for (final MapEntry(key: table, value: required)
      in kValidatorCoreColumns.entries) {
    if (!caps.has(table)) continue;
    final missing = [
      for (final c in required)
        if (!caps.col(table, c)) c,
    ];
    if (missing.isEmpty) continue;
    report._add(
      table == 'book' ? Severity.error : Severity.warning,
      'missing_columns',
      'Table "$table" lacks column(s): ${missing.join(', ')}.',
    );
  }
}

void _checkGroups(_Caps caps, PersonalDbReport report) {
  for (final (name, triggers, required, flag) in _featureGroups) {
    if (!triggers.any(caps.has)) continue;
    if (report.capabilities[flag] == true) continue;
    final missing = [
      for (final t in required)
        if (!caps.has(t)) t,
    ];
    report._add(
      Severity.warning,
      'incomplete_group',
      'Feature "$name" is disabled'
          '${missing.isEmpty ? '' : ': missing ${missing.join(', ')}'}.',
    );
  }
  if (caps.has('category') && !caps.col('book', 'categoryId')) {
    report._add(
      Severity.warning,
      'incomplete_group',
      'Table "category" exists but book.categoryId does not — '
          'all books will sit under the database root.',
    );
  }
  if (caps.has('external_link') &&
      report.capabilities['hasExternalLinks'] != true) {
    report._add(
      Severity.warning,
      'incomplete_group',
      'Table "external_link" is ignored: it needs sourceBookId, '
          'sourceLineIndex and targetTitle.',
    );
  }
}

void _readMeta(Database db, _Caps caps, PersonalDbReport report) {
  final meta = <String, String>{};
  if (caps.col('schema_meta', 'key') && caps.col('schema_meta', 'value')) {
    final rows = db.select(
      'SELECT key, value FROM schema_meta '
      "WHERE key IN ('library_id', 'library_name', 'db_version')",
    );
    for (final row in rows) {
      final value = row['value']?.toString().trim();
      if (row['key'] is String && value != null && value.isNotEmpty) {
        meta[row['key'] as String] = value;
      }
    }
  }
  final baseName = p.basenameWithoutExtension(report.path);
  report.libraryId = meta['library_id'];
  report.displayName = meta['library_name'] ?? baseName;
  report.dbVersion = meta['db_version'];
  report.slug = validatorSlugFor(
    libraryId: report.libraryId,
    fileName: baseName,
  );
  final id = report.libraryId;
  if (id == null) {
    report._add(
      Severity.info,
      'no_library_id',
      'No schema_meta.library_id — the identity comes from the file name, '
          'so renaming the file orphans bookmarks and history.',
    );
  } else if (validatorSanitizeSlug(id) != id) {
    report._add(
      Severity.warning,
      'library_id_normalized',
      'library_id "$id" is used as "${report.slug}". Use only lowercase '
          'letters, digits, ".", "_" and "-" (up to 64).',
    );
  }
  if (report.dbVersion == null) {
    report._add(
      Severity.info,
      'no_db_version',
      'No schema_meta.db_version — changes are detected by size and date only.',
    );
  }
}

void _checkFilePaths(
  Database db,
  _Caps caps,
  PersonalDbReport report, {
  required bool checkFiles,
}) {
  if (!caps.col('book', 'filePath')) return;
  final rejected = <int>[];
  final missing = <int>[];
  for (final row in db.select(
    "SELECT id, filePath FROM book WHERE COALESCE(TRIM(filePath), '') <> ''",
  )) {
    final id = row['id'] as int? ?? -1;
    final resolved = resolveAttachedBookFilePath(
      report.path,
      row['filePath']?.toString(),
    );
    if (resolved == null) {
      rejected.add(id);
    } else if (checkFiles && !File(resolved).existsSync()) {
      missing.add(id);
    }
  }
  String sample(List<int> ids) =>
      '${ids.take(10).join(', ')}${ids.length > 10 ? ', …' : ''}';
  if (rejected.isNotEmpty) {
    report._add(
      Severity.error,
      'file_path_rejected',
      '${rejected.length} book(s) have a filePath that is absolute, UNC, '
          'contains ":" or "..", or leaves the database folder (book id: '
          '${sample(rejected)}). These books will not open.',
    );
  }
  if (missing.isNotEmpty) {
    report._add(
      Severity.warning,
      'file_missing',
      '${missing.length} book file(s) not found next to the database '
          '(book id: ${sample(missing)}).',
    );
  }
}

void _checkExternalLinks(Database db, _Caps caps, PersonalDbReport report) {
  if (report.capabilities['hasExternalLinks'] != true) return;
  final rows = _count(
    db,
    'SELECT COUNT(*) FROM '
    '(SELECT 1 FROM external_link LIMIT ${kValidatorMaxExternalLinkRows + 1})',
  );
  report.externalLinkRows = rows;
  if (rows > kValidatorMaxExternalLinkRows) {
    report._add(
      Severity.error,
      'external_link_too_large',
      'external_link has more than $kValidatorMaxExternalLinkRows rows — '
          'all of its links will be skipped.',
    );
    return;
  }
  final hasIndex = db
      .select("SELECT name FROM pragma_index_list('external_link')")
      .any((index) {
        final cols = db
            .select('SELECT name FROM pragma_index_info(?) ORDER BY seqno', [
              index['name'],
            ])
            .map((r) => (r['name'] as String?)?.toLowerCase())
            .toList();
        return cols.length >= 2 &&
            cols[0] == 'sourcebookid' &&
            cols[1] == 'sourcelineindex';
      });
  if (!hasIndex && rows > 0) {
    report._add(
      Severity.warning,
      'external_link_no_index',
      'Recommended: CREATE INDEX idx_external_link_source '
          'ON external_link(sourceBookId, sourceLineIndex);',
    );
  }
  final longCheck = [
    'length(targetTitle) > $kValidatorMaxExternalTextLength',
    if (caps.col('external_link', 'targetRef'))
      'length(targetRef) > $kValidatorMaxExternalTextLength',
  ].join(' OR ');
  final long = _count(
    db,
    'SELECT COUNT(*) FROM external_link WHERE $longCheck',
  );
  if (long > 0) {
    report._add(
      Severity.warning,
      'external_link_long_text',
      '$long row(s) have targetTitle/targetRef longer than '
          '$kValidatorMaxExternalTextLength characters; they are cut and '
          'will likely not resolve.',
    );
  }
  final orphans = _count(
    db,
    'SELECT COUNT(*) FROM external_link e '
    'WHERE NOT EXISTS (SELECT 1 FROM book b WHERE b.id = e.sourceBookId) '
    "OR e.sourceLineIndex IS NULL OR COALESCE(TRIM(e.targetTitle), '') = ''",
  );
  if (orphans > 0) {
    report._add(
      Severity.warning,
      'external_link_invalid_rows',
      '$orphans row(s) have no matching source book, no sourceLineIndex or '
          'an empty targetTitle; they are ignored.',
    );
  }
  if (caps.col('external_link', 'connectionType')) {
    final types = db
        .select(
          'SELECT DISTINCT connectionType AS t FROM external_link LIMIT 50',
        )
        .map((r) => LinkTypes.normalize(r['t']?.toString()))
        .map((t) => t.isEmpty ? '(empty => REFERENCE)' : t)
        .toSet();
    report._add(
      Severity.info,
      'external_link_types',
      'connectionType values: ${types.join(', ')}.',
    );
  }
  if (caps.col('external_link', 'targetSource')) {
    final sources = db
        .select('SELECT DISTINCT targetSource AS s FROM external_link LIMIT 50')
        .map((r) => r['s']?.toString().trim() ?? '')
        .toSet();
    final invalid = [
      for (final s in sources)
        if (s.isNotEmpty &&
            s.toLowerCase() != 'official' &&
            validatorSanitizeSlug(s).isEmpty)
          s,
    ];
    if (invalid.isNotEmpty) {
      report._add(
        Severity.warning,
        'external_link_bad_target_source',
        'targetSource value(s) that match no database: ${invalid.join(', ')}.',
      );
    }
  }
}

int _count(Database db, String sql) =>
    (db.select(sql).first.values.first as int?) ?? 0;

/// הדוח כטקסט לקונסולה.
String formatReport(PersonalDbReport report) {
  final b = StringBuffer()
    ..writeln('Database: ${report.path}')
    ..writeln('  slug:          ${report.slug ?? '-'}')
    ..writeln('  library_id:    ${report.libraryId ?? '-'}')
    ..writeln('  display name:  ${report.displayName ?? '-'}')
    ..writeln('  db_version:    ${report.dbVersion ?? '-'}')
    ..writeln(
      '  journal:       ${report.isWal ? 'WAL' : 'rollback'}'
      '${report.openedImmutable ? ' (opened immutable)' : ''}',
    )
    ..writeln('  books:         ${report.bookCount ?? '-'}');
  if (report.externalLinkRows != null) {
    b.writeln(
      '  external_link: ${report.externalLinkRows} / '
      '$kValidatorMaxExternalLinkRows rows',
    );
  }
  final missing = [
    for (final t in kValidatorKnownTables)
      if (!report.knownTables.any((k) => k.toLowerCase() == t.toLowerCase())) t,
  ];
  b
    ..writeln(
      'Tables read (${report.knownTables.length}): '
      '${(report.knownTables.toList()..sort()).join(', ')}',
    )
    ..writeln('Known tables absent (${missing.length}): ${missing.join(', ')}')
    ..writeln(
      'Ignored (not on the allowlist): '
      '${report.ignoredTables.isEmpty ? '-' : (report.ignoredTables.toList()..sort()).join(', ')}',
    );
  if (report.impostors.isNotEmpty) {
    b.writeln('Ignored VIEW/virtual: ${report.impostors.join(', ')}');
  }
  if (report.capabilities.isNotEmpty) {
    b.writeln('Capabilities:');
    for (final MapEntry(:key, :value) in report.capabilities.entries) {
      b.writeln('  ${value ? '[x]' : '[ ]'} $key');
    }
  }
  if (report.issues.isEmpty) {
    b.writeln('No problems found.');
  } else {
    b.writeln('Findings:');
    for (final issue in report.issues) {
      b.writeln('  $issue');
    }
  }
  b.writeln(report.hasErrors ? 'RESULT: FAILED' : 'RESULT: OK');
  return b.toString();
}
