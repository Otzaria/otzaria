import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

/// התקדמות בניית האינדקס של מסד אחד: [done] שורות נסרקו מתוך [total] שורות
/// `external_link` במסד המקור.
class ExternalLinkBuildProgress {
  const ExternalLinkBuildProgress({required this.done, required this.total});

  final int done;
  final int total;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

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
    final titles = _inIsolate(_queryIndexedTargets, path);
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
  Future<Set<String>> sync({bool autoResume = false}) =>
      _enqueue(() => _sync(autoResume: autoResume));

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// אחרי כשל, [incompleteSlugs] ו-[tooLargeSlugs] נשארים עם ערכם הקודם.
  Future<Set<String>> _sync({
    String? resumeSlug,
    bool autoResume = false,
  }) async {
    if (WindowRole.isSecondary) return const {};
    final libraries = _registry.libraries;
    if (libraries.isEmpty) {
      tooLargeSlugs.value = const {};
      incompleteSlugs.value = const {};
    }
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
    // מילת בקרה בזיכרון משותף: ה-isolate של הבנייה סינכרוני, ולכן קורא אותה
    // בין מנות במקום להאזין להודעות.
    final control = calloc<Int32>();
    _control = control;
    try {
      final result = await _syncInIsolate((
        path: path,
        jobs: jobs,
        targets: targets,
        maxRows: maxIndexRows,
        batchSize: insertBatchSize,
        progressIntervalMs: progressInterval.inMilliseconds,
        batchPauseMs: batchPause.inMilliseconds,
        resumeSlug: resumeSlug,
        autoResume: autoResume,
        control: control.address,
      ), _onSyncMessage);
      _indexKnownAbsent = jobs.isEmpty && result.hadIndex == false;
      tooLargeSlugs.value = result.tooLarge;
      incompleteSlugs.value = result.incomplete;
      if (result.rebuilt.isNotEmpty) _invalidateIndexCaches();
      return result.rebuilt;
    } catch (_) {
      _invalidateIndexCaches();
      rethrow;
    } finally {
      _control = null;
      calloc.free(control);
      buildProgress.value = const {};
      buildingSlugs.value = const {};
      buildPaused.value = false;
      buildEconomy.value = false;
    }
  }

  /// הודעה מה-isolate של הסנכרון: רשימת ה-slugs שייבנו (בתחילתו), או
  /// התקדמות של מסד אחד.
  void _onSyncMessage(Object? message) {
    switch (message) {
      case List<Object?> pending:
        buildProgress.value = {
          for (final slug in pending)
            slug as String: const ExternalLinkBuildProgress(done: 0, total: 0),
        };
        buildingSlugs.value = buildProgress.value.keys.toSet();
      case (String slug, int done, int total):
        buildProgress.value = {
          ...buildProgress.value,
          slug: ExternalLinkBuildProgress(done: done, total: total),
        };
    }
  }

  Pointer<Int32>? _control;

  void _setControlBit(int bit, bool on) {
    final control = _control;
    if (control == null) return;
    control.value = on ? control.value | bit : control.value & ~bit;
  }

  /// משהה את הבנייה בין מנות. ההשהיה מחזיקה את שרשרת הסנכרונים: [sync] ו-
  /// [rebuild] אחרים ממתינים עד [resumeBuild] או [cancelBuild]. אין השפעה כשאין
  /// בנייה.
  void pauseBuild() {
    if (_control == null) return;
    _setControlBit(_ctlPaused, true);
    buildPaused.value = true;
  }

  void resumeBuild() {
    if (_control == null) return;
    _setControlBit(_ctlPaused, false);
    buildPaused.value = false;
  }

  /// עוצר את הבנייה אחרי המנה הנוכחית ושומר את ההתקדמות. הסימון `!building`
  /// נשאר, והמסד נחשב לא שלם ([incompleteSlugs]) עד [requestResume] (המשך) או
  /// [requestRebuild] (מאפס).
  void cancelBuild() => _setControlBit(_ctlCancel, true);

  /// מצב חסכוני: מנות קטנות יותר והשהיה קצרה ביניהן.
  void setBuildEconomy(bool on) {
    if (_control == null) return;
    _setControlBit(_ctlEconomy, on);
    buildEconomy.value = on;
  }

  /// בונה מחדש את אינדקס הקישורים של [slug] מאפס. רץ באותה שרשרת של [sync],
  /// כך שמחיקת ה-meta אינה מקדימה סנכרון שכותב. הממשק משתמש ב-[requestRebuild].
  @visibleForTesting
  Future<void> rebuild(String slug) => _enqueue(() async {
    if (WindowRole.isSecondary) return;
    await _inIsolate(_forgetIndexMeta, (await _cacheDbPath(), slug));
    await _sync();
  });

  /// ממשיך בנייה שנקטעה ([cancelBuild], קריסה) מהנקודה השמורה: שורות האינדקס
  /// שכבר נכתבו נשמרות. תקף רק לאותו קובץ ואותם מסדי יעד, אחרת המסד נבנה מאפס.
  /// המשך אוטומטי בהפעלה מתבצע ב-`sync(autoResume: true)`.
  void requestResume(String slug) =>
      _request(slug, () => _enqueue(() => _sync(resumeSlug: slug)));

  /// בנייה מאפס מהממשק: מוחק את הסימון והשורות של [slug].
  void requestRebuild(String slug) => _request(slug, () => rebuild(slug));

  final Set<String> _requestedSlugs = {};

  /// בקשת משתמש לגבי [slug] שכבר מתבצעת (לחיצה כפולה) אינה מתחילה שוב. כשל
  /// נרשם ואינו הופך לשגיאה אסינכרונית לא נתפסת.
  void _request(String slug, Future<Object?> Function() task) {
    if (!_requestedSlugs.add(slug)) return;
    unawaited(
      task()
          .then<void>(
            (_) {},
            onError: (Object e) =>
                debugPrint('[ExternalLinks] request "$slug" failed: $e'),
          )
          .whenComplete(() => _requestedSlugs.remove(slug)),
    );
  }

  /// תקרת השורות למסד אחד בבניית האינדקס — עוברת ל-isolate כארגומנט.
  @visibleForTesting
  static int maxIndexRows = kMaxExternalLinkRows;

  @visibleForTesting
  static int insertBatchSize = kExternalLinkInsertBatchSize;

  /// קצב מרבי של דיווחי ההתקדמות מה-isolate.
  @visibleForTesting
  static Duration progressInterval = const Duration(milliseconds: 200);

  /// השהיה קבועה אחרי כל מנה — לבדיקות שצריכות לתפוס בנייה באמצע.
  @visibleForTesting
  static Duration batchPause = Duration.zero;

  /// התקדמות הבנייה לכל מסד שנבנה כעת (המפתחות זהים ל-[buildingSlugs]):
  /// `done` שורות נסרקו מתוך `total` שורות `external_link` במקור.
  final ValueNotifier<Map<String, ExternalLinkBuildProgress>> buildProgress =
      ValueNotifier(const {});

  /// הבנייה מושהית ([pauseBuild]); מתאפס בסיום הסנכרון.
  final ValueNotifier<bool> buildPaused = ValueNotifier(false);

  /// מצב חסכוני ([setBuildEconomy]); מתאפס בסיום הסנכרון.
  final ValueNotifier<bool> buildEconomy = ValueNotifier(false);

  /// ה-slugs של מסדים שקישוריהם החיצוניים לא נטענו כי עברו את תקרת השורות.
  final ValueNotifier<Set<String>> tooLargeSlugs = ValueNotifier(const {});

  /// ה-slugs של מסדים שאינדקס הקישורים שלהם נבנה כעת. עד הסיום המפרשים שלהם
  /// אינם מוצגים על ספרים רשמיים.
  final ValueNotifier<Set<String>> buildingSlugs = ValueNotifier(const {});

  /// ה-slugs של מסדים שהבנייה שלהם נקטעה (הסימון `!building` נשאר). האינדקס
  /// חלקי ואינו מוגש, והבנייה אינה מנוסה שוב עד ש-[rebuild] מוחק את הסימון.
  final ValueNotifier<Set<String>> incompleteSlugs = ValueNotifier(const {});

  /// אחרי סנכרון שמצא cache.db בלי אינדקס ובלי מסדים — אין מה לנקות עוד.
  bool _indexKnownAbsent = false;
}

/// מריץ את [computation] ב-isolate. הסגור נבנה כאן, מחוץ למתודת מופע, כדי
/// שלא ילכוד את ההקשר שלה (Future וכד') שאינו עובר את גבול ה-isolate.
Future<R> _inIsolate<A, R>(R Function(A) computation, A argument) =>
    Isolate.run(() => computation(argument));

/// מריץ את סנכרון האינדקס ב-isolate אחד; הודעות ההתקדמות שלו מגיעות ל-
/// [onMessage] בזמן הריצה.
Future<_SyncResult> _syncInIsolate(
  _SyncArgs args,
  void Function(Object? message) onMessage,
) {
  final port = ReceivePort();
  port.listen(onMessage);
  final sendPort = port.sendPort;
  return Isolate.run(
    () => _syncIndex(args, sendPort),
  ).whenComplete(port.close);
}

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

/// קבוצת-על של היעדים המוגשים, מתוך אינדקס מכסה; [_queryReverseRows]
/// מסנן את שורות הקישורים לפי המקורות המוגשים וגרסאותיהם.
Set<String> _queryIndexedTargets(String path) {
  if (!File(path).existsSync()) return const {};
  final db = _openCacheDb(path);
  try {
    if (!_hasTable(db, _indexTable)) return const {};
    return {
      for (final row in db.select(
        'SELECT DISTINCT targetSource, targetTitle FROM $_indexTable',
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

typedef _SyncArgs = ({
  String path,
  List<_SyncJob> jobs,
  List<ExternalTargetDb> targets,
  int maxRows,
  int batchSize,
  int progressIntervalMs,
  int batchPauseMs,
  String? resumeSlug,
  bool autoResume,
  int control,
});

const _ctlPaused = 1;
const _ctlCancel = 2;
const _ctlEconomy = 4;

/// נזרק בין מנות כשהבנייה בוטלה; הסימון `!building` נשאר.
class _BuildCancelled implements Exception {
  const _BuildCancelled();
}

/// נקודת בקרה בין מנות: ממתין בזמן השהיה (בלי לצרוך CPU), זורק בעצירה, ובמצב
/// חסכוני נח בין המנות.
void _controlPoint(Pointer<Int32> control, int batchPauseMs) {
  while (true) {
    final state = control.value;
    if (state & _ctlCancel != 0) throw const _BuildCancelled();
    if (state & _ctlPaused == 0) break;
    sleep(const Duration(milliseconds: 50));
  }
  final economyMs = control.value & _ctlEconomy != 0 ? 100 : 0;
  final pauseMs = batchPauseMs + economyMs;
  if (pauseMs > 0) sleep(Duration(milliseconds: pauseMs));
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
  Set<String> incomplete,
});

/// גודל מנת הכנסה — טרנזקציה קצרה, כדי שכותבים אחרים ל-cache.db לא יקבלו BUSY.
const kExternalLinkInsertBatchSize = 5000;

/// סימון שנכתב ל-meta לפני הבנייה: אם הוא נשאר (קריסה, מסד גדול מדי), הבנייה
/// לא תנוסה שוב עד שהקובץ או מסדי היעד ישתנו.
///
/// אחרי ה-signature יכולה לבוא סיומת, בלי שינוי סכמה: `\u0001stop` - עצירה
/// ידנית (אין המשך אוטומטי בהפעלה), או `\u0001auto=N` - המשך אוטומטי שהתחיל
/// כש-N שורות היו באינדקס (אין המשך אוטומטי נוסף בלי התקדמות מעבר ל-N).
String _buildingMarker(String signature, {String suffix = ''}) =>
    '!building:$signature$suffix';

const _stoppedSuffix = '\u0001stop';
String _autoSuffix(int rows) => '\u0001auto=$rows';

/// מצב סימון `!building` של [signature] ב-[value], או null כשאינו כזה.
({int? autoRows, bool stopped})? _buildingState(
  String value,
  String signature,
) {
  final base = _buildingMarker(signature);
  if (!value.startsWith(base)) return null;
  final rest = value.substring(base.length);
  if (rest.isEmpty) return (autoRows: null, stopped: false);
  if (rest == _stoppedSuffix) return (autoRows: null, stopped: true);
  const autoPrefix = '\u0001auto=';
  if (!rest.startsWith(autoPrefix)) return null;
  final rows = int.tryParse(rest.substring(autoPrefix.length));
  return rows == null ? null : (autoRows: rows, stopped: false);
}

/// סימון מסד שעבר את תקרת השורות — קישוריו לא נטענו, והכרטיס שלו מציג זאת.
const _tooLargePrefix = '!toolarge:';
String _tooLargeMarker(String signature) => '$_tooLargePrefix$signature';

/// חתימת מסדי היעד שהאינדקס של [wireKey] נבנה מולם (בלי המסד עצמו).
String _signatureFor(String wireKey, List<ExternalTargetDb> targets) => [
  for (final t in targets)
    if (t.wireKey != wireKey) '${t.wireKey}=${t.version}',
].join(';');

/// האם ה-meta הקיים מכסה את [fingerprint] וה-[signature]: אינדקס שנבנה, או
/// סימון שמונע ניסיון חוזר (`!building` אחרי הפסקה, `!toolarge`).
bool _isCurrentOrMarked(
  (String, String)? previous,
  String fingerprint,
  String signature,
) =>
    previous != null &&
    previous.$1 == fingerprint &&
    (previous.$2 == signature ||
        _buildingState(previous.$2, signature) != null ||
        previous.$2 == _tooLargeMarker(signature));

/// מספר שורות `external_link` במסד המקור — היעד של דיווח ההתקדמות — ומספר
/// השורות שמתחת ל-[resumeFrom], שכבר נסרקו בבנייה שנקטעה.
({int total, int before}) _countExternalLinks(
  ReadOnlyDbTarget source,
  (int, int)? resumeFrom,
) {
  final db = openReadOnlyTarget(source);
  try {
    if (!DbCapabilities.probe(db).hasExternalLinks) {
      return (total: 0, before: 0);
    }
    final row = db.select(
      'SELECT COUNT(*) AS total, '
      '${resumeFrom == null ? '0' : 'COALESCE(SUM((sourceBookId, sourceLineIndex) < (?, ?)), 0)'} '
      'AS before FROM external_link',
      [?resumeFrom?.$1, ?resumeFrom?.$2],
    ).first;
    return (total: row['total'] as int, before: row['before'] as int);
  } finally {
    db.close();
  }
}

/// מוחק את ה-meta של [slug], כך שהסנכרון הבא יבנה לו אינדקס מחדש.
void _forgetIndexMeta((String, String) args) {
  final (path, slug) = args;
  if (!File(path).existsSync()) return;
  final db = _openCacheDb(path);
  try {
    if (!_hasTable(db, _metaTable)) return;
    db.execute('DELETE FROM $_metaTable WHERE sourceSlug = ?', [slug]);
  } finally {
    db.close();
  }
}

_SyncResult _syncIndex(_SyncArgs args, SendPort progress) {
  final (
    :path,
    :jobs,
    :targets,
    :maxRows,
    :batchSize,
    :progressIntervalMs,
    :batchPauseMs,
    :resumeSlug,
    :autoResume,
    control: controlAddress,
  ) = args;
  final control = Pointer<Int32>.fromAddress(controlAddress);
  // מצב חסכוני: חצי ממנת ההכנסה הרגילה.
  int currentBatchSize() => control.value & _ctlEconomy != 0
      ? (batchSize ~/ 2).clamp(1, batchSize)
      : batchSize;
  final db = _openCacheDb(path);
  try {
    final hadIndex = _hasTable(db, _metaTable);
    // בלי מסדים מצורפים לא יוצרים טבלאות ב-cache.db של משתמש שלא צירף מעולם.
    if (jobs.isEmpty && !hadIndex) {
      return (
        rebuilt: const {},
        hadIndex: false,
        tooLarge: const {},
        incomplete: const {},
      );
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

    int indexRowCount(String slug) =>
        db.select(
              'SELECT COUNT(*) AS c FROM $_indexTable WHERE sourceSlug = ?',
              [slug],
            ).first['c']
            as int;

    // המשך תקף רק לאותו מקור ויעדים; המשך אוטומטי דורש התקדמות מאז הניסיון
    // הקודם ולא אחרי עצירה ידנית, כדי למנוע לולאת קריסות.
    ({bool resume, int? autoRows}) resumeDecision(
      _SyncJob job,
      (String, String)? previous,
      String signature,
    ) {
      final state = previous == null || previous.$1 != job.fingerprint
          ? null
          : _buildingState(previous.$2, signature);
      if (state == null) return (resume: false, autoRows: null);
      if (job.slug == resumeSlug) return (resume: true, autoRows: null);
      if (!autoResume || state.stopped) return (resume: false, autoRows: null);
      final rows = indexRowCount(job.slug);
      final progressed = state.autoRows == null || rows > state.autoRows!;
      return rows > 0 && progressed
          ? (resume: true, autoRows: rows)
          : (resume: false, autoRows: null);
    }

    final pending = [
      for (final job in jobs)
        if (job.status == _SyncStatus.build)
          if (_signatureFor(BookSource.attached(job.slug).wireKey, targets)
              case final signature)
            if (resumeDecision(job, stored[job.slug], signature).resume ||
                !_isCurrentOrMarked(
                  stored[job.slug],
                  job.fingerprint,
                  signature,
                ))
              job.slug,
    ];
    if (pending.isNotEmpty) progress.send(pending);

    final rebuilt = <String>{};
    jobsLoop:
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
      final signature = _signatureFor(wireKey, targets);
      final previous = stored[job.slug];
      final decision = resumeDecision(job, previous, signature);
      final resuming = decision.resume;
      if (!resuming &&
          _isCurrentOrMarked(previous, job.fingerprint, signature)) {
        continue;
      }
      // הסימון ומחיקת האינדקס הישן אטומיים. שורות בלי יעד ב-_targetTable
      // אינן מוגשות, ולכן כתיבה במנות אינה חושפת אינדקס חלקי.
      _transaction(db, () {
        writeMeta(
          job.slug,
          job.fingerprint,
          _buildingMarker(
            signature,
            suffix: decision.autoRows == null
                ? ''
                : _autoSuffix(decision.autoRows!),
          ),
        );
        if (!resuming) {
          db.execute('DELETE FROM $_indexTable WHERE sourceSlug = ?', [
            job.slug,
          ]);
          db.execute('DELETE FROM $_targetTable WHERE sourceSlug = ?', [
            job.slug,
          ]);
        }
      });
      var scanned = 0;
      var total = 0;
      (int, int)? resumeFrom;
      if (resuming) {
        final last = db.select(
          'SELECT sourceBookId, sourceLineIndex FROM $_indexTable '
          'WHERE sourceSlug = ? '
          'ORDER BY sourceBookId DESC, sourceLineIndex DESC LIMIT 1',
          [job.slug],
        );
        if (last.isNotEmpty) {
          final from = (
            last.first['sourceBookId'] as int,
            last.first['sourceLineIndex'] as int,
          );
          resumeFrom = from;
          // מנה יכולה להיחתך באמצע קישורי אותה שורה — קוראים אותה כולה מחדש.
          _transaction(db, () {
            db.execute(
              'DELETE FROM $_indexTable WHERE sourceSlug = ? '
              'AND sourceBookId = ? AND sourceLineIndex = ?',
              [job.slug, from.$1, from.$2],
            );
          });
        }
      }
      final clock = Stopwatch()..start();
      var lastReportMs = -progressIntervalMs;
      void report({bool force = false}) {
        final now = clock.elapsedMilliseconds;
        if (!force && now - lastReportMs < progressIntervalMs) return;
        lastReportMs = now;
        progress.send((job.slug, force ? total : scanned, total));
      }

      final batch = <ResolvedExternalLink>[];
      var scannedInBatch = 0;
      void flush() {
        if (batch.isNotEmpty) {
          _transaction(db, () => _insertRows(db, job.slug, batch));
        }
        batch.clear();
        scannedInBatch = 0;
        report();
        _controlPoint(control, batchPauseMs);
      }

      try {
        final counts = _countExternalLinks(job.source, resumeFrom);
        total = counts.total;
        scanned = counts.before;
        report();
        readResolvedExternalLinks(
          source: job.source,
          sourceWireKey: wireKey,
          targets: jobTargets,
          maxRows: maxRows - counts.before,
          resumeFrom: resumeFrom,
          onScanned: () {
            scanned++;
            if (++scannedInBatch >= currentBatchSize()) flush();
          },
          onRow: batch.add,
        );
        if (scannedInBatch > 0) flush();
        report(force: true);
      } on _BuildCancelled {
        // השורות שנכתבו נשארות — המשך מהנקודה השמורה, רק לבקשת המשתמש.
        _transaction(
          db,
          () => writeMeta(
            job.slug,
            job.fingerprint,
            _buildingMarker(signature, suffix: _stoppedSuffix),
          ),
        );
        break jobsLoop;
      } on ExternalLinksTooLargeException {
        // הסימון נשאר — לא ננסה שוב עד שהקובץ ישתנה.
        _transaction(db, () {
          clear(job.slug);
          writeMeta(job.slug, job.fingerprint, _tooLargeMarker(signature));
        });
        continue;
      } catch (e) {
        // כשל בהמשך משאיר את ההתקדמות השמורה ואת הסימון כמות שהם.
        if (resuming && resumeFrom != null) {
          debugPrint('[ExternalLinks] resume of "${job.slug}" failed: $e');
          continue;
        }
        // מסד שלא נקרא כעת — ננסה בסנכרון הבא, מאפס.
        _transaction(db, () => clear(job.slug));
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
    final incomplete = {
      for (final row in db.select(
        'SELECT sourceSlug FROM $_metaTable WHERE targetsSignature LIKE ?',
        ['!building:%'],
      ))
        row['sourceSlug'] as String,
    };
    return (
      rebuilt: rebuilt,
      hadIndex: true,
      tooLarge: tooLarge,
      incomplete: incomplete,
    );
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
