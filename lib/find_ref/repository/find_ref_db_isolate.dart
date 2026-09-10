import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/cache/acronym_cache_data.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// נזרק כשבקשה נזרקה מתור ה-worker בגלל הקלדה חדשה. אינו שגיאה — הקורא
/// אמור לנטוש בשקט את השאילתה שהתיישנה.
class FindRefQueryCancelled implements Exception {
  const FindRefQueryCancelled();

  @override
  String toString() => 'FindRefQueryCancelled';
}

/// מריץ את שאילתות ה-DB הכבדות של "איתור מקורות" ב-isolate נפרד, כך שהן
/// אינן חוסמות את ה-thread של ה-UI בזמן הקלדה.
///
/// הרקע: שאילתות ה-TOC/AltToc/מפרשים רצות דרך `package:sqlite3` הסינכרוני
/// ([MyDatabase]); כשהן מורצות על ה-main isolate הן מקפיאות את ההקלדה בדיוק
/// כשהמשתמש מקליד את המילה השנייה (שמפעילה את מסלול ה-TOC הכבד). ה-isolate
/// הזה מחזיק חיבור read-only **משלו** ל-`seforim.db` ומשרת בקשות נקודתיות,
/// כך שה-main isolate נשאר פנוי לקלוט קלט.
///
/// המופע הוא singleton עצל — נוצר בקריאה הראשונה ([instance]) ושורד לכל אורך
/// חיי האפליקציה. הקאש הפנימי של ה-`SeforimRepository` (TOC per-book, וכו')
/// מצטבר בתוך ה-isolate בין הקלדות. בעת רענון/החלפת ספרייה יש לקרוא ל-
/// [resetIfRunning] כדי לסגור את החיבור הישן ולנקות את הקאש.
///
/// **צרכנים:** מלבד "איתור מקורות", ה-isolate משרת גם את הקאש המשותף של טבלת
/// `book` ואת טעינת ה-TOC בפתיחת ספר — שאילתות ארוכות שאין להריץ על ה-isolate
/// של ה-UI. כולן חולקות את חיבור ה-RO היחיד (50MB cache + 64MB mmap).
///
/// **תחום:** רק שאילתות `seforim.db` עוברות ל-isolate. ספרי המשתמש
/// (`user_books.db`, מסלול אופציונלי "כלול ספרים אישיים") נשארים על ה-main
/// isolate — הם מסלול opt-in על DB קטן, ופתיחת חיבור RW שני אליו מ-isolate
/// נושאת סיכון נעילה שאינו מוצדק כאן.
class FindRefDbIsolate {
  FindRefDbIsolate._();

  static FindRefDbIsolate? _instance;
  static Future<FindRefDbIsolate>? _spawnFuture;

  /// נתיב reset שהתבקש בזמן ש-spawn עדיין רץ. מוחל כפקודה הראשונה ברגע
  /// שה-isolate מוכן (ראה [instance]) — לפני כל בקשת חיפוש שכבר ממתינה ל-
  /// spawn, כך שה-worker לא יעבד אפילו שאילתה אחת מול נתיב DB ישן.
  static String? _pendingResetPath;

  /// כתיבה חיצונית (עדכון ספרייה) מוחקת ומחליפה את קובץ ה-DB. ב-Windows
  /// מחיקת קובץ עם handle פתוח נכשלת, ולכן ה-worker חייב להישאר בלי חיבור.
  static bool _suspendedForExternalWrite = false;

  /// מחזיר את המופע הפעיל, ומאתחל (spawn) בעצלתיים בקריאה הראשונה.
  /// קריאות מקבילות שמגיעות בזמן ה-spawn חולקות את אותו Future.
  static Future<FindRefDbIsolate> instance() {
    final existing = _instance;
    if (existing != null && !existing._disposed) return Future.value(existing);
    return _spawnFuture ??= _spawn().then(
      (service) {
        _instance = service;
        _spawnFuture = null;
        // reset שהתבקש תוך כדי spawn נשלח **כאן**, סינכרונית בתוך ה-then
        // ולפני `return service`. בכך פקודת ה-reset נכנסת לתור ה-worker לפני
        // הבקשות של הממתינים על ה-spawn (ש-continuation שלהם מתוזמן רק אחרי
        // ש-`return service` מסיים את ה-Future) — מסדר הזרקה דטרמיניסטי.
        final pendingPath = _pendingResetPath;
        _pendingResetPath = null;
        if (pendingPath != null) {
          service._request('reset', {'dbPath': pendingPath}).ignore();
        }
        // אותו סדר הזרקה: השהיה שהתבקשה תוך כדי spawn נכנסת לתור לפני כל
        // שאילתה ממתינה, כך שה-worker לא יפתח חיבור בחלון הכתיבה החיצונית.
        if (_suspendedForExternalWrite) {
          service._request('suspend', const {}).ignore();
        }
        return service;
      },
      onError: (Object error, StackTrace st) {
        _spawnFuture = null;
        // spawn נכשל — מנקים את ה-reset הממתין כדי שלא יוחל בטעות על spawn
        // עתידי שכבר לכד את הנתיב העדכני בעצמו.
        _pendingResetPath = null;
        throw error;
      },
    );
  }

  static Future<FindRefDbIsolate> _spawn() async {
    // QueryLoader חייב להיות מאותחל על ה-main isolate כדי שנוכל להעביר את
    // ה-snapshot ל-worker (rootBundle אינו זמין שם).
    await QueryLoader.initialize();

    final service = FindRefDbIsolate._();
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    service._receivePort = receivePort;
    service._errorPort = errorPort;
    service._exitPort = exitPort;
    service._messagesSub = receivePort.listen(service._handleMessage);
    service._errorSub = errorPort.listen(service._handleWorkerError);
    service._exitSub = exitPort.listen(service._handleWorkerExit);

    service._isolate = await Isolate.spawn<_Bootstrap>(
      _workerMain,
      _Bootstrap(
        mainSendPort: receivePort.sendPort,
        queryCache: QueryLoader.cacheSnapshot,
        dbPath: DatabaseConstants.getDatabasePath(),
      ),
      debugName: 'find_ref_db_worker',
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    await service._readyCompleter.future;
    return service;
  }

  late final ReceivePort _receivePort;
  late final ReceivePort _errorPort;
  late final ReceivePort _exitPort;
  late final StreamSubscription<dynamic> _messagesSub;
  late final StreamSubscription<dynamic> _errorSub;
  late final StreamSubscription<dynamic> _exitSub;

  final Completer<void> _readyCompleter = Completer<void>();
  final Map<int, Completer<dynamic>> _pending = {};
  Isolate? _isolate;
  SendPort? _commandPort;
  int _nextId = 0;
  int _epoch = 0;
  bool _disposed = false;

  // ── Public query API (מופעל מתוך ה-proxy hooks של FindRefRepository) ────────

  Future<List<Map<String, dynamic>>> getTocEntries(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  }) async {
    final res = await _request('toc', {
      'bookId': bookId,
      'bookTitle': bookTitle,
      'queryTokens': queryTokens,
    }, cancellable: true);
    return _castRows(res);
  }

  Future<List<Map<String, dynamic>>> getAltTocEntries(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  }) async {
    final res = await _request('altToc', {
      'bookId': bookId,
      'bookTitle': bookTitle,
      'queryTokens': queryTokens,
    }, cancellable: true);
    return _castRows(res);
  }

  Future<List<Map<String, dynamic>>> getAllAltTocFlat() async {
    final res = await _request('allAltTocFlat', const {});
    return _castRows(res);
  }

  /// מסנן את קאש ה-AltToc השטוח **בתוך ה-worker** ומחזיר רק את ההתאמות —
  /// כך 61k+ הערכים (והנרמול שלהם) לעולם לא חוצים את גבול ה-isolate.
  Future<List<Map<String, dynamic>>> searchAltTocFlat(
    List<String> queryTokens, {
    int? maxRefTokens,
  }) async {
    final res = await _request('searchAltTocFlat', {
      'queryTokens': queryTokens,
      'maxRefTokens': maxRefTokens,
    }, cancellable: true);
    return _castRows(res);
  }

  /// בונה מראש את קאש ה-AltToc השטוח בתוך ה-worker (בנייה + נרמול ~1-2s),
  /// כדי שהחיפוש הראשון שזקוק לו לא ישלם את המחיר. fire-and-forget.
  Future<void> prewarmAltTocFlat() async {
    await _request('prewarmAltTocFlat', const {});
  }

  /// מזהי הספרים שיש להם מבנה AltToc — מאפשר לדלג על שאילתות AltToc
  /// עבור ~95% מהספרים שאין להם כזה.
  Future<List<int>?> getAltStructureBookIds() async {
    final res = await _request('altBookIds', const {});
    if (res == null) return null;
    return (res as List).cast<int>();
  }

  /// פותר מפתח הפניה קנוני מול אינדקס `line_ref` עבור כל הספרים המועמדים
  /// בשאילתה מאוגדת אחת. מפתח התוצאה הוא ה-bookId.
  Future<Map<int, ({int lineIndex, int lineId, String? heRef})>>
  resolveLineRefs(List<int> bookIds, String refKey) async {
    final res = await _request('lineRefs', {
      'bookIds': bookIds,
      'refKey': refKey,
    }, cancellable: true);
    return {
      for (final row in _castRows(res))
        row['bookId'] as int: (
          lineIndex: row['lineIndex'] as int,
          lineId: row['lineId'] as int,
          heRef: row['heRef'] as String?,
        ),
    };
  }

  Future<List<Map<String, dynamic>>> getCommentatorRows({
    required int bookId,
    required String bookTitle,
    required int sourceLineId,
    required int startLineIndex,
    required int level,
    required bool isAltToc,
    required bool isSourceLine,
  }) async {
    final res = await _request('commentators', {
      'bookId': bookId,
      'bookTitle': bookTitle,
      'sourceLineId': sourceLineId,
      'startLineIndex': startLineIndex,
      'level': level,
      'isAltToc': isAltToc,
      'isSourceLine': isSourceLine,
    }, cancellable: true);
    return _castRows(res);
  }

  /// מחזיר את דור המפרש לפי שמו. הזיהוי מתבצע בתוך ה-isolate מול ה-DB שלו,
  /// וחוזר כ-`order` (int); ההמרה חזרה ל-[CommentaryEra] נעשית כאן.
  Future<CommentaryEra> getBookEra(String bookTitle) async {
    final order =
        await _request(
              'era',
              {'bookTitle': bookTitle},
              cancellable: true,
            )
            as int;
    return CommentaryEra.values.firstWhere(
      (e) => e.order == order,
      orElse: () => CommentaryEra.other,
    );
  }

  // ── Shared seforim.db queries (צרכנים מחוץ ל"איתור מקורות") ────────────────

  /// כל הספרים המקומיים בהקרנה רזה (id/title/filePath/fileType/categoryId/
  /// orderIndex) — סריקת טבלת `book` המלאה מקפיאה את ה-UI על ספרייה גדולה.
  Future<List<Map<String, dynamic>>> getAllLocalBooksSlim() async {
    final res = await _request('allLocalBooksSlim', const {});
    return _castRows(res);
  }

  /// שולף ומכין את קאש הכינויים כולו ב-worker, בלי לממש עשרות אלפי שורות
  /// SQLite על ה-UI isolate.
  Future<AcronymCacheData> getBookAcronymCache() async {
    final raw = (await _request('bookAcronymCache', const {}) as Map)
        .cast<String, Object?>();
    return AcronymCacheData(
      acronymsByBookId: (raw['acronymsByBookId'] as Map)
          .cast<int, List<String>>(),
      bookIdsByBigram: (raw['bookIdsByBigram'] as Map).cast<int, Int32List>(),
      rowCount: raw['rowCount'] as int,
    );
  }

  /// שורות ה-TOC של ספר מ-`seforim.db`. המיפוי ל-`TocEntry` נעשה בצד הקורא
  /// דרך `TocEntry.fromMap`, כך שאין כפילות בלוגיקת ההמרה.
  Future<List<Map<String, dynamic>>> getBookTocRows(int bookId) async {
    final res = await _request('bookToc', {'bookId': bookId});
    return _castRows(res);
  }

  // ── Reset / lifecycle ───────────────────────────────────────────────────────

  /// מאפס את חיבור ה-DB והקאשים בתוך ה-isolate (בעת רענון/החלפת ספרייה).
  /// no-op אם ה-isolate עדיין לא נוצר. fire-and-forget — מסלול הרענון אינו
  /// צריך להמתין לסיום.
  static void resetIfRunning() {
    // נלכד את הנתיב **עכשיו** (לאחר שהספרייה כבר הוחלפה) כדי שגם reset שמתעכב
    // עד סיום spawn ישתמש בנתיב החדש.
    final dbPath = DatabaseConstants.getDatabasePath();
    final service = _instance;
    if (service != null && !service._disposed) {
      service._request('reset', {'dbPath': dbPath}).ignore();
      return;
    }
    // ה-isolate עדיין באמצע spawn (_instance עוד null): מסמנים reset ממתין.
    // הוא יישלח כפקודה הראשונה ברגע שה-isolate מוכן (ב-[instance]), לפני כל
    // חיפוש שכבר ממתין על אותו spawn-future — כך ה-worker לא יעבד אפילו
    // שאילתה אחת מול נתיב ה-DB הישן שנלכד ב-spawn.
    if (_spawnFuture != null) {
      _pendingResetPath = dbPath;
    }
  }

  /// תקרת המתנה לפקודות ההשהיה/השחרור. הן נכנסות לתור הסדרתי של ה-worker
  /// ועשויות להמתין לחימום AltToc (1-2 שניות); worker תקוע אינו זורק, ולכן
  /// בלי תקרה `closeForExternalWrite` — שנקרא מחוץ ל-try של העדכון — היה
  /// חוסם לנצח את שחרור ה-write session.
  static const Duration _lifecycleCommandTimeout = Duration(seconds: 10);

  /// משחרר את חיבור ה-RO של ה-worker לפני שכתיבה חיצונית מחליפה את קובץ
  /// ה-DB, ומונע פתיחה מחדש עד [resumeAfterExternalWrite].
  ///
  /// מחזיר האם שחרור ה-handle **אומת**. `false` פירושו שהחיבור עשוי להיות
  /// עוד פתוח, ולכן מחיקה/החלפה של קובץ ה-DB עלולה להיכשל.
  static Future<bool> suspendForExternalWrite() async {
    _suspendedForExternalWrite = true;
    final service = _instance;
    // אין מופע: אין חיבור פתוח, וה-spawn הבא יקבל את ההשהיה כפקודה ראשונה.
    if (service == null || service._disposed) return true;
    final request = service._request('suspend', const {});
    try {
      final released = await request.timeout(_lifecycleCommandTimeout);
      if (released == true) return true;
      debugPrint(
        '[FindRef isolate] suspend: close failed in worker — '
        'DB handle may still be open',
      );
      return false;
    } on TimeoutException {
      // תשובה מאוחרת לא תיפול כשגיאה לא-מטופלת.
      request.ignore();
      debugPrint(
        '[FindRef isolate] suspend timed out — DB handle may still be open',
      );
      return false;
    } catch (e) {
      // ‏kill של isolate אינו מריץ finalizers, ולכן ה-handle הנייטיבי עשוי
      // לשרוד את נפילת ה-worker עד סוף התהליך.
      debugPrint(
        '[FindRef isolate] suspend failed ($e) — DB handle may still be open',
      );
      return false;
    }
  }

  /// מתיר ל-worker לפתוח מחדש חיבור, על נתיב ה-DB המעודכן.
  static Future<void> resumeAfterExternalWrite() async {
    _suspendedForExternalWrite = false;
    final service = _instance;
    if (service == null || service._disposed) return;
    final request = service._request('resume', {
      'dbPath': DatabaseConstants.getDatabasePath(),
    });
    try {
      await request.timeout(_lifecycleCommandTimeout);
    } on TimeoutException {
      request.ignore();
      debugPrint('[FindRef isolate] resume timed out');
    } catch (e) {
      debugPrint('[FindRef isolate] resume failed: $e');
    }
  }

  /// גרסה סטטית של [beginSearchEpoch] — בטוחה לקריאה סינכרונית גם כשה-worker
  /// עוד לא נוצר (אין אז דבר בתור).
  static void beginSearchEpochIfRunning() {
    final service = _instance;
    if (service == null || service._disposed) return;
    service.beginSearchEpoch();
  }

  /// בדיקות בלבד — סוגר את ה-isolate ומשחרר את ה-singleton, כדי שקובץ בדיקה
  /// לא ישאיר worker חי אחרי סיומו.
  @visibleForTesting
  void disposeForTesting() => _tearDown();

  /// שולח בקשה ל-worker. [cancellable] מסמן אותה כשייכת לשאילתת ההקלדה
  /// הנוכחית ([_epoch]) — ההקלדה הבאה תזרוק אותה מהתור דרך [beginSearchEpoch].
  /// בקשות שאינן שייכות לאיתור מקורות (קאש הספרים, TOC בפתיחת ספר) נשלחות
  /// בלי epoch ולעולם אינן מבוטלות.
  Future<dynamic> _request(
    String method,
    Map<String, Object?> args, {
    bool cancellable = false,
  }) async {
    if (_disposed) {
      throw StateError('FindRefDbIsolate was disposed');
    }
    await _readyCompleter.future;
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _commandPort!.send({
      'id': id,
      'method': method,
      'args': args,
      // ה-epoch נקרא בזמן השליחה ולא בזמן הקריאה: בקשות שנשלחות אחרי שההקלדה
      // התקדמה שייכות ממילא לשאילתה החדשה.
      if (cancellable) 'epoch': _epoch,
    });
    return completer.future;
  }

  /// מקדם את מחזור השאילתות ומורה ל-worker לזרוק כל בקשה **ממתינה** של
  /// מחזורים קודמים. הבקשה שכבר רצה ב-worker מסתיימת (sqlite3 סינכרוני), אבל
  /// היא אחת — ולא עשרות שאילתות TOC של ההקלדה הקודמת.
  ///
  /// נקרא בתחילת כל חיפוש. בטוח לקריאה גם לפני ש-spawn הסתיים.
  void beginSearchEpoch() {
    _epoch++;
    final port = _commandPort;
    if (port == null || _disposed) return;
    port.send({'method': 'cancel', 'epoch': _epoch});
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _commandPort = message;
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      return;
    }
    if (message is! Map) return;
    final id = message['id'] as int?;
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (message['cancelled'] == true) {
      completer.completeError(const FindRefQueryCancelled());
    } else if (message.containsKey('error')) {
      completer.completeError(StateError(message['error'].toString()));
    } else {
      completer.complete(message['result']);
    }
  }

  void _handleWorkerError(dynamic message) {
    _failAllPending(StateError('find_ref DB isolate error: $message'));
    if (kReleaseMode) {
      ErrorLogFile.append(
        title: 'FindRef DB Isolate Error',
        error: message?.toString() ?? 'unknown',
        stackTrace: StackTrace.current,
        details: const {'Service': 'FindRefDbIsolate'},
      );
    }
    _tearDown();
  }

  void _handleWorkerExit(dynamic _) {
    if (_disposed) return;
    _failAllPending(StateError('find_ref DB isolate exited unexpectedly'));
    _tearDown();
  }

  /// מסיים את כל הבקשות הממתינות בשגיאה — כדי שלא ייתקעו לנצח אם ה-isolate נפל.
  void _failAllPending(Object error) {
    if (!_readyCompleter.isCompleted) _readyCompleter.completeError(error);
    final pending = List<Completer<dynamic>>.from(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
  }

  /// מנקה את המשאבים ומשחרר את ה-singleton, כך שהקריאה הבאה תיצור isolate חדש.
  void _tearDown() {
    if (_disposed) return;
    _disposed = true;
    _messagesSub.cancel();
    _errorSub.cancel();
    _exitSub.cancel();
    _receivePort.close();
    _errorPort.close();
    _exitPort.close();
    _isolate?.kill(priority: Isolate.immediate);
    if (identical(_instance, this)) _instance = null;
  }

  static List<Map<String, dynamic>> _castRows(dynamic res) => (res as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList(growable: false);
}

// ── Worker bootstrap & entry point ──────────────────────────────────────────

class _Bootstrap {
  final SendPort mainSendPort;
  final Map<String, Map<String, String>> queryCache;
  final String dbPath;

  const _Bootstrap({
    required this.mainSendPort,
    required this.queryCache,
    required this.dbPath,
  });
}

void _workerMain(_Bootstrap bootstrap) {
  // אין גישה ל-rootBundle ב-isolate — נזרע את ה-QueryLoader מה-snapshot.
  QueryLoader.seedCache(bootstrap.queryCache);

  final receivePort = ReceivePort();
  bootstrap.mainSendPort.send(receivePort.sendPort);

  // נפתח read-only — SqliteDataProvider על ה-main כבר נרמל את היומן ל-DELETE,
  // כך שפתיחת RO בטוחה. החיבור נוצר עצל בבקשה הראשונה.
  var dbPath = bootstrap.dbPath;
  SeforimRepository? repository;
  var suspended = false;

  // קאש AltToc שטוח עם טוקנים מנורמלים מראש — נבנה פעם אחת ב-worker ומשרת
  // את פקודת searchAltTocFlat. חי עד reset (רענון/החלפת ספרייה).
  List<({Map<String, dynamic> row, List<String> refTokens})>? altTocFlatCache;

  Future<SeforimRepository?> ensureRepo() async {
    if (suspended) return null;
    if (repository != null) return repository;
    try {
      final db = MyDatabase.withPath(dbPath, readOnly: true);
      final repo = SeforimRepository(db);
      await repo.ensureInitialized();
      repository = repo;
      return repo;
    } catch (e) {
      // כשל פתיחה (DB חסר/נעול רגעית) — מחזירים null; הקריאה תחזיר רשימה ריקה,
      // בדיוק כפי שמסלול ה-main isolate היה מתנהג מול repository == null.
      debugPrint('[FindRef isolate] DB open failed for $dbPath: $e');
      return null;
    }
  }

  Future<List<({Map<String, dynamic> row, List<String> refTokens})>>
  ensureAltTocFlatCache() async {
    final cached = altTocFlatCache;
    if (cached != null) return cached;
    final repo = await ensureRepo();
    if (repo == null) return const [];
    final rows = await repo.getAllAltTocFlatEntries();
    final built = [
      for (final r in rows)
        (
          row: r,
          refTokens: normalizeForFindRefMatch(
            r['reference'] as String,
          ).split(' ').where((t) => t.isNotEmpty).toList(growable: false),
        ),
    ];
    altTocFlatCache = built;
    return built;
  }

  Future<Object?> dispatch(String method, Map<String, Object?> args) async {
    switch (method) {
      case 'reset':
        repository?.database.close();
        repository = null;
        altTocFlatCache = null;
        final newPath = args['dbPath'] as String?;
        if (newPath != null && newPath.isNotEmpty) dbPath = newPath;
        return null;
      case 'suspend':
        // הדגל והאיפוס קודמים ל-close: גם אם הסגירה זורקת, ensureRepo לא
        // יחזיר את החיבור הישן ולא ייצור handle נוסף.
        suspended = true;
        altTocFlatCache = null;
        final closing = repository;
        repository = null;
        try {
          closing?.database.close();
          return true;
        } catch (e) {
          // מוחזר false כדי שהקורא לא ידווח על שחרור שלא אומת.
          debugPrint('[FindRef isolate] close during suspend failed: $e');
          return false;
        }
      case 'resume':
        suspended = false;
        final resumePath = args['dbPath'] as String?;
        if (resumePath != null && resumePath.isNotEmpty) dbPath = resumePath;
        return null;
      case 'toc':
        final repo = await ensureRepo();
        if (repo == null) return const <Map<String, dynamic>>[];
        return repo.getTocEntriesForReference(
          args['bookId'] as int,
          args['bookTitle'] as String,
          queryTokens: (args['queryTokens'] as List?)?.cast<String>(),
        );
      case 'altToc':
        final repo = await ensureRepo();
        if (repo == null) return const <Map<String, dynamic>>[];
        return repo.getAltTocEntriesForReference(
          args['bookId'] as int,
          args['bookTitle'] as String,
          queryTokens: (args['queryTokens'] as List?)?.cast<String>(),
        );
      case 'allLocalBooksSlim':
        final repo = await ensureRepo();
        if (repo == null) {
          throw StateError('seforim.db unavailable for allLocalBooksSlim');
        }
        return repo.database.bookDao.selectAllLocalBooksSlim();
      case 'bookAcronymCache':
        final repo = await ensureRepo();
        if (repo == null) {
          throw StateError('seforim.db unavailable for bookAcronymCache');
        }
        final db = await repo.database.database;
        final rows = db.select(
          'SELECT bookId, term FROM book_acronym ORDER BY bookId',
        );
        final data = buildAcronymCacheData(
          rows.map(
            (row) => (
              row['bookId'] as int,
              (row['term'] as String?) ?? '',
            ),
          ),
        );
        return {
          'acronymsByBookId': data.acronymsByBookId,
          'bookIdsByBigram': data.bookIdsByBigram,
          'rowCount': data.rowCount,
        };
      case 'bookToc':
        final repo = await ensureRepo();
        if (repo == null) {
          throw StateError('seforim.db unavailable for bookToc');
        }
        return repo.database.tocDao.selectRowsByBookId(args['bookId'] as int);
      case 'allAltTocFlat':
        final repo = await ensureRepo();
        if (repo == null) return const <Map<String, dynamic>>[];
        return repo.getAllAltTocFlatEntries();
      case 'searchAltTocFlat':
        final cache = await ensureAltTocFlatCache();
        final queryTokens = (args['queryTokens'] as List).cast<String>();
        final maxRefTokens = args['maxRefTokens'] as int?;
        return [
          for (final e in cache)
            if (altTocFlatMatches(
              e.refTokens,
              queryTokens,
              maxRefTokens: maxRefTokens,
            ))
              e.row,
        ];
      case 'prewarmAltTocFlat':
        await ensureAltTocFlatCache();
        return null;
      case 'altBookIds':
        final repo = await ensureRepo();
        if (repo == null) return null;
        return repo.getAltStructureBookIds();
      case 'lineRefs':
        final repo = await ensureRepo();
        if (repo == null) return const <Map<String, dynamic>>[];
        final resolved = await repo.resolveRefKeyInBooks(
          (args['bookIds'] as List).cast<int>(),
          args['refKey'] as String,
        );
        return [
          for (final entry in resolved.entries)
            {
              'bookId': entry.key,
              'lineIndex': entry.value.lineIndex,
              'lineId': entry.value.lineId,
              'heRef': entry.value.heRef,
            },
        ];
      case 'commentators':
        final repo = await ensureRepo();
        if (repo == null) return const <Map<String, dynamic>>[];
        return repo.getCommentatorsForReference(
          bookId: args['bookId'] as int,
          bookTitle: args['bookTitle'] as String,
          sourceLineId: args['sourceLineId'] as int,
          startLineIndex: args['startLineIndex'] as int,
          level: args['level'] as int,
          isAltToc: args['isAltToc'] as bool,
          isSourceLine: args['isSourceLine'] as bool? ?? false,
        );
      case 'era':
        final repo = await ensureRepo();
        if (repo == null) return CommentaryEra.other.order;
        final info = await repo.getBookGenerationInfoByTitle(
          args['bookTitle'] as String,
        );
        if (info == null) return CommentaryEra.other.order;
        final era = CommentaryEra.values.firstWhere(
          (e) => e.hebrewName == info.generationName,
          orElse: () => CommentaryEra.other,
        );
        return era.order;
      default:
        throw StateError('Unknown find_ref DB isolate method: $method');
    }
  }

  // הבקשות מעובדות **בזו אחר זו** מהתור הזה, לפי סדר ההגעה. בלי זה, בקשות
  // מקבילות (למשל כמה `era` ב-Future.wait, או טעינת מפרשים לכמה שורות במקביל)
  // היו נכנסות ל-ensureRepo יחד ופותחות יותר מחיבור DB אחד, ו-reset היה יכול
  // לסגור את החיבור באמצע שאילתה אחרת בנקודת await. עיבוד עוקב מבטל את שני
  // ה-races בלי לפגוע ב-throughput (sqlite3 סינכרוני — ממילא לא רץ במקביל על
  // אותו חיבור), וה-main isolate נשאר פנוי כך או כך.
  //
  // תור מפורש ולא שרשרת `Future.then`: שרשרת אינה ניתנת לגזירה, ולכן שאילתה
  // של הקלדה חדשה הייתה ממתינה שכל עבודת ההקלדה הקודמת תתרוקן.
  final queue = <Map<String, Object?>>[];
  var draining = false;

  // בקשות שנשלחו עם `epoch` קטן מזה נזרקות מהתור. הבקשה שכבר רצה אינה
  // ניתנת לקטיעה — sqlite3 סינכרוני.
  var minEpoch = 0;

  void reply(int id, {Object? result, String? error, bool cancelled = false}) {
    bootstrap.mainSendPort.send({
      'id': id,
      'error': ?error,
      if (cancelled) 'cancelled': true,
      if (error == null && !cancelled) 'result': result,
    });
  }

  Future<void> drain() async {
    if (draining) return;
    draining = true;
    try {
      while (queue.isNotEmpty) {
        // חובה למסור את התור לתור-האירועים בין בקשה לבקשה: `await` על
        // dispatch מתוזמן כ-microtask, וכל עוד יש microtasks הודעות ה-
        // ReceivePort אינן נמסרות — פקודת 'cancel' הייתה מגיעה רק אחרי
        // שהתור התרוקן, כלומר בדיוק מתי שהיא כבר חסרת תועלת.
        await Future<void>.delayed(Duration.zero);
        if (queue.isEmpty) break;
        final message = queue.removeAt(0);
        final id = message['id'] as int;
        final epoch = message['epoch'] as int?;
        if (epoch != null && epoch < minEpoch) {
          reply(id, cancelled: true);
          continue;
        }
        final method = message['method'] as String;
        final args =
            (message['args'] as Map?)?.cast<String, Object?>() ?? const {};
        try {
          reply(id, result: await dispatch(method, args));
        } catch (e) {
          reply(id, error: e.toString());
        }
      }
    } finally {
      draining = false;
    }
  }

  receivePort.listen((dynamic message) {
    if (message is! Map) return;

    // 'cancel' מטופלת **מיד** ולא נכנסת לתור — אחרת היא הייתה ממתינה בדיוק
    // מאחורי העבודה שהיא באה לבטל.
    if (message['method'] == 'cancel') {
      final epoch = message['epoch'] as int? ?? 0;
      if (epoch > minEpoch) minEpoch = epoch;
      queue.removeWhere((queued) {
        final queuedEpoch = queued['epoch'] as int?;
        if (queuedEpoch == null || queuedEpoch >= minEpoch) return false;
        reply(queued['id'] as int, cancelled: true);
        return true;
      });
      return;
    }

    final id = message['id'] as int?;
    final method = message['method'] as String?;
    if (id == null || method == null) return;
    queue.add({
      'id': id,
      'method': method,
      'args': message['args'],
      'epoch': message['epoch'],
    });
    drain();
  });
}
