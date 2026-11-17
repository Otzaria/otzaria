import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/services/commentary_service.dart';

/// מטמון בזיכרון של דור הספר לכל ספר (bookId), מתוך טבלת book_generation →
/// generation. משמש לשובר-שוויון לפי סדר הדורות בחיפוש הספרייה.
///
/// הדור נלקח מהנתון המוסמך ב-DB (לא היוריסטי לפי נתיב); ספר בלי דור משויך
/// לסוף ([CommentaryEra.other]).
class GenerationCache {
  GenerationCache._();

  static final GenerationCache instance = GenerationCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;
  ({Future<void> done, Completer<void> superseded})? _attachedReload;
  final _attachedReads =
      <
        (String, ReadOnlyDbTarget, AttachedLibraryFingerprint),
        Future<Map<int, int>>
      >{};
  int _generation = 0;
  int _revision = 0;

  /// משתנה כשמיפוי הדורות נטען מחדש או מתאפס.
  int get revision => _revision;

  /// דור לפי id ב-seforim.db.
  final Map<int, int> _orderByBookId = <int, int>{};

  /// דור לפי id ב-user_books.db — מרחב id נפרד, לכן מפה נפרדת.
  final Map<int, int> _orderByUserBookId = <int, int>{};

  /// דור לפי id בכל מסד מצורף, לפי slug.
  final Map<String, Map<int, int>> _orderByAttachedBookId = {};

  bool get isLoaded => _isLoaded;

  static const String _selectSql = '''
        SELECT b.id AS bookId, g.name AS generationName
        FROM book b
        JOIN book_generation bg ON bg.bookId = b.id
        JOIN generation g ON g.id = bg.generationId
      ''';

  /// מחזיר את סדר הדור של הספר (נמוך = מוקדם). ספר לא ידוע → סוף הרשימה.
  /// [source] בוחר את מפת ה-id של המסד (מרחבי id נפרדים).
  int getOrderForBook(int? bookId, BookSource source) {
    if (bookId == null) return CommentaryEra.other.order;
    final map = switch (source) {
      OfficialBookSource() => _orderByBookId,
      UserBookSource() => _orderByUserBookId,
      AttachedBookSource(:final slug) =>
        _orderByAttachedBookId[slug] ?? const <int, int>{},
    };
    return map[bookId] ?? CommentaryEra.other.order;
  }

  Future<void> warmUp() async {
    final myGen = _generation;
    // האינדוקס ממתין לרענון העדכני לפני דירוג ספרים ממסד מצורף.
    if (_attachedReload != null) {
      try {
        await _waitForAttachedReloads(myGen);
      } catch (_) {}
      if (myGen != _generation) return;
    }
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    final loading = _loadInternal();
    _loadingFuture = loading;
    try {
      await loading;
    } finally {
      // clear() may have started a newer generation while this one awaited.
      // Never detach that newer in-flight load.
      if (identical(_loadingFuture, loading)) _loadingFuture = null;
    }
  }

  Future<void> _loadInternal() async {
    final myGen = _generation;
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[GenerationCache] DB not initialized; skipping warmup');
      return;
    }

    try {
      // ב-isolate: JOIN על seforim.db בכונן קר חוסם את ה-UI לשניות.
      final local = await _readOfficialGenerations(
        repository.database.readOnlyTarget,
      );
      if (myGen != _generation) return;

      // דורות של ספרים אישיים (user_books.db) — רק אם ה-DB כבר פתוח, בלי
      // לכפות יצירתו. מרחב id נפרד, לכן מפה נפרדת.
      var localUser = <int, int>{};
      final userHolder = UserBooksDatabaseHolder.instance;
      final userRepo = userHolder.repositoryIfInitialized;
      if (userRepo != null) {
        try {
          final userTarget = userRepo.database.readOnlyTarget;
          // close() ממתין לקריאה, כדי שהחיבור ב-isolate לא יחזיק את הקובץ.
          await userHolder.trackRead(() async {
            localUser = await readGenerationsInIsolate(userTarget);
          });
          if (myGen != _generation) return;
        } catch (e) {
          debugPrint('[GenerationCache] user_books generations skipped: $e');
        }
      }

      if (myGen != _generation) return;
      if (_attachedReload == null) unawaited(reloadAttached());
      await _waitForAttachedReloads(myGen);
      if (myGen != _generation) return;
      _orderByBookId
        ..clear()
        ..addAll(local);
      _orderByUserBookId
        ..clear()
        ..addAll(localUser);
      _isLoaded = true;
      _revision++;
      debugPrint(
        '[GenerationCache] Loaded generations for ${_orderByBookId.length} '
        'books (+${_orderByUserBookId.length} user books)',
      );
    } catch (e) {
      debugPrint('[GenerationCache] Warmup failed: $e');
      // לא מסמנים loaded: כשל זמני (למשל DB locked בעלייה) יאופשר retry
      // ב-warmUp הבא לפני החיפוש, במקום להישאר עם כל הספרים כ-other לכל ה-session.
      if (myGen == _generation) {
        _orderByBookId.clear();
        _orderByUserBookId.clear();
      }
    }
  }

  /// טוען מחדש את דורות המסדים המצורפים אחרי צירוף, ניתוק או שינוי בקובץ.
  /// [changedSlugs] מתיר שיתוף למסדים שלא השתנו. null מבקש קריאות טריות.
  Future<void> reloadAttached({Set<String>? changedSlugs}) {
    final superseded = Completer<void>();
    final done = _reloadAttached(superseded, changedSlugs).whenComplete(() {
      if (identical(_attachedReload?.superseded, superseded)) {
        _attachedReload = null;
      }
    });
    _attachedReload?.superseded.complete();
    _attachedReload = (done: done, superseded: superseded);
    return done;
  }

  Future<void> _reloadAttached(
    Completer<void> superseded,
    Set<String>? changedSlugs,
  ) async {
    final localAttached = await _readAttached(changedSlugs);
    if (superseded.isCompleted) return;
    _orderByAttachedBookId
      ..clear()
      ..addAll(localAttached);
    _revision++;
  }

  /// כל מסד נקרא ב-isolate בפתיחה מוקשחת לפי נתיב, במקביל.
  Future<Map<String, Map<int, int>>> _readAttached(
    Set<String>? changedSlugs,
  ) async {
    final localAttached = <String, Map<int, int>>{};
    await Future.wait([
      for (final library in AttachedLibraryRegistry.instance.visibleLibraries)
        () async {
          try {
            final orders = await _readAttachedLibrary(library, changedSlugs);
            if (orders.isNotEmpty) localAttached[library.slug] = orders;
          } catch (e) {
            debugPrint(
              '[GenerationCache] ${library.slug} generations skipped: $e',
            );
          }
        }(),
    ]);
    return localAttached;
  }

  Future<Map<int, int>> _readAttachedLibrary(
    AttachedLibrary library,
    Set<String>? changedSlugs,
  ) {
    final target = (
      path: library.path,
      untrusted: true,
      immutable: library.immutable,
    );
    final timeout = AttachedLibraryRegistry.openTimeout;
    final fingerprint = library.fingerprint;
    if (fingerprint == null) {
      return readAttachedGenerations(target).timeout(timeout);
    }
    final key = (library.slug, target, fingerprint);
    final inFlight =
        changedSlugs != null && !changedSlugs.contains(library.slug)
        ? _attachedReads[key]
        : null;
    final read =
        inFlight ?? (_attachedReads[key] = readAttachedGenerations(target));
    return read.timeout(timeout).whenComplete(() {
      if (identical(_attachedReads[key], read)) _attachedReads.remove(key);
    });
  }

  Future<void> _waitForAttachedReloads(int myGen) async {
    while (myGen == _generation) {
      final reload = _attachedReload;
      if (reload == null) return;
      await Future.any([reload.done, reload.superseded.future]);
    }
  }

  @visibleForTesting
  static Future<Map<int, int>> Function(ReadOnlyDbTarget)
  readAttachedGenerations = readGenerationsInIsolate;

  /// מתודה סטטית: closure בתוך מתודה אסינכרונית לוכד את כל ההקשר שלה, ועלול
  /// להכיל אובייקט שאינו עובר ל-isolate.
  @visibleForTesting
  static Future<Map<int, int>> readGenerationsInIsolate(
    ReadOnlyDbTarget target,
  ) => Isolate.run(() => readGenerations(target));

  /// כתיבה חיצונית ל-seforim.db ממתינה לקריאה הרשומה ב-[DbReadWorker].
  static Future<Map<int, int>> _readOfficialGenerations(
    ReadOnlyDbTarget target,
  ) => DbReadWorker.runOnFreshIsolate(
    () => readGenerations(target),
    requestArguments: {'dbPath': target.path},
  );

  /// דורות הספרים של [target] — רץ ב-isolate. מסד בלי טבלאות הדורות → ריק.
  @visibleForTesting
  static Map<int, int> readGenerations(ReadOnlyDbTarget target) {
    final db = openReadOnlyTarget(target);
    try {
      // user_books.db נכתב במקביל מה-isolate הראשי.
      if (!target.untrusted) db.execute('PRAGMA busy_timeout=5000');
      final tables = db.select(
        "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' "
        "AND name IN ('book_generation', 'generation')",
      );
      if (tables.first['n'] != 2) return const {};
      final statement = db.prepare(_selectSql);
      try {
        final cursor = statement.selectCursor();
        final orders = <int, int>{};
        while (cursor.moveNext()) {
          final row = cursor.current;
          final bookId = row.columnAt(0) as int?;
          final name = row.columnAt(1) as String?;
          if (bookId == null || name == null) continue;
          final order = _orderForGenerationName(name);
          // לספר רב-מחברי שומרים את הדור המוקדם ביותר.
          final existing = orders[bookId];
          if (existing == null || order < existing) {
            orders[bookId] = order;
          }
        }
        return orders;
      } finally {
        statement.close();
      }
    } finally {
      db.close();
    }
  }

  void clear() {
    _generation++;
    _revision++;
    _orderByAttachedBookId.clear();
    _orderByBookId.clear();
    _orderByUserBookId.clear();
    _isLoaded = false;
    _loadingFuture = null;
    _attachedReload?.superseded.complete();
    _attachedReload = null;
    _attachedReads.clear();
  }

  /// סדר הדור לפי שם מנורמל (ללא גרשיים), מחושב פעם אחת. נקרא לכל ספר
  /// באינדוקס, ונרמול שמות הדורות מראש חוסך חישוב חוזר שלהם בכל שורה.
  static final Map<String, int> _orderByStrippedGenerationName = {
    for (final era in CommentaryEra.values)
      _stripGershayim(era.hebrewName): era.order,
  };

  /// ממפה שם דור מה-DB לסדר ([CommentaryEra]). גרשיים מנורמלים כדי
  /// להתאים בין כתיב ה-DB ל-hebrewName של ה-enum.
  static int _orderForGenerationName(String name) =>
      _orderByStrippedGenerationName[name] ??
      _orderByStrippedGenerationName[_stripGershayim(name)] ??
      CommentaryEra.other.order;

  static String _stripGershayim(String s) => s
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '')
      .trim();
}
