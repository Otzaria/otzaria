import 'dart:isolate';

import 'package:flutter/foundation.dart';
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
  int _generation = 0;

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
    // האינדוקס מדרג ספרי מסד מצורף לפי הדור — ממתין לטעינה מחדש שבדרך.
    final attachedReload = _attachedReload;
    if (attachedReload != null) {
      try {
        await attachedReload;
      } catch (_) {}
    }
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    _loadingFuture = _loadInternal();
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
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

      final localAttached = await _readAttached(myGen);

      if (myGen != _generation) return;
      _orderByAttachedBookId
        ..clear()
        ..addAll(localAttached);
      _orderByBookId
        ..clear()
        ..addAll(local);
      _orderByUserBookId
        ..clear()
        ..addAll(localUser);
      _isLoaded = true;
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

  /// טוען מחדש רק את דורות המסדים המצורפים — אחרי צירוף, ניתוק או שינוי
  /// בקובץ מסד. הדורות של seforim.db ו-user_books.db אינם נקראים שוב.
  /// [warmUp] ממתין לה, כך שהקורא אינו חייב להמתין בעצמו.
  Future<void> reloadAttached() {
    late final Future<void> reload;
    reload = _reloadAttached().whenComplete(() {
      if (identical(_attachedReload, reload)) _attachedReload = null;
    });
    return _attachedReload = reload;
  }

  Future<void>? _attachedReload;

  Future<void> _reloadAttached() async {
    final myGen = _generation;
    final localAttached = await _readAttached(myGen);
    if (myGen != _generation) return;
    _orderByAttachedBookId
      ..clear()
      ..addAll(localAttached);
  }

  /// כל מסד נקרא ב-isolate בפתיחה מוקשחת לפי נתיב, במקביל — קריאה סינכרונית
  /// של מסד גדול (או בכונן רשת) לא תקפיא את ה-UI.
  Future<Map<String, Map<int, int>>> _readAttached(int myGen) async {
    final localAttached = <String, Map<int, int>>{};
    await Future.wait([
      for (final library in AttachedLibraryRegistry.instance.visibleLibraries)
        () async {
          final path = library.path;
          final immutable = library.immutable;
          try {
            final orders = await readGenerationsInIsolate((
              path: path,
              untrusted: true,
              immutable: immutable,
            )).timeout(AttachedLibraryRegistry.openTimeout);
            if (myGen != _generation || orders.isEmpty) return;
            localAttached[library.slug] = orders;
          } catch (e) {
            debugPrint(
              '[GenerationCache] ${library.slug} generations skipped: $e',
            );
          }
        }(),
    ]);
    return localAttached;
  }

  /// מתודה סטטית: closure בתוך מתודה אסינכרונית לוכד את כל ההקשר שלה, ועלול
  /// להכיל אובייקט שאינו עובר ל-isolate.
  @visibleForTesting
  static Future<Map<int, int>> readGenerationsInIsolate(
    ReadOnlyDbTarget target,
  ) => Isolate.run(() => readGenerations(target));

  /// כתיבה חיצונית ל-seforim.db ממתינה לקריאה הרשומה ב-[DbReadWorker].
  static Future<Map<int, int>> _readOfficialGenerations(
    ReadOnlyDbTarget target,
  ) => DbReadWorker.runOnFreshIsolate(() => readGenerations(target));

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
      final orders = <int, int>{};
      _accumulate(db.select(_selectSql), orders);
      return orders;
    } finally {
      db.close();
    }
  }

  /// צובר bookId→order מתוצאת [_selectSql]. ספר רב-מחברי → הדור המוקדם
  /// ביותר (order מינימלי), קומוטטיבי ולכן דטרמיניסטי בלי תלות בסדר השורות.
  static void _accumulate(Iterable rows, Map<int, int> into) {
    for (final row in rows) {
      final bookId = row['bookId'] as int?;
      final name = row['generationName'] as String?;
      if (bookId == null || name == null) continue;
      final order = _orderForGenerationName(name);
      final existing = into[bookId];
      if (existing == null || order < existing) {
        into[bookId] = order;
      }
    }
  }

  void clear() {
    _generation++;
    _orderByAttachedBookId.clear();
    _orderByBookId.clear();
    _orderByUserBookId.clear();
    _isLoaded = false;
    _loadingFuture = null;
  }

  /// ממפה שם דור מה-DB לסדר ([CommentaryEra]). גרשיים מנורמלים כדי
  /// להתאים בין כתיב ה-DB ל-hebrewName של ה-enum.
  static int _orderForGenerationName(String name) {
    final normalized = _stripGershayim(name);
    for (final era in CommentaryEra.values) {
      if (_stripGershayim(era.hebrewName) == normalized) return era.order;
    }
    return CommentaryEra.other.order;
  }

  static String _stripGershayim(String s) => s
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '')
      .trim();
}
