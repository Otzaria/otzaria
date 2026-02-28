import 'package:equatable/equatable.dart';

abstract class EmptyLibraryEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class PickDatabaseFileRequested extends EmptyLibraryEvent {
  final String? filePath;

  PickDatabaseFileRequested({this.filePath});

  @override
  List<Object?> get props => [filePath];
}

class DownloadLibraryRequested extends EmptyLibraryEvent {}

class DeleteZipAnswered extends EmptyLibraryEvent {
  final bool shouldDelete;
  final String zipPath;
  final String extractedPath;

  DeleteZipAnswered({
    required this.shouldDelete,
    required this.zipPath,
    required this.extractedPath,
  });

  @override
  List<Object?> get props => [shouldDelete, zipPath, extractedPath];
}
