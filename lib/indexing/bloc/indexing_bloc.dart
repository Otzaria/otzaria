import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/services/indexing_failure_reporter.dart';
import 'package:otzaria/indexing/services/indexing_wakelock.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';

class IndexingBloc extends Bloc<IndexingEvent, IndexingState> {
  final IndexingRepository _repository;
  final void Function(IndexingRunResult result, Duration elapsed)
  _reportFailures;
  final void Function(String message) _showHiddenReconciliationError;
  int _nextWorkId = 0;
  int? _activeWorkId;
  bool _isPaused = false;
  bool _isEconomy = false;
  bool _isFinalizing = false;

  // ביטול מנקז את ריצות האינדוקס שכבר בתור: הן נשלחו לפני שהמשתמש עצר.
  final _enqueuedAtCancelCount = Expando<int>();
  int _cancelCount = 0;

  IndexingBloc(
    this._repository, {
    void Function(IndexingRunResult result, Duration elapsed)? reportFailures,
    void Function(String message)? showHiddenReconciliationError,
  }) : _reportFailures = reportFailures ?? IndexingFailureReporter.write,
       _showHiddenReconciliationError =
           showHiddenReconciliationError ?? UiSnack.showError,
       super(IndexingInitial()) {
    _isEconomy = _repository.isEconomyIndexing;
    on<IndexingWorkEvent>((event, emit) async {
      try {
        await _onIndexingWork(event, emit);
      } finally {
        event.onSettled?.call();
      }
    }, transformer: sequential());
    on<CheckIndexStatus>(_onCheckIndexStatus);
    on<CancelIndexing>(_onCancelIndexing);
    on<PauseIndexing>(_onPauseIndexing);
    on<ResumeIndexing>(_onResumeIndexing);
    on<SetEconomyIndexing>(_onSetEconomyIndexing, transformer: sequential());
    on<ActualIndexingStarted>(_onActualIndexingStarted);
    on<IndexingFinalizing>(_onFinalizing);
    on<UpdateIndexingProgress>(_onUpdateProgress);
    on<ClearIndex>(_onEraseIndex);
  }

  /// Factory constructor that creates an IndexingBloc with a default repository
  factory IndexingBloc.create() {
    IndexingWakelock.instance.attach(TantivyDataProvider.instance.isIndexing);
    return IndexingBloc(
      IndexingRepository(TantivyDataProvider.instance),
    );
  }

  @override
  void add(IndexingEvent event) {
    if (event is RunIndexing) _enqueuedAtCancelCount[event] = _cancelCount;
    super.add(event);
  }

  /// כל מצבי ההתקדמות נפלטים דרך כאן כדי שדגלי ההשהיה והמצב החסכוני
  /// יישמרו על פני כל עדכון התקדמות.
  IndexingInProgress _inProgress({
    int? booksProcessed,
    int? totalBooks,
    bool isCreatingIndex = false,
    bool isScanning = false,
  }) => IndexingInProgress(
    booksProcessed: booksProcessed,
    totalBooks: totalBooks,
    isCreatingIndex: isCreatingIndex,
    isScanning: isScanning,
    isPaused: _isPaused,
    isEconomy: _isEconomy,
    isFinalizing: _isFinalizing,
  );

  Future<void> _onIndexingWork(
    IndexingWorkEvent event,
    Emitter<IndexingState> emit,
  ) async {
    if (event is DeferIndexing) {
      await _repository.rememberChangedBooks(
        event.changedBooks,
        checkLibrary: event.checkLibrary,
      );
      await _onCheckIndexStatus(CheckIndexStatus(event.library), emit);
      return;
    }

    // בלי קטלוג תקין אין לאנדקס או לסמן שחזור הסתרות כהצלחה.
    final schemaCheck = SqliteDataProvider.instance.checkUnsupportedDbSchema();
    final schemaBlocked = schemaCheck is bool ? schemaCheck : await schemaCheck;
    if (event is RunIndexing &&
        (schemaBlocked ||
            (_enqueuedAtCancelCount[event] ?? _cancelCount) != _cancelCount)) {
      // הריצה הבאה תחליף ותבדוק את מה שזו הייתה מטפלת בו; ספרים שנשלחו
      // לבדיקה מוחלפים — החלפה מיותרת עדיפה על תוכן ישן.
      try {
        await _repository.rememberChangedBooks(
          [...event.changedBooks, ...event.check.books],
          checkLibrary: schemaBlocked || event.check.wholeLibrary,
        );
      } catch (e) {
        debugPrint('⚠️ שמירת ספרים שהשתנו מריצה שבוטלה נכשלה: $e');
      }
      return;
    }
    if (schemaBlocked) {
      if (event is ApplyHiddenIndexDelta) event.onCompleted?.call(false);
      return;
    }

    _isFinalizing = false;
    // ריצה חדשה מתחילה ללא השהיה; המצב החסכוני נשמר בין ריצות.
    if (_isPaused) {
      _isPaused = false;
      _repository.resumeIndexing();
    }

    if (event is ResetAndIndex) {
      final cancelCount = _cancelCount;
      _activeWorkId = null;
      final requiresReset = await _repository.requiresManualReindex(
        event.library,
      );
      if (cancelCount != _cancelCount) return;
      // בקשה כפולה או מחלון שמצבו לא התעדכן הייתה מוחקת אינדקס שזה עתה נבנה.
      if (requiresReset && !await _repository.clearIndex()) return;
      if (cancelCount != _cancelCount) return;
    }

    if (event is RunIndexing) {
      await _onRunIndexing(event, emit);
      return;
    }

    if (event is SyncBookOrder) {
      await _repository.syncBookOrder(event.library);
      return;
    }

    if (event is ReconcileHiddenIndex) {
      var success = false;
      try {
        if (!await _repository.dropHiddenIndexEntries(event.library)) {
          throw StateError('מחיקת ספרים מוסתרים מהאינדקס נכשלה');
        }
        if (event.indexVisible) {
          if (_repository.eligibleBookCount(event.library) == 0) {
            emit(const IndexingComplete());
          } else {
            await _onRunIndexing(RunIndexing(event.library), emit);
          }
        }
        success =
            !event.indexVisible ||
            (state is IndexingComplete && (state as IndexingComplete).isClean);
        if (success) {
          if (event.clearRestoreMarker) {
            await const HiddenLibraryStore().clearPendingIndexReconciliation();
          }
          if (event.clearVisibilityMarker && event.visibilityRevision != null) {
            await const HiddenLibraryStore().clearPendingVisibilityIndex(
              event.visibilityRevision!,
            );
          }
        }
      } catch (error) {
        success = false;
        emit(IndexingError(error.toString()));
      }
      if (!success &&
          state is! IndexingComplete &&
          (event.indexVisible ||
              !const HiddenLibraryStore().load().isEmpty ||
              const HiddenLibraryStore().hasPendingIndexReconciliation ||
              const HiddenLibraryStore().hasPendingVisibilityIndex)) {
        _showHiddenReconciliationError(
          SettingsMessages.hiddenBooksIndexUpdateFailed,
        );
      }
      return;
    }

    if (event is ApplyHiddenIndexDelta) {
      var success = false;
      try {
        if (event.newlyHidden.isNotEmpty &&
            !await _repository.dropBookIndexEntries(event.newlyHidden)) {
          throw StateError('מחיקת ספרים מוסתרים מהאינדקס נכשלה');
        }
        if (event.newlyVisible.isNotEmpty) {
          success = await _onRunIndexing(
            RunIndexing(event.library, books: event.newlyVisible),
            emit,
          );
        } else {
          success = true;
        }
      } catch (error) {
        emit(IndexingError(error.toString()));
      }
      try {
        if (event.visibilityRevision != null) {
          await const HiddenLibraryStore().completeVisibilityIndexUpdate(
            event.visibilityRevision!,
            success,
          );
        } else if (!success) {
          await const HiddenLibraryStore().beginVisibilityIndexUpdate();
        }
      } catch (error) {
        success = false;
        debugPrint('Failed to update visibility index marker: $error');
      }
      event.onCompleted?.call(success);
      return;
    }

    if (event is DropOrphanedIndexEntries) {
      // עבודת רקע שקטה — בלי מצבי התקדמות; כשל אינו קריטי (ינוקה ברענון הבא).
      try {
        await _repository.dropOrphanedIndexEntries(event.library);
      } catch (e) {
        debugPrint('⚠️ ניקוי רשומות יתומות מהאינדקס נכשל: $e');
      }
    }
  }

  /// מחזיר הצלחה של הריצה גם כשנותרה עבודה בספרייה. InProgress נפלט רק
  /// כשיש עבודה, עם מספר הספרים לבדיקה או לאינדוקס.
  Future<bool> _onRunIndexing(
    RunIndexing event,
    Emitter<IndexingState> emit,
  ) async {
    final workId = ++_nextWorkId;
    final runClock = Stopwatch()..start();
    _activeWorkId = workId;

    return _runIndexing(
      event,
      emit,
      workId,
      runClock,
      () => _repository.runIndexing(
        event.library,
        books: event.books,
        changedBooks: event.changedBooks,
        check: event.check,
        // שלב הבדיקה נפלט ישירות (ולא UpdateIndexingProgress) כדי ש-
        // processed==total בסופו לא ייתפס כהתקדמות של שלב האינדוקס.
        onScanProgress: (processed, total) {
          if (_activeWorkId != workId) return;
          emit(
            _inProgress(
              booksProcessed: processed,
              totalBooks: total,
              isScanning: true,
            ),
          );
        },
        onWorkListReady: (total) {
          if (_activeWorkId != workId) return;
          emit(_inProgress(booksProcessed: 0, totalBooks: total));
        },
        onActualIndexingStarted: () => add(ActualIndexingStarted(workId)),
        onProgress: _progressOf(workId),
        onFinalizing: () => add(IndexingFinalizing(workId)),
      ),
    );
  }

  void Function(int processed, int total) _progressOf(int workId) =>
      (processed, total) => add(
        UpdateIndexingProgress(
          workId: workId,
          processed: processed,
          total: total,
        ),
      );

  void _onActualIndexingStarted(
    ActualIndexingStarted event,
    Emitter<IndexingState> emit,
  ) {
    if (_activeWorkId != event.workId) {
      return;
    }

    final currentState = state;
    if (currentState is! IndexingInProgress || currentState.isCreatingIndex) {
      return;
    }

    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: true,
      ),
    );
  }

  void _onFinalizing(IndexingFinalizing event, Emitter<IndexingState> emit) {
    if (_activeWorkId != event.workId) return;
    final currentState = state;
    if (currentState is! IndexingInProgress) return;
    _isFinalizing = true;
    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: currentState.isCreatingIndex,
      ),
    );
  }

  /// מסיים חיווי ומחזיר הצלחה של הריצה, כל עוד [workId] עדיין פעיל.
  Future<bool> _runIndexing(
    RunIndexing event,
    Emitter<IndexingState> emit,
    int workId,
    Stopwatch runClock,
    Future<IndexingRunResult> Function() run,
  ) async {
    try {
      final result = await run();
      if (_activeWorkId != workId) {
        return false;
      }
      final hasPendingWork =
          result.isClean &&
          event.books != null &&
          await _repository.hasUnindexedBooks(event.library);
      if (_activeWorkId != workId) return false;
      _activeWorkId = null;
      _reportRunFailures(result, runClock.elapsed);
      if (result.completed && !hasPendingWork) {
        emit(IndexingComplete(failures: result.failures));
      } else {
        emit(IndexingInitial());
      }
      return result.isClean;
    } catch (e) {
      if (_activeWorkId != workId) {
        return false;
      }
      _activeWorkId = null;
      emit(
        IndexingError(
          e.toString(),
          booksProcessed: state.booksProcessed,
          totalBooks: state.totalBooks,
        ),
      );
      return false;
    }
  }

  void _reportRunFailures(IndexingRunResult result, Duration elapsed) {
    if (result.failures.isNotEmpty ||
        IndexingFailureReporter.isSlowRun(elapsed)) {
      _reportFailures(result, elapsed);
    }
  }

  Future<void> _onCheckIndexStatus(
    CheckIndexStatus event,
    Emitter<IndexingState> emit,
  ) async {
    if (state is IndexingInProgress) return;

    await _repository.awaitReady();

    if (state is IndexingInProgress) return;

    if (await _repository.requiresManualReindex(event.library)) {
      emit(IndexingInitial());
      return;
    }

    final hasUnindexedBooks = await _repository.hasUnindexedBooks(
      event.library,
    );
    emit(hasUnindexedBooks ? IndexingInitial() : const IndexingComplete());
  }

  void _onCancelIndexing(
    CancelIndexing event,
    Emitter<IndexingState> emit,
  ) {
    _activeWorkId = null;
    _isPaused = false;
    _cancelCount++;
    _repository.cancelIndexing();
    emit(IndexingStopped());
  }

  void _onPauseIndexing(PauseIndexing event, Emitter<IndexingState> emit) {
    if (state is! IndexingInProgress || _isPaused) return;
    _isPaused = true;
    _repository.pauseIndexing();
    _reemitProgressFlags(emit);
  }

  void _onResumeIndexing(ResumeIndexing event, Emitter<IndexingState> emit) {
    if (!_isPaused) return;
    _isPaused = false;
    _repository.resumeIndexing();
    _reemitProgressFlags(emit);
  }

  Future<void> _onSetEconomyIndexing(
    SetEconomyIndexing event,
    Emitter<IndexingState> emit,
  ) async {
    if (_isEconomy == event.enabled) return;
    try {
      await _repository.setEconomyIndexing(event.enabled);
      _isEconomy = event.enabled;
      _reemitProgressFlags(emit);
    } catch (e) {
      debugPrint('⚠️ החלפת מצב אינדוקס חסכוני נכשלה: $e');
    }
  }

  /// פליטה מחדש של מצב ההתקדמות הנוכחי עם דגלי ההשהיה/החיסכון העדכניים.
  void _reemitProgressFlags(Emitter<IndexingState> emit) {
    final currentState = state;
    if (currentState is! IndexingInProgress) return;
    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: currentState.isCreatingIndex,
        isScanning: currentState.isScanning,
      ),
    );
  }

  Future<void> _onEraseIndex(
    ClearIndex event,
    Emitter<IndexingState> emit,
  ) async {
    _activeWorkId = null;
    if (!await _repository.clearIndex()) return;
    emit(IndexingInitial());
  }

  void _onUpdateProgress(
    UpdateIndexingProgress event,
    Emitter<IndexingState> emit,
  ) {
    if (_activeWorkId != event.workId) {
      return;
    }

    // processed==total כאן פירושו "בעבודה על הספר האחרון" — ההשלמה נפלטת
    // ממטפל העבודה עצמו אחרי שה-repository מסיים (כולל commit ו-optimize).
    if (!_repository.isIndexing()) {
      emit(IndexingInitial());
    } else {
      emit(
        _inProgress(
          booksProcessed: event.processed,
          totalBooks: event.total,
          isCreatingIndex: state.isCreatingIndex,
        ),
      );
    }
  }
}
