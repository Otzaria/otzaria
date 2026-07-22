import 'package:equatable/equatable.dart';

abstract class EmptyLibraryState extends Equatable {
  final bool isLoading;
  final String? selectedPath;
  final String? errorMessage;
  final List<String>? zipFiles;
  // non-null = כפתור ההורדה מושבת + הסיבה מוצגת למשתמש
  final String? downloadDisabledReason;

  const EmptyLibraryState({
    this.isLoading = false,
    this.selectedPath,
    this.errorMessage,
    this.zipFiles,
    this.downloadDisabledReason,
  });

  @override
  List<Object?> get props => [
        isLoading,
        selectedPath,
        errorMessage,
        zipFiles,
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
  const EmptyLibraryDirectorySelected({
    required String selectedPath,
  }) : super(selectedPath: selectedPath);
}

class EmptyLibraryError extends EmptyLibraryState {
  const EmptyLibraryError({
    super.errorMessage,
    super.selectedPath,
    super.zipFiles,
    super.downloadDisabledReason,
  });
}

class EmptyLibraryZipExtracted extends EmptyLibraryState {
  final String extractedFileName;

  const EmptyLibraryZipExtracted({
    required String selectedPath,
    required this.extractedFileName,
  }) : super(selectedPath: selectedPath);

  @override
  List<Object?> get props => [
        ...super.props,
        extractedFileName,
      ];
}

class EmptyLibraryExtracting extends EmptyLibraryState {
  final double progress;
  final String message;

  const EmptyLibraryExtracting({
    required String selectedPath,
    required this.progress,
    required this.message,
  }) : super(selectedPath: selectedPath, isLoading: true);

  @override
  List<Object?> get props => [
        ...super.props,
        progress,
        message,
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

/// Android בלבד: שואל את המשתמש אם להעתיק או להעביר את seforim.db
/// מאחסון חיצוני (לא נגיש ל-sqlite3 native) לאחסון פנימי.
class EmptyLibraryAskingDbCopy extends EmptyLibraryState {
  /// הנתיב החיצוני של seforim.db (שנבחר ע"י המשתמש)
  final String externalDbPath;

  /// תיקיית הספרייה שנבחרה (תישמר ב-keyLibraryPath ללא שינוי)
  final String libraryPath;

  /// הנתיב הפנימי המוצע שאליו יועתק/יועבר seforim.db
  final String internalDbPath;

  /// גודל seforim.db בבייטים
  final int dbSizeBytes;

  /// מקום פנוי באחסון הפנימי בבייטים
  final int freeSpaceBytes;

  const EmptyLibraryAskingDbCopy({
    required this.externalDbPath,
    required this.libraryPath,
    required this.internalDbPath,
    required this.dbSizeBytes,
    required this.freeSpaceBytes,
    // errorMessage מוגדר ב-EmptyLibraryState — מועבר דרך super
    super.errorMessage,
  });

  @override
  List<Object?> get props => [
        externalDbPath,
        libraryPath,
        internalDbPath,
        dbSizeBytes,
        freeSpaceBytes,
        errorMessage,
      ];
}
