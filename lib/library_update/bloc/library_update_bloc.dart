import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/internet_connectivity.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/update_source_reachability.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/utils/text/byte_size_text.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../repository/library_update_repository.dart';

part 'library_update_event.dart';
part 'library_update_state.dart';

/// מנהל את תהליך עדכון ספריית הספרים החדש (מחליף את `FileSyncBloc`).
///
/// בודק זמינות עדכון, מחיל מסלול דלתא אוטומטית, ומבקש אישור להורדה מלאה.
/// אינו מפעיל אינדוקס/ריענון ספרייה ישירות — ה-UI מאזין ל-state ומפעיל
/// `RefreshLibrary` + `StartIndexing` כש-[LibraryUpdateState.hasUpdate].
class LibraryUpdateBloc extends Bloc<LibraryUpdateEvent, LibraryUpdateState> {
  final LibraryUpdateService repository;

  /// אימות ועדכון הקבצים הנלווים (תלמוד, קטלוגים, מילון) בסוף כל עדכון.
  /// null (בבדיקות) — מדלגים.
  final CompanionAssetsService? companionAssets;

  /// קוראים את ההגדרות הרלוונטיות — ניתנים להזרקה לבדיקות.
  final bool Function() isOfflineMode;
  final bool Function() areUpdatesEnabled;
  final bool Function() allowPrerelease;

  /// בדיקת חיבור אמיתי לאינטרנט — ניתנת להזרקה לבדיקות.
  final Future<bool> Function() hasInternet;

  /// בדיקת נגישות שרת העדכונים — ניתנת להזרקה לבדיקות.
  final Future<bool> Function() isSourceReachable;

  /// נקרא אחרי כל בדיקת עדכון שהצליחה (גם "אין עדכון") — משמש לרישום
  /// חותמת הזמן שממנה נגזרת תדירות הבדיקה האוטומטית בעלייה.
  final void Function()? onCheckSucceeded;

  /// שעון — ניתן להזרקה לבדיקות ויסות ההתקדמות.
  final DateTime Function() _now;

  // מזהה הריצה הפעילה. כל התחלה/ביטול/איפוס מגדילים אותו, כך שריצה ישנה
  // (Future שעדיין לא הסתיים) מזוהה כמבוטלת ולא פולטת state או מחליפה DB.
  int _operationId = 0;

  bool _isStale(int opId) => opId != _operationId;

  // ה-state הסופי של עדכון שכבר נכתב ל-DB, בזמן שהקבצים הנלווים עוד רצים.
  // ביטול בשלב הזה פולט אותו — אחרת hasUpdate אובד והריענון/אינדוקס לא רצים.
  LibraryUpdateState? _pendingCompleted;

  // מרגע שצעד הדלתא הראשון נכנס ל-applying, ייתכן שכבר נכתב DB גם אם צעד
  // מאוחר חזר ל-downloading. הביטול נשאר חסום עד סיום כל מסלול הדלתא.
  bool _deltaWriteStarted = false;

  // נקודת האל-חזור של הורדה מלאה מדווחת סינכרונית מיד אחרי החלפת הקובץ,
  // לפני await של פתיחת ה-DB מחדש. כך Cancel/Reset לא יכולים לנצח את ה-state.
  bool _fullDownloadDbReplaced = false;

  // הריצה הנוכחית היא דלתא כבדה שאין לה חלופה מלאה — הודעות שלב ההחלה
  // נושאות אזהרה שההחלה ארוכה.
  bool _heavyDeltaNotice = false;

  // שינוי נלווים שריצה מבוטלת לא יכלה לדווח כי ריצה חדשה כבר busy —
  // הריצה החדשה תדווח אותו, אחרת הריענון/אינדוקס אובדים.
  bool _unreportedAssetsChange = false;

  LibraryUpdateBloc({
    required this.repository,
    required this.isOfflineMode,
    required this.areUpdatesEnabled,
    required this.allowPrerelease,
    this.companionAssets,
    this.hasInternet = hasInternetConnection,
    this.isSourceReachable = isUpdateSourceReachable,
    this.onCheckSucceeded,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const LibraryUpdateState()) {
    on<StartLibraryUpdate>(_onStart);
    on<ConfirmFullDownload>(_onConfirmFull);
    on<ConfirmHeavyDelta>(_onConfirmHeavyDelta);
    on<DeclineFullDownload>(_onDeclineFull);
    on<CancelLibraryUpdate>(_onCancel);
    on<ResetLibraryUpdate>(_onReset);
    on<_LibraryUpdateProgressed>(_onProgressed);
  }

  /// הקצב המרבי של עדכוני התקדמות שוטפים (בייטים/אחוז) אל ה-state.
  static const progressInterval = Duration(milliseconds: 200);

  DateTime? _lastProgressAt;
  LibraryUpdatePhase? _lastPhase;
  int _lastStepIndex = -1;
  String? _lastStage;

  // onProgress נורה על כל chunk רשת; פליטת state לכל chunk מציפה את ה-UI
  // בבניות-מחדש ומאיטה את כל התוכנה. שינוי שלב/סיום עוברים תמיד.
  void _reportProgress(LibraryUpdateProgress p, int opId) {
    final structural =
        p.phase != _lastPhase ||
        p.stepIndex != _lastStepIndex ||
        p.stage != _lastStage ||
        (p.bytesTotal != null && p.bytesDownloaded == p.bytesTotal);
    if (!_throttleAllows(structural: structural)) return;
    _lastPhase = p.phase;
    _lastStepIndex = p.stepIndex;
    _lastStage = p.stage;
    add(_LibraryUpdateProgressed(p, opId));
  }

  bool _throttleAllows({required bool structural}) {
    final now = _now();
    final last = _lastProgressAt;
    if (!structural &&
        last != null &&
        now.difference(last) < progressInterval) {
      return false;
    }
    _lastProgressAt = now;
    return true;
  }

  void _resetProgressThrottle() {
    _lastProgressAt = null;
    _lastPhase = null;
    _lastStepIndex = -1;
    _lastStage = null;
  }

  @override
  void onChange(Change<LibraryUpdateState> change) {
    super.onChange(change);
    // hasUpdate נפלט ⇒ ה-UI מריץ ריענון/אינדוקס שמכסים גם שינוי נלווים שמור.
    if (change.nextState.hasUpdate) _unreportedAssetsChange = false;
  }

  Future<void> _onStart(
    StartLibraryUpdate event,
    Emitter<LibraryUpdateState> emit,
  ) async {
    // מונע עדכון כפול: התעלם מבקשה חדשה כשעדכון כבר רץ (auto + לחיצה ידנית).
    if (state.isBusy) return;
    if (isOfflineMode()) {
      emit(const LibraryUpdateState(message: 'מצב לא מקוון — עדכון מושבת'));
      return;
    }
    if (!areUpdatesEnabled()) {
      emit(const LibraryUpdateState(message: 'עדכוני ספרים מושבתים'));
      return;
    }

    final opId = ++_operationId;
    _heavyDeltaNotice = false;
    _resetProgressThrottle();
    emit(
      const LibraryUpdateState(
        status: LibraryUpdateStatus.checking,
        message: 'בודק עדכוני ספרייה',
      ),
    );

    try {
      final plan = await repository.checkForUpdate(
        allowPrerelease: allowPrerelease(),
      );
      // אם המשתמש ביטל/התחיל ריצה חדשה במהלך הבדיקה — לא להמשיך.
      if (_isStale(opId)) return;
      onCheckSucceeded?.call();
      switch (plan.kind) {
        case LibraryUpdatePlanKind.none:
          final assetsChanged =
              await _runCompanionAssets(emit, opId) || _unreportedAssetsChange;
          // ביטול בזמן הנלווים אחרי שתלמוד/קטלוג כבר שונו: בלי completed עם
          // hasUpdate הריענון והאינדוקס לא ירוצו עד הפעלה מחדש. state.isBusy
          // מגן מדריסת ריצה חדשה שכבר התחילה — במקרה כזה השינוי נשמר לדיווח
          // ע"י הריצה החדשה.
          if (_isStale(opId) && (!assetsChanged || state.isBusy)) {
            _unreportedAssetsChange = assetsChanged;
            return;
          }
          // תלמוד/קטלוג שהותקנו משנים את תוכן הספרייה — hasUpdate מפעיל
          // ריענון ואינדוקס ב-UI גם כשה-DB עצמו לא עודכן.
          emit(
            LibraryUpdateState(
              status: LibraryUpdateStatus.completed,
              message: assetsChanged ? 'הספרייה עודכנה' : 'הספרייה מעודכנת',
              hasUpdate: assetsChanged,
            ),
          );
        case LibraryUpdatePlanKind.delta:
          // דלתא כבדה (issue #1211): ההחלה עשויה להימשך שעה. כשיש הורדה מלאה
          // חלופית הבחירה היא של המשתמש; בלעדיה רק מזהירים וממשיכים.
          if (plan.isHeavyDelta && plan.fullDbAsset != null) {
            emit(
              LibraryUpdateState(
                status: LibraryUpdateStatus.needsRouteChoice,
                message: LibraryMessages.heavyDeltaRouteChoice(
                  reason: plan.heavyDeltaReason!,
                  deltaDownloadSize: _formatSize(plan.totalDownloadSize),
                  deltaApplySize: _formatSize(plan.deltaUncompressedBytes),
                  fullDownloadSize: _formatSize(plan.fullDbAsset!.size),
                ),
                plan: plan,
              ),
            );
            return;
          }
          _heavyDeltaNotice = plan.isHeavyDelta;
          await _runDelta(plan, emit, opId);
        case LibraryUpdatePlanKind.fullDownload:
          emit(
            LibraryUpdateState(
              status: LibraryUpdateStatus.needsFullConfirmation,
              message:
                  'נדרשת הורדה מלאה (${_formatSize(plan.totalDownloadSize)})',
              plan: plan,
            ),
          );
        case LibraryUpdatePlanKind.blocked:
          emit(
            LibraryUpdateState(
              status: LibraryUpdateStatus.blocked,
              message: plan.reason ?? 'העדכון חסום',
              errorMessage: plan.reason,
            ),
          );
      }
    } catch (e, st) {
      // אם בוטל/הוחלף במהלך הבדיקה — לא לדרוס state של ריצה חדשה בשגיאה.
      if (_isStale(opId)) return;
      _logUpdateError('checkForUpdate', e, st);
      final failure = await _checkFailureState(
        LibraryMessages.updateCheckError,
        e,
      );
      if (isClosed || _isStale(opId)) return;
      emit(failure);
    }
  }

  /// בכשל בבדיקת הזמינות בלבד, רשת שאינה מגיעה לשרת העדכונים אינה שגיאה
  /// למשתמש: ברשת מסוננת הבדיקה תיכשל בכל עלייה ואין לו מה לתקן.
  Future<LibraryUpdateState> _checkFailureState(
    String message,
    Object error,
  ) async {
    if (await isSourceReachable()) {
      return LibraryUpdateState(
        status: LibraryUpdateStatus.error,
        message: message,
        errorMessage: _errorDetail(error),
        isCheckFailure: true,
      );
    }
    return LibraryUpdateState(
      status: LibraryUpdateStatus.disconnected,
      message: await hasInternet()
          ? LibraryMessages.updateSourceUnreachable
          : LibraryMessages.noInternetConnection,
    );
  }

  Future<void> _runDelta(
    LibraryUpdatePlan plan,
    Emitter<LibraryUpdateState> emit,
    int opId,
  ) async {
    _deltaWriteStarted = false;
    try {
      final deltaResult = await repository.applyDeltaPlan(
        plan,
        isCancelled: () => _isStale(opId),
        onProgress: (progress) {
          if (progress.phase == LibraryUpdatePhase.applying) {
            _deltaWriteStarted = true;
          }
          _reportProgress(progress, opId);
        },
      );
      // הגענו לכאן ⇒ ה-apply וה-ריענון הצליחו וה-DB עודכן. אם בוטל/הוחלף
      // בינתיים — לא נדרוס את ה-state של הריצה החדשה (ה-DB כבר רוענן ממילא).
      if (_isStale(opId)) return;
      // נקודת אל-חזור: ביטול במהלך הקבצים הנלווים יפלוט את זה מ-_onCancel.
      _pendingCompleted = state.copyWith(
        status: LibraryUpdateStatus.completed,
        message: 'הספרייה עודכנה לגרסה ${plan.targetVersion}',
        hasUpdate: true,
        changedBookIds: deltaResult.changedBookIds,
        requiresFullIndexRefresh: deltaResult.requiresFullIndexRefresh,
      );
      await _runCompanionAssets(emit, opId);
      final completed = _pendingCompleted;
      _pendingCompleted = null;
      if (_isStale(opId) || completed == null) return;
      emit(completed);
    } on PatchDownloadCancelled {
      // ביטול לפני apply — לא שגיאה; _onCancel כבר העביר ל-idle.
    } catch (e, st) {
      if (_isStale(opId)) return;
      final drift = e is LibraryDeltaContentDriftException ? e : null;
      // סטייה אחרי commit כבר נרשמה ל-errors.txt על ידי הריפוזיטורי.
      if (drift == null) _logUpdateError('applyDeltaPlan', e, st);
      final partial = switch (e) {
        PartiallyAppliedLibraryDeltaException(:final appliedResult) =>
          appliedResult,
        LibraryDeltaContentDriftException(:final appliedResult) =>
          appliedResult,
        _ => null,
      };
      final applyError = e is PartiallyAppliedLibraryDeltaException
          ? e.cause
          : e;
      final requiresFullIndexRefresh =
          drift != null || (partial?.requiresFullIndexRefresh ?? false);
      // כל כשל apply (וגם סטייה שהתגלתה אחרי commit) מנותב להורדה מלאה — אחרת
      // כשל שאינו אי-התאמת תוכן משאיר את המשתמש בלולאת שגיאה עד עדכון אפליקציה.
      final mismatchReason = drift != null
          ? LibraryMessages.libraryContentDriftAfterUpdate
          : applyError is PatchApplyException
          ? _applyMismatchReason(applyError)
          : null;
      if (mismatchReason != null) {
        final fallback = plan.toFullDownloadFallback(
          reason: mismatchReason,
        );
        if (fallback != null) {
          emit(
            LibraryUpdateState(
              status: LibraryUpdateStatus.needsFullConfirmation,
              message: LibraryMessages.fullLibraryDownloadRequired(
                mismatchReason,
                _formatSize(fallback.totalDownloadSize),
              ),
              plan: fallback,
              hasUpdate: partial?.hasDatabaseChanges ?? false,
              changedBookIds: partial?.changedBookIds ?? const {},
              requiresFullIndexRefresh: requiresFullIndexRefresh,
            ),
          );
          return;
        }
      }
      emit(
        LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          // חוסר מקום אינו כשל החלה: הוא נבדק לפני ההורדה, ולכן גם אינו מציע
          // הורדה מלאה — היא דורשת עוד יותר מקום.
          message: applyError is LibraryUpdateDiskSpaceException
              ? LibraryMessages.updateDiskSpaceError
              : 'שגיאה בהחלת העדכון',
          hasUpdate: partial?.hasDatabaseChanges ?? false,
          changedBookIds: partial?.changedBookIds ?? const {},
          requiresFullIndexRefresh: requiresFullIndexRefresh,
          errorMessage: _errorDetail(applyError),
        ),
      );
    } finally {
      _deltaWriteStarted = false;
    }
  }

  String _applyMismatchReason(PatchApplyException error) {
    if (!error.isContentMismatch) return LibraryMessages.deltaApplyFailed;
    return error.hashMismatchStage == PatchHashMismatchStage.toContentHash
        ? LibraryMessages.deltaResultMismatch
        : LibraryMessages.localLibraryContentMismatch;
  }

  Future<void> _onConfirmFull(
    ConfirmFullDownload event,
    Emitter<LibraryUpdateState> emit,
  ) async {
    if (state.isBusy) return; // הורדה כבר רצה — מתעלמים מאישור כפול.
    // בבחירת מסלול, ה-plan שב-state הוא תוכנית הדלתא — ההורדה המלאה היא
    // ה-fallback שלה. חייב להיכנס ל-state, אחרת אין reconcile של האינדקס.
    final plan = state.status == LibraryUpdateStatus.needsRouteChoice
        ? state.plan?.toFullDownloadFallback(
            reason: state.plan?.heavyDeltaReason,
          )
        : state.plan;
    if (plan == null || plan.kind != LibraryUpdatePlanKind.fullDownload) {
      emit(const LibraryUpdateState());
      return;
    }
    final opId = ++_operationId;
    _heavyDeltaNotice = false;
    _fullDownloadDbReplaced = false;
    _resetProgressThrottle();
    emit(
      state.copyWith(
        status: LibraryUpdateStatus.downloading,
        message: 'מוריד ספרייה מלאה',
        plan: plan,
      ),
    );
    try {
      await repository.applyFullDownload(
        plan,
        isCancelled: () => _isStale(opId),
        onDbReplaced: () => _fullDownloadDbReplaced = true,
        onProgress: (progress) => _reportProgress(progress, opId),
      );
      if (_isStale(opId)) return;
      _pendingCompleted = state.copyWith(
        status: LibraryUpdateStatus.completed,
        message: 'הספרייה הותקנה מחדש לגרסה ${plan.targetVersion}',
        hasUpdate: true,
      );
      await _runCompanionAssets(emit, opId);
      final completed = _pendingCompleted;
      _pendingCompleted = null;
      if (_isStale(opId) || completed == null) return;
      emit(completed);
    } on PatchDownloadCancelled {
      // ביטול — _onCancel כבר העביר ל-idle.
    } catch (e, st) {
      if (_isStale(opId)) return;
      _logUpdateError('applyFullDownload', e, st);
      final dbReplaced = _fullDownloadDbReplaced;
      emit(
        LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          message: e is LibraryUpdateDiskSpaceException
              ? LibraryMessages.updateDiskSpaceError
              : 'שגיאה בהורדה המלאה',
          // fallback אחרי דלתא חלקית: ההורדה המלאה נכשלה, אבל הצעדים שכבר
          // נכתבו ל-DB עדיין דורשים ריענון ספרייה ואינדקס.
          hasUpdate: dbReplaced || state.hasUpdate,
          changedBookIds: state.changedBookIds,
          // אחרי החלפת DB מלאה אין רשימת מזהים אמינה; נדרש reconcile מלא.
          requiresFullIndexRefresh:
              dbReplaced || state.requiresFullIndexRefresh,
          plan: dbReplaced ? plan : null,
          errorMessage: _errorDetail(e),
        ),
      );
    } finally {
      _fullDownloadDbReplaced = false;
    }
  }

  Future<void> _onConfirmHeavyDelta(
    ConfirmHeavyDelta event,
    Emitter<LibraryUpdateState> emit,
  ) async {
    if (state.isBusy) return;
    final plan = state.plan;
    if (plan == null || plan.kind != LibraryUpdatePlanKind.delta) {
      emit(const LibraryUpdateState());
      return;
    }
    final opId = ++_operationId;
    _heavyDeltaNotice = plan.isHeavyDelta;
    _resetProgressThrottle();
    emit(
      state.copyWith(
        status: LibraryUpdateStatus.downloading,
        message: 'מוריד עדכון ספרייה',
      ),
    );
    await _runDelta(plan, emit, opId);
  }

  /// מוודא שהקבצים הנלווים (תלמוד, קטלוגים, מילון) קיימים ומעודכנים, בסוף
  /// כל בדיקת/החלת עדכון. best-effort — כשל לא הופך את העדכון לשגיאה.
  /// מחזיר האם תוכן הספרייה השתנה (ראה [CompanionAssetsService.verifyAndUpdate]).
  Future<bool> _runCompanionAssets(
    Emitter<LibraryUpdateState> emit,
    int opId,
  ) async {
    final service = companionAssets;
    if (service == null) return false;
    try {
      return await service.verifyAndUpdate(
        isCancelled: () => _isStale(opId),
        onStatus: (message, phase) {
          if (_isStale(opId)) return;
          emit(
            state.copyWith(
              status: switch (phase) {
                CompanionAssetPhase.checking => LibraryUpdateStatus.checking,
                CompanionAssetPhase.downloading =>
                  LibraryUpdateStatus.downloading,
                CompanionAssetPhase.applying => LibraryUpdateStatus.applying,
              },
              message: message,
            ),
          );
        },
        onDownloadProgress: (received, total) {
          if (_isStale(opId)) return;
          // גם כאן ההתקדמות מגיעה על כל chunk — מוויסתת באותו מנגנון.
          final isFinal = total != null && received == total;
          if (!_throttleAllows(structural: isFinal)) return;
          emit(
            state.copyWith(
              status: LibraryUpdateStatus.downloading,
              bytesDownloaded: received,
              // total לא ידוע ⇒ 0, כדי לא לרשת bytesTotal ישן מהורדת ה-DB.
              bytesTotal: total ?? 0,
            ),
          );
        },
      );
    } catch (e, st) {
      _logUpdateError('companionAssets', e, st);
      return false;
    }
  }

  void _onDeclineFull(
    DeclineFullDownload event,
    Emitter<LibraryUpdateState> emit,
  ) {
    // המשתמש בחר להישאר עם הגרסה הנוכחית — לא מורידים כלום. אם fallback
    // הוצע אחרי כשל בצעד מאוחר, שומרים את שינויי הצעדים שכבר הושלמו כדי
    // שהספרייה והאינדקס יתרעננו לגרסת הביניים התקינה.
    emit(
      LibraryUpdateState(
        status: LibraryUpdateStatus.completed,
        message: 'ממשיך עם הגרסה הנוכחית',
        hasUpdate: state.hasUpdate,
        changedBookIds: state.changedBookIds,
        requiresFullIndexRefresh: state.requiresFullIndexRefresh,
      ),
    );
  }

  void _onCancel(CancelLibraryUpdate event, Emitter<LibraryUpdateState> emit) {
    // משלב כתיבת ה-DB ואילך ביטול אסור: ה-DB מתעדכן אטומית והריענון כבר בדרך,
    // וביטול כאן היה משאיר קטלוג ואינדקס ישנים עד restart.
    if (!_canCancel(state)) return;
    _operationId++; // מבטל את הריצה הפעילה — ה-Future הישן יזהה זאת.
    // ה-DB כבר עודכן והביטול עצר רק את הקבצים הנלווים — פולטים את ה-completed
    // השמור כדי שהריענון והאינדוקס יופעלו בכל זאת.
    final pending = _pendingCompleted;
    _pendingCompleted = null;
    if (pending != null) {
      emit(pending);
      return;
    }
    // ביטול הורדה מלאה שהוצעה אחרי כשל בצעד דלתא מאוחר אינו מבטל את
    // הצעדים שכבר נכתבו. פולטים completed כדי שה-listener ירענן אותם.
    if (state.hasUpdate) {
      emit(
        LibraryUpdateState(
          status: LibraryUpdateStatus.completed,
          message: 'ממשיך עם הגרסה הנוכחית',
          hasUpdate: true,
          changedBookIds: state.changedBookIds,
          requiresFullIndexRefresh: state.requiresFullIndexRefresh,
        ),
      );
      return;
    }
    emit(const LibraryUpdateState(message: 'העדכון בוטל'));
  }

  /// ביטול אפשרי עד שמתחילים לכתוב ל-DB. בדלתא נקודת האל-חזור היא שלב ה-applying
  /// (החלת ה-patch); בהורדה מלאה שלב ה-applying הוא רק חילוץ, והחסימה מתחילה
  /// בהתראת onDbReplaced הסינכרונית או כשה-state כבר הגיע ל-refreshing.
  bool _canCancel(LibraryUpdateState state) {
    if (_deltaWriteStarted && _pendingCompleted == null) return false;
    if (_fullDownloadDbReplaced && _pendingCompleted == null) return false;
    switch (state.status) {
      case LibraryUpdateStatus.refreshing:
        return false;
      case LibraryUpdateStatus.applying:
        // בדלתא, applying לפני הכתיבה הוא אימות ה-patch הפרוס — עדיין ניתן לבטל.
        return state.plan?.kind == LibraryUpdatePlanKind.fullDownload ||
            !_deltaWriteStarted;
      default:
        return true;
    }
  }

  void _onReset(ResetLibraryUpdate event, Emitter<LibraryUpdateState> emit) {
    if (_deltaWriteStarted && _pendingCompleted == null) return;
    if (_fullDownloadDbReplaced && _pendingCompleted == null) return;
    _operationId++;
    _pendingCompleted = null;
    _heavyDeltaNotice = false;
    emit(const LibraryUpdateState());
  }

  void _onProgressed(
    _LibraryUpdateProgressed event,
    Emitter<LibraryUpdateState> emit,
  ) {
    // התקדמות מריצה שבוטלה/הוחלפה — מתעלמים כדי לא לדרוס state חדש.
    if (_isStale(event.opId)) return;
    final p = event.progress;
    // phase=done הוא רגע לפני שה-completed נפלט מ-_runDelta; ה-event מגיע בתור
    // אחרי ה-completed, אז emit כאן ידרוס אותו וה-UI ייתקע ב'מסיים'.
    if (p.phase == LibraryUpdatePhase.done) return;
    final message = switch (p.phase) {
      LibraryUpdatePhase.checking => 'בודק עדכוני ספרייה',
      LibraryUpdatePhase.downloading =>
        'מוריד עדכון ספרייה'
            '${p.totalSteps > 1 ? ' (${p.stepIndex + 1}/${p.totalSteps})' : ''}',
      LibraryUpdatePhase.verifying => 'מאמת קובץ עדכון',
      LibraryUpdatePhase.applying =>
        _heavyDeltaNotice
            ? LibraryMessages.applyStageWithHeavyDeltaNotice(
                _applyStageMessage(p.stage),
              )
            : _applyStageMessage(p.stage),
      LibraryUpdatePhase.refreshing => 'מרענן ספרייה',
      LibraryUpdatePhase.done => 'מסיים',
    };
    final status = switch (p.phase) {
      LibraryUpdatePhase.checking => LibraryUpdateStatus.checking,
      LibraryUpdatePhase.downloading => LibraryUpdateStatus.downloading,
      LibraryUpdatePhase.verifying => LibraryUpdateStatus.applying,
      LibraryUpdatePhase.applying => LibraryUpdateStatus.applying,
      LibraryUpdatePhase.refreshing => LibraryUpdateStatus.refreshing,
      LibraryUpdatePhase.done => LibraryUpdateStatus.checking,
    };
    emit(
      state.copyWith(
        status: status,
        message: message,
        stepIndex: p.stepIndex,
        totalSteps: p.totalSteps,
        bytesDownloaded: p.bytesDownloaded,
        bytesTotal: p.bytesTotal,
        applyProgress: p.applyProgress,
      ),
    );
  }

  // ממפה את תת-שלבי ה-apply (מ-PatchApplier.onStage) להודעות קריאות למשתמש.
  String _applyStageMessage(String? stage) => switch (stage) {
    'preflight' => 'בודק תאימות גרסה',
    'verifyFromHash' => 'מאמת את הספרייה הנוכחית',
    'attach' => 'מכין את העדכון',
    'migrations' => 'מעדכן מבנה נתונים',
    'upserts' => 'מוסיף ומעדכן רשומות',
    'deletes' => 'מסיר רשומות שהוסרו',
    'verifyToHash' => 'מאמת את הספרייה המעודכנת',
    'verifyDeferred' => 'בודק את שאר הספרייה (ניתן להמשיך לקרוא)',
    'commit' => 'שומר שינויים',
    _ => 'מחיל עדכון',
  };

  String _formatSize(int bytes) {
    if (bytes >= 1 << 30) {
      return ltrIsolate('${(bytes / (1 << 30)).toStringAsFixed(1)}GB');
    }
    if (bytes >= 1 << 20) {
      return ltrIsolate('${(bytes / (1 << 20)).toStringAsFixed(0)}MB');
    }
    return ltrIsolate('${(bytes / (1 << 10)).toStringAsFixed(0)}KB');
  }

  /// פרט הכשל לחיווי. חריגות ה-updater נושאות הודעה עברית; קטיעת רשת גולמית
  /// ממופה לטקסט קצר. הפרטים המלאים נרשמים ל-errors.txt ב-[_logUpdateError].
  String _errorDetail(Object error) {
    if (error is PatchDownloadException) return error.message;
    if (error is GithubRateLimitException) {
      return LibraryMessages.updateRateLimited(error.minutesUntilReset());
    }
    if (PatchDownloader.isTransientNetworkError(error)) {
      return LibraryMessages.updateNetworkInterrupted;
    }
    return error.toString();
  }

  void _logUpdateError(String stage, Object e, StackTrace st) {
    debugPrint('[LibraryUpdate] ERROR in $stage: $e\n$st');
    try {
      ErrorLogFile.append(
        title: 'Library Update Error ($stage)',
        error: e,
        stackTrace: st,
      );
    } catch (_) {}
  }
}
