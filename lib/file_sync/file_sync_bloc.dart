import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/file_sync/file_sync_event.dart';
import 'package:otzaria/file_sync/file_sync_state.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';

class FileSyncBloc extends Bloc<FileSyncEvent, FileSyncState> {
  final FileSyncRepository repository;
  Timer? _progressTimer;

  // Getter לבדיקת מצב אופליין
  bool get _isOffline =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  FileSyncBloc({required this.repository}) : super(const FileSyncState()) {
    on<StartSync>(_onStartSync);
    on<StopSync>(_onStopSync);
    on<UpdateProgress>(_onUpdateProgress);
    on<ResetState>(_onResetState);

    // Check for auto-sync setting and offline mode
    final isAutoSync =
        Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true;
    if (isAutoSync && !_isOffline) {
      add(const StartSync());
    }
  }

  Future<void> _onStartSync(
      StartSync event, Emitter<FileSyncState> emit) async {
    // Check if offline mode is enabled
    if (_isOffline) {
      emit(state.copyWith(
        status: FileSyncStatus.initial,
        message: 'מצב אופליין מופעל',
      ));
      return;
    }

    // If already syncing or completed, reset first
    if (state.status == FileSyncStatus.syncing ||
        state.status == FileSyncStatus.completed) {
      emit(const FileSyncState());
    }

    emit(state.copyWith(
      status: FileSyncStatus.syncing,
      message: 'מסנכרן...',
    ));

    // Set up a timer to update progress periodically
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (repository.isSyncing && repository.totalFiles > 0) {
        add(UpdateProgress(
          current: repository.currentProgress,
          total: repository.totalFiles,
        ));
      }
    });

    try {
      final successCount = await repository.syncFiles();
      final catalogUpdated = repository.catalogUpdatedInLastSync;
      _progressTimer?.cancel();

      if (successCount > 0 || catalogUpdated) {
        final message = successCount > 0 && catalogUpdated
            ? 'הוחלו $successCount עדכוני DB ועודכן גם קטלוג הספרים'
            : successCount > 0
                ? 'הוחלו $successCount עדכוני DB'
                : 'קטלוג הספרים עודכן';
        emit(state.copyWith(
          status: FileSyncStatus.completed,
          hasNewSync: true,
          message: message,
        ));
      } else {
        emit(state.copyWith(
          status: FileSyncStatus.completed,
          hasNewSync: false,
          message: 'הספרייה מעודכנת',
        ));
      }
    } catch (e) {
      _progressTimer?.cancel();
      emit(state.copyWith(
        status: FileSyncStatus.error,
        message: 'שגיאה בסנכרון: ${e.toString()}',
        errorMessage: e.toString(),
      ));
    }
  }

  void _onStopSync(StopSync event, Emitter<FileSyncState> emit) {
    _progressTimer?.cancel();
    repository.stopSyncing();
    emit(const FileSyncState());
  }

  void _onUpdateProgress(UpdateProgress event, Emitter<FileSyncState> emit) {
    emit(state.copyWith(
      currentProgress: event.current,
      totalFiles: event.total,
      message: 'מסנכרן... ${event.current}/${event.total}',
    ));
  }

  void _onResetState(ResetState event, Emitter<FileSyncState> emit) {
    emit(const FileSyncState());
  }

  @override
  Future<void> close() {
    _progressTimer?.cancel();
    return super.close();
  }
}