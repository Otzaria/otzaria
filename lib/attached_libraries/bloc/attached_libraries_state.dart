part of 'attached_libraries_bloc.dart';

/// הודעה למשתמש (UiSnack). [id] עולה בכל הודעה, כדי שאותו טקסט פעמיים ברצף
/// עדיין יוצג.
class AttachedLibrariesNotice extends Equatable {
  final int id;
  final String text;
  final bool isError;

  const AttachedLibrariesNotice(this.id, this.text, {this.isError = false});

  @override
  List<Object?> get props => [id, text, isError];
}

class AttachedLibrariesState extends Equatable {
  final List<AttachedLibrary> libraries;
  final List<String> folders;
  final bool isBusy;
  final AttachedLibrariesNotice? notice;

  const AttachedLibrariesState({
    this.libraries = const [],
    this.folders = const [],
    this.isBusy = false,
    this.notice,
  });

  AttachedLibrariesState copyWith({
    List<AttachedLibrary>? libraries,
    List<String>? folders,
    bool? isBusy,
    AttachedLibrariesNotice? notice,
  }) {
    return AttachedLibrariesState(
      libraries: libraries ?? this.libraries,
      folders: folders ?? this.folders,
      isBusy: isBusy ?? this.isBusy,
      notice: notice ?? this.notice,
    );
  }

  @override
  List<Object?> get props => [libraries, folders, isBusy, notice];
}
