import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/query_loader.dart';
import 'package:otzaria/services/commentary_service.dart';

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
    });
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
    });
    return _castRows(res);
  }

  Future<List<Map<String, dynamic>>> getAllAltTocFlat() async {
    final res = await _request('allAltTocFlat', const {});
    return _castRows(res);
  }

  Future<List<Map<String, dynamic>>> getCommentatorRows({
    required int bookId,
    required String bookTitle,
    required int sourceLineId,
    required int startLineIndex,
    required int level,
    required bool isAltToc,
  }) async {
    final res = await _request('commentators', {
      'bookId': bookId,
      'bookTitle': bookTitle,
      'sourceLineId': sourceLineId,
      'startLineIndex': startLineIndex,
      'level': level,
      'isAltToc': isAltToc,
    });
    return _castRows(res);
  }

  /// מחזיר את דור המפרש לפי שמו. הזיהוי מתבצע בתוך ה-isolate מול ה-DB שלו,
  /// וחוזר כ-`order` (int); ההמרה חזרה ל-[CommentaryEra] נעשית כאן.
  Future<CommentaryEra> getBookEra(String bookTitle) async {
    final order = await _request('era', {'bookTitle': bookTitle}) as int;
    return CommentaryEra.values.firstWhere(
      (e) => e.order == order,
      orElse: () => CommentaryEra.other,
    );
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

  Future<dynamic> _request(String method, Map<String, Object?> args) async {
    if (_disposed) {
      throw StateError('FindRefDbIsolate was disposed');
    }
    await _readyCompleter.future;
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _commandPort!.send({'id': id, 'method': method, 'args': args});
    return completer.future;
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
    if (message.containsKey('error')) {
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

  Future<SeforimRepository?> ensureRepo() async {
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

  Future<Object?> dispatch(String method, Map<String, Object?> args) async {
    switch (method) {
      case 'reset':
        repository?.database.close();
        repository = null;
        final newPath = args['dbPath'] as String?;
        if (newPath != null && newPath.isNotEmpty) dbPath = newPath;
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
      case 'allAltTocFlat':
        final repo = await ensureRepo();
        if (repo == null) return const <Map<String, dynamic>>[];
        return repo.getAllAltTocFlatEntries();
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

  // הבקשות מעובדות **בזו אחר זו** דרך השרשרת הזו, לפי סדר ההגעה. בלי זה,
  // בקשות מקבילות (למשל כמה `era` ב-Future.wait, או טעינת מפרשים לכמה שורות
  // במקביל) היו נכנסות ל-ensureRepo יחד ופותחות יותר מחיבור DB אחד, ו-reset
  // היה יכול לסגור את החיבור באמצע שאילתה אחרת בנקודת await. עיבוד עוקב מבטל
  // את שני ה-races בלי לפגוע ב-throughput (sqlite3 סינכרוני — ממילא לא רץ
  // במקביל על אותו חיבור), וה-main isolate נשאר פנוי כך או כך.
  var processingChain = Future<void>.value();

  receivePort.listen((dynamic message) {
    if (message is! Map) return;
    final id = message['id'] as int?;
    final method = message['method'] as String?;
    if (id == null || method == null) return;
    final args = (message['args'] as Map?)?.cast<String, Object?>() ?? const {};

    processingChain = processingChain.then((_) async {
      try {
        final result = await dispatch(method, args);
        bootstrap.mainSendPort.send({'id': id, 'result': result});
      } catch (e) {
        bootstrap.mainSendPort.send({'id': id, 'error': e.toString()});
      }
    });
  });
}
