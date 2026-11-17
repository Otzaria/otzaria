import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/repository/data_repository.dart';

/// חיפוש בספרייה שהוחלף בחיפוש חדש יותר עם אותו מפתח, לפני שתוצאתו נמסרה.
class BookSearchSupersededException implements Exception {
  const BookSearchSupersededException();

  @override
  String toString() => 'BookSearchSupersededException';
}

/// isolate קבוע לחיפוש בספרייה: מקבל את רשומות הספרייה רק כשהן משתנות, ואת
/// השאילתות כהודעות. נוצר בחיפוש הראשון; כשל שלו מעביר ל-[Isolate.run] חד-פעמי.
class BookSearchWorker {
  SendPort? _toWorker;
  Completer<SendPort>? _starting;
  RawReceivePort? _fromWorker;
  Isolate? _isolate;
  bool _failed = false;

  /// הרשומות שהאינדקס ב-worker נבנה מהן.
  List<BookSearchEntry>? _workerEntries;

  // FIFO dequeue must remain O(1) even with many queued search requests.
  final Queue<_BookSearchJob> _queue = Queue<_BookSearchJob>();
  _BookSearchJob? _inFlight;
  Completer<List<int>>? _reply;

  @visibleForTesting
  int indexUploads = 0;

  @visibleForTesting
  bool get usesWorker => !_failed;

  /// מחפש את [query] ברשומות [entries]. חיפוש חדש עם אותו [supersedeKey]
  /// מבטל את הקודם, שנכשל ב-[BookSearchSupersededException].
  Future<List<int>> search(
    List<BookSearchEntry> entries,
    BookSearchQuery query, {
    Object? supersedeKey,
  }) {
    if (supersedeKey != null) {
      _queue.removeWhere((job) {
        if (job.supersedeKey != supersedeKey) return false;
        job.result.completeError(const BookSearchSupersededException());
        return true;
      });
      final inFlight = _inFlight;
      if (inFlight != null && inFlight.supersedeKey == supersedeKey) {
        inFlight.superseded = true;
      }
    }
    final job = _BookSearchJob(entries, query, supersedeKey);
    _queue.add(job);
    _pump();
    return job.result.future;
  }

  void _pump() {
    if (_inFlight != null || _queue.isEmpty) return;
    final job = _inFlight = _queue.removeFirst();
    unawaited(_run(job));
  }

  Future<void> _run(_BookSearchJob job) async {
    try {
      List<int> indices;
      try {
        indices = await _searchOnWorker(job);
      } catch (error) {
        debugPrint('[BookSearchWorker] falling back to Isolate.run: $error');
        indices = await _searchInFreshIsolate(job.entries, job.query);
      }
      if (job.superseded) {
        job.result.completeError(const BookSearchSupersededException());
      } else {
        job.result.complete(indices);
      }
    } catch (error, stackTrace) {
      job.result.completeError(error, stackTrace);
    } finally {
      _inFlight = null;
      _pump();
    }
  }

  Future<List<int>> _searchOnWorker(_BookSearchJob job) async {
    final port = await _ensureStarted();
    if (!identical(port, _toWorker)) {
      throw StateError('book search worker disposed before sending');
    }
    if (!_sameEntries(_workerEntries, job.entries)) {
      indexUploads++;
      port.send(_SetIndexMessage(job.entries));
    }
    _workerEntries = job.entries;
    final reply = _reply = Completer<List<int>>();
    port.send(job.query);
    return reply.future;
  }

  Future<SendPort> _ensureStarted() {
    if (_failed) {
      return Future.error(StateError('book search worker unavailable'));
    }
    final port = _toWorker;
    if (port != null) return Future.value(port);
    final starting = _starting;
    if (starting != null) return starting.future;
    final completer = _starting = Completer<SendPort>();
    final fromWorker = _fromWorker = RawReceivePort(
      _onMessage,
      'book search worker replies',
    )..keepIsolateAlive = false;
    Isolate.spawn(
      _bookSearchWorkerMain,
      fromWorker.sendPort,
      onExit: fromWorker.sendPort,
      onError: fromWorker.sendPort,
      debugName: 'book search worker',
    ).then(
      (isolate) {
        // dispose קרה בזמן ההקמה — ה-isolate הזה כבר אינו בשימוש.
        if (identical(_fromWorker, fromWorker)) {
          _isolate = isolate;
        } else {
          isolate.kill(priority: Isolate.immediate);
        }
      },
      onError: (Object error) {
        if (identical(_fromWorker, fromWorker)) _shutDown(error);
      },
    );
    return completer.future;
  }

  void _onMessage(Object? message) {
    switch (message) {
      case SendPort port:
        _toWorker = port;
        _starting?.complete(port);
        _starting = null;
      case _SearchReply(:final indices?):
        _takeReply()?.complete(indices);
      case _SearchReply(:final error):
        // שגיאה בשאילתה אחת אינה פוסלת את ה-worker; Isolate.run יחזור עליה.
        _takeReply()?.completeError(StateError('$error'));
      default:
        // null מ-onExit, או [error, stack] מ-onError.
        _shutDown(StateError('book search worker exited: $message'));
    }
  }

  Completer<List<int>>? _takeReply() {
    final reply = _reply;
    _reply = null;
    return reply;
  }

  void _shutDown(Object error) {
    _failed = true;
    _release();
    _starting?.completeError(error);
    _starting = null;
    _takeReply()?.completeError(error);
  }

  void _release() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker?.close();
    _fromWorker = null;
    _toWorker = null;
    _workerEntries = null;
  }

  /// סוגר את ה-isolate ומשחרר את האינדקס; החיפוש הבא יפתח אותו מחדש.
  void dispose() {
    final error = StateError('book search worker disposed');
    _release();
    _starting?.completeError(error);
    _starting = null;
    _takeReply()?.completeError(error);
  }

  static bool _sameEntries(
    List<BookSearchEntry>? previous,
    List<BookSearchEntry> next,
  ) {
    if (identical(previous, next)) return true;
    if (previous == null || previous.length != next.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (!previous[i].sameAs(next[i])) return false;
    }
    return true;
  }
}

/// מסלול הגיבוי. פונקציה עליונה כדי שה-closure לא ילכוד את מצב ה-worker.
Future<List<int>> _searchInFreshIsolate(
  List<BookSearchEntry> entries,
  BookSearchQuery query,
) => Isolate.run(() => PreparedBookSearchIndex(entries).search(query));

class _BookSearchJob {
  _BookSearchJob(this.entries, this.query, this.supersedeKey);

  final List<BookSearchEntry> entries;
  final BookSearchQuery query;
  final Object? supersedeKey;
  final Completer<List<int>> result = Completer<List<int>>();
  bool superseded = false;
}

class _SetIndexMessage {
  const _SetIndexMessage(this.entries);

  final List<BookSearchEntry> entries;
}

class _SearchReply {
  const _SearchReply({this.indices, this.error});

  final List<int>? indices;
  final String? error;
}

void _bookSearchWorkerMain(SendPort replies) {
  PreparedBookSearchIndex? index;
  final inbox = RawReceivePort();
  inbox.handler = (Object? message) {
    switch (message) {
      case _SetIndexMessage(:final entries):
        index = null;
        index = PreparedBookSearchIndex(entries);
      case BookSearchQuery query:
        try {
          replies.send(_SearchReply(indices: index!.search(query)));
        } catch (error, stackTrace) {
          replies.send(_SearchReply(error: '$error\n$stackTrace'));
        }
    }
  };
  replies.send(inbox.sendPort);
}
