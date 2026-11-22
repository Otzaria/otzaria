part of 'attached_libraries_bloc.dart';

sealed class AttachedLibrariesEvent extends Equatable {
  const AttachedLibrariesEvent();

  @override
  List<Object?> get props => [];
}

class LoadAttachedLibraries extends AttachedLibrariesEvent {
  const LoadAttachedLibraries();
}

class ImportAttachedLibraryFile extends AttachedLibrariesEvent {
  final String path;

  const ImportAttachedLibraryFile(this.path);

  @override
  List<Object?> get props => [path];
}

class AddAttachedLibraryFolder extends AttachedLibrariesEvent {
  final String path;

  const AddAttachedLibraryFolder(this.path);

  @override
  List<Object?> get props => [path];
}

class RemoveAttachedLibraryFolder extends AttachedLibrariesEvent {
  final String path;

  const RemoveAttachedLibraryFolder(this.path);

  @override
  List<Object?> get props => [path];
}

class RemoveAttachedLibrary extends AttachedLibrariesEvent {
  final AttachedLibrary library;

  const RemoveAttachedLibrary(this.library);

  @override
  List<Object?> get props => [library];
}

class SetAttachedLibraryPlacement extends AttachedLibrariesEvent {
  final AttachedLibrary library;
  final AttachedLibraryPlacement placement;

  const SetAttachedLibraryPlacement(this.library, this.placement);

  @override
  List<Object?> get props => [library, placement];
}

class SetAttachedLibraryHidden extends AttachedLibrariesEvent {
  final AttachedLibrary library;
  final bool hidden;

  const SetAttachedLibraryHidden(this.library, this.hidden);

  @override
  List<Object?> get props => [library, hidden];
}

class MoveAttachedLibrary extends AttachedLibrariesEvent {
  final AttachedLibrary library;

  /// שלילי — למעלה בסדר ההצגה.
  final int delta;

  const MoveAttachedLibrary(this.library, this.delta);

  @override
  List<Object?> get props => [library, delta];
}

class RescanAttachedLibraries extends AttachedLibrariesEvent {
  const RescanAttachedLibraries();
}

class ReleaseAttachedLibrary extends AttachedLibrariesEvent {
  final AttachedLibrary library;

  const ReleaseAttachedLibrary(this.library);

  @override
  List<Object?> get props => [library];
}

/// Manual "check for updates" for one database.
class CheckAttachedLibraryUpdate extends AttachedLibrariesEvent {
  final AttachedLibrary library;

  const CheckAttachedLibraryUpdate(this.library);

  @override
  List<Object?> get props => [library];
}

/// Installs the update the user just approved in the confirmation dialog.
/// [forceFull] replaces an official copy that no longer matches its version.
class InstallAttachedLibraryUpdate extends AttachedLibrariesEvent {
  final AttachedLibrary library;
  final bool forceFull;

  const InstallAttachedLibraryUpdate(this.library, {this.forceFull = false});

  @override
  List<Object?> get props => [library, forceFull];
}

/// מביא את פרטי ההורדה של המסדים הרשמיים שאינם מותקנים (בפתיחת הכרטיס).
class CheckOfficialLibraries extends AttachedLibrariesEvent {
  const CheckOfficialLibraries();
}

class InstallOfficialLibrary extends AttachedLibrariesEvent {
  final OfficialAttachedLibrary entry;

  const InstallOfficialLibrary(this.entry);

  @override
  List<Object?> get props => [entry.libraryId];
}

class CancelOfficialLibrary extends AttachedLibrariesEvent {
  final String libraryId;

  const CancelOfficialLibrary(this.libraryId);

  @override
  List<Object?> get props => [libraryId];
}

/// התקנת מסד רשמי מחבילה לא-מקוונת (`<name>-offline.tar.zst`, שלם או בחלקים).
class ImportOfficialLibraryPackage extends AttachedLibrariesEvent {
  final PackageFolder folder;
  final String archiveName;
  final String? selectedName;

  const ImportOfficialLibraryPackage(
    this.folder,
    this.archiveName, {
    this.selectedName,
  });

  @override
  List<Object?> get props => [folder, archiveName, selectedName];
}

/// "לא תודה" על הצעה, או החזרתה להצגה.
class SetOfficialLibraryDeclined extends AttachedLibrariesEvent {
  final String libraryId;
  final bool declined;

  const SetOfficialLibraryDeclined(this.libraryId, {required this.declined});

  @override
  List<Object?> get props => [libraryId, declined];
}

class CancelAttachedLibraryUpdate extends AttachedLibrariesEvent {
  final AttachedLibrary library;

  const CancelAttachedLibraryUpdate(this.library);

  @override
  List<Object?> get props => [library];
}

class _AttachedUpdatesChanged extends AttachedLibrariesEvent {
  const _AttachedUpdatesChanged(this.updates);

  final Map<String, AttachedUpdateStatus> updates;

  @override
  List<Object?> get props => [updates];
}

/// הרשימה השתנתה ב-repository (גם מסריקת רקע) — טוענים מחדש ומרעננים את העץ.
class _AttachedLibrariesChanged extends AttachedLibrariesEvent {
  const _AttachedLibrariesChanged(this.contentChangedSlugs);

  final Set<String> contentChangedSlugs;

  @override
  List<Object?> get props => [contentChangedSlugs];
}
