import 'package:equatable/equatable.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';

abstract class EmptyLibraryState extends Equatable {
  final bool isLoading;
  final String? selectedPath;
  final String? errorMessage;
  // non-null = כפתור ההורדה מושבת + הסיבה מוצגת למשתמש
  final String? downloadDisabledReason;

  const EmptyLibraryState({
    this.isLoading = false,
    this.selectedPath,
    this.errorMessage,
    this.downloadDisabledReason,
  });

  @override
  List<Object?> get props => [
    isLoading,
    selectedPath,
    errorMessage,
    downloadDisabledReason,
  ];
}

class EmptyLibraryInitial extends EmptyLibraryState {
  const EmptyLibraryInitial({super.downloadDisabledReason});
}

class EmptyLibraryLoading extends EmptyLibraryState {
  const EmptyLibraryLoading({
    super.selectedPath,
  }) : super(isLoading: true);
}

class EmptyLibraryDirectorySelected extends EmptyLibraryState {
  /// בייבוא — מה הותקן ומה חסר בספרייה; null בבחירת ספרייה קיימת.
  final LibraryImportReport? importReport;

  const EmptyLibraryDirectorySelected({
    required String selectedPath,
    this.importReport,
  }) : super(selectedPath: selectedPath);

  @override
  List<Object?> get props => [...super.props, importReport];
}

class EmptyLibraryError extends EmptyLibraryState {
  const EmptyLibraryError({
    super.errorMessage,
    super.selectedPath,
    super.downloadDisabledReason,
  });
}

class EmptyLibraryExtracting extends EmptyLibraryState {
  final double progress;
  final String message;

  /// הפעולה ניתנת לעצירה ([CancelLibraryImportRequested]) בשלב הזה.
  final bool cancellable;

  const EmptyLibraryExtracting({
    required String selectedPath,
    required this.progress,
    required this.message,
    this.cancellable = false,
  }) : super(selectedPath: selectedPath, isLoading: true);

  @override
  List<Object?> get props => [
    ...super.props,
    progress,
    message,
    cancellable,
  ];
}

class EmptyLibraryDownloading extends EmptyLibraryState {
  final double progress;
  final String message;

  const EmptyLibraryDownloading({
    required this.progress,
    required this.message,
  }) : super(isLoading: true);

  @override
  List<Object?> get props => [
    ...super.props,
    progress,
    message,
  ];
}
