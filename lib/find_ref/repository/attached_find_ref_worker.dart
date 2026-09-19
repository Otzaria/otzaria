import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

/// עבודה על מאגר של מסד מצורף, שרצה בתוך ה-worker. חייבת להיווצר בפונקציה
/// סטטית: סגור שנוצר במתודת מופע גורר את `this` ל-isolate.
typedef AttachedDbJob<R> = Future<R> Function(SeforimRepository repository);

/// isolate ארוך-חיים ששאילתות "איתור מקורות" על מסדים מצורפים רצות בו —
/// החיבור הסינכרוני (FFI) לא יחסום את ההקלדה ב-main isolate.
///
/// החיבורים נפתחים בו בפתיחה מוקשחת לפי נתיב, ונסגרים אחרי [idleClose].
/// קריאה שלא חזרה תוך [callTimeout] נוטשת את ה-worker (ייתכן שהוא תקוע
/// בקריאה נייטיב) ומשביתה את המסד ל-[failureBackoff].
class AttachedFindRefWorker {
  AttachedFindRefWorker._();

  static final AttachedFindRefWorker instance = AttachedFindRefWorker._();

  @visibleForTesting
  static Duration callTimeout = const Duration(seconds: 5);
  static Duration idleClose = const Duration(minutes: 1);
  static Duration failureBackoff = const Duration(minutes: 1);

  Isolate? _isolate;
  Future<SendPort>? _port;
  final Map<String, DateTime> _failedUntil = {};

  /// מריץ את [job] על המסד שב-[path]. [version] מזהה את תוכן הקובץ; שינוי
  /// שלו סוגר את החיבור הקודם לאותו נתיב.
  Future<R> run<R>(
    String path, {
    required bool immutable,
    required String version,
    required AttachedDbJob<R> job,
  }) async {
    final failedUntil = _failedUntil[path];
    if (failedUntil != null && failedUntil.isAfter(DateTime.now())) {
      throw StateError('attached library unavailable: $path');
    }
    final portFuture = _port ??= _spawn();
    final port = await portFuture;
    final reply = ReceivePort();
    _pending.add(reply);
    try {
      port.send(
        _Request(path, immutable, version, job, reply.sendPort),
      );
      final message = await reply.first.timeout(callTimeout);
      if (message is _Failure) throw StateError(message.error);
      return message as R;
    } on TimeoutException {
      _failedUntil[path] = DateTime.now().add(failureBackoff);
      if (identical(_port, portFuture)) _abandon();
      rethrow;
    } finally {
      _pending.remove(reply);
      reply.close();
    }
  }

  final Set<ReceivePort> _pending = {};

  /// סוגר את ה-worker ואת כל חיבוריו — משחרר את קבצי המסדים (ניתוק, שינוי
  /// ברשימה). קריאות שממתינות נכשלות מיד, בלי להשבית את המסד.
  void reset() {
    _failedUntil.clear();
    for (final reply in _pending) {
      reply.close();
    }
    _abandon();
  }

  void _abandon() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
  }

  Future<SendPort> _spawn() async {
    // rootBundle אינו זמין ב-isolate — השאילתות עוברות כ-snapshot.
    await QueryLoader.initialize();
    final ready = ReceivePort();
    try {
      _isolate = await Isolate.spawn<_Bootstrap>(
        _workerMain,
        _Bootstrap(ready.sendPort, QueryLoader.cacheSnapshot, idleClose),
        debugName: 'attached_find_ref_worker',
      );
      return await ready.first as SendPort;
    } catch (_) {
      _port = null;
      rethrow;
    } finally {
      ready.close();
    }
  }

  static void _workerMain(_Bootstrap bootstrap) {
    QueryLoader.seedCache(bootstrap.queryCache);
    final inbox = ReceivePort();
    final open = <String, _OpenDb>{};
    var tail = Future<void>.value();

    Timer.periodic(bootstrap.idleClose ~/ 2, (_) {
      final cutoff = DateTime.now().subtract(bootstrap.idleClose);
      open.removeWhere((_, entry) {
        if (!entry.lastUsed.isBefore(cutoff)) return false;
        entry.repository.database.retire();
        return true;
      });
    });

    Future<void> handle(_Request request) async {
      try {
        var entry = open[request.path];
        if (entry != null && entry.version != request.version) {
          entry.repository.database.retire();
          open.remove(request.path);
          entry = null;
        }
        entry ??= open[request.path] = await _openDb(request);
        entry.lastUsed = DateTime.now();
        request.reply.send(await request.job(entry.repository));
      } catch (e) {
        request.reply.send(_Failure('$e'));
      }
    }

    // בקשה אחת בכל פעם: הקריאות סינכרוניות ממילא, והפתיחה לא תוכפל.
    inbox.listen((message) {
      tail = tail.then((_) => handle(message as _Request));
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
  const _Bootstrap(this.ready, this.queryCache, this.idleClose);

  final SendPort ready;
  final Map<String, Map<String, String>> queryCache;
  final Duration idleClose;
}

class _Request {
  const _Request(this.path, this.immutable, this.version, this.job, this.reply);

  final String path;
  final bool immutable;
  final String version;
  final AttachedDbJob<Object?> job;
  final SendPort reply;
}

class _Failure {
  const _Failure(this.error);

  final String error;
}
