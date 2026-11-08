import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/foreground_work.dart';
import '../models/android_update.dart';
import '../repository/android_update_repository.dart';
import 'android_update_event.dart';
import 'android_update_state.dart';

class AndroidUpdateBloc extends Bloc<AndroidUpdateEvent, AndroidUpdateState> {
  AndroidUpdateBloc({
    required this.repository,
    required this.networkAllowed,
    required this.checkDue,
    required this.recordSuccessfulCheck,
    ForegroundWork? foregroundWork,
  }) : _foregroundWork = foregroundWork ?? ForegroundWork.instance,
       super(const AndroidUpdateState()) {
    on<AndroidUpdateInitialize>(_initialize);
    on<AndroidUpdateCheck>(_check);
    on<AndroidUpdateDownload>(_download);
    on<AndroidUpdateInstall>(_install);
    on<AndroidUpdateCancel>(_cancel);
    on<AndroidUpdateResumed>(_resume);
    on<AndroidUpdateNativeChanged>((event, emit) {
      _nativeRevision++;
      _applyNative(event.status, emit);
    });
    on<AndroidUpdateDownloadProgress>((event, emit) {
      if (event.operation == _operation &&
          state.phase == AndroidUpdatePhase.downloading) {
        emit(
          state.copyWith(
            bytesDownloaded: event.received,
            totalBytes: event.total,
          ),
        );
      }
    });
    _nativeSubscription = repository.changes.listen((status) {
      if (!isClosed) add(AndroidUpdateNativeChanged(status));
    });
  }

  final AndroidUpdateRepository repository;
  final bool Function() networkAllowed;
  final bool Function() checkDue;
  final Future<void> Function() recordSuccessfulCheck;
  final ForegroundWork _foregroundWork;
  late final StreamSubscription<AndroidNativeUpdateStatus> _nativeSubscription;
  AndroidDownloadCancellation? _cancellation;
  int _operation = 0;
  int _nativeRevision = 0;
  bool _controlling = false;
  bool _resuming = false;

  Future<void> _initialize(
    AndroidUpdateInitialize event,
    Emitter<AndroidUpdateState> emit,
  ) async {
    if (state.environment != null || state.busy) return;
    emit(state.copyWith(phase: AndroidUpdatePhase.initializing));
    try {
      final environment = await repository.environment();
      if (emit.isDone) return;
      emit(state.copyWith(environment: environment));
      if (state.isPlay && networkAllowed()) {
        // A new process may miss a lifecycle resume notification. Recover an
        // existing Play flow even when the scheduled update check is not due.
        _resuming = true;
        try {
          final revision = _nativeRevision;
          final native = await repository.status(resume: true);
          if (!emit.isDone && revision == _nativeRevision) {
            _applyNative(native, emit);
          }
        } finally {
          _resuming = false;
        }
        return;
      } else if (!state.isPlay) {
        final native = await repository.status();
        if (emit.isDone) return;
        if (native.stage == 'installing' || native.stage == 'confirmation') {
          _applyNative(native, emit);
          return;
        }
        final prepared = await repository.restorePrepared();
        if (emit.isDone) return;
        if (prepared != null) {
          emit(
            state.copyWith(phase: AndroidUpdatePhase.ready, prepared: prepared),
          );
          return;
        }
      }
      emit(state.copyWith(phase: AndroidUpdatePhase.idle));
      add(const AndroidUpdateCheck(automatic: true));
    } catch (error) {
      if (!emit.isDone) _fail(error, emit);
    }
  }

  Future<void> _check(
    AndroidUpdateCheck event,
    Emitter<AndroidUpdateState> emit,
  ) async {
    if (state.busy || state.prepared != null || _controlling) return;
    if (!networkAllowed()) {
      if (!event.automatic) {
        emit(
          state.copyWith(
            phase: AndroidUpdatePhase.failed,
            failure: AndroidUpdateFailure.disabled,
          ),
        );
      }
      return;
    }
    if (event.automatic && !checkDue()) return;
    final operation = ++_operation;
    emit(state.copyWith(phase: AndroidUpdatePhase.checking));
    try {
      final environment = state.environment ?? await repository.environment();
      if (emit.isDone || operation != _operation) return;
      emit(state.copyWith(environment: environment));
      if (state.isPlay) {
        final revision = _nativeRevision;
        final status = await repository.status(resume: true);
        if (emit.isDone || operation != _operation) return;
        if (revision == _nativeRevision) _applyNative(status, emit);
      } else {
        final release = await repository.checkDirect();
        if (emit.isDone || operation != _operation) return;
        emit(
          state.copyWith(
            phase: release == null
                ? AndroidUpdatePhase.upToDate
                : AndroidUpdatePhase.available,
            release: release,
            clearRelease: release == null,
          ),
        );
      }
      await recordSuccessfulCheck();
    } catch (error) {
      if (!emit.isDone && operation == _operation) _fail(error, emit);
    }
  }

  Future<void> _download(
    AndroidUpdateDownload event,
    Emitter<AndroidUpdateState> emit,
  ) async {
    if (state.busy ||
        _controlling ||
        _cancellation != null ||
        state.prepared != null) {
      return;
    }
    if (!networkAllowed()) {
      emit(
        state.copyWith(
          phase: AndroidUpdatePhase.failed,
          failure: AndroidUpdateFailure.disabled,
        ),
      );
      return;
    }
    if (state.isPlay) {
      await _playAction(repository.startPlay, emit);
      return;
    }
    final release = state.release;
    if (release == null) return;
    final operation = ++_operation;
    final cancellation = _cancellation = AndroidDownloadCancellation();
    emit(
      state.copyWith(
        phase: AndroidUpdatePhase.downloading,
        bytesDownloaded: 0,
        totalBytes: release.size,
      ),
    );
    _foregroundWork.acquire(
      this,
      notice: (
        channelName: 'עדכוני תוכנה',
        title: 'עדכון אוצריא',
        text: 'מוריד את עדכון התוכנה',
      ),
      userInitiated: true,
      onTimeout: cancellation.cancel,
    );
    try {
      final prepared = await repository.download(release, cancellation, (
        received,
        total,
      ) {
        if (!isClosed) {
          add(AndroidUpdateDownloadProgress(operation, received, total));
        }
      });
      if (emit.isDone || operation != _operation) return;
      if (cancellation.isCancelled) {
        await repository.discardPrepared();
        if (!emit.isDone) {
          emit(state.copyWith(phase: AndroidUpdatePhase.cancelled));
        }
      } else {
        emit(
          state.copyWith(phase: AndroidUpdatePhase.ready, prepared: prepared),
        );
      }
    } on AndroidDownloadCancelled {
      if (!emit.isDone && operation == _operation) {
        emit(state.copyWith(phase: AndroidUpdatePhase.cancelled));
      }
    } catch (error) {
      if (!emit.isDone && operation == _operation) _fail(error, emit);
    } finally {
      _foregroundWork.release(this);
      _cancellation = null;
    }
  }

  void _cancel(AndroidUpdateCancel event, Emitter<AndroidUpdateState> emit) {
    if (state.isPlay || _cancellation == null) return;
    _cancellation!.cancel();
    emit(state.copyWith(phase: AndroidUpdatePhase.cancelling));
  }

  Future<void> _install(
    AndroidUpdateInstall event,
    Emitter<AndroidUpdateState> emit,
  ) async {
    if (state.busy || _controlling || _cancellation != null) return;
    if (state.isPlay) {
      await _playAction(repository.completePlay, emit);
      return;
    }
    _controlling = true;
    _operation++;
    try {
      final prepared = state.prepared ?? await repository.restorePrepared();
      if (emit.isDone) return;
      if (prepared == null) {
        emit(
          state.copyWith(
            phase: AndroidUpdatePhase.failed,
            failure: AndroidUpdateFailure.interrupted,
            clearPrepared: true,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          prepared: prepared,
          phase: AndroidUpdatePhase.awaitingPermission,
        ),
      );
      if (!await repository.canInstall() &&
          !await repository.requestInstallPermission()) {
        if (!emit.isDone) {
          emit(
            state.copyWith(
              phase: AndroidUpdatePhase.failed,
              failure: AndroidUpdateFailure.permissionDenied,
            ),
          );
        }
        return;
      }
      if (emit.isDone) return;
      emit(state.copyWith(phase: AndroidUpdatePhase.installing));
      final revision = _nativeRevision;
      final status = await repository.install(prepared);
      if (!emit.isDone && revision == _nativeRevision) {
        _applyNative(status, emit);
      }
    } catch (error) {
      if (error is AndroidUpdateException &&
          const {
            AndroidUpdateFailure.signatureMismatch,
            AndroidUpdateFailure.packageMismatch,
            AndroidUpdateFailure.hashMismatch,
            AndroidUpdateFailure.sizeMismatch,
            AndroidUpdateFailure.notNewer,
            AndroidUpdateFailure.invalidMetadata,
          }.contains(error.failure)) {
        await repository.discardPrepared();
        if (!emit.isDone) emit(state.copyWith(clearPrepared: true));
      }
      if (!emit.isDone) _fail(error, emit);
    } finally {
      _controlling = false;
    }
  }

  Future<void> _playAction(
    Future<AndroidNativeUpdateStatus> Function() action,
    Emitter<AndroidUpdateState> emit,
  ) async {
    _controlling = true;
    _operation++;
    final revision = _nativeRevision;
    emit(state.copyWith(phase: AndroidUpdatePhase.installing));
    try {
      final status = await action();
      if (!emit.isDone && revision == _nativeRevision) {
        _applyNative(status, emit);
      }
    } catch (error) {
      if (!emit.isDone) _fail(error, emit);
    } finally {
      _controlling = false;
    }
  }

  Future<void> _resume(
    AndroidUpdateResumed event,
    Emitter<AndroidUpdateState> emit,
  ) async {
    if (_resuming ||
        _controlling ||
        state.environment == null ||
        _cancellation != null) {
      return;
    }
    if (state.isPlay && !networkAllowed()) return;
    _resuming = true;
    final revision = _nativeRevision;
    final operation = _operation;
    try {
      final status = await repository.status(resume: true);
      if (!emit.isDone &&
          revision == _nativeRevision &&
          operation == _operation &&
          !_controlling) {
        _applyNative(status, emit);
      }
    } catch (error) {
      if (!emit.isDone && state.busy) _fail(error, emit);
    } finally {
      _resuming = false;
    }
  }

  void _applyNative(
    AndroidNativeUpdateStatus native,
    Emitter<AndroidUpdateState> emit,
  ) {
    if (!state.isPlay) {
      if (_cancellation != null) return;
      if (native.stage == 'idle') return;
      final version = native.versionCode;
      if (version != null &&
          state.prepared != null &&
          version != state.prepared!.versionCode) {
        return;
      }
      if (native.stage == 'completed' &&
          state.phase != AndroidUpdatePhase.installing &&
          state.phase != AndroidUpdatePhase.confirmation) {
        return;
      }
    }
    final phase = switch (native.stage) {
      'idle' => AndroidUpdatePhase.idle,
      'upToDate' => AndroidUpdatePhase.upToDate,
      'available' => AndroidUpdatePhase.available,
      'downloading' => AndroidUpdatePhase.downloading,
      'ready' => AndroidUpdatePhase.ready,
      'confirmation' => AndroidUpdatePhase.confirmation,
      'preparing' || 'installing' => AndroidUpdatePhase.installing,
      'completed' => AndroidUpdatePhase.completed,
      'cancelled' => AndroidUpdatePhase.cancelled,
      'failed' || 'interrupted' || 'unavailable' => AndroidUpdatePhase.failed,
      _ => null,
    };
    if (phase == null) return;
    emit(
      state.copyWith(
        phase: phase,
        bytesDownloaded: native.bytesDownloaded,
        totalBytes: native.totalBytes,
        failure: native.stage == 'unavailable'
            ? AndroidUpdateFailure.playUnavailable
            : native.stage == 'interrupted'
            ? AndroidUpdateFailure.interrupted
            : native.stage == 'failed'
            ? AndroidUpdateFailure.installerFailed
            : null,
      ),
    );
  }

  void _fail(Object error, Emitter<AndroidUpdateState> emit) {
    final failure = switch (error) {
      AndroidUpdateException(:final failure) => failure,
      SocketException() ||
      TimeoutException() ||
      http.ClientException() => AndroidUpdateFailure.network,
      FileSystemException() => AndroidUpdateFailure.storage,
      _ => AndroidUpdateFailure.installerFailed,
    };
    emit(state.copyWith(phase: AndroidUpdatePhase.failed, failure: failure));
  }

  @override
  Future<void> close() async {
    _cancellation?.cancel();
    await _nativeSubscription.cancel();
    _foregroundWork.release(this);
    await super.close();
    await repository.dispose();
  }
}
