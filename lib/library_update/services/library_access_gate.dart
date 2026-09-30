import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/windowing/library_suspension_marker.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';

/// חלון אחר לא שחרר את הספרייה בזמן. הספרייה כבר חודשה בכל החלונות.
class LibrarySuspendFailed implements Exception {
  const LibrarySuspendFailed(this.message, {this.slots = const []});

  final String message;

  /// המשבצות שלא אישרו.
  final List<int> slots;

  @override
  String toString() => 'LibrarySuspendFailed: $message';
}

/// מסד הספרייה עדיין פתוח בתהליך אחרי שכל החלונות אישרו סגירה.
class LibraryStillOpenException implements Exception {
  const LibraryStillOpenException(this.path, this.detail);

  final String path;
  final String detail;

  @override
  String toString() =>
      'LibraryStillOpenException: $path is still open in this process '
      '($detail)';
}

/// הסגירה והפתיחה-מחדש של הספרייה ב-isolate אחד.
class LibraryAccessRoutine {
  const LibraryAccessRoutine({required this.suspend, required this.resume});

  /// חייב לחזור רק אחרי שכל ה-handles נסגרו בפועל, ולזרוק אם לא.
  final Future<void> Function() suspend;
  final Future<void> Function(bool dbReplaced) resume;
}

/// השעיה פעילה שהוחזרה מ-[LibraryAccessGate.suspendAll].
class LibrarySuspension {
  LibrarySuspension._(this.operationId);

  final String operationId;
  final Set<int> _sent = {};
  final Set<int> _acked = {};
  bool _resumed = false;

  /// המשבצות שאישרו שחרור.
  Set<int> get releasedSlots => Set.unmodifiable(_acked);

  bool get isResumed => _resumed;
}

/// מאפשר ל-[LibraryAccessGate.runExclusive] לדעת אם המסד הוחלף.
class LibraryExclusiveScope {
  LibraryExclusiveScope._();

  bool _dbReplaced = false;

  bool get dbReplaced => _dbReplaced;

  /// לקרוא מיד אחרי נקודת האל-חזור (למשל ה-rename), כדי שכל החלונות ירעננו.
  void markDbReplaced() => _dbReplaced = true;
}

/// מבטיח שאף isolate בתהליך אינו מחזיק את מסד הספרייה.
///
/// כל חלון הוא isolate נפרד עם חיבורים משלו, ו-`closeForExternalWrite`
/// סוגר רק את אלה של ה-isolate שקורא לו. החלפת בסיס, דחיסה או rename
/// נכשלים (ב-Windows) או מקבלים busy כל עוד חלון אחר פתוח.
///
/// הפרוטוקול: `library.suspend` לכל חלון, והוא מאשר רק אחרי שסגר את
/// ה-provider, ה-DbReadWorker וה-FindRef; אחר כך `library.resume` עם
/// התוצאה. חלון שנפתח באמצע ממתין ל-[LibrarySuspensionMarker].
///
/// שימוש (A3/A4 — דחיסה, installZdb):
/// ```dart
/// await LibraryAccessGate.instance.runExclusive(
///   dbPath: dbPath,
///   body: (scope) async {
///     installZdb(...);
///     scope.markDbReplaced();
///   },
/// );
/// ```
/// זורק [LibrarySuspendFailed] או [LibraryStillOpenException] לפני ש-body
/// רץ, ואז הספרייה כבר פתוחה שוב בכל מקום. לא רה-אנטרנטי.
class LibraryAccessGate {
  LibraryAccessGate({
    WindowBus? bus,
    LibraryAccessRoutine? selfAccess,
    LibraryAccessRoutine? peerAccess,
    this.ackTimeout = const Duration(seconds: 20),
    this.resumeTimeout = const Duration(seconds: 30),
    this.leaseCheckInterval = const Duration(seconds: 2),
    this.maxSweeps = 3,
    bool Function(String path)? isOpenInProcess,
    bool? renameProbe,
    void Function(String title, Object error, StackTrace? stackTrace)? logError,
  }) : _logError = logError ?? _appendToErrorLog,
       _bus = bus ?? WindowBus.instance,
       selfAccess = selfAccess ?? _sqliteSelfAccess,
       peerAccess = peerAccess ?? _sqlitePeerAccess,
       _isOpenInProcess = isOpenInProcess ?? isLibraryDbOpenInProcess,
       _renameProbe = renameProbe ?? Platform.isWindows;

  static LibraryAccessGate instance = LibraryAccessGate();

  static const String requestSuspend = 'library.suspend';
  static const String requestResume = 'library.resume';

  final WindowBus _bus;
  final LibraryAccessRoutine selfAccess;
  final LibraryAccessRoutine peerAccess;
  final Duration ackTimeout;

  /// החלון המשני מרענן לפני שהוא מאשר חידוש, ולכן זה ארוך מ-[ackTimeout].
  final Duration resumeTimeout;
  final Duration leaseCheckInterval;

  /// סבבים שבהם נשלח suspend גם לחלונות שנרשמו באמצע.
  final int maxSweeps;
  final bool Function(String path) _isOpenInProcess;
  final bool _renameProbe;
  final void Function(String title, Object error, StackTrace? stackTrace)
  _logError;

  static void _appendToErrorLog(
    String title,
    Object error,
    StackTrace? stackTrace,
  ) {
    try {
      ErrorLogFile.append(
        title: 'Library access gate: $title',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}
  }

  /// נקרא בחלון משני אחרי ריענון על מסד שהוחלף — כדי לבנות מחדש את העץ.
  void Function()? onLibraryReplaced;

  static final LibraryAccessRoutine _sqliteSelfAccess = LibraryAccessRoutine(
    suspend: () => SqliteDataProvider.instance.closeForExternalWrite(),
    // הרענון של החלון המתאם נעשה אצל הקורא, עם דיווח ההתקדמות שלו.
    resume: (_) => SqliteDataProvider.instance.reopenAfterExternalWrite(),
  );

  static final LibraryAccessRoutine _sqlitePeerAccess = LibraryAccessRoutine(
    suspend: () => SqliteDataProvider.instance.closeForExternalWrite(),
    resume: (dbReplaced) async {
      if (!dbReplaced) {
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
        return;
      }
      // פתיחה ישירה הייתה נכנסת ל-initialize לפני שהקאשים של המסד הישן נוקו.
      await SqliteDataProvider.instance.reopenAfterExternalWrite(
        reopenDatabase: false,
      );
      await const LibraryRuntimeRefreshService().refreshAfterDbUpdate();
    },
  );

  LibrarySuspension? _active;
  int _counter = 0;

  /// האם השעיה שהתחילה כאן עדיין פעילה.
  bool get isSuspending => _active != null;

  // ---------------------------------------------------------------- מתאם

  /// משעה את הספרייה בכל שאר החלונות וממתין לאישור שכל ה-handles נסגרו.
  ///
  /// אינו סוגר את ה-isolate הנוכחי — זה תפקיד [selfAccess] / הקורא. בכשל
  /// זורק [LibrarySuspendFailed] אחרי שכבר שלח resume לכולם.
  Future<LibrarySuspension> suspendAll() async {
    if (_active != null) {
      throw StateError('LibraryAccessGate.suspendAll is not reentrant');
    }
    if (!LibrarySuspensionMarker.acquire()) {
      throw const LibrarySuspendFailed(
        'חלון אחר כבר מחליף את מסד הספרייה. נסו שוב בעוד רגע.',
      );
    }
    final suspension = LibrarySuspension._(
      '$pid-${DateTime.now().microsecondsSinceEpoch}-${++_counter}',
    );
    _active = suspension;
    try {
      final failed = <int>{};
      var pending = const <int>[];
      for (var sweep = 0; sweep < maxSweeps; sweep++) {
        pending = _unackedSlots(suspension);
        if (pending.isEmpty) break;
        final outcomes = await Future.wait([
          for (final slot in pending) _suspendPeer(suspension, slot),
        ]);
        for (var i = 0; i < pending.length; i++) {
          if (outcomes[i] == _PeerOutcome.failed) failed.add(pending[i]);
        }
        if (failed.isNotEmpty) break;
      }
      if (failed.isEmpty) failed.addAll(_unackedSlots(suspension));
      if (failed.isNotEmpty) {
        final slots = failed.toList()..sort();
        _log(
          'suspend failed',
          'windows ${slots.join(', ')} did not release the library '
              'within ${ackTimeout.inMilliseconds}ms',
        );
        throw LibrarySuspendFailed(
          'לא ניתן לסגור את הספרייה בחלון נוסף שפתוח (${slots.join(', ')}). '
          'סגרו את החלונות הנוספים ונסו שוב.',
          slots: slots,
        );
      }
      return suspension;
    } catch (_) {
      await resumeAll(suspension, dbReplaced: false);
      rethrow;
    }
  }

  List<int> _unackedSlots(LibrarySuspension suspension) => [
    for (final slot in _bus.otherRegisteredSlots())
      if (!suspension._acked.contains(slot)) slot,
  ];

  Future<_PeerOutcome> _suspendPeer(
    LibrarySuspension suspension,
    int slot,
  ) async {
    final port = _bus.portOf(slot);
    if (port == null) return _PeerOutcome.gone;
    suspension._sent.add(slot);
    final response = await _bus.requestPortDetailed(
      port,
      {'type': requestSuspend, 'operationId': suspension.operationId},
      timeout: ackTimeout,
      label: '$requestSuspend slot $slot',
    );
    final result = response.result;
    if (result is Map && result['released'] == true) {
      suspension._acked.add(slot);
      return _PeerOutcome.released;
    }
    // חלון שנסגר באמצע: האימות שאחרי ההשעיה יתפוס handle שנשאר.
    if (_bus.portOf(slot) != port) {
      debugPrint('[LibraryAccessGate] slot $slot left during suspend');
      return _bus.portOf(slot) == null ? _PeerOutcome.gone : _PeerOutcome.retry;
    }
    final reason = result is Map ? result['error'] : response.failure?.name;
    debugPrint('[LibraryAccessGate] slot $slot did not release: $reason');
    return _PeerOutcome.failed;
  }

  /// מחדש את הספרייה בכל החלונות שקיבלו suspend. אידמפוטנטי ואינו זורק.
  Future<void> resumeAll(
    LibrarySuspension suspension, {
    required bool dbReplaced,
  }) async {
    if (suspension._resumed) return;
    suspension._resumed = true;
    if (identical(_active, suspension)) _active = null;
    // קודם הסימון: חלון שמתחדש פותח את המסד, והפתיחה ממתינה לסימון.
    LibrarySuspensionMarker.release();
    final slots = suspension._sent.toList()..sort();
    await Future.wait([
      for (final slot in slots) _resumePeer(suspension, slot, dbReplaced),
    ]);
  }

  Future<void> _resumePeer(
    LibrarySuspension suspension,
    int slot,
    bool dbReplaced,
  ) async {
    final port = _bus.portOf(slot);
    if (port == null) return;
    final response = await _bus.requestPortDetailed(
      port,
      {
        'type': requestResume,
        'operationId': suspension.operationId,
        'dbReplaced': dbReplaced,
      },
      timeout: resumeTimeout,
      label: '$requestResume slot $slot',
    );
    // החלון מתחדש לבד כשהסימון נעלם, ולכן כשל כאן אינו משאיר אותו סגור.
    if (response.failure != null) {
      _log('resume not acknowledged', 'slot $slot: ${response.failure!.name}');
    }
  }

  /// זורק [LibraryStillOpenException] אם [dbPath] עדיין פתוח בתהליך.
  ///
  /// zdb נבדק ברישום של zvfs; מסד רגיל ב-Windows נבדק ב-rename שמוחזר מיד,
  /// כי SQLite פותח בלי FILE_SHARE_DELETE.
  Future<void> verifyReleased(String dbPath) async {
    if (isZdbPath(dbPath)) {
      try {
        if (_isOpenInProcess(dbPath)) {
          _log('verify failed', '$dbPath is open through zvfs');
          throw LibraryStillOpenException(dbPath, 'zvfs reports open');
        }
        return;
      } on LibraryStillOpenException {
        rethrow;
      } catch (error) {
        debugPrint('[LibraryAccessGate] zvfs check unavailable: $error');
      }
    }
    if (!_renameProbe) return;
    final file = File(dbPath);
    if (!file.existsSync()) return;
    final probePath = '$dbPath.release-probe';
    try {
      file.renameSync(probePath);
    } on FileSystemException catch (error) {
      _log('verify failed', '$dbPath rename probe: $error');
      throw LibraryStillOpenException(dbPath, 'rename probe: ${error.message}');
    }
    await _restoreProbe(probePath, dbPath);
  }

  Future<void> _restoreProbe(String probePath, String dbPath) async {
    FileSystemException? last;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        File(probePath).renameSync(dbPath);
        return;
      } on FileSystemException catch (error) {
        last = error;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _log('probe restore failed', '$probePath -> $dbPath: $last');
    throw StateError('מסד הספרייה נשאר בשם $probePath: $last');
  }

  /// משעה את כל החלונות, סוגר את ה-isolate הזה, מאמת, ומריץ את [body].
  ///
  /// בכל יציאה הספרייה נפתחת מחדש כאן ובכל החלונות, עם
  /// [LibraryExclusiveScope.dbReplaced] כתוצאה. rollback הוא באחריות [body].
  Future<T> runExclusive<T>({
    required String dbPath,
    required Future<T> Function(LibraryExclusiveScope scope) body,
  }) async {
    final suspension = await suspendAll();
    final scope = LibraryExclusiveScope._();
    try {
      await selfAccess.suspend();
      try {
        await verifyReleased(dbPath);
        return await body(scope);
      } finally {
        await selfAccess.resume(scope.dbReplaced);
      }
    } finally {
      await resumeAll(suspension, dbReplaced: scope.dbReplaced);
    }
  }

  // ---------------------------------------------------------------- חלון משני

  String? _peerOperation;
  Future<void> _peerChain = Future.value();
  Timer? _lease;
  int _leaseMisses = 0;

  /// האם ה-isolate הזה מושעה כרגע לבקשת חלון אחר.
  bool get isPeerSuspended => _peerOperation != null;

  /// מטפל ב-`library.suspend` / `library.resume` שהגיעו באפיק.
  Future<Object?> handlePeerRequest(Map<String, dynamic> request) {
    final operationId = request['operationId'];
    if (operationId is! String) return Future.value();
    switch (request['type']) {
      case requestSuspend:
        return _serialize(() => _peerSuspend(operationId));
      case requestResume:
        return _serialize(
          () => _peerResume(operationId, request['dbReplaced'] == true),
        );
      default:
        return Future.value();
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _peerChain.then((_) => operation());
    _peerChain = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<Map<String, Object?>> _peerSuspend(String operationId) async {
    if (_peerOperation == operationId) return {'released': true};
    if (_peerOperation != null) await _peerResumeLocal(dbReplaced: true);
    try {
      await peerAccess.suspend();
    } catch (error) {
      debugPrint('[LibraryAccessGate] peer suspend failed: $error');
      return {'released': false, 'error': '$error'};
    }
    _peerOperation = operationId;
    _startLease();
    return {'released': true};
  }

  Future<bool> _peerResume(String? operationId, bool dbReplaced) async {
    final current = _peerOperation;
    if (current == null) return true;
    if (operationId != null && operationId != current) return false;
    await _peerResumeLocal(dbReplaced: dbReplaced);
    return true;
  }

  Future<void> _peerResumeLocal({required bool dbReplaced}) async {
    _lease?.cancel();
    _lease = null;
    _peerOperation = null;
    try {
      await peerAccess.resume(dbReplaced);
      if (dbReplaced) onLibraryReplaced?.call();
    } catch (error, stackTrace) {
      _log('peer resume failed', error, stackTrace);
    }
  }

  /// resume שאבד לא ישאיר את החלון סגור: הסימון הוא מקור האמת.
  void _startLease() {
    _lease?.cancel();
    _leaseMisses = 0;
    _lease = Timer.periodic(leaseCheckInterval, (_) {
      if (LibrarySuspensionMarker.isRegistered) {
        _leaseMisses = 0;
        return;
      }
      // שתי בדיקות: ה-resume הרגיל מגיע מיד אחרי הסרת הסימון.
      if (++_leaseMisses < 2) return;
      _lease?.cancel();
      _lease = null;
      _log('peer resumed without resume message', _peerOperation);
      unawaited(_serialize(() => _peerResume(null, true)));
    });
  }

  @visibleForTesting
  Future<void> get peerIdle => _peerChain;

  void _log(String title, Object? error, [StackTrace? stackTrace]) {
    debugPrint('[LibraryAccessGate] $title: $error');
    _logError(title, error ?? '', stackTrace);
  }
}

enum _PeerOutcome { released, gone, retry, failed }
