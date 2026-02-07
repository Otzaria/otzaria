import 'package:equatable/equatable.dart';

/// Represents the current state of the text editor
class EditorState extends Equatable {
  /// Whether the editor dialog is currently open
  final bool isOpen;

  /// Index of the section currently being edited
  final int? currentIndex;

  /// Section ID of the section currently being edited
  final String? currentSectionId;

  /// Current text content in the editor
  final String? currentText;

  /// Whether there are unsaved changes
  final bool hasUnsavedChanges;

  /// Whether there's a draft available for the current section
  final bool hasDraft;

  /// Whether line breaks should be prevented (for books with links)
  final bool preventLineBreaks;

  const EditorState({
    this.isOpen = false,
    this.currentIndex,
    this.currentSectionId,
    this.currentText,
    this.hasUnsavedChanges = false,
    this.hasDraft = false,
    this.preventLineBreaks = false,
  });

  /// Creates a copy with updated values
  EditorState copyWith({
    bool? isOpen,
    int? currentIndex,
    String? currentSectionId,
    String? currentText,
    bool? hasUnsavedChanges,
    bool? hasDraft,
    bool? preventLineBreaks,
  }) {
    return EditorState(
      isOpen: isOpen ?? this.isOpen,
      currentIndex: currentIndex ?? this.currentIndex,
      currentSectionId: currentSectionId ?? this.currentSectionId,
      currentText: currentText ?? this.currentText,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      hasDraft: hasDraft ?? this.hasDraft,
      preventLineBreaks: preventLineBreaks ?? this.preventLineBreaks,
    );
  }

  @override
  List<Object?> get props => [
        isOpen,
        currentIndex,
        currentSectionId,
        currentText,
        hasUnsavedChanges,
        hasDraft,
        preventLineBreaks,
      ];
}
