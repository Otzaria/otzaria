import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';

class StartupRefreshWait {
  Completer<void>? _pending;
  int? _requestId;

  bool get isPending => _pending != null;
  int? get requestId => _requestId;

  Future<void> begin() {
    cancel();
    return (_pending = Completer<void>()).future;
  }

  void attachRequest(int requestId) {
    if (_pending != null) _requestId ??= requestId;
  }

  bool settledBy(LibraryState state) =>
      _requestId != null &&
      LibraryState.refreshRequestSettled(state, _requestId!);

  void settle(LibraryState state) {
    if (settledBy(state)) cancel();
  }

  void cancel() {
    final pending = _pending;
    _pending = null;
    _requestId = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}

/// מתאם פשוט שמונע הרצת עבודות startup כבדות לפני שהוחלט
/// אם האינדוקס האוטומטי ירוץ, ולפני שהוא הסתיים בפועל.
class StartupWorkGate {
  bool _libraryLoaded = false;
  bool _indexingDecisionResolved = false;
  bool _indexingPendingOrRunning = false;
  bool _startupIndexingBatchPending = false;
  bool _startupWorkStarted = false;
  bool _deferredWorkHeld = false;
  final Completer<void> _indexingSettled = Completer<void>();

  Future<void> get indexingSettled => _indexingSettled.future;
  bool get indexingDecisionResolved => _indexingDecisionResolved;

  void holdDeferredWork() => _deferredWorkHeld = true;

  void releaseDeferredWork() => _deferredWorkHeld = false;

  void markStartupIndexingSettled() {
    _startupIndexingBatchPending = false;
    _indexingPendingOrRunning = false;
    if (!_indexingSettled.isCompleted) _indexingSettled.complete();
  }

  void markStartupIndexingBatchPending() {
    _startupIndexingBatchPending = true;
    _indexingPendingOrRunning = true;
  }

  /// מסמן שהספרייה נטענה.
  void markLibraryLoaded() {
    _libraryLoaded = true;
  }

  /// מסמן שהוחלט האם האינדוקס האוטומטי אמור לרוץ.
  void markIndexingDecisionResolved({required bool expectIndexing}) {
    _indexingDecisionResolved = true;
    _indexingPendingOrRunning = expectIndexing;
    if (!expectIndexing && !_indexingSettled.isCompleted) {
      _indexingSettled.complete();
    }
  }

  /// מעדכן את מצב האינדוקס בפועל.
  void markIndexingRunning(bool isRunning) {
    _indexingPendingOrRunning = isRunning || _startupIndexingBatchPending;
  }

  /// מחזיר `true` פעם אחת בלבד, ורק כאשר בטוח להתחיל עבודות startup נוספות.
  bool consumeStartPermission() {
    if (_startupWorkStarted ||
        _deferredWorkHeld ||
        !_libraryLoaded ||
        !_indexingDecisionResolved ||
        _indexingPendingOrRunning) {
      return false;
    }

    _startupWorkStarted = true;
    return true;
  }
}

Future<void> resolveStartupIndexingNonFatal({
  required StartupWorkGate gate,
  required Future<void> Function() resolve,
  required void Function(Object, StackTrace) onError,
}) async {
  try {
    await resolve();
  } catch (error, stackTrace) {
    onError(error, stackTrace);
    if (!gate.indexingDecisionResolved) {
      gate.markIndexingDecisionResolved(expectIndexing: false);
    } else {
      gate.markStartupIndexingSettled();
    }
  }
}

/// בזמן סיור החיפוש צריך לקבל אינדקס לפני שהעדכונים המושהים מתחילים.
/// [onFinished] רץ בסוף הרצף גם כשאחד השלבים נכשל.
///
/// בלי סיור ההחלטה מגיעה רק אחרי העדכונים, שכוללים הורדת ספרייה ארוכה. עד אז
/// חיווי האינדקס נשאר במצב ההתחלתי ("לא מעודכן") בלי שנבדק דבר (#4461), ולכן
/// [previewIndexStatus] מרענן אותו מראש; כשל בו אינו עוצר את הרצף.
Future<void> runStartupIndexingSequence({
  required bool tourActive,
  required Future<void> Function() resolveIndexing,
  required Future<void> Function() waitForIndexing,
  required Future<void> Function() runUpdates,
  Future<void> Function()? previewIndexStatus,
  VoidCallback? onFinished,
}) async {
  try {
    if (tourActive) {
      await resolveIndexing();
      await waitForIndexing();
    } else if (previewIndexStatus != null) {
      try {
        await previewIndexStatus();
      } catch (error, stackTrace) {
        debugPrint('Startup index status preview failed: $error\n$stackTrace');
      }
    }
    await runUpdates();
    if (!tourActive) await resolveIndexing();
  } finally {
    onFinished?.call();
  }
}

/// מחזיק את הסימון "האינדוקס ממתין לעדכון הספרייה" עד שהאינדוקס מתחיל
/// בפועל, כדי שאזהרת האינדקס החלקי לא תיעלם לפני שמצב ההתקדמות מוצג.
class StartupIndexingDeferral {
  StartupIndexingDeferral(
    this.flag, {
    this.startTimeout = const Duration(seconds: 30),
  });

  final ValueNotifier<bool> flag;

  /// גיבוי למסלול שבו האינדוקס לא מתחיל — הסימון לא נשאר דלוק לתמיד.
  final Duration startTimeout;

  StreamSubscription<IndexingState>? _subscription;
  Timer? _timer;

  /// מכבה את הסימון כשה-bloc יוצא מ-[IndexingInitial], או אחרי [startTimeout].
  void releaseWhenStarted(IndexingState current, Stream<IndexingState> states) {
    if (!flag.value || current is! IndexingInitial) return clear();
    _cancelWait();
    _subscription = states.listen((state) {
      if (state is! IndexingInitial) clear();
    }, onDone: clear);
    _timer = Timer(startTimeout, clear);
  }

  void clear() {
    _cancelWait();
    flag.value = false;
  }

  void _cancelWait() {
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}

/// מתחיל את סנכרון הרקע פעם אחת לאחר פתיחת [gate].
bool tryStartDeferredStartupWork({
  required StartupWorkGate gate,
  required VoidCallback startBackgroundSync,
}) {
  if (!gate.consumeStartPermission()) {
    return false;
  }
  startBackgroundSync();
  return true;
}

/// האם עדכון ספרייה שהתחיל הגיע למצב שבו אפשר להמשיך לאינדוקס.
/// דיאלוג ההורדה המלאה חוסם ונפתר מיד; בחירת מסלול באזור ההתראות — לא.
bool libraryUpdateSettledForIndexing(LibraryUpdateState state) =>
    !state.isBusy && state.status != LibraryUpdateStatus.needsFullConfirmation;

/// שלבי העלייה שלפני האינדוקס: סיור ← בדיקת תוכנה ← עדכון ספרייה.
///
/// כשעדכון הספרייה לא אמור לרוץ ([shouldCheckLibraryUpdate]) חוזרים מיד.
/// גרסת תוכנה חדשה מדלגת עליו — היא עשויה לשנות את סכמת הספרייה.
Future<void> runStartupUpdatesBeforeIndexing({
  required bool Function() shouldCheckLibraryUpdate,
  required Future<void> Function() tourFinished,
  required Future<bool> Function() isSoftwareUpdateAvailable,
  required Future<void> Function() runLibraryUpdate,
}) async {
  if (!shouldCheckLibraryUpdate()) return;
  await tourFinished();
  if (!shouldCheckLibraryUpdate()) return;
  if (await isSoftwareUpdateAvailable()) return;
  if (!shouldCheckLibraryUpdate()) return;
  await runLibraryUpdate();
}
