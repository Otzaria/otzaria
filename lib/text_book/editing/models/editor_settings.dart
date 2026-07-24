import 'package:equatable/equatable.dart';

/// Configuration settings for the text editor
class EditorSettings extends Equatable {
  /// Debounce duration for preview updates
  final Duration previewDebounce;

  /// Global quota for all drafts in MB
  final int globalDraftsQuotaMB;

  /// Number of days after which to clean up old drafts
  final int draftCleanupDays;

  const EditorSettings({
    this.previewDebounce = const Duration(milliseconds: 150),
    this.globalDraftsQuotaMB = 100,
    this.draftCleanupDays = 30,
  });

  /// Creates a copy with updated values
  EditorSettings copyWith({
    Duration? previewDebounce,
    int? globalDraftsQuotaMB,
    int? draftCleanupDays,
  }) {
    return EditorSettings(
      previewDebounce: previewDebounce ?? this.previewDebounce,
      globalDraftsQuotaMB: globalDraftsQuotaMB ?? this.globalDraftsQuotaMB,
      draftCleanupDays: draftCleanupDays ?? this.draftCleanupDays,
    );
  }

  @override
  List<Object?> get props => [
    previewDebounce,
    globalDraftsQuotaMB,
    draftCleanupDays,
  ];
}
