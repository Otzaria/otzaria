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
    final existing = _officialVersion;
    if (existing != null) return existing;
    final future = _readCurrentOfficialVersion();
    _officialVersion = future;
    // אין מסד — לא שומרים null לתמיד; ננסה שוב בפעם הבאה.
    future.then((version) {
      if (version == null && identical(_officialVersion, future)) {
        _officialVersion = null;
      }
    });
    return future;
  }

  Future<String?> _readCurrentOfficialVersion() async {
    final target = _officialDb();
    if (target == null) return null;
    try {
      return await _inIsolate(_readOfficialVersion, target);
    } catch (e) {
      debugPrint('[ExternalLinks] official version: $e');
      return null;
    }
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
        for (final row in await _forwardBookRows(title, categoryId, source))
          if (row.sourceLineIndex >= startLineIndex &&
              row.sourceLineIndex <= endLineIndex)
            _forwardLink(row),
        for (final row in await _reverseRows(
          title,
          categoryId,
          source,
          lineRange: (startLineIndex, endLineIndex),
        ))
          _reverseLink(row),
      ];
      return _filterCommentators(links, targetBookTitles);
    } catch (e) {
      debugPrint('[ExternalLinks] "$title": $e');
      return const [];
    }
  }

  static Link _forwardLink(ResolvedExternalLink row) => Link(
    heRef: row.targetHeRef ?? row.targetTitle,
    index1: row.sourceLineIndex + 1,
    path2: row.targetTitle,
    index2: row.targetLineIndex + 1,
    connectionType: row.connectionType,
    targetCategoryId: row.targetCategoryId,
    targetBookId: row.targetBookId,
    targetSource: BookSource.tryParse(row.targetWireKey) ?? BookSource.official,
  );

  static Link _reverseLink(_ReverseRow row) => Link(
    heRef: row.sourceHeRef ?? row.sourceTitle,
    index1: row.targetLineIndex + 1,
    path2: row.sourceTitle,
    index2: row.sourceLineIndex + 1,
    connectionType: inverseExternalConnectionType(row.connectionType),
    targetCategoryId: row.sourceCategoryId,
    targetBookId: row.sourceBookId,
    targetSource: BookSource.attached(row.sourceSlug),
  );

  /// סיכום הקישורים החיצוניים של הספר כולו לפי (יעד, סוג), מנקודת המבט של
  /// הספר הנקרא, והשורה הגבוהה ביותר שיש עליה קישור (1-based; 0 אם אין).
  Future<({List<LinkTargetSummary> targets, int maxSourceLine})>
  targetsSummary({
    required String title,
    required int? categoryId,
    required BookSource source,
  }) async {
    const empty = (targets: <LinkTargetSummary>[], maxSourceLine: 0);
    if (source.isUser) return empty;
    try {
      if (_withExternalLinks.isEmpty) return empty;
      final counts = <(String, String, BookSource), int>{};
      var maxLine = -1;
      void add(String target, String type, BookSource targetSource, int line) {
        final key = (target, type, targetSource);
        counts[key] = (counts[key] ?? 0) + 1;
        if (line > maxLine) maxLine = line;
      }

      for (final row in await _forwardBookRows(title, categoryId, source)) {
        add(
          row.targetTitle,
          row.connectionType,
          BookSource.tryParse(row.targetWireKey) ?? BookSource.official,
          row.sourceLineIndex,
        );
      }
      for (final row in await _reverseRows(title, categoryId, source)) {
        add(
          row.sourceTitle,
          inverseExternalConnectionType(row.connectionType),
          BookSource.attached(row.sourceSlug),
          row.targetLineIndex,
        );
      }
      return (
        targets: [
          for (final MapEntry(key: (target, type, targetSource), :value)
              in counts.entries)
            LinkTargetSummary(
              targetTitle: target,
              connectionType: type,
              linkCount: value,
              targetSource: targetSource,
            ),
        ],
        maxSourceLine: maxLine + 1,
      );
    } catch (e) {
      debugPrint('[ExternalLinks] summary "$title": $e');
      return empty;
    }
  }

  /// הקישורים הישירים של הספר כולו, פתורים — נשמרים לפי ספר וגרסאות המסדים,
  /// כך שגלילה אינה פותחת מחדש את מסדי היעד בכל חלון.
  Future<List<ResolvedExternalLink>> _forwardBookRows(
    String title,
    int? categoryId,
    BookSource source,
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
    final key = _cacheKey([
      source.wireKey,
      library.path,
      if (library.fingerprint case final fingerprint?)
        fingerprintKey(fingerprint),
      for (final t in targets) '${t.wireKey}=${t.version}',
      title,
      '$categoryId',
    ]);
    final cached = _forwardCache.remove(key);
    if (cached != null) return _forwardCache[key] = cached;

    final sourceTarget = (
      path: library.path,
      untrusted: true,
      immutable: library.immutable,
    );
    final future = _inIsolate(
      _forwardRows,
      (sourceTarget, source.wireKey, targets, title, categoryId),
    );
    _forwardCache[key] = future;
    if (_forwardCache.length > _forwardCacheSize) {
      _forwardCache.remove(_forwardCache.keys.first);
    }
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_forwardCache[key], future)) _forwardCache.remove(key);
      },
    );
    return future;
  }

  static const _forwardCacheSize = 8;
  final Map<String, Future<List<ResolvedExternalLink>>> _forwardCache = {};

  /// שורות האינדקס ההפוך שמצביעות אל הספר. בלי [lineRange] — הספר כולו.
  Future<List<_ReverseRow>> _reverseRows(
    String title,
    int? categoryId,
    BookSource source, {
    (int, int)? lineRange,
    String? connectionType,
  }) async {
    _maybeSyncAfterReset();
    final served = _servedSources(exclude: source);
    if (served.isEmpty) return const [];
    final version = await _versionOf(source);
    if (version == null) return const [];
    final path = await _cacheDbPath();
    final targetWireKey = source.wireKey;
    // יציאה מוקדמת בלי isolate על cache.db לספר שאין אליו קישור הפוך.
    final indexed = await _indexedTargets(path, served);
    if (!indexed.contains(_targetKey(targetWireKey, title))) return const [];
    return _inIsolate(_queryReverseRows, (
      path: path,
      served: served,
      targetWireKey: targetWireKey,
      targetVersion: version,
      targetTitle: title,
      targetCategoryId: categoryId,
      lineRange: lineRange,
      connectionType: connectionType,
    ));
  }

  static String _targetKey(String wireKey, String title) =>
      _cacheKey([wireKey, title]);

  /// מפתח מטמון מרכיבים שעשויים להכיל כל תו — מופרדים בתו NUL.
  static String _cacheKey(List<String> parts) => parts.join('\u0000');

  Future<Set<String>> _indexedTargets(
    String path,
    Map<String, String> served,
  ) {
    final key = [
      for (final entry in served.entries) '${entry.key}=${entry.value}',
    ].join(';');
    final cached = _indexedTargetsCache;
    if (cached != null && cached.key == key) return cached.titles;
    final titles = _inIsolate(_queryIndexedTargets, (path, served));
    _indexedTargetsCache = (key: key, titles: titles);
    titles.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_indexedTargetsCache?.titles, titles)) {
          _indexedTargetsCache = null;
        }
      },
    );
    return titles;
  }

  ({String key, Future<Set<String>> titles})? _indexedTargetsCache;

  /// מה שנגזר מהאינדקס ההפוך מתאפס כשהוא נבנה מחדש. המטמון הישיר אינו תלוי
  /// בו — המפתח שלו כולל את גרסאות המסדים.
  void _invalidateIndexCaches() {
    _indexedTargetsCache = null;
    _commentatorSourcesCache.clear();
  }

  /// slug → טביעת האצבע, לכל מסד מצורף תקין שאינו [exclude]. שורות של מסד לא
  /// נגיש, או שנבנו מגרסה אחרת שלו, אינן מוגשות.
  Map<String, String> _servedSources({BookSource? exclude}) => {
    for (final library in _withExternalLinks)
      if (library.slug != exclude?.attachedSlug)
        library.slug: fingerprintKey(library.fingerprint!),
  };

  /// המפרשים שמקורם בקישורים חיצוניים, עם המסד שממנו כל אחד — לסיווג לדורות
  /// לפי המסד שלו. פתיחת ספר מבקשת אותם פעמיים, ולכן התוצאה נשמרת.
  Future<Map<String, BookSource>> commentatorSources({
    required String title,
    required int? categoryId,
    required BookSource source,
  }) {
    if (source.isUser || _withExternalLinks.isEmpty) {
      return Future.value(const {});
    }
    final key = _cacheKey([
      source.wireKey,
      title,
      '$categoryId',
      for (final entry in _servedSources(exclude: source).entries)
        '${entry.key}=${entry.value}',
    ]);
    final cached = _commentatorSourcesCache.remove(key);
    if (cached != null) return _commentatorSourcesCache[key] = cached;
    final future = _readCommentatorSources(title, categoryId, source);
    _commentatorSourcesCache[key] = future;
    if (_commentatorSourcesCache.length > _forwardCacheSize) {
      _commentatorSourcesCache.remove(_commentatorSourcesCache.keys.first);
    }
    return future;
  }

  final Map<String, Future<Map<String, BookSource>>> _commentatorSourcesCache =
      {};

  Future<Map<String, BookSource>> _readCommentatorSources(
    String title,
    int? categoryId,
    BookSource source,
  ) async {
    final result = <String, BookSource>{};
    try {
      for (final row in await _forwardBookRows(title, categoryId, source)) {
        if (!LinkTypes.isDependentTextLink(row.connectionType)) continue;
        final target = BookSource.tryParse(row.targetWireKey);
        if (target != null) result.putIfAbsent(row.targetTitle, () => target);
      }
      for (final row in await _reverseRows(
        title,
        categoryId,
        source,
        connectionType: LinkTypes.source,
      )) {
        result.putIfAbsent(
          row.sourceTitle,
          () => BookSource.attached(row.sourceSlug),
        );
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
    if (libraries.isEmpty) tooLargeSlugs.value = const {};
    // בלי מסדים מצורפים — ניקוי בלבד, ורק אם נבנה אי-פעם אינדקס.
    if (libraries.isEmpty && _indexKnownAbsent) return const {};
    final path = await _cacheDbPath();
    if (libraries.isEmpty && !await File(path).exists()) return const {};
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
    // פתיחת המסדים לחישוב הגרסאות — רק כשיש מה לבנות.
    final targets = jobs.any((job) => job.status == _SyncStatus.build)
        ? await _targets()
        : const <ExternalTargetDb>[];
    try {
      final result = await _inIsolate(_syncIndexEntry, (
        path,
        jobs,
        targets,
        maxIndexRows,
        insertBatchSize,
      ));
      _indexKnownAbsent = jobs.isEmpty && result.hadIndex == false;
      tooLargeSlugs.value = result.tooLarge;
      if (result.rebuilt.isNotEmpty) _invalidateIndexCaches();
      return result.rebuilt;
    } catch (_) {
      _invalidateIndexCaches();
      rethrow;
    }
  }

  /// תקרת השורות למסד אחד בבניית האינדקס — עוברת ל-isolate כארגומנט.
  @visibleForTesting
  static int maxIndexRows = kMaxExternalLinkRows;

  @visibleForTesting
  static int insertBatchSize = kExternalLinkInsertBatchSize;

  /// ה-slugs של מסדים שקישוריהם החיצוניים לא נטענו כי עברו את תקרת השורות.
  final ValueNotifier<Set<String>> tooLargeSlugs = ValueNotifier(const {});

  /// אחרי סנכרון שמצא cache.db בלי אינדקס ובלי מסדים — אין מה לנקות עוד.
  bool _indexKnownAbsent = false;
}

/// מריץ את [computation] ב-isolate. הסגור נבנה כאן, מחוץ למתודת מופע, כדי
/// שלא ילכוד את ההקשר שלה (Future וכד') שאינו עובר את גבול ה-isolate.
Future<R> _inIsolate<A, R>(R Function(A) computation, A argument) =>
    Isolate.run(() => computation(argument));

/// ספר שעבר את התקרה מחזיר ריק (ולא זורק), כדי שהתוצאה תישמר במטמון ולא
/// תיקרא מחדש בכל גלילה.
List<ResolvedExternalLink> _forwardRows(
  (ReadOnlyDbTarget, String, List<ExternalTargetDb>, String, int?) args,
) {
  try {
    return readResolvedExternalLinks(
      source: args.$1,
      sourceWireKey: args.$2,
      targets: args.$3,
      book: (title: args.$4, categoryId: args.$5),
      maxRows: kMaxExternalLinkRowsPerBook,
    );
  } on ExternalLinksTooLargeException {
    return const [];
  }
}

/// כל היעדים (wireKey + כותרת) שיש אליהם שורות מוגשות באינדקס ההפוך.
Set<String> _queryIndexedTargets((String, Map<String, String>) args) {
  final (path, served) = args;
  if (!File(path).existsSync()) return const {};
  final db = _openCacheDb(path);
  try {
    if (!_hasTable(db, _indexTable) || !_hasTable(db, _metaTable)) {
      return const {};
    }
    final pairs = served.entries.toList();
    final pairPlaceholders = List.filled(pairs.length, '(?, ?)').join(', ');
    return {
      for (final row in db.select(
        '''
        WITH served(slug, fingerprint) AS (VALUES $pairPlaceholders)
        SELECT DISTINCT i.targetSource, i.targetTitle
        FROM $_indexTable i
        JOIN $_metaTable m ON m.sourceSlug = i.sourceSlug
        JOIN served s ON s.slug = m.sourceSlug AND s.fingerprint = m.fingerprint
        ''',
        [
          for (final pair in pairs) ...[pair.key, pair.value],
        ],
      ))
        ExternalLinkRepository._targetKey(
          row['targetSource'] as String,
          row['targetTitle'] as String,
        ),
    };
  } finally {
    db.close();
  }
}

_SyncResult _syncIndexEntry(
  (String, List<_SyncJob>, List<ExternalTargetDb>, int, int) args,
) => _syncIndex(
  args.$1,
  args.$2,
  args.$3,
  maxRows: args.$4,
  batchSize: args.$5,
);

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

typedef _ReverseQuery = ({
  String path,
  Map<String, String> served,
  String targetWireKey,
  String targetVersion,
  String targetTitle,
  int? targetCategoryId,
  (int, int)? lineRange,
  String? connectionType,
});

List<_ReverseRow> _queryReverseRows(_ReverseQuery query) {
  final (
    :path,
    :served,
    :targetWireKey,
    :targetVersion,
    :targetTitle,
    :targetCategoryId,
    :lineRange,
    :connectionType,
  ) = query;
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

typedef _SyncResult = ({
  Set<String> rebuilt,
  bool hadIndex,
  Set<String> tooLarge,
});

/// גודל מנת הכנסה — טרנזקציה קצרה, כדי שכותבים אחרים ל-cache.db לא יקבלו BUSY.
const kExternalLinkInsertBatchSize = 5000;

/// סימון שנכתב ל-meta לפני הבנייה: אם הוא נשאר (קריסה, מסד גדול מדי), הבנייה
/// לא תנוסה שוב עד שהקובץ או מסדי היעד ישתנו.
String _buildingMarker(String signature) => '!building:$signature';

/// סימון מסד שעבר את תקרת השורות — קישוריו לא נטענו, והכרטיס שלו מציג זאת.
const _tooLargePrefix = '!toolarge:';
String _tooLargeMarker(String signature) => '$_tooLargePrefix$signature';

_SyncResult _syncIndex(
  String path,
  List<_SyncJob> jobs,
  List<ExternalTargetDb> targets, {
  int maxRows = kMaxExternalLinkRows,
  int batchSize = kExternalLinkInsertBatchSize,
}) {
  final db = _openCacheDb(path);
  try {
    final hadIndex = _hasTable(db, _metaTable);
    // בלי מסדים מצורפים לא יוצרים טבלאות ב-cache.db של משתמש שלא צירף מעולם.
    if (jobs.isEmpty && !hadIndex) {
      return (rebuilt: const {}, hadIndex: false, tooLarge: const {});
    }
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

    void writeMeta(String slug, String fingerprint, String signature) =>
        db.execute('INSERT OR REPLACE INTO $_metaTable VALUES (?, ?, ?)', [
          slug,
          fingerprint,
          signature,
        ]);

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
          (previous.$2 == signature ||
              previous.$2 == _buildingMarker(signature) ||
              previous.$2 == _tooLargeMarker(signature))) {
        continue;
      }
      _transaction(
        db,
        () => writeMeta(job.slug, job.fingerprint, _buildingMarker(signature)),
      );
      // שורות בלי שורת יעד ב-_targetTable אינן מוגשות, ולכן הכתיבה במנות תוך
      // כדי הקריאה אינה חושפת אינדקס חלקי.
      var started = false;
      final batch = <ResolvedExternalLink>[];
      void flush() {
        _transaction(db, () {
          if (!started) {
            db.execute('DELETE FROM $_indexTable WHERE sourceSlug = ?', [
              job.slug,
            ]);
            db.execute('DELETE FROM $_targetTable WHERE sourceSlug = ?', [
              job.slug,
            ]);
            started = true;
          }
          _insertRows(db, job.slug, batch);
        });
        batch.clear();
      }

      try {
        readResolvedExternalLinks(
          source: job.source,
          sourceWireKey: wireKey,
          targets: jobTargets,
          maxRows: maxRows,
          onRow: (row) {
            batch.add(row);
            if (batch.length >= batchSize) flush();
          },
        );
        flush();
      } on ExternalLinksTooLargeException {
        // הסימון נשאר — לא ננסה שוב עד שהקובץ ישתנה.
        _transaction(db, () {
          clear(job.slug);
          writeMeta(job.slug, job.fingerprint, _tooLargeMarker(signature));
        });
        continue;
      } catch (_) {
        // מסד שלא נקרא כעת — ננסה בסנכרון הבא. השורות הקודמות נשמרות רק אם
        // הכתיבה טרם החלה.
        _transaction(db, () {
          if (started) clear(job.slug);
          if (previous == null || started) {
            db.execute('DELETE FROM $_metaTable WHERE sourceSlug = ?', [
              job.slug,
            ]);
          } else {
            writeMeta(job.slug, previous.$1, previous.$2);
          }
        });
        continue;
      }
      _transaction(db, () {
        for (final t in jobTargets) {
          db.execute('INSERT INTO $_targetTable VALUES (?, ?, ?)', [
            job.slug,
            t.wireKey,
            t.version,
          ]);
        }
        writeMeta(job.slug, job.fingerprint, signature);
      });
      rebuilt.add(job.slug);
    }
    final tooLarge = {
      for (final row in db.select(
        'SELECT sourceSlug FROM $_metaTable WHERE targetsSignature LIKE ?',
        ['$_tooLargePrefix%'],
      ))
        row['sourceSlug'] as String,
    };
    return (rebuilt: rebuilt, hadIndex: true, tooLarge: tooLarge);
  } finally {
    db.close();
  }
}

void _insertRows(
  sqlite3.Database db,
  String slug,
  List<ResolvedExternalLink> rows,
) {
  final insert = db.prepare(
    'INSERT INTO $_indexTable (sourceSlug, sourceBookId, sourceTitle, '
    'sourceCategoryId, sourceLineIndex, sourceHeRef, targetSource, '
    'targetTitle, targetCategoryId, targetLineIndex, connectionType) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  );
  try {
    for (final r in rows) {
      insert.execute([
        slug,
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
