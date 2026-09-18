import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
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
  }) : _repository = repository ?? AttachedLibrariesRepository.instance,
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
    _subscription = _repository.changes.listen(
      (slugs) => add(_AttachedLibrariesChanged(slugs)),
    );
  }

  final void Function(LibraryEvent event) _addLibraryEvent;
  final AttachedLibrariesRepository _repository;
  late final StreamSubscription<void> _subscription;
  int _noticeId = 0;

  AttachedLibrariesState _loaded(AttachedLibrariesState state) =>
      state.copyWith(
        libraries: _repository.libraries,
        folders: _repository.folders,
      );

  AttachedLibrariesNotice _notice(String text, {bool isError = false}) =>
      AttachedLibrariesNotice(++_noticeId, text, isError: isError);

  void _onLoad(
    LoadAttachedLibraries event,
    Emitter<AttachedLibrariesState> emit,
  ) => emit(_loaded(state));

  void _onChanged(
    _AttachedLibrariesChanged event,
    Emitter<AttachedLibrariesState> emit,
  ) {
    emit(_loaded(state));
    _addLibraryEvent(
      RefreshLibrary(
        source: RefreshSource.attachedLibraries,
        changedAttachedSlugs: event.contentChangedSlugs,
      ),
    );
  }

  /// מריץ [operation] עם חיווי עבודה, ומציג את [success] או את השגיאה.
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
      return _notice(
        SettingsMessages.attachedLibraryAdded(result.library!.displayName),
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
    await _subscription.cancel();
    return super.close();
  }
}
