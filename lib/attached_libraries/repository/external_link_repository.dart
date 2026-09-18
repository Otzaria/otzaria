import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

/// קישורים חוצי-מסדים מטבלת `external_link` של מסד מצורף.
///
/// כיוון ישיר (קורא ספר מהמסד המצורף) נפתר בזמן הקריאה. כיוון הפוך (מפרש
/// במסד מצורף מוצג על ספר רשמי) נשען על אינדקס-צד ב-cache.db, שנבנה מחדש רק
/// כשהמסד המצורף או אחד ממסדי היעד השתנה.
class ExternalLinkRepository {
  ExternalLinkRepository({
    AttachedLibraryRegistry? registry,
    Future<String> Function()? cacheDbPath,
    ReadOnlyDbTarget? Function()? officialTarget,
  }) : _registryOverride = registry,
       _cacheDbPath = cacheDbPath ?? CacheDatabaseHolder.resolveDbPath,
       _officialTargetOverride = officialTarget;

  static ExternalLinkRepository instance = ExternalLinkRepository();

  final AttachedLibraryRegistry? _registryOverride;
  final Future<String> Function() _cacheDbPath;
  final ReadOnlyDbTarget? Function()? _officialTargetOverride;

  Future<String?>? _officialVersion;
  Future<void> _tail = Future.value();
  bool _syncOnNextUse = false;

  AttachedLibraryRegistry get _registry =>
      _registryOverride ?? AttachedLibraryRegistry.instance;

  List<AttachedLibrary> get _withExternalLinks => [
    for (final library in _registry.libraries)
      if (library.isOk &&
          library.fingerprint != null &&
          library.capabilities.contains(
            AttachedLibraryCapability.externalLinks,
          ))
        library,
  ];

  /// מנקה את מצב הזיכרון אחרי בנייה מחדש של הריצה (למשל עדכון ספרייה). האינדקס
  /// נבנה שוב בשימוש הבא, כי גרסת המסד הרשמי עשויה להשתנות.
  void resetRuntime() {
    _officialVersion = null;
    _syncOnNextUse = true;
  }

  static String fingerprintKey(AttachedLibraryFingerprint fingerprint) =>
      '${fingerprint.size}:${fingerprint.modifiedMs}:'
      '${fingerprint.dbVersion ?? ''}';

  ReadOnlyDbTarget? _officialDb() {
    final override = _officialTargetOverride;
    if (override != null) return override();
    final sqlite = SqliteDataProvider.instance;
    if (!sqlite.isInitialized || sqlite.repository == null) return null;
    return trustedDbTarget(sqlite.dbPath);
  }

  Future<String?> _currentOfficialVersion() {
    return _officialVersion ??= () async {
      final target = _officialDb();
      String? version;
      if (target != null) {
        try {
          version = await Isolate.run(() => _readOfficialVersion(target));
        } catch (e) {
          debugPrint('[ExternalLinks] official version: $e');
        }
      }
      // אין מסד — לא שומרים null לתמיד; ננסה שוב בפעם הבאה.
      if (version == null) _officialVersion = null;
      return version;
    }();
  }

  Future<List<ExternalTargetDb>> _targets() async {
    final officialVersion = await _currentOfficialVersion();
    final officialDb = officialVersion == null ? null : _officialDb();
    return [
      if (officialDb != null)
        (
          wireKey: BookSource.official.wireKey,
          slug: null,
          target: officialDb,
          version: officialVersion!,
        ),
      for (final library in _registry.libraries)
        if (library.isOk && library.fingerprint != null)
          (
            wireKey: BookSource.attached(library.slug).wireKey,
            slug: library.slug,
            target: (
              path: library.path,
              untrusted: true,
              immutable: library.immutable,
            ),
            version: fingerprintKey(library.fingerprint!),
          ),
    ];
  }

  /// הגרסה הנוכחית של המסד [source] — שורות אינדקס שנפתרו מול גרסה אחרת לא
  /// מוגשות.
  Future<String?> _versionOf(BookSource source) async => switch (source) {
    OfficialBookSource() => await _currentOfficialVersion(),
    AttachedBookSource(:final slug) => switch (_registry
        .libraryFor(slug)
        ?.fingerprint) {
      final fingerprint? => fingerprintKey(fingerprint),
      null => null,
    },
    UserBookSource() => null,
  };

  /// הקישורים החיצוניים של ספר בטווח השורות (0-based, כולל): הישירים כשהספר
  /// ממסד מצורף, וההפוכים מכל מסד מצורף שמצביע אליו. כשל מחזיר ריק.
  Future<List<Link>> linksInRange({
    required String title,
    required int? categoryId,
    required BookSource source,
    required int startLineIndex,
    required int endLineIndex,
    List<String>? targetBookTitles,
  }) async {
    if (source.isUser) return const [];
    try {
      if (_withExternalLinks.isEmpty) return const [];
      final links = [
        ...await _forwardLinks(
          title,
          categoryId,
          source,
          startLineIndex,
          endLineIndex,
        ),
        ...await _reverseLinks(
          title,
          categoryId,
          source,
          startLineIndex,
          endLineIndex,
        ),
      ];
      return _filterCommentators(links, targetBookTitles);
    } catch (e) {
      debugPrint('[ExternalLinks] "$title": $e');
      return const [];
    }
  }

  Future<List<Link>> _forwardLinks(
    String title,
    int? categoryId,
    BookSource source,
    int start,
    int end,
  ) async {
    final slug = source.attachedSlug;
    final library = slug == null ? null : _registry.libraryFor(slug);
    if (library == null ||
        !library.capabilities.contains(
          AttachedLibraryCapability.externalLinks,
        )) {
      return const [];
    }
    final targets = await _targets();
    final sourceTarget = (
      path: library.path,
      untrusted: true,
      immutable: library.immutable,
    );
    final sourceWireKey = source.wireKey;
    final rows = await Isolate.run(
      () => readResolvedExternalLinks(
        source: sourceTarget,
        sourceWireKey: sourceWireKey,
        targets: targets,
        book: (title: title, categoryId: categoryId),
        lineRange: (start, end),
      ),
    );
    return [
      for (final row in rows)
        Link(
          heRef: row.targetHeRef ?? row.targetTitle,
          index1: row.sourceLineIndex + 1,
          path2: row.targetTitle,
          index2: row.targetLineIndex + 1,
          connectionType: row.connectionType,
          targetCategoryId: row.targetCategoryId,
          targetBookId: row.targetBookId,
          targetSource:
              BookSource.tryParse(row.targetWireKey) ?? BookSource.official,
        ),
    ];
  }

  Future<List<Link>> _reverseLinks(
    String title,
    int? categoryId,
    BookSource source,
    int start,
    int end,
  ) async {
    _maybeSyncAfterReset();
    final served = _servedSources(exclude: source);
    final version = await _versionOf(source);
    if (served.isEmpty || version == null) return const [];
    final path = await _cacheDbPath();
    final targetWireKey = source.wireKey;
    final rows = await Isolate.run(
      () => _queryReverseRows(
        path,
        served: served,
        targetWireKey: targetWireKey,
        targetVersion: version,
        targetTitle: title,
        targetCategoryId: categoryId,
        lineRange: (start, end),
      ),
    );
    return [
      for (final row in rows)
        Link(
          heRef: row.sourceHeRef ?? row.sourceTitle,
          index1: row.targetLineIndex + 1,
          path2: row.sourceTitle,
          index2: row.sourceLineIndex + 1,
          connectionType: inverseExternalConnectionType(row.connectionType),
          targetCategoryId: row.sourceCategoryId,
          targetBookId: row.sourceBookId,
          targetSource: BookSource.attached(row.sourceSlug),
        ),
    ];
  }

  /// slug → טביעת האצבע, לכל מסד מצורף תקין שאינו [exclude]. שורות של מסד לא
  /// נגיש, או שנבנו מגרסה אחרת שלו, אינן מוגשות.
  Map<String, String> _servedSources({BookSource? exclude}) => {
    for (final library in _withExternalLinks)
      if (library.slug != exclude?.attachedSlug)
        library.slug: fingerprintKey(library.fingerprint!),
  };

  /// המפרשים שמקורם בקישורים חיצוניים, עם המסד שממנו כל אחד — לסיווג לדורות
  /// לפי המסד שלו.
  Future<Map<String, BookSource>> commentatorSources({
    required String title,
    required int? categoryId,
    required BookSource source,
  }) async {
    if (source.isUser) return const {};
    final result = <String, BookSource>{};
    try {
      if (_withExternalLinks.isEmpty) return const {};
      final slug = source.attachedSlug;
      final library = slug == null ? null : _registry.libraryFor(slug);
      if (library != null &&
          library.capabilities.contains(
            AttachedLibraryCapability.externalLinks,
          )) {
        final targets = await _targets();
        final sourceTarget = (
          path: library.path,
          untrusted: true,
          immutable: library.immutable,
        );
        final sourceWireKey = source.wireKey;
        final rows = await Isolate.run(
          () => readExternalLinkTargets(
            source: sourceTarget,
            sourceWireKey: sourceWireKey,
            targets: targets,
            title: title,
            categoryId: categoryId,
          ),
        );
        for (final row in rows) {
          if (!LinkTypes.isDependentTextLink(row.connectionType)) continue;
          final target = BookSource.tryParse(row.targetWireKey);
          if (target != null) result.putIfAbsent(row.targetTitle, () => target);
        }
      }

      final served = _servedSources(exclude: source);
      final version = await _versionOf(source);
      if (served.isNotEmpty && version != null) {
        final path = await _cacheDbPath();
        final targetWireKey = source.wireKey;
        final rows = await Isolate.run(
          () => _queryReverseRows(
            path,
            served: served,
            targetWireKey: targetWireKey,
            targetVersion: version,
            targetTitle: title,
            targetCategoryId: categoryId,
            connectionType: LinkTypes.source,
          ),
        );
        for (final row in rows) {
          result.putIfAbsent(
            row.sourceTitle,
            () => BookSource.attached(row.sourceSlug),
          );
        }
      }
    } catch (e) {
      debugPrint('[ExternalLinks] commentators "$title": $e');
    }
    return result;
  }

  void _maybeSyncAfterReset() {
    if (!_syncOnNextUse || WindowRole.isSecondary) return;
    _syncOnNextUse = false;
    unawaited(
      sync().then<void>(
        (_) {},
        onError: (Object e) => debugPrint('[ExternalLinks] sync failed: $e'),
      ),
    );
  }

  /// בונה מחדש את אינדקס הכיוון ההפוך לכל מסד שהשתנה (או שמסד יעד שלו
  /// השתנה), ומוחק את שורותיו של מסד שהוסר. מסד לא נגיש נשמר כמות שהוא.
  /// מחזיר את ה-slugs שנבנו מחדש.
  Future<Set<String>> sync() {
    final result = _tail.then((_) => _sync());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Set<String>> _sync() async {
    final libraries = _registry.libraries;
    final path = await _cacheDbPath();
    if (libraries.isEmpty && !await File(path).exists()) return const {};
    final targets = await _targets();
    final jobs = [
      for (final library in libraries)
        (
          slug: library.slug,
          status: !library.isOk || library.fingerprint == null
              ? _SyncStatus.keep
              : library.capabilities.contains(
                  AttachedLibraryCapability.externalLinks,
                )
              ? _SyncStatus.build
              : _SyncStatus.clear,
          fingerprint: library.fingerprint == null
              ? ''
              : fingerprintKey(library.fingerprint!),
          source: (
            path: library.path,
            untrusted: true,
            immutable: library.immutable,
          ),
        ),
    ];
    return Isolate.run(() => _syncIndex(path, jobs, targets));
  }
}

enum _SyncStatus { build, clear, keep }

typedef _SyncJob = ({
  String slug,
  _SyncStatus status,
  String fingerprint,
  ReadOnlyDbTarget source,
});

typedef _ReverseRow = ({
  String sourceSlug,
  int sourceBookId,
  String sourceTitle,
  int? sourceCategoryId,
  int sourceLineIndex,
  String? sourceHeRef,
  int targetLineIndex,
  String connectionType,
});

const _indexTable = 'attached_external_link_index';
const _metaTable = 'attached_external_link_meta';
const _targetTable = 'attached_external_link_target';

bool _hasTable(sqlite3.Database db, String name) => db.select(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
  [name],
).isNotEmpty;

void _ensureSchema(sqlite3.Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS $_indexTable (
      sourceSlug TEXT NOT NULL,
      sourceBookId INTEGER NOT NULL,
      sourceTitle TEXT NOT NULL,
      sourceCategoryId INTEGER,
      sourceLineIndex INTEGER NOT NULL,
      sourceHeRef TEXT,
      targetSource TEXT NOT NULL,
      targetTitle TEXT NOT NULL,
      targetCategoryId INTEGER,
      targetLineIndex INTEGER NOT NULL,
      connectionType TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_${_indexTable}_target
      ON $_indexTable (targetSource, targetTitle, targetLineIndex);
    CREATE INDEX IF NOT EXISTS idx_${_indexTable}_source
      ON $_indexTable (sourceSlug);
    CREATE TABLE IF NOT EXISTS $_metaTable (
      sourceSlug TEXT PRIMARY KEY,
      fingerprint TEXT NOT NULL,
      targetsSignature TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS $_targetTable (
      sourceSlug TEXT NOT NULL,
      targetSource TEXT NOT NULL,
      targetVersion TEXT NOT NULL,
      PRIMARY KEY (sourceSlug, targetSource)
    );
  ''');
}

sqlite3.Database _openCacheDb(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    // cache.db נכתב גם מחיבורים אחרים; בלי המתנה הבנייה נכשלת על נעילה.
    db.execute('PRAGMA busy_timeout=5000');
  } catch (_) {
    db.close();
    rethrow;
  }
  return db;
}

String? _readOfficialVersion(ReadOnlyDbTarget target) {
  final file = File(target.path);
  if (!file.existsSync()) return null;
  final db = openReadOnlyTarget(target);
  try {
    final hasMeta = db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'schema_meta'",
        )
        .isNotEmpty;
    if (hasMeta) {
      final rows = db.select(
        "SELECT value FROM schema_meta WHERE key = 'db_version'",
      );
      final value = rows.isEmpty ? null : rows.first['value'];
      if (value != null) return 'v:$value';
    }
    final stat = file.statSync();
    return 'f:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  } finally {
    db.close();
  }
}

List<_ReverseRow> _queryReverseRows(
  String path, {
  required Map<String, String> served,
  required String targetWireKey,
  required String targetVersion,
  required String targetTitle,
  required int? targetCategoryId,
  (int, int)? lineRange,
  String? connectionType,
}) {
  if (!File(path).existsSync()) return const [];
  final db = _openCacheDb(path);
  try {
    if (!_hasTable(db, _indexTable)) return const [];
    final pairs = served.entries.toList();
    final pairPlaceholders = List.filled(pairs.length, '(?, ?)').join(', ');
    final rows = db.select(
      '''
      WITH served(slug, fingerprint) AS (VALUES $pairPlaceholders)
      SELECT i.sourceSlug, i.sourceBookId, i.sourceTitle, i.sourceCategoryId,
        i.sourceLineIndex, i.sourceHeRef, i.targetLineIndex, i.connectionType
      FROM $_indexTable i
      JOIN $_metaTable m ON m.sourceSlug = i.sourceSlug
      JOIN served s ON s.slug = m.sourceSlug AND s.fingerprint = m.fingerprint
      JOIN $_targetTable t
        ON t.sourceSlug = i.sourceSlug AND t.targetSource = i.targetSource
      WHERE i.targetSource = ? AND i.targetTitle = ? AND t.targetVersion = ?
        ${targetCategoryId != null ? 'AND i.targetCategoryId = ?' : ''}
        ${lineRange != null ? 'AND i.targetLineIndex BETWEEN ? AND ?' : ''}
        ${connectionType != null ? 'AND i.connectionType = ?' : ''}
      ORDER BY i.targetLineIndex, i.sourceSlug, i.sourceBookId,
        i.sourceLineIndex
      ''',
      [
        for (final pair in pairs) ...[pair.key, pair.value],
        targetWireKey,
        targetTitle,
        targetVersion,
        ?targetCategoryId,
        if (lineRange != null) ...[lineRange.$1, lineRange.$2],
        ?connectionType,
      ],
    );
    return [
      for (final row in rows)
        (
          sourceSlug: row['sourceSlug'] as String,
          sourceBookId: row['sourceBookId'] as int,
          sourceTitle: row['sourceTitle'] as String,
          sourceCategoryId: row['sourceCategoryId'] as int?,
          sourceLineIndex: row['sourceLineIndex'] as int,
          sourceHeRef: row['sourceHeRef'] as String?,
          targetLineIndex: row['targetLineIndex'] as int,
          connectionType: row['connectionType'] as String,
        ),
    ];
  } finally {
    db.close();
  }
}

Set<String> _syncIndex(
  String path,
  List<_SyncJob> jobs,
  List<ExternalTargetDb> targets,
) {
  final db = _openCacheDb(path);
  try {
    // בלי מסדים מצורפים לא יוצרים טבלאות ב-cache.db של משתמש שלא צירף מעולם.
    if (jobs.isEmpty && !_hasTable(db, _metaTable)) return const {};
    _ensureSchema(db);
    final known = {for (final job in jobs) job.slug};
    final stored = {
      for (final row in db.select(
        'SELECT sourceSlug, fingerprint, targetsSignature FROM $_metaTable',
      ))
        row['sourceSlug'] as String: (
          row['fingerprint'] as String,
          row['targetsSignature'] as String,
        ),
    };

    void clear(String slug) {
      db.execute('DELETE FROM $_indexTable WHERE sourceSlug = ?', [slug]);
      db.execute('DELETE FROM $_targetTable WHERE sourceSlug = ?', [slug]);
      db.execute('DELETE FROM $_metaTable WHERE sourceSlug = ?', [slug]);
    }

    for (final slug in stored.keys) {
      if (!known.contains(slug)) _transaction(db, () => clear(slug));
    }

    final rebuilt = <String>{};
    for (final job in jobs) {
      switch (job.status) {
        case _SyncStatus.keep:
          continue;
        case _SyncStatus.clear:
          if (stored.containsKey(job.slug)) {
            _transaction(db, () => clear(job.slug));
          }
          continue;
        case _SyncStatus.build:
          break;
      }
      final wireKey = BookSource.attached(job.slug).wireKey;
      final jobTargets = [
        for (final t in targets)
          if (t.wireKey != wireKey) t,
      ];
      final signature = [
        for (final t in jobTargets) '${t.wireKey}=${t.version}',
      ].join(';');
      final previous = stored[job.slug];
      if (previous != null &&
          previous.$1 == job.fingerprint &&
          previous.$2 == signature) {
        continue;
      }
      List<ResolvedExternalLink> rows;
      try {
        rows = readResolvedExternalLinks(
          source: job.source,
          sourceWireKey: wireKey,
          targets: jobTargets,
        );
      } catch (_) {
        // מסד שלא נקרא כעת — נשאר עם השורות הקודמות, וננסה בסנכרון הבא.
        continue;
      }
      _transaction(db, () {
        clear(job.slug);
        final insert = db.prepare(
          'INSERT INTO $_indexTable (sourceSlug, sourceBookId, sourceTitle, '
          'sourceCategoryId, sourceLineIndex, sourceHeRef, targetSource, '
          'targetTitle, targetCategoryId, targetLineIndex, connectionType) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        try {
          for (final r in rows) {
            insert.execute([
              job.slug,
              r.sourceBookId,
              r.sourceTitle,
              r.sourceCategoryId,
              r.sourceLineIndex,
              r.sourceHeRef,
              r.targetWireKey,
              r.targetTitle,
              r.targetCategoryId,
              r.targetLineIndex,
              r.connectionType,
            ]);
          }
        } finally {
          insert.close();
        }
        for (final t in jobTargets) {
          db.execute('INSERT INTO $_targetTable VALUES (?, ?, ?)', [
            job.slug,
            t.wireKey,
            t.version,
          ]);
        }
        db.execute('INSERT INTO $_metaTable VALUES (?, ?, ?)', [
          job.slug,
          job.fingerprint,
          signature,
        ]);
      });
      rebuilt.add(job.slug);
    }
    return rebuilt;
  } finally {
    db.close();
  }
}

void _transaction(sqlite3.Database db, void Function() body) {
  db.execute('BEGIN IMMEDIATE');
  try {
    body();
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

List<Link> _filterCommentators(List<Link> links, List<String>? selected) {
  if (selected == null) return links;
  final titles = selected.toSet();
  return [
    for (final link in links)
      if (!LinkTypes.isDependentTextLink(link.connectionType) ||
          titles.contains(link.path2))
        link,
  ];
}
