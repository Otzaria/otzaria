import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/library/bloc/library_event.dart';

part 'attached_libraries_event.dart';
part 'attached_libraries_state.dart';

/// ניהול המסדים המצורפים מהממשק. כל שינוי ב-repository — מהממשק או מסריקת
/// הרקע בעלייה — מגיע דרך [AttachedLibrariesRepository.changes] ומרענן את העץ.
class AttachedLibrariesBloc
    extends Bloc<AttachedLibrariesEvent, AttachedLibrariesState> {
  AttachedLibrariesBloc({
    required this._addLibraryEvent,
    AttachedLibrariesRepository? repository,
    AttachedLibraryUpdateService? updates,
  }) : _repository = repository ?? AttachedLibrariesRepository.instance,
       _updates = updates ?? AttachedLibraryUpdateService.instance,
       super(const AttachedLibrariesState()) {
    on<LoadAttachedLibraries>(_onLoad);
    on<_AttachedLibrariesChanged>(_onChanged);
    on<ImportAttachedLibraryFile>(_onImport);
    on<AddAttachedLibraryFolder>(_onAddFolder);
    on<RemoveAttachedLibraryFolder>(_onRemoveFolder);
    on<RemoveAttachedLibrary>(_onRemove);
    on<SetAttachedLibraryPlacement>(_onSetPlacement);
    on<SetAttachedLibraryHidden>(_onSetHidden);
    on<MoveAttachedLibrary>(_onMove);
    on<RescanAttachedLibraries>(_onRescan);
    on<ReleaseAttachedLibrary>(_onRelease);
    on<CheckAttachedLibraryUpdate>(_onCheckUpdate);
    on<InstallAttachedLibraryUpdate>(_onInstallUpdate);
    on<CancelAttachedLibraryUpdate>(_onCancelUpdate);
    on<_AttachedUpdatesChanged>(_onUpdatesChanged);
    _subscription = _repository.changes.listen(
      (slugs) => add(_AttachedLibrariesChanged(slugs)),
    );
    _updates.statuses.addListener(_forwardUpdates);
  }

  void _forwardUpdates() =>
      add(_AttachedUpdatesChanged(_updates.statuses.value));

  final void Function(LibraryEvent event) _addLibraryEvent;
  final AttachedLibrariesRepository _repository;
  final AttachedLibraryUpdateService _updates;
  late final StreamSubscription<void> _subscription;
  int _noticeId = 0;

  AttachedLibrariesState _loaded(AttachedLibrariesState state) =>
      state.copyWith(
        libraries: _repository.libraries,
        folders: _repository.folders,
      );

  AttachedLibrariesNotice _notice(String text, {bool isError = false}) =>
      AttachedLibrariesNotice(++_noticeId, text, isError: isError);

  Future<void> _onLoad(
    LoadAttachedLibraries event,
    Emitter<AttachedLibrariesState> emit,
  ) async {
    emit(_loaded(state).copyWith(updates: _updates.statuses.value));
    await _updates.restorePending();
  }

  Future<void> _onChanged(
    _AttachedLibrariesChanged event,
    Emitter<AttachedLibrariesState> emit,
  ) async {
    emit(_loaded(state));
    AcronymsCache.instance.clearAttached();
    // האינדוקס שאחרי הרענון ממתין לה דרך GenerationCache.warmUp.
    unawaited(
      GenerationCache.instance.reloadAttached().catchError((Object e) {
        debugPrint('[AttachedLibrariesBloc] generations reload failed: $e');
      }),
    );
    _addLibraryEvent(
      RefreshLibrary(
        source: RefreshSource.attachedLibraries,
        changedAttachedSlugs: event.contentChangedSlugs,
      ),
    );
  }

  /// מריץ [operation] עם חיווי עבודה, ומציג את ההודעה שהחזירה או את השגיאה.
  Future<void> _run(
    Emitter<AttachedLibrariesState> emit,
    Future<AttachedLibrariesNotice?> Function() operation,
  ) async {
    emit(state.copyWith(isBusy: true));
    AttachedLibrariesNotice? notice;
    try {
      notice = await operation();
    } catch (e) {
      notice = _notice(SettingsMessages.attachedLibraryError(e), isError: true);
    }
    emit(_loaded(state).copyWith(isBusy: false, notice: notice));
  }

  Future<void> _onImport(
    ImportAttachedLibraryFile event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    final result = await _repository.importFile(event.path);
    if (result.isOk) {
      return AttachedLibrariesNotice(
        ++_noticeId,
        SettingsMessages.attachedLibraryAdded(result.library!.displayName),
        attached: result.library,
      );
    }
    return _notice(problemMessage(result.problem!), isError: true);
  });

  Future<void> _onAddFolder(
    AddAttachedLibraryFolder event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.addFolder(event.path);
    return _notice(SettingsMessages.attachedLibraryFolderAdded);
  });

  Future<void> _onRemoveFolder(
    RemoveAttachedLibraryFolder event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.removeFolder(event.path);
    return _notice(SettingsMessages.attachedLibraryFolderRemoved);
  });

  Future<void> _onRemove(
    RemoveAttachedLibrary event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.remove(event.library);
    return _notice(SettingsMessages.attachedLibraryRemoved);
  });

  Future<void> _onSetPlacement(
    SetAttachedLibraryPlacement event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.setPlacement(event.library, event.placement);
    return null;
  });

  Future<void> _onSetHidden(
    SetAttachedLibraryHidden event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.setHidden(event.library, event.hidden);
    return null;
  });

  Future<void> _onMove(
    MoveAttachedLibrary event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.move(event.library, event.delta);
    return null;
  });

  Future<void> _onRescan(
    RescanAttachedLibraries event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.rescan();
    return _notice(SettingsMessages.attachedLibrariesRescanned);
  });

  Future<void> _onRelease(
    ReleaseAttachedLibrary event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    await _repository.release(event.library);
    return _notice(SettingsMessages.attachedLibraryReleased);
  });

  Future<void> _onCheckUpdate(
    CheckAttachedLibraryUpdate event,
    Emitter<AttachedLibrariesState> emit,
  ) async {
    final status = await _updates.check(event.library);
    if (status is AttachedUpdateUpToDate) {
      emit(state.copyWith(notice: _notice(SettingsMessages.attachedUpToDate)));
    }
  }

  void _onInstallUpdate(
    InstallAttachedLibraryUpdate event,
    Emitter<AttachedLibrariesState> emit,
  ) => unawaited(_updates.install(event.library));

  void _onCancelUpdate(
    CancelAttachedLibraryUpdate event,
    Emitter<AttachedLibrariesState> emit,
  ) => _updates.cancel(event.library);

  void _onUpdatesChanged(
    _AttachedUpdatesChanged event,
    Emitter<AttachedLibrariesState> emit,
  ) {
    AttachedLibrariesNotice? notice;
    for (final library in state.libraries) {
      final now = event.updates[library.path];
      if (now is AttachedUpdateInstalled &&
          state.updateOf(library) is! AttachedUpdateInstalled) {
        notice = _notice(
          SettingsMessages.attachedUpdateInstalled(
            library.displayName,
            now.dbVersion,
          ),
        );
      }
    }
    emit(state.copyWith(updates: event.updates, notice: notice));
  }

  /// ההודעה למשתמש על מסד שלא צורף.
  static String problemMessage(
    AttachedLibraryProblem problem,
  ) => switch (problem) {
    AttachedLibraryProblem.notFound => SettingsMessages.attachedLibraryNotFound,
    AttachedLibraryProblem.notSqlite =>
      SettingsMessages.attachedLibraryNotSqlite,
    AttachedLibraryProblem.pendingJournal =>
      SettingsMessages.attachedLibraryPendingJournal,
    AttachedLibraryProblem.noBooks => SettingsMessages.attachedLibraryNoBooks,
    AttachedLibraryProblem.openFailed =>
      SettingsMessages.attachedLibraryOpenFailed,
    AttachedLibraryProblem.duplicateSlug =>
      SettingsMessages.attachedLibraryDuplicate,
    AttachedLibraryProblem.copyFailed =>
      SettingsMessages.attachedLibraryCopyFailed,
    AttachedLibraryProblem.alreadyAttached =>
      SettingsMessages.attachedLibraryAlreadyAttached,
  };

  @override
  Future<void> close() async {
    _updates.statuses.removeListener(_forwardUpdates);
    await _subscription.cancel();
    return super.close();
  }
}
