import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/official_attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
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
    on<CheckOfficialLibraries>(_onCheckOfficial);
    on<InstallOfficialLibrary>(_onInstallOfficial);
    on<CancelOfficialLibrary>(_onCancelOfficial);
    on<SetOfficialLibraryDeclined>(_onSetOfficialDeclined);
    on<ImportOfficialLibraryPackage>(_onImportOfficialPackage);
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
        officialOffers: AttachedLibraryUpdateService.notInstalledOfficial(
          _repository.libraries,
        ),
        declinedOfficial: _updates.declinedOfficial(),
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
      GenerationCache.instance
          .reloadAttached(changedSlugs: event.contentChangedSlugs)
          .catchError((Object e) {
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
      _identifyManualCopies();
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
    _identifyManualCopies();
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
    // אחרי ההסרה: עדכון שייעצר מעכשיו כבר לא ימצא את המסד ולא ישאיר מצב.
    await _updates.forget(event.library);
    if (event.library.official case final official?) {
      await _updates.setOfficialDeclined(official.libraryId, declined: true);
    }
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
    _identifyManualCopies();
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
  ) => unawaited(_updates.install(event.library, forceFull: event.forceFull));

  void _onCancelUpdate(
    CancelAttachedLibraryUpdate event,
    Emitter<AttachedLibrariesState> emit,
  ) => _updates.cancel(event.library);

  Future<void> _onCheckOfficial(
    CheckOfficialLibraries event,
    Emitter<AttachedLibrariesState> emit,
  ) => _updates.checkOfficialOffers();

  void _onInstallOfficial(
    InstallOfficialLibrary event,
    Emitter<AttachedLibrariesState> emit,
  ) => unawaited(_updates.installOfficial(event.entry));

  void _onCancelOfficial(
    CancelOfficialLibrary event,
    Emitter<AttachedLibrariesState> emit,
  ) => _updates.cancelOfficial(event.libraryId);

  Future<void> _onSetOfficialDeclined(
    SetOfficialLibraryDeclined event,
    Emitter<AttachedLibrariesState> emit,
  ) async {
    await _updates.setOfficialDeclined(
      event.libraryId,
      declined: event.declined,
    );
    emit(_loaded(state));
    if (!event.declined) await _updates.checkOfficialOffers();
  }

  /// עותק ידני של מסד רשמי מזוהה ברקע; כשל אינו מגיע למשתמש.
  void _identifyManualCopies() => unawaited(
    _updates.adoptManualCopies().catchError((Object e) {
      debugPrint('[AttachedLibrariesBloc] identification failed: $e');
    }),
  );

  Future<void> _onImportOfficialPackage(
    ImportOfficialLibraryPackage event,
    Emitter<AttachedLibrariesState> emit,
  ) => _run(emit, () async {
    final result = await _updates.importOfflinePackageFromFolder(
      event.folder,
      event.archiveName,
      selectedName: event.selectedName,
    );
    final message = packageMessage(result);
    return _notice(
      message,
      isError:
          result != OfficialPackageResult.installed &&
          result != OfficialPackageResult.alreadyInstalled,
    );
  });

  /// ההודעה למשתמש על חבילה לא-מקוונת של מסד רשמי.
  static String packageMessage(
    OfficialPackageResult result,
  ) => switch (result) {
    OfficialPackageResult.installed =>
      SettingsMessages.officialPackageInstalled,
    OfficialPackageResult.alreadyInstalled =>
      SettingsMessages.officialPackageAlreadyInstalled,
    OfficialPackageResult.notPackage =>
      SettingsMessages.officialPackageNotPackage,
    OfficialPackageResult.badSignature =>
      SettingsMessages.officialPackageBadSignature,
    OfficialPackageResult.hashMismatch =>
      SettingsMessages.officialPackageCorrupt,
    OfficialPackageResult.olderVersion => SettingsMessages.officialPackageOlder,
    OfficialPackageResult.noSpace => SettingsMessages.officialPackageNoSpace,
    OfficialPackageResult.failed => SettingsMessages.officialPackageFailed,
  };

  void _onUpdatesChanged(
    _AttachedUpdatesChanged event,
    Emitter<AttachedLibrariesState> emit,
  ) {
    AttachedLibrariesNotice? notice;
    for (final library in state.libraries) {
      final now = event.updates[library.path];
      final before = state.updateOf(library);
      if (now is AttachedUpdateInstalled &&
          before is! AttachedUpdateInstalled) {
        notice = _notice(
          SettingsMessages.attachedUpdateInstalled(
            library.displayName,
            now.dbVersion,
          ),
        );
      }
      if (now case AttachedUpdateFailed(
        error: AttachedUpdateError.integrityMismatch,
      ) when before != now) {
        notice = _notice(
          SettingsMessages.officialLibraryIntegrityMismatch(
            library.displayName,
          ),
          isError: true,
        );
      }
    }
    for (final entry in OfficialAttachedLibraries.catalog) {
      final key = AttachedLibraryUpdateService.officialKey(entry.libraryId);
      if (event.updates[key] is AttachedUpdateInstalled &&
          state.updates[key] is! AttachedUpdateInstalled) {
        notice = _notice(
          SettingsMessages.officialLibraryInstalled(entry.displayName),
        );
      }
    }
    emit(
      _loaded(state).copyWith(updates: event.updates, notice: notice),
    );
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
