part of 'attached_libraries_bloc.dart';

/// הודעה למשתמש (UiSnack). [id] עולה בכל הודעה, כדי שאותו טקסט פעמיים ברצף
/// עדיין יוצג.
class AttachedLibrariesNotice extends Equatable {
  final int id;
  final String text;
  final bool isError;

  /// Set after a successful attach, for the summary dialog.
  final AttachedLibrary? attached;

  const AttachedLibrariesNotice(
    this.id,
    this.text, {
    this.isError = false,
    this.attached,
  });

  @override
  List<Object?> get props => [id, text, isError, attached];
}

class AttachedLibrariesState extends Equatable {
  final List<AttachedLibrary> libraries;
  final List<String> folders;
  final bool isBusy;
  final AttachedLibrariesNotice? notice;

  /// Update status per database path.
  final Map<String, AttachedUpdateStatus> updates;

  const AttachedLibrariesState({
    this.libraries = const [],
    this.folders = const [],
    this.isBusy = false,
    this.notice,
    this.updates = const {},
  });

  AttachedUpdateStatus updateOf(AttachedLibrary library) =>
      updates[library.path] ?? const AttachedUpdateIdle();

  AttachedLibrariesState copyWith({
    List<AttachedLibrary>? libraries,
    List<String>? folders,
    bool? isBusy,
    AttachedLibrariesNotice? notice,
    Map<String, AttachedUpdateStatus>? updates,
  }) {
    return AttachedLibrariesState(
      libraries: libraries ?? this.libraries,
      folders: folders ?? this.folders,
      isBusy: isBusy ?? this.isBusy,
      notice: notice ?? this.notice,
      updates: updates ?? this.updates,
    );
  }

  @override
  List<Object?> get props => [libraries, folders, isBusy, notice, updates];
}
