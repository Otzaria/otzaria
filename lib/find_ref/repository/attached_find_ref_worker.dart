import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart'
    show FindRefQueryCancelled;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

/// עבודה ב-worker, שנוצרת בפונקציה סטטית כדי שלא תגרור `this` ל-isolate.
typedef AttachedDbJob<R> = Future<R> Function(SeforimRepository repository);

/// עובד נפרד למסדים משניים; אצוות מתקדמות ספר אחד בכל תור.
/// עבודה פעילה תקועה משחררת את העובד ומשביתה את המסד זמנית.
class AttachedFindRefWorker {
  AttachedFindRefWorker._();

  static final AttachedFindRefWorker instance = AttachedFindRefWorker._();

  @visibleForTesting
  static Duration callTimeout = const Duration(seconds: 5);

  /// תוספת לכל שאילתה נוספת בעבודה מאוגדת — כונן תקוע מזוהה כמעט באותו זמן.
  @visibleForTesting
  static Duration perCallTimeout = const Duration(milliseconds: 250);
  static Duration idleClose = const Duration(minutes: 1);
  static Duration failureBackoff = const Duration(minutes: 1);

  Isolate? _isolate;
  Future<SendPort>? _port;
  final Map<String, DateTime> _failedUntil = {};

  static int _nextScope = 0;

  /// זהות נפרדת לכל מאגר, כדי שחלון אחד לא יבטל חלון אחר.
  static int allocateSearchScope() {
    final scope = ++_nextScope;
    instance._epochs[scope] = 0;
    return scope;
  }

  final Map<int, int> _epochs = {};
  int _generation = 0;

  /// מבטל את יתר העבודות של דורות ישנים באותו מאגר.
  void cancelSearchScope(int scope, int epoch) {
    _epochs[scope] = epoch;
    _commandPort?.send(_Cancel(scope, epoch));
  }

  /// משחרר מאגר שנסגר ועוצר גם את המשך האצווה הפעילה שלו.
  void releaseSearchScope(int scope) {
    _epochs.remove(scope);
    _commandPort?.send(_Release(scope));
  }

  SendPort? _commandPort;

  /// מריץ עבודה אחת; ההמתנה בתור אינה נחשבת לזמן הריצה שלה.
  Future<R> run<R>(
    String path, {
    required bool immutable,
    required String version,
    required AttachedDbJob<R> job,
    int calls = 1,
  }) async => (await _run<R>(
    path,
    immutable: immutable,
    version: version,
    jobs: [job],
    calls: calls,
  )).single;

  /// שולח אצווה אחת; כל עבודה חוזרת לסוף התור ומאפשרת ביטול בין ספרים.
  Future<List<R>> runBatch<R>(
    String path, {
    required bool immutable,
    required String version,
    required List<AttachedDbJob<R>> jobs,
    required int searchScope,
    required int searchEpoch,
  }) => _run<R>(
    path,
    immutable: immutable,
    version: version,
    jobs: jobs,
    searchScope: searchScope,
    searchEpoch: searchEpoch,
  );

  Future<List<R>> _run<R>(
    String path, {
    required bool immutable,
    required String version,
    required List<AttachedDbJob<R>> jobs,
    int calls = 1,
    int? searchScope,
    int? searchEpoch,
  }) async {
    if (jobs.isEmpty) return [];
    final failedUntil = _failedUntil[path];
    if (failedUntil != null && failedUntil.isAfter(DateTime.now())) {
      throw StateError('attached library unavailable: $path');
    }
    final generation = _generation;
    final portFuture = _port ??= _spawn();
    final port = await portFuture;
    if (generation != _generation) throw StateError('secondary worker stopped');
    if (searchScope != null &&
        (!_epochs.containsKey(searchScope) ||
            searchEpoch! < _epochs[searchScope]!)) {
      throw const FindRefQueryCancelled();
    }
    final reply = ReceivePort();
    final result = Completer<List<R>>();
    Timer? timer;
    _pending.add(reply);
    reply.listen(
      (message) {
        if (message is _Started) {
          timer = Timer(callTimeout + perCallTimeout * (calls - 1), () {
            result.completeError(
              TimeoutException('secondary database job', callTimeout),
            );
            _failedUntil[path] = DateTime.now().add(failureBackoff);
            if (identical(_port, portFuture)) _abandon();
          });
        } else if (message is _Progress) {
          timer?.cancel();
        } else if (message is _Cancelled) {
          result.completeError(const FindRefQueryCancelled());
        } else if (message is _Failure) {
          result.completeError(StateError(message.error));
        } else {
          result.complete((message as List).cast<R>());
        }
      },
      onDone: () {
        if (!result.isCompleted) {
          result.completeError(StateError('secondary worker stopped'));
        }
      },
    );
    try {
      port.send(
        _Request(
          path,
          immutable,
          version,
          jobs,
          reply.sendPort,
          searchScope,
          searchEpoch,
        ),
      );
      return await result.future;
    } finally {
      timer?.cancel();
      _pending.remove(reply);
      reply.close();
    }
  }

  final Set<ReceivePort> _pending = {};

  /// סוגר את ה-worker ואת כל חיבוריו — משחרר את קבצי המסדים (ניתוק, שינוי
  /// ברשימה). קריאות שממתינות נכשלות מיד, בלי להשבית את המסד.
  void reset() {
    _failedUntil.clear();
    _abandon();
  }

  void _abandon() {
    _generation++;
    for (final reply in _pending) {
      reply.close();
    }
    _pending.clear();
    _commandPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
  }

  Future<SendPort> _spawn() async {
    // rootBundle אינו זמין ב-isolate — השאילתות עוברות כ-snapshot.
    final generation = _generation;
    await QueryLoader.initialize();
    if (generation != _generation) throw StateError('secondary worker stopped');
    final ready = ReceivePort();
    _pending.add(ready);
    try {
      final isolate = await Isolate.spawn<_Bootstrap>(
        _workerMain,
        _Bootstrap(
          ready.sendPort,
          QueryLoader.cacheSnapshot,
          idleClose,
          Map.of(_epochs),
        ),
        debugName: 'attached_find_ref_worker',
      );
      if (generation != _generation) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('secondary worker stopped');
      }
      _isolate = isolate;
      final port = await ready.first as SendPort;
      if (generation != _generation) {
        throw StateError('secondary worker stopped');
      }
      return _commandPort = port;
    } catch (_) {
      if (generation == _generation) _port = null;
      rethrow;
    } finally {
      _pending.remove(ready);
      ready.close();
    }
  }

  static void _workerMain(_Bootstrap bootstrap) {
    QueryLoader.seedCache(bootstrap.queryCache);
    final inbox = ReceivePort();
    final open = <String, _OpenDb>{};
    final queue = Queue<_Request>();
    final epochs = bootstrap.epochs;
    var running = false;
    _Request? active;
    bool cancelled(_Request request) =>
        request.cancelled ||
        (request.scope != null &&
            request.epoch! < (epochs[request.scope] ?? 0));

    Timer.periodic(bootstrap.idleClose ~/ 2, (_) {
      final cutoff = DateTime.now().subtract(bootstrap.idleClose);
      open.removeWhere((_, entry) {
        if (!entry.lastUsed.isBefore(cutoff)) return false;
        entry.repository.database.retire();
        return true;
      });
    });

    Future<void> handle(_Request request) async {
      request.reply.send(const _Started());
      try {
        var entry = open[request.path];
        if (entry != null && entry.version != request.version) {
          entry.repository.database.retire();
          open.remove(request.path);
          entry = null;
        }
        entry ??= open[request.path] = await _openDb(request);
        entry.lastUsed = DateTime.now();
        request.results.add(
          await request.jobs[request.index++](entry.repository),
        );
        if (cancelled(request)) {
          request.reply.send(const _Cancelled());
        } else if (request.index == request.jobs.length) {
          request.reply.send(request.results);
        } else {
          request.reply.send(const _Progress());
          queue.add(request);
        }
      } catch (e) {
        request.reply.send(_Failure('$e'));
      }
    }

    Future<void> drain() async {
      if (running || queue.isEmpty) return;
      final request = queue.removeFirst();
      if (cancelled(request)) {
        request.reply.send(const _Cancelled());
      } else {
        running = true;
        active = request;
        await handle(request);
        active = null;
        running = false;
      }
      if (queue.isNotEmpty) inbox.sendPort.send(const _Drain());
    }

    inbox.listen((message) {
      if (message is _Cancel) {
        epochs[message.scope] = message.epoch;
        if (active?.scope == message.scope && cancelled(active!)) {
          active!.cancelled = true;
        }
        queue.removeWhere((request) {
          if (!cancelled(request)) return false;
          request.reply.send(const _Cancelled());
          return true;
        });
      } else if (message is _Release) {
        if (active?.scope == message.scope) active!.cancelled = true;
        queue.removeWhere((request) {
          if (request.scope != message.scope) return false;
          request.reply.send(const _Cancelled());
          return true;
        });
        epochs.remove(message.scope);
      } else if (message is _Request) {
        queue.add(message);
        inbox.sendPort.send(const _Drain());
      } else if (message is _Drain) {
        unawaited(drain());
      }
    });
    bootstrap.ready.send(inbox.sendPort);
  }

  static Future<_OpenDb> _openDb(_Request request) async {
    if (!File(request.path).existsSync()) {
      throw StateError('missing file: ${request.path}');
    }
    final database = MyDatabase.untrusted(
      request.path,
      immutable: request.immutable,
    );
    final repository = SeforimRepository(database);
    try {
      await repository.ensureInitialized();
      // ensureInitialized בולע כשלי קריאה — שאילתה מפורשת מאמתת שהקובץ נפתח.
      await database.capabilities;
    } catch (_) {
      database.retire();
      rethrow;
    }
    return _OpenDb(repository, request.version);
  }
}

class _OpenDb {
  _OpenDb(this.repository, this.version);

  final SeforimRepository repository;
  final String version;
  DateTime lastUsed = DateTime.now();
}

class _Bootstrap {
  const _Bootstrap(this.ready, this.queryCache, this.idleClose, this.epochs);

  final SendPort ready;
  final Map<String, Map<String, String>> queryCache;
  final Duration idleClose;
  final Map<int, int> epochs;
}

class _Request {
  _Request(
    this.path,
    this.immutable,
    this.version,
    this.jobs,
    this.reply,
    this.scope,
    this.epoch,
  );

  final String path;
  final bool immutable;
  final String version;
  final List<AttachedDbJob<Object?>> jobs;
  final int? scope;
  final int? epoch;
  int index = 0;
  bool cancelled = false;
  final List<Object?> results = [];
  final SendPort reply;
}

class _Failure {
  const _Failure(this.error);

  final String error;
}

class _Started {
  const _Started();
}

class _Progress {
  const _Progress();
}

class _Drain {
  const _Drain();
}

class _Cancelled {
  const _Cancelled();
}

class _Cancel {
  const _Cancel(this.scope, this.epoch);
  final int scope;
  final int epoch;
}

class _Release {
  const _Release(this.scope);
  final int scope;
}
