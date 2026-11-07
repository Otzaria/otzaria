import 'dart:async';
import 'dart:collection';
import 'dart:io' show FileMode;
import 'dart:isolate';

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode, visibleForTesting;
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart'
    show runRangeRequestOnConnection;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/book_read.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/file/document_format.dart';

/// חיבור RO פתוח ויכולותיו, כפי שה-worker מעביר לטעינות הטווח.
typedef ReadOnlyConnection = ({
  sqlite3.Database db,
  DbCapabilities capabilities,
});

/// ה-worker לא ענה, נפל או לא עלה — הקורא עובר למסלול חלופי.
class DbReadWorkerUnavailable implements Exception {
  const DbReadWorkerUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'DbReadWorkerUnavailable: $reason';
}

/// התור מלא או פג תוקפו; פתיחת חיבור חלופי רק תגדיל את העומס.
class DbReadWorkerBusy implements Exception {
  const DbReadWorkerBusy(this.reason);

  final String reason;

  @override
  String toString() => 'DbReadWorkerBusy: $reason';
}

/// ה-worker מושהה לכתיבה חיצונית; אסור לפתוח את seforim.db עד השחרור.
class DbReadWorkerSuspended implements Exception {
  const DbReadWorkerSuspended();

  @override
  String toString() => 'DbReadWorkerSuspended';
}

/// נזרק כשרק ה-worker לא שחרר את הקובץ, כדי שעדכון שכבר הצליח יוכל להמשיך.
class DbReadWorkerNotReleased extends StateError {
  DbReadWorkerNotReleased(super.message);
}

/// תוכן קישור משורות [bookId]: שורה [index2], או כל הטווח עד [index2End]
/// (1-based, כולל). משותף ל-worker ולמסלול הישיר, כדי שהפלט יהיה זהה.
Future<String> linkContentFromDbLines(
  SeforimRepository repository,
  int bookId,
  int index2,
  int? index2End,
) async => (await linkSourceLinesFromDb(
  repository,
  bookId,
  index2,
  index2End,
)).map((line) => line.content).join('<br>');

/// שורות היעד בשאילתת טווח אחת, גם כשכל אחת מכילה מעברי שורה פנימיים.
Future<List<LinkContentLine>> linkSourceLinesFromDb(
  SeforimRepository repository,
  int bookId,
  int index2,
  int? index2End,
) async {
  final end0 = (index2End ?? index2) - 1;
  if (end0 <= index2 - 1) {
    final line = await repository.getLineByIndex(bookId, index2 - 1);
    return [
      (
        lineIndex: index2 - 1,
        content: line?.content ?? 'שגיאה: אינדקס מחוץ לטווח',
      ),
    ];
  }
  final lines = await repository.getLines(bookId, index2 - 1, end0);
  return lines.isEmpty || lines.first.lineIndex != index2 - 1
      ? [(lineIndex: index2 - 1, content: 'שגיאה: אינדקס מחוץ לטווח')]
      : lines
            .map((line) => (lineIndex: line.lineIndex, content: line.content))
            .toList(growable: false);
}

Future<Map<String, Object?>> _officialLinkContent(
  SeforimRepository repository,
  db_models.Book? book,
  Map<String, Object?> args,
) async {
  if (book == null) return const {'fallback': true};
  final format = documentFormatOf(fileType: book.fileType, path: book.filePath);
  if (book.isFileBacked &&
      book.filePath != null &&
      (format?.isTextual ?? false)) {
    return const {'fallback': true};
  }
  final lines = await linkSourceLinesFromDb(
    repository,
    book.id,
    args['index2'] as int,
    args['index2End'] as int?,
  );
  return args['includeLines'] == true
      ? {'lines': lines}
      : {'content': lines.map((line) => line.content).join('<br>')};
}

/// שורה של ספר שכבר נפתר ב-seforim.db, כפי ש-[DbReadWorker.lines] מחזיר.
typedef BookLineText = ({String content, String? heRef});

/// קריאות שורות לפי `bookId`; רצות ב-worker כדי שהפענוח לא יחסום את ה-UI.
Future<Object?> _readBookLines(
  SeforimRepository repository,
  String method,
  Map<String, Object?> args,
) async {
  final bookId = args['bookId'] as int;
  if (method == 'lineContents') return repository.getLineContents(bookId);
  final lines = await repository.getLines(
    bookId,
    args['startIndex'] as int,
    args['endIndex'] as int,
  );
  return <BookLineText>[
    for (final line in lines) (content: line.content, heRef: line.heRef),
  ];
}

const _bookLineMethods = {'lineContents', 'lines'};

/// כתובת שורה אחת: נתיב הכותרות (`breadcrumb`) או ה-heRef המלא (`heRef`).
Future<String?> _readLineRef(
  SeforimRepository repository,
  String method,
  Map<String, Object?> args,
) {
  final bookId = args['bookId'] as int;
  final lineIndex = args['lineIndex'] as int;
  return method == 'heRef'
      ? repository.getLineHeRef(bookId, lineIndex)
      : repository.getLineBreadcrumb(bookId, lineIndex);
}

const _lineRefMethods = {'breadcrumb', 'heRef'};

Future<List<Map<String, dynamic>>> _readSiblingCommentaryRows(
  SeforimRepository repository,
  Map<String, Object?> args,
) => repository.getSiblingCommentaryLinkRowsForLine(
  bookId: args['bookId'] as int,
  bookTitle: args['bookTitle'] as String,
  lineIndex: args['lineIndex'] as int,
  excludeBookId: args['excludeBookId'] as int,
);

Future<Object?> _readBooks(
  SeforimRepository repository,
  Map<String, Object?> args,
) {
  final dao = repository.database.bookDao;
  final arguments = args['arguments'] as List;
  final includeRelations = args['includeRelations'] == true;
  return switch (args['operation'] as BookReadOperation) {
    BookReadOperation.allBooks => dao.getAllBooks(),
    BookReadOperation.allLocalBooks => dao.getAllLocalBooks(),
    BookReadOperation.localBooksSlim => dao.selectAllLocalBooksSlim(),
    BookReadOperation.allBooksWithRelations => dao.getAllBooksWithRelations(),
    BookReadOperation.byId =>
      includeRelations
          ? repository.getBook(arguments[0] as int)
          : dao.getBookById(arguments[0] as int),
    BookReadOperation.byCategory =>
      includeRelations
          ? repository.getBooksByCategory(arguments[0] as int)
          : dao.getBooksByCategory(arguments[0] as int),
    BookReadOperation.byTitle =>
      includeRelations
          ? repository.getBookByTitle(arguments[0] as String)
          : dao.getBookByTitle(arguments[0] as String),
    BookReadOperation.byTitleAndCategory =>
      includeRelations
          ? repository.getBookByTitleAndCategory(
              arguments[0] as String,
              arguments[1] as int,
            )
          : dao.getBookByTitleAndCategory(
              arguments[0] as String,
              arguments[1] as int,
            ),
    BookReadOperation.byTitleCategoryAndFileType =>
      includeRelations
          ? repository.getBookByTitleCategoryAndFileType(
              arguments[0] as String,
              arguments[1] as int,
              arguments[2] as String,
            )
          : dao.getBookByTitleCategoryAndFileType(
              arguments[0] as String,
              arguments[1] as int,
              arguments[2] as String,
            ),
    BookReadOperation.byFilePath => dao.getBookByFilePath(
      arguments[0] as String,
    ),
    BookReadOperation.count => dao.countAllBooks(),
  };
}

Future<List<Map<String, Object?>>> _readBatchOnFreshConnection(
  List<Map<String, Object?>> items,
  Map<String, Map<String, String>> queryCache,
) async {
  QueryLoader.seedCache(queryCache);
  MyDatabase? database;
  SeforimRepository? repository;
  String? openPath;
  final resolvedBooks = <(String, int?), db_models.Book?>{};
  Future<SeforimRepository> repoFor(String path) async {
    if (repository != null && openPath == path) return repository!;
    database?.close();
    openPath = null;
    resolvedBooks.clear();
    database = MyDatabase.withPath(path, readOnly: true, official: true);
    repository = SeforimRepository(database!);
    await repository!.ensureInitialized();
    openPath = path;
    return repository!;
  }

  try {
    final results = <Map<String, Object?>>[];
    for (final item in items) {
      try {
        final method = item['method'] as String;
        final args = (item['args'] as Map).cast<String, Object?>();
        final repo = await repoFor(args['dbPath'] as String);
        if (method == 'bookRead') {
          results.add({'result': await _readBooks(repo, args)});
          continue;
        }
        if (_lineRefMethods.contains(method)) {
          results.add({'result': await _readLineRef(repo, method, args)});
          continue;
        }
        if (_bookLineMethods.contains(method)) {
          results.add({'result': await _readBookLines(repo, method, args)});
          continue;
        }
        if (method == 'bookCatalog') {
          results.add({
            'result': (
              books: await repo.getAllBooksLean(),
              categories: await repo.getAllCategories(),
            ),
          });
          continue;
        }
        if (method == 'commentatorsByBook') {
          results.add({
            'result': await repo.database.linkDao.selectCommentatorsByBook(
              args['bookId'] as int,
            ),
          });
          continue;
        }
        if (method == 'siblingCommentaryRows') {
          results.add({'result': await _readSiblingCommentaryRows(repo, args)});
          continue;
        }
        if (method != 'linkContent') {
          throw StateError('Unknown DbReadWorker method: $method');
        }
        final key = (args['title'] as String, args['categoryId'] as int?);
        if (!resolvedBooks.containsKey(key)) {
          final resolved = await BookDatabaseResolver.resolveBookInCandidates(
            title: key.$1,
            candidates: [
              ResolvedBookRepositoryCandidate(
                repository: repo,
                source: BookSource.official,
              ),
            ],
            categoryId: key.$2,
          );
          resolvedBooks[key] = resolved?.book;
        }
        results.add({
          'result': await _officialLinkContent(repo, resolvedBooks[key], args),
        });
      } catch (error, stackTrace) {
        results.add({'error': error.toString(), 'stack': '$stackTrace'});
      }
    }
    return results;
  } finally {
    database?.close();
  }
}

/// שני חיבורי RO עצלים: טווחים וקישורים באחד, ספרים שלמים בשני.
/// קריאת ספר אינה מעכבת פתיחה וגלילה של ספר אחר.
class DbReadWorker {
  DbReadWorker._(this._slot);

  static final _ranges = _WorkerSlot('db_read_worker');
  static final _books = _WorkerSlot('book_text_worker');
  static final _slots = [_ranges, _books];
  final _WorkerSlot _slot;
  static int _generation = 0;
  static bool _suspendedForExternalWrite = false;
  static bool _closedUntilReopen = false;
  static final Set<Future<void>> _oneShotReads = {};
  static Completer<bool>? _oneShotWaiter;
  static Timer? _oneShotWaitTimer;

  /// חיבורים זמניים שרצים יחד (fallback, קטלוג ודורות); השאר בתור. שתיים
  /// ולא אחת: קריאת ספר שלם איטית לא תחסום לבדה טווח קטן.
  @visibleForTesting
  static int maxFallbackReads = 2;
  static int _activeFallbackReads = 0;
  static final Queue<_FallbackWaiter> _fallbackQueue = Queue();
  static int _fallbackQueuedBytes = 0;

  @visibleForTesting
  static int maxQueuedFallbackReads = 32;

  @visibleForTesting
  static int maxPendingWorkerReads = 64;

  /// אומדן זיכרון תיאורי הבקשות בלבד, ללא תוצאות או מטמון SQLite.
  @visibleForTesting
  static int maxPendingRequestBytes = 512 * 1024;

  @visibleForTesting
  static Duration admissionTimeout = const Duration(seconds: 10);

  static const _maxBatchItems = 64;
  static const _maxPendingLifecycleCommands = 4;

  /// בקשה שלא נענתה בזמן הזה מסמנת את ה-worker כתקוע; עד שיענה, הבקשות
  /// עוברות למסלול חלופי מחוץ ל-UI isolate.
  @visibleForTesting
  static Duration stallTimeout = const Duration(seconds: 10);

  // קצר בכוונה: פקודת בקרה ממתינה רק לבקשה שכבר בביצוע, וכל המתנה
  // מעכבת את עדכון הספרייה ואת הסגירה.
  @visibleForTesting
  static Duration lifecycleCommandTimeout = const Duration(seconds: 4);

  /// שער בדיקה בנקודת checkpoint של ספר שלם; מקבל SendPort לשחרור הקריאה.
  @visibleForTesting
  static SendPort? bookReadCheckpointPort;

  /// רץ ראשון בכל isolate של ה-worker; בדיקות טוענות בו את libzstd.
  @visibleForTesting
  static void Function()? workerSetUpForTesting;

  static Iterable<DbReadWorker> get _runningWorkers => _slots
      .map((slot) => slot.instance)
      .whereType<DbReadWorker>()
      .where((worker) => !worker._disposed);

  /// כולל קריאות שעדיין חיות אחרי timeout, בלי ליצור worker חדש.
  static bool get hasPendingReads =>
      _oneShotReads.isNotEmpty ||
      _fallbackQueue.isNotEmpty ||
      _batch.isNotEmpty ||
      _slots.any((slot) => slot.spawnFuture != null) ||
      _runningWorkers.any(
        (worker) =>
            worker._pending.isNotEmpty ||
            worker._deferredLifecycle != null ||
            worker._lifecycleRecovery != null,
      );

  static Future<DbReadWorker> _instanceOrSpawn(_WorkerSlot slot) {
    final existing = slot.instance;
    if (existing != null && !existing._disposed) return Future.value(existing);
    final pending = slot.spawnFuture;
    if (pending != null) return pending;
    late final Future<DbReadWorker> spawning;
    spawning = _spawn(slot).then(
      (service) {
        if (!identical(slot.spawnFuture, spawning)) {
          service._tearDown();
          throw const DbReadWorkerUnavailable('spawn superseded');
        }
        slot.instance = service;
        slot.spawnFuture = null;
        // נשלח לפני כל בקשה שממתינה ל-spawn, כדי שלא ייפתח חיבור בחלון הכתיבה.
        if (_suspendedForExternalWrite) {
          service._send('suspend', const {}).ignore();
        }
        if (_closedUntilReopen) {
          service._send('close', const {}).ignore();
        }
        return service;
      },
      onError: (Object error, StackTrace st) {
        if (identical(slot.spawnFuture, spawning)) slot.spawnFuture = null;
        throw DbReadWorkerUnavailable('spawn failed: $error');
      },
    );
    return slot.spawnFuture = spawning;
  }

  static Future<DbReadWorker> _spawn(_WorkerSlot slot) async {
    await QueryLoader.initialize();
    final service = DbReadWorker._(slot);
    service._messagesSub = service._receivePort.listen(service._handleMessage);
    service._errorSub = service._errorPort.listen(service._handleWorkerError);
    service._exitSub = service._exitPort.listen(service._handleWorkerExit);
    try {
      service._isolate = await Isolate.spawn<_Bootstrap>(
        _workerMain,
        _Bootstrap(
          mainSendPort: service._receivePort.sendPort,
          queryCache: QueryLoader.cacheSnapshot,
          bookReadCheckpointPort: identical(slot, _books)
              ? bookReadCheckpointPort
              : null,
          setUpForTesting: workerSetUpForTesting,
          cacheKib: identical(slot, _books) ? 8000 : null,
        ),
        debugName: slot.name,
        onError: service._errorPort.sendPort,
        onExit: service._exitPort.sendPort,
      );
      await service._readyCompleter.future;
    } catch (_) {
      service._tearDown();
      rethrow;
    }
    return service;
  }

  final ReceivePort _receivePort = ReceivePort();
  final ReceivePort _errorPort = ReceivePort();
  final ReceivePort _exitPort = ReceivePort();
  late final StreamSubscription<dynamic> _messagesSub;
  late final StreamSubscription<dynamic> _errorSub;
  late final StreamSubscription<dynamic> _exitSub;
  final Completer<void> _readyCompleter = Completer<void>();
  final Map<int, Completer<Object?>> _pending = {};
  final Map<String, Future<Object?>> _maintenanceRequests = {};
  // חזרה אחרי timeout אינה מצמידה listener נוסף לפקודה שעדיין חיה.
  final _lifecycleWaits = Expando<Future<Object?>>();
  int _pendingLifecycleCommands = 0;
  _DeferredLifecycle? _deferredLifecycle;
  Future<Object?>? _lifecycleRecovery;
  Isolate? _isolate;
  SendPort? _commandPort;
  int _nextId = 0;
  bool _disposed = false;
  bool get _stalled => _slot.stalled;
  set _stalled(bool value) => _slot.stalled = value;

  /// שולח בקשה ל-worker. [DbReadWorkerUnavailable] מציין worker שאינו זמין,
  /// [DbReadWorkerBusy] מציין עומס שאין לעקוף ב-fallback, ו-[DbReadWorkerSuspended]
  /// מציין כתיבה חיצונית.
  static Future<Object?> request(
    String method,
    Map<String, Object?> args,
  ) async {
    final generation = _generation;
    // קודם ההשהיה: worker תקוע היה שולח את הקורא לפתוח את הקובץ באמצע כתיבה.
    if (_suspendedForExternalWrite || _closedUntilReopen) {
      throw const DbReadWorkerSuspended();
    }
    final slot = method == 'bookText' || method == 'bookTextBytes'
        ? _books
        : _ranges;
    if (slot.stalled) throw const DbReadWorkerUnavailable('stalled');
    final bytes = _requestBytes(args);
    if (slot.reads.length >= maxPendingWorkerReads ||
        slot.pendingBytes + bytes > maxPendingRequestBytes) {
      throw const DbReadWorkerBusy('worker queue capacity');
    }
    final reservation = _ReadReservation(bytes);
    slot.reads.add(reservation);
    slot.pendingBytes += bytes;
    final run = _requestOnSlot(slot, method, args, generation).whenComplete(() {
      slot.reads.remove(reservation);
      slot.pendingBytes -= bytes;
      if (slot.reads.isEmpty && slot.instance == null) slot.stalled = false;
    });
    try {
      final result = await run.timeout(
        stallTimeout,
        onTimeout: () {
          if (generation != _generation) {
            throw const DbReadWorkerSuspended();
          }
          slot.stalled = true;
          debugPrint('[DbReadWorker] "$method" stalled — using fallback');
          _logStall(method, args, slot.name);
          throw const DbReadWorkerUnavailable('timeout');
        },
      );
      if (generation != _generation) throw const DbReadWorkerSuspended();
      return result;
    } on _WorkerReadError catch (error) {
      if (generation != _generation) throw const DbReadWorkerSuspended();
      _logReadFailure(method, args, slot.name, error);
      rethrow;
    } catch (_) {
      if (generation != _generation) throw const DbReadWorkerSuspended();
      rethrow;
    }
  }

  static Future<Object?> _requestOnSlot(
    _WorkerSlot slot,
    String method,
    Map<String, Object?> args,
    int generation,
  ) async {
    final service = await _instanceOrSpawn(slot);
    while (true) {
      if (_suspendedForExternalWrite ||
          _closedUntilReopen ||
          generation != _generation) {
        throw const DbReadWorkerSuspended();
      }
      final recovery =
          service._deferredLifecycle?.completer.future ??
          service._lifecycleRecovery;
      if (recovery == null) return service._send(method, args);
      await recovery;
    }
  }

  static final Set<String> _loggedFailures = {};

  /// סוגי כשל שנרשמו ב-errors.txt בתהליך הזה; תקרה, כי כשל חוזר בכל לחיצה.
  static const _maxLoggedFailures = 20;

  /// בבדיקות ובהרצת פיתוח לא נרשם, כדי לא לכתוב ל-errors.txt של המפתח.
  @visibleForTesting
  static bool logFailuresInDebug = false;

  @visibleForTesting
  static void resetLoggedFailuresForTesting() => _loggedFailures.clear();

  /// נדלק כשקריאה נכשלה כי seforim.db עצמו פגום, ונכבה רק אחרי
  /// התקנת מסד חדש בהצלחה; קריאה פגומה אחריה מדליקה אותו שוב.
  static final ValueNotifier<bool> corruptDatabaseDetected = ValueNotifier(
    false,
  );

  /// הקוראים מציגים הודעה כללית או רשימה ריקה, ולכן השגיאה עצמה נרשמת כאן.
  static void _logReadFailure(
    String method,
    Map<String, Object?> args,
    String connection,
    _WorkerReadError error,
  ) {
    if (_isCorruptDatabaseError(error.message)) {
      corruptDatabaseDetected.value = true;
    }
    if (kDebugMode && !logFailuresInDebug) return;
    final kind = '$method|${error.message.split('\n').first}';
    if (_loggedFailures.length >= _maxLoggedFailures ||
        !_loggedFailures.add(kind)) {
      return;
    }
    try {
      ErrorLogFile.append(
        title: 'DB read worker failure',
        error: error.message,
        stackTrace: error.stack,
        details: {
          'Method': method,
          'Connection': connection,
          'Database': args['dbPath']?.toString(),
          'Args': _describeArgs(args),
        },
      );
    } catch (_) {
      // כשל בכתיבת הלוג אינו משנה את תשובת הקריאה.
    }
  }

  static String _describeArgs(Map<String, Object?> args) => [
    for (final MapEntry(:key, :value) in args.entries)
      if (key != 'dbPath' && (value is num || value is String)) '$key=$value',
  ].join(', ');

  // חלק מהמסלולים החלופיים רצים על ה-UI isolate; בלי הרשומה תקיעה שנגרמה
  // מהם אינה מזוהה בדוח.
  static void _logStall(
    String method,
    Map<String, Object?> args,
    String connection,
  ) {
    if (kDebugMode && !logFailuresInDebug) return;
    if (_loggedFailures.length >= _maxLoggedFailures ||
        !_loggedFailures.add('$method|stalled')) {
      return;
    }
    final file = ErrorLogFile.resolveFile();
    final entry = ErrorLogFile.formatEntry(
      title: 'DB read worker stalled',
      error:
          '"$method" did not answer within ${stallTimeout.inSeconds}s; '
          'using fallback',
      details: {
        'Method': method,
        'Connection': connection,
        'Args': _describeArgs(args),
      },
    );
    // הדיסק כנראה כבר איטי, וכתיבה סינכרונית עם flush הייתה תוקעת את ה-UI.
    unawaited(
      file.parent
          .create(recursive: true)
          .then(
            (_) => file.writeAsString(
              entry,
              mode: FileMode.append,
              flush: true,
            ),
          )
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  /// אצוות התאוששות על חיבור זמני מחוץ ל-UI isolate.
  static Future<List<Map<String, Object?>>> _batchOnFreshIsolate(
    List<Map<String, Object?>> items,
  ) async {
    if (_suspendedForExternalWrite || _closedUntilReopen) {
      throw const DbReadWorkerSuspended();
    }
    final generation = _generation;
    return trackFallbackRead(
      () async {
        await QueryLoader.initialize();
        if (generation != _generation) throw const DbReadWorkerSuspended();
        final queryCache = QueryLoader.cacheSnapshot;
        return Isolate.run(
          () => _readBatchOnFreshConnection(items, queryCache),
        );
      },
      requestArguments: {'items': items},
    );
  }

  /// קריאה על חיבור זמני כפופה לאותו admission גם בקטלוג ובדורות הספרים.
  /// השהיה לכתיבה חיצונית ממתינה לה עד שתשחרר את הקובץ.
  static Future<T> runOnFreshIsolate<T>(
    FutureOr<T> Function() read, {
    Map<String, Object?>? requestArguments,
  }) => trackFallbackRead(
    () => Isolate.run(read),
    requestArguments: requestArguments,
  );

  /// מסלול ההתאוששות משתמש באותה מכסת חיבורים זמניים.
  static Future<T> runFallbackOnFreshIsolate<T>(
    FutureOr<T> Function() read, {
    Map<String, Object?>? requestArguments,
  }) => runOnFreshIsolate(read, requestArguments: requestArguments);

  /// רישום קריאה זמנית כפוף לאותו admission, לפני הפעלת הקורא.
  static Future<T> trackTemporaryRead<T>(Future<T> Function() read) =>
      trackFallbackRead(read);

  /// הגבלת קריאות חיות: timeout אינו עוצר I/O ולכן אינו מפנה מקום.
  /// ההמתנה בתור מוגבלת בנפח, בכמות וב-[admissionTimeout].
  static Future<T> trackFallbackRead<T>(
    Future<T> Function() read, {
    Map<String, Object?>? requestArguments,
  }) async {
    if (_suspendedForExternalWrite || _closedUntilReopen) {
      throw const DbReadWorkerSuspended();
    }
    final generation = _generation;
    final bytes = _requestBytes(requestArguments);
    if (bytes > maxPendingRequestBytes) {
      throw const DbReadWorkerBusy('fallback request size');
    }
    if (_activeFallbackReads < maxFallbackReads) {
      _activeFallbackReads++;
    } else {
      if (_fallbackQueue.length >= maxQueuedFallbackReads ||
          _fallbackQueuedBytes + bytes > maxPendingRequestBytes) {
        throw const DbReadWorkerBusy('fallback queue capacity');
      }
      final turn = _FallbackWaiter(bytes);
      _fallbackQueue.add(turn);
      _fallbackQueuedBytes += bytes;
      final deadline = Timer(admissionTimeout, () {
        if (!_fallbackQueue.remove(turn)) return;
        _fallbackQueuedBytes -= bytes;
        turn.completer.completeError(
          const DbReadWorkerBusy('fallback admission timeout'),
        );
      });
      try {
        await turn.completer.future;
      } finally {
        deadline.cancel();
      }
    }
    try {
      if (generation != _generation) throw const DbReadWorkerSuspended();
      return await _trackTemporaryRead(read);
    } finally {
      if (_fallbackQueue.isEmpty) {
        _activeFallbackReads--;
      } else {
        final next = _fallbackQueue.removeFirst();
        _fallbackQueuedBytes -= next.bytes;
        next.completer.complete();
      }
    }
  }

  // ממתין בתור עוד לא תפס מקום, ולכן אינו משחרר אחד.
  static void _failQueuedReads() {
    while (_fallbackQueue.isNotEmpty) {
      _fallbackQueue.removeFirst().completer.completeError(
        const DbReadWorkerSuspended(),
      );
    }
    _fallbackQueuedBytes = 0;
    for (final item in _batch) {
      item.completer.completeError(const DbReadWorkerSuspended());
    }
    _batch.clear();
    _batchBytes = 0;
  }

  /// עוקב אחר קריאה זמנית במסד הרשמי עד שהחיבור שלה נסגר.
  /// גם fallback שכבר יוצר isolate חייב להשתחרר לפני כתיבה חיצונית.
  static Future<T> _trackTemporaryRead<T>(Future<T> Function() read) async {
    if (_suspendedForExternalWrite || _closedUntilReopen) {
      throw const DbReadWorkerSuspended();
    }
    final generation = _generation;
    final run = read();
    final tracked = run.then<void>((_) {}, onError: (Object _) {});
    _oneShotReads.add(tracked);
    try {
      final result = await run;
      if (generation != _generation) throw const DbReadWorkerSuspended();
      return result;
    } finally {
      _oneShotReads.remove(tracked);
      if (_oneShotReads.isEmpty) _finishOneShotWait(true);
    }
  }

  static Future<bool> _waitForOneShotReads() {
    if (_oneShotReads.isEmpty) return Future.value(true);
    // timeout אינו מצמיד ממתין חדש לקריאות החיות; ניסיון נוסף מקבל חלון חדש.
    final existing = _oneShotWaiter;
    if (existing != null) return existing.future;
    final waiter = _oneShotWaiter = Completer<bool>();
    _oneShotWaitTimer = Timer(lifecycleCommandTimeout, () {
      if (!identical(_oneShotWaiter, waiter)) return;
      debugPrint('[DbReadWorker] fallback reads did not release DB in time');
      _finishOneShotWait(false);
    });
    return waiter.future;
  }

  static void _finishOneShotWait(bool released) {
    _oneShotWaitTimer?.cancel();
    _oneShotWaitTimer = null;
    final waiter = _oneShotWaiter;
    _oneShotWaiter = null;
    waiter?.complete(released);
  }

  static final List<_BatchItem> _batch = [];
  static int _batchBytes = 0;

  /// כמו [request], אבל בקשות שנשלחות באותו סבב סינכרוני (למשל כל המפרשים
  /// שנבנו באותו פריים) יוצאות ל-worker כבקשה אחת.
  static Future<Object?> batched(String method, Map<String, Object?> args) {
    if (_suspendedForExternalWrite || _closedUntilReopen) {
      return Future.error(const DbReadWorkerSuspended());
    }
    final bytes = _requestBytes({'method': method, 'args': args});
    if (bytes > maxPendingRequestBytes) {
      return Future.error(const DbReadWorkerBusy('batch item size'));
    }
    if (_batch.isNotEmpty &&
        (_batch.length >= _maxBatchItems ||
            _batchBytes + bytes > maxPendingRequestBytes ~/ 2)) {
      unawaited(_flushBatch());
    }
    final item = _BatchItem(method, args);
    _batch.add(item);
    _batchBytes += bytes;
    if (_batch.length == 1) scheduleMicrotask(_flushBatch);
    return item.completer.future;
  }

  /// קריאת ספרים מלאה, כולל בדיקות הסכמה והיחסים, מחוץ ל-UI isolate.
  static Future<Object?> readBooks(
    String dbPath,
    BookReadOperation operation,
    List<Object?> arguments, {
    required bool includeRelations,
  }) => batched('bookRead', {
    'dbPath': dbPath,
    'operation': operation,
    'arguments': arguments,
    'includeRelations': includeRelations,
  });

  /// תוכן כל שורות [bookId] ב-seforim.db שב-[dbPath], בסדר השורות.
  static Future<List<String>> lineContents(String dbPath, int bookId) async =>
      (await batched('lineContents', {'dbPath': dbPath, 'bookId': bookId})
              as List)
          .cast<String>();

  /// השורות [startIndex]..[endIndex] (כולל, 0-based) של [bookId].
  static Future<List<BookLineText>> lines(
    String dbPath,
    int bookId,
    int startIndex,
    int endIndex,
  ) async =>
      (await batched('lines', {
                'dbPath': dbPath,
                'bookId': bookId,
                'startIndex': startIndex,
                'endIndex': endIndex,
              })
              as List)
          .cast<BookLineText>();

  static Future<void> _flushBatch() async {
    if (_batch.isEmpty) return;
    final generation = _generation;
    final items = List.of(_batch);
    _batch.clear();
    _batchBytes = 0;
    try {
      final requests = [
        for (final item in items) {'method': item.method, 'args': item.args},
      ];
      List results;
      try {
        results = await request('batch', {'items': requests}) as List;
        if (generation != _generation) throw const DbReadWorkerSuspended();
        if (results.any(
          (result) => result is Map && result.containsKey('error'),
        )) {
          results = await _batchOnFreshIsolate(requests);
        }
      } on DbReadWorkerUnavailable {
        if (generation != _generation) throw const DbReadWorkerSuspended();
        results = await _batchOnFreshIsolate(requests);
      }
      if (generation != _generation) throw const DbReadWorkerSuspended();
      for (var i = 0; i < items.length; i++) {
        final result = results[i] as Map;
        final completer = items[i].completer;
        if (result['suspended'] == true) {
          completer.completeError(const DbReadWorkerSuspended());
        } else if (result.containsKey('error')) {
          final error = _WorkerReadError.from(result);
          _logReadFailure(
            items[i].method,
            items[i].args,
            'one-shot isolate',
            error,
          );
          completer.completeError(error);
        } else {
          completer.complete(result['result']);
        }
      }
    } catch (error) {
      for (final item in items) {
        if (!item.completer.isCompleted) item.completer.completeError(error);
      }
    }
  }

  /// משחרר את חיבור ה-RO לפני כתיבה חיצונית ומונע פתיחה עד
  /// [resumeAfterExternalWrite]. `false` — השחרור לא אומת.
  static Future<bool> suspendForExternalWrite() async {
    _suspendedForExternalWrite = true;
    _generation++;
    _failQueuedReads();
    final released = await Future.wait([
      for (final service in _runningWorkers)
        service
            ._lifecycle('suspend', const {})
            .then(
              (value) => value == true,
              onError: (Object error) {
                if (error is DbReadWorkerBusy) return false;
                throw error;
              },
            ),
      _waitForOneShotReads(),
    ]);
    return released.every((value) => value);
  }

  static Future<void> resumeAfterExternalWrite() async {
    _suspendedForExternalWrite = false;
    await Future.wait([
      for (final service in _runningWorkers)
        service._lifecycle('resume', const {}),
    ]);
  }

  /// סוגר את החיבור עד [allowReopen]. נקרא כשהחיבור הראשי נסגר,
  /// כדי שה-worker לא יחזיק את הקובץ אחרי שה-provider שחרר אותו.
  /// [wait] כבוי ביציאה מהתוכנה: סיום התהליך משחרר את הקובץ ממילא.
  static Future<void> closeConnectionIfRunning({bool wait = true}) async {
    _closedUntilReopen = true;
    _generation++;
    _failQueuedReads();
    final closings = <Future<Object?>>[];
    for (final service in _runningWorkers) {
      final rejected = service._lifecycleQueueFull;
      final closing = service._send('close', const {});
      if (wait && rejected) {
        closings.add(closing);
      } else if (!wait || service._stalled) {
        closing.ignore();
      } else {
        closings.add(service._awaitLifecycle(closing, 'close'));
      }
    }
    if (wait) {
      await Future.wait<Object?>([...closings, _waitForOneShotReads()]);
    }
  }

  /// שוכח את הספרים שנפתרו — נקרא מיד אחרי commit של עדכון, כדי שבקשה
  /// שלפני הסגירה לא תקבל מזהה ספר ישן.
  /// מתיר שוב פתיחת חיבור אחרי [closeConnectionIfRunning]; נקרא רק אחרי אתחול
  /// מוצלח של ה-provider, כדי שקורא מקביל לא יפתח קובץ שמוחלף.
  static void allowReopen() {
    _closedUntilReopen = false;
    for (final service in _runningWorkers) {
      service._send('open', const {}).ignore();
    }
  }

  /// משחרר את מטמון הדפים של חיבורי ה-workers; לא מפעיל worker ולא פותח חיבור.
  static Future<bool> shrinkMemoryIfRunning() async {
    final results = await Future.wait([
      for (final service in _runningWorkers)
        if (!service._stalled && service._pending.isEmpty)
          service._lifecycle('shrinkMemory', const {}),
    ]);
    return results.any((result) => result == true);
  }

  static void clearBookCacheIfRunning() {
    for (final service in _runningWorkers) {
      service._send('clearBookCache', const {}).ignore();
    }
  }

  @visibleForTesting
  static Future<Object?> cacheSizeForTesting(
    String dbPath, {
    required bool books,
  }) async {
    final service = await _instanceOrSpawn(books ? _books : _ranges);
    return service._send('cacheSizeForTesting', {'dbPath': dbPath});
  }

  @visibleForTesting
  static void disposeForTesting() {
    _closedUntilReopen = false;
    bookReadCheckpointPort = null;
    _generation++;
    _failQueuedReads();
    for (final slot in _slots) {
      slot.spawnFuture = null;
      slot.instance?._tearDown();
    }
  }

  /// תמונת עומס ללא פתיחת חיבור. liveWorkers כולל workers מוכנים גם כשהם
  /// בטלים; activeWorkerReads סופר slots עם reservation, כולל spawn ממתין.
  /// אלו אינם OS threads. queuedReads סופר הודעות worker, callbacks חלופיים
  /// ופריטים שטרם אוגדו. הבייטים הם אומדן תיאורי הבקשות שבתור, ללא תוצאות.
  static ({
    int liveWorkers,
    int activeWorkerReads,
    int activeFallbackReads,
    int pendingWorkerReads,
    int queuedReads,
    int estimatedQueuedBytes,
  })
  get resourceUsage => (
    liveWorkers: _runningWorkers.length,
    activeWorkerReads: _slots.where((slot) => slot.reads.isNotEmpty).length,
    activeFallbackReads: _activeFallbackReads,
    pendingWorkerReads: _slots.fold(
      0,
      (count, slot) => count + slot.reads.length,
    ),
    queuedReads:
        _batch.length +
        _fallbackQueue.length +
        _slots.fold(0, (count, slot) => count + slot.reads.skip(1).length),
    estimatedQueuedBytes:
        _batchBytes +
        _fallbackQueuedBytes +
        _slots.fold(
          0,
          (bytes, slot) =>
              bytes + slot.reads.skip(1).fold(0, (n, r) => n + r.bytes),
        ),
  );

  Future<Object?> _lifecycle(String method, Map<String, Object?> args) =>
      _awaitLifecycle(_send(method, args), method);

  Future<Object?> _awaitLifecycle(Future<Object?> request, String method) =>
      _lifecycleWaits[request] ??= _waitForLifecycle(request, method);

  Future<Object?> _waitForLifecycle(
    Future<Object?> request,
    String method,
  ) async {
    try {
      return await request.timeout(lifecycleCommandTimeout);
    } on TimeoutException {
      request.ignore();
      debugPrint('[DbReadWorker] $method timed out — DB handle may be open');
    } on DbReadWorkerBusy {
      rethrow;
    } catch (e) {
      debugPrint('[DbReadWorker] $method failed: $e');
    }
    return null;
  }

  /// מספר ההודעות שנשלחו ל-worker — לבדיקת איגוד הבקשות.
  @visibleForTesting
  static int sentMessageCount = 0;

  Future<Object?> _send(String method, Map<String, Object?> args) {
    if (_disposed) {
      return Future.error(const DbReadWorkerUnavailable('disposed'));
    }
    if (const {'close', 'open', 'suspend', 'resume'}.contains(method)) {
      return _sendLifecycle(method, args);
    }
    if (method != 'shrinkMemory' && method != 'clearBookCache') {
      return _sendRequest(method, args);
    }
    final existing = _maintenanceRequests[method];
    if (existing != null) return existing;
    late final Future<Object?> run;
    run = _sendRequest(method, args).whenComplete(() {
      if (identical(_maintenanceRequests[method], run)) {
        _maintenanceRequests.remove(method);
      }
    });
    return _maintenanceRequests[method] = run;
  }

  bool get _lifecycleQueueFull =>
      _pendingLifecycleCommands >= _maxPendingLifecycleCommands ||
      _deferredLifecycle != null ||
      _lifecycleRecovery != null;

  Future<Object?> _sendLifecycle(String method, Map<String, Object?> args) {
    if (!_lifecycleQueueFull) return _sendLifecycleRequest(method, args);
    final deferred = _deferredLifecycle ??= _DeferredLifecycle();
    deferred.closed = _closedUntilReopen;
    deferred.suspended = _suspendedForExternalWrite;
    final mustClose = method == 'close' || method == 'suspend';
    deferred.mustClose |= mustClose;
    // מצב היעד יוחל אחרי התור, אבל אין אישור סגירה לפקודה שלא התקבלה.
    if (mustClose) {
      return Future.error(const DbReadWorkerBusy('lifecycle queue capacity'));
    }
    return deferred.completer.future;
  }

  Future<Object?> _sendLifecycleRequest(
    String method,
    Map<String, Object?> args,
  ) {
    _pendingLifecycleCommands++;
    return _sendRequest(method, args).whenComplete(() {
      _pendingLifecycleCommands--;
      _flushDeferredLifecycle();
    });
  }

  void _flushDeferredLifecycle() {
    if (_disposed ||
        _pendingLifecycleCommands != 0 ||
        _lifecycleRecovery != null) {
      return;
    }
    final deferred = _deferredLifecycle;
    if (deferred == null) return;
    _deferredLifecycle = null;
    final recovery = deferred.completer.future;
    _lifecycleRecovery = recovery;
    unawaited(
      _sendLifecycleRequest('lifecycleState', {
            'closed': deferred.closed,
            'suspended': deferred.suspended,
            'mustClose': deferred.mustClose,
          })
          .then(
            (result) {
              if (result == true) {
                deferred.completer.complete(result);
              } else {
                deferred.completer.completeError(
                  const DbReadWorkerUnavailable('lifecycle recovery failed'),
                );
              }
            },
            onError: (Object error, StackTrace stack) {
              deferred.completer.completeError(error, stack);
            },
          )
          .whenComplete(() {
            if (identical(_lifecycleRecovery, recovery)) {
              _lifecycleRecovery = null;
            }
            _flushDeferredLifecycle();
          }),
    );
  }

  Future<Object?> _sendRequest(String method, Map<String, Object?> args) async {
    if (_disposed) throw const DbReadWorkerUnavailable('disposed');
    if (!_readyCompleter.isCompleted) await _readyCompleter.future;
    sentMessageCount++;
    final id = _nextId++;
    final completer = Completer<Object?>();
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
    _stalled = false;
    final completer = _pending.remove(message['id']);
    if (completer == null || completer.isCompleted) return;
    if (message['suspended'] == true) {
      completer.completeError(const DbReadWorkerSuspended());
    } else if (message.containsKey('error')) {
      completer.completeError(_WorkerReadError.from(message));
    } else {
      completer.complete(message['result']);
    }
  }

  void _handleWorkerError(dynamic message) {
    _failAllPending(DbReadWorkerUnavailable('worker error: $message'));
    _tearDown();
  }

  void _handleWorkerExit(dynamic _) {
    if (_disposed) return;
    _failAllPending(const DbReadWorkerUnavailable('worker exited'));
    _tearDown();
  }

  void _failAllPending(Object error) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.future.ignore();
      _readyCompleter.completeError(error);
    }
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
  }

  void _tearDown() {
    if (_disposed) return;
    _disposed = true;
    _failAllPending(const DbReadWorkerUnavailable('disposed'));
    _deferredLifecycle?.completer.completeError(
      const DbReadWorkerUnavailable('disposed'),
    );
    _deferredLifecycle = null;
    _messagesSub.cancel();
    _errorSub.cancel();
    _exitSub.cancel();
    _receivePort.close();
    _errorPort.close();
    _exitPort.close();
    // ניתוק ה-finalizer של SQLite חייב להסתיים לפני עצירת ה-isolate.
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    if (identical(_slot.instance, this)) _slot.instance = null;
  }
}

/// שגיאה שה-worker החזיר, עם ה-stack מה-isolate שבו נזרקה.
class _WorkerReadError extends StateError {
  _WorkerReadError(super.message, this.stack);

  factory _WorkerReadError.from(Map<dynamic, dynamic> result) =>
      _WorkerReadError(
        result['error'].toString(),
        switch (result['stack']) {
          final String stack => StackTrace.fromString(stack),
          _ => null,
        },
      );

  final StackTrace? stack;
}

/// SQLITE_CORRUPT או SQLITE_NOTADB. השגיאה חוצה את ה-isolate כטקסט, ולכן
/// הקוד נקרא מתוך "SqliteException(N)".
bool _isCorruptDatabaseError(String message) {
  final match = RegExp(r'SqliteException\((\d+)\)').firstMatch(message);
  final code = match == null ? null : int.parse(match.group(1)!);
  return code != null && const {11, 26}.contains(code & 0xFF);
}

class _DeferredLifecycle {
  _DeferredLifecycle() {
    completer.future.ignore();
  }

  bool closed = false;
  bool suspended = false;
  bool mustClose = false;
  final completer = Completer<Object?>();
}

class _WorkerSlot {
  _WorkerSlot(this.name);

  final String name;
  DbReadWorker? instance;
  Future<DbReadWorker>? spawnFuture;
  bool stalled = false;
  final Set<_ReadReservation> reads = {};
  int pendingBytes = 0;
}

class _ReadReservation {
  const _ReadReservation(this.bytes);

  final int bytes;
}

class _FallbackWaiter {
  _FallbackWaiter(this.bytes);

  final int bytes;
  final Completer<void> completer = Completer<void>();
}

int _requestBytes(Object? value) {
  var bytes = 256;
  void count(Object? value) {
    if (bytes > DbReadWorker.maxPendingRequestBytes) return;
    bytes += 32;
    if (value is String) {
      bytes += value.length * 2;
    } else if (value is Map) {
      for (final entry in value.entries) {
        count(entry.key);
        count(entry.value);
        if (bytes > DbReadWorker.maxPendingRequestBytes) break;
      }
    } else if (value is Iterable) {
      for (final item in value) {
        count(item);
        if (bytes > DbReadWorker.maxPendingRequestBytes) break;
      }
    }
  }

  count(value);
  return bytes;
}

class _BatchItem {
  _BatchItem(this.method, this.args);

  final String method;
  final Map<String, Object?> args;
  final Completer<Object?> completer = Completer<Object?>();
}

class _Bootstrap {
  const _Bootstrap({
    required this.mainSendPort,
    required this.queryCache,
    this.bookReadCheckpointPort,
    this.setUpForTesting,
    this.cacheKib,
  });

  final SendPort mainSendPort;
  final Map<String, Map<String, String>> queryCache;
  final SendPort? bookReadCheckpointPort;
  final void Function()? setUpForTesting;

  // קריאת ספר שלם נוגעת בכל דף פעם אחת; מטמון גדול רק מחזיק זיכרון.
  final int? cacheKib;
}

class _Suspended implements Exception {
  const _Suspended();
}

BookTextKey _bookTextKey(Map<String, Object?> args) =>
    (id: args['bookId'] as int, title: args['title'] as String);

/// ספרים שנפתרו כבר על החיבור הנוכחי; מתנקה בכל סגירה.
const _maxResolvedBooks = 4096;

void _workerMain(_Bootstrap bootstrap) {
  bootstrap.setUpForTesting?.call();
  QueryLoader.seedCache(bootstrap.queryCache);
  final receivePort = ReceivePort();
  bootstrap.mainSendPort.send(receivePort.sendPort);

  String? openPath;
  SeforimRepository? repository;
  var suspended = false;
  var closed = false;
  final resolvedBooks = <String, db_models.Book?>{};

  bool closeConnection() {
    final closing = repository;
    repository = null;
    openPath = null;
    resolvedBooks.clear();
    try {
      closing?.database.close();
      return true;
    } catch (e) {
      debugPrint('[DbReadWorker] close failed: $e');
      return false;
    }
  }

  Future<SeforimRepository> ensureRepo(String path) async {
    if (suspended || closed) throw const _Suspended();
    final current = repository;
    if (current != null && openPath == path) return current;
    closeConnection();
    final repo = SeforimRepository(
      MyDatabase.withPath(path, readOnly: true, official: true),
    );
    try {
      await repo.ensureInitialized();
      final cacheKib = bootstrap.cacheKib;
      if (cacheKib != null) {
        await repo.executeRawQuery('PRAGMA cache_size=-$cacheKib');
      }
    } catch (_) {
      repo.database.close();
      rethrow;
    }
    repository = repo;
    openPath = path;
    return repo;
  }

  Future<db_models.Book?> resolveOfficialBook(
    SeforimRepository repo,
    String title,
    int? categoryId,
  ) async {
    final key = '$title\u0000${categoryId ?? ''}';
    if (resolvedBooks.containsKey(key)) return resolvedBooks[key];
    final resolved = await BookDatabaseResolver.resolveBookInCandidates(
      title: title,
      candidates: [
        ResolvedBookRepositoryCandidate(
          repository: repo,
          source: BookSource.official,
        ),
      ],
      categoryId: categoryId,
    );
    if (resolvedBooks.length >= _maxResolvedBooks) resolvedBooks.clear();
    return resolvedBooks[key] = resolved?.book;
  }

  // קריאת ספר שלם נמשכת שניות: suspend/close שהגיע קוטע אותה, במקום שיפוג
  // ה-timeout שלו ועדכון הספרייה ייכשל על קובץ תפוס.
  Future<void> yieldToControls() async {
    await Future<void>.delayed(Duration.zero);
    if (suspended || closed) throw const _Suspended();
  }

  Future<void> bookReadCheckpoint() async {
    final checkpointPort = bootstrap.bookReadCheckpointPort;
    if (checkpointPort != null) {
      final release = ReceivePort();
      try {
        checkpointPort.send(release.sendPort);
        await release.first;
      } finally {
        release.close();
      }
    }
    await yieldToControls();
  }

  Future<Object?> dispatch(String method, Map<String, Object?> args) async {
    switch (method) {
      case 'suspend':
        suspended = true;
        return closeConnection();
      case 'resume':
        suspended = false;
        return null;
      case 'close':
        closed = true;
        return closeConnection();
      case 'open':
        closed = false;
        return null;
      case 'lifecycleState':
        closed = args['closed'] as bool;
        suspended = args['suspended'] as bool;
        return args['mustClose'] == true || closed || suspended
            ? closeConnection()
            : true;
      case 'clearBookCache':
        resolvedBooks.clear();
        return null;
      case 'shrinkMemory':
        return repository?.database.shrinkMemoryIfOpen() ?? false;
      case 'cacheSizeForTesting':
        final repo = await ensureRepo(args['dbPath'] as String);
        final db = await repo.database.database;
        return db.select('PRAGMA cache_size').single.values.single;
      case 'linkContent':
        final repo = await ensureRepo(args['dbPath'] as String);
        final book = await resolveOfficialBook(
          repo,
          args['title'] as String,
          args['categoryId'] as int?,
        );
        return _officialLinkContent(repo, book, args);
      case 'bookRead':
        final repo = await ensureRepo(args['dbPath'] as String);
        return _readBooks(repo, args);
      case 'breadcrumb' || 'heRef':
        final repo = await ensureRepo(args['dbPath'] as String);
        return _readLineRef(repo, method, args);
      case 'lineContents' || 'lines':
        final repo = await ensureRepo(args['dbPath'] as String);
        return _readBookLines(repo, method, args);
      case 'commentatorsByBook':
        final repo = await ensureRepo(args['dbPath'] as String);
        return repo.database.linkDao.selectCommentatorsByBook(
          args['bookId'] as int,
        );
      case 'bookCatalog':
        final repo = await ensureRepo(args['dbPath'] as String);
        return (
          books: await repo.getAllBooksLean(),
          categories: await repo.getAllCategories(),
        );
      case 'siblingCommentaryRows':
        final repo = await ensureRepo(args['dbPath'] as String);
        return _readSiblingCommentaryRows(repo, args);
      case 'bookText':
        final repo = await ensureRepo(args['dbPath'] as String);
        return readBookContentText(
          await repo.database.database,
          _bookTextKey(args),
          checkpoint: bookReadCheckpoint,
        );
      case 'bookTextBytes':
        final repo = await ensureRepo(args['dbPath'] as String);
        return readBookContentTransferable(
          await repo.database.database,
          _bookTextKey(args),
          checkpoint: bookReadCheckpoint,
        );
      default:
        final repo = await ensureRepo(args['dbPath'] as String);
        final connection = (
          db: await repo.database.database,
          capabilities: await repo.database.capabilities,
        );
        return runRangeRequestOnConnection(method, args, connection);
    }
  }

  Future<Map<String, Object?>> runItem(
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      if (method == 'batch') {
        final results = <Map<String, Object?>>[];
        for (final item in (args['items'] as List).cast<Map>()) {
          // השאילתות סינכרוניות: בלי ויתור על תור האירועים suspend/close שהגיע
          // לא ייקלט עד סוף ה-batch.
          if (results.isNotEmpty) await Future<void>.delayed(Duration.zero);
          results.add(
            await runItem(
              item['method'] as String,
              (item['args'] as Map).cast<String, Object?>(),
            ),
          );
        }
        return {'result': results};
      }
      return {'result': await dispatch(method, args)};
    } on _Suspended {
      return const {'suspended': true};
    } catch (e, stackTrace) {
      return {'error': e.toString(), 'stack': '$stackTrace'};
    }
  }

  // עיבוד סדרתי: פקודת סגירה לא תסגור חיבור באמצע שאילתה בנקודת await.
  final controls = <Map>[];
  final queue = <Map>[];
  var draining = false;

  Future<void> drain() async {
    if (draining) return;
    draining = true;
    try {
      while (controls.isNotEmpty || queue.isNotEmpty) {
        // מחזור באירועים: פקודת בקרה שכבר הגיעה נקלטת לפני הבקשה הבאה.
        await Future<void>.delayed(Duration.zero);
        if (controls.isEmpty && queue.isEmpty) break;
        final message = controls.isNotEmpty
            ? controls.removeAt(0)
            : queue.removeAt(0);
        final reply = await runItem(
          message['method'] as String,
          (message['args'] as Map).cast<String, Object?>(),
        );
        bootstrap.mainSendPort.send({'id': message['id'], ...reply});
      }
    } finally {
      draining = false;
    }
  }

  receivePort.listen((dynamic message) {
    if (message is! Map) return;
    final method = message['method'];
    if (const {
      'suspend',
      'resume',
      'close',
      'open',
      'lifecycleState',
      'clearBookCache',
      'shrinkMemory',
    }.contains(method)) {
      final state = method == 'lifecycleState' ? message['args'] as Map : null;
      final suspend = method == 'suspend' || state?['suspended'] == true;
      final close =
          method == 'close' ||
          state?['closed'] == true ||
          state?['mustClose'] == true;
      if (suspend || close) {
        // הדגל נקבע כבר כאן, כדי שגם פריטי batch שרץ כעת לא יתחילו שאילתה חדשה
        // ולא יפתחו מחדש את החיבור לפני שהפקודה עצמה מבוצעת.
        if (suspend) suspended = true;
        if (close) closed = true;
        for (final queued in queue) {
          bootstrap.mainSendPort.send({'id': queued['id'], 'suspended': true});
        }
        queue.clear();
      }
      controls.add(message);
    } else {
      queue.add(message);
    }
    drain();
  });
}
