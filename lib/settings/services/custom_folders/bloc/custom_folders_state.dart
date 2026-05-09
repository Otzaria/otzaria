part of 'custom_folders_bloc.dart';

class CustomFoldersState extends Equatable {
  const CustomFoldersState({
    this.folders = const [],
    this.isSyncing = false,
    this.message,
    this.error,
  });

  final List<CustomFolder> folders;
  final bool isSyncing;
  final String? message;
  final String? error;

  CustomFoldersState copyWith({
    List<CustomFolder>? folders,
    bool? isSyncing,
    Object? message = _sentinel,
    Object? error = _sentinel,
  }) {
    return CustomFoldersState(
      folders: folders ?? this.folders,
      isSyncing: isSyncing ?? this.isSyncing,
      message: identical(message, _sentinel) ? this.message : message as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  @override
  List<Object?> get props => [folders, isSyncing, message, error];
}

const Object _sentinel = Object();
