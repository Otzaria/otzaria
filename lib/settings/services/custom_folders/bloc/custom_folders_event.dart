part of 'custom_folders_bloc.dart';

sealed class CustomFoldersEvent extends Equatable {
  const CustomFoldersEvent();
}

class LoadCustomFolders extends CustomFoldersEvent {
  const LoadCustomFolders();
  @override
  List<Object> get props => [];
}

class AddCustomFolder extends CustomFoldersEvent {
  const AddCustomFolder(this.path);
  final String path;
  @override
  List<Object> get props => [path];
}

class RemoveCustomFolder extends CustomFoldersEvent {
  const RemoveCustomFolder(this.folder, {required this.deleteFromDb});
  final CustomFolder folder;
  final bool deleteFromDb;
  @override
  List<Object> get props => [folder, deleteFromDb];
}

class ToggleAddToDatabase extends CustomFoldersEvent {
  const ToggleAddToDatabase(this.folder, this.value);
  final CustomFolder folder;
  final bool value;
  @override
  List<Object> get props => [folder, value];
}

class RescanCustomFolders extends CustomFoldersEvent {
  const RescanCustomFolders({this.showNoChangesMessage = true});
  final bool showNoChangesMessage;
  @override
  List<Object> get props => [showNoChangesMessage];
}
