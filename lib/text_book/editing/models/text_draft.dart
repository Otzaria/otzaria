import 'package:equatable/equatable.dart';

/// Represents an auto-saved draft of a text section being edited
class TextDraft extends Equatable {
  /// Book identifier
  final String bookId;

  /// Stable section identifier
  final String sectionId;

  /// Markdown content of the draft
  final String markdownContent;

  /// When this draft was created/updated
  final DateTime timestamp;

  const TextDraft({
    required this.bookId,
    required this.sectionId,
    required this.markdownContent,
    required this.timestamp,
  });

  /// Creates a draft from current editing content
  factory TextDraft.create({
    required String bookId,
    required String sectionId,
    required String markdownContent,
  }) {
    return TextDraft(
      bookId: bookId,
      sectionId: sectionId,
      markdownContent: markdownContent,
      timestamp: DateTime.now(),
    );
  }

  /// Creates a draft from file content
  factory TextDraft.fromFileContent({
    required String bookId,
    required String sectionId,
    required String fileContent,
    required DateTime fileTimestamp,
  }) {
    return TextDraft(
      bookId: bookId,
      sectionId: sectionId,
      markdownContent: fileContent,
      timestamp: fileTimestamp,
    );
  }

  /// Converts the draft to file content (plain markdown, no frontmatter for drafts)
  String toFileContent() {
    return markdownContent;
  }

  /// Creates a copy with updated values
  TextDraft copyWith({
    String? bookId,
    String? sectionId,
    String? markdownContent,
    DateTime? timestamp,
  }) {
    return TextDraft(
      bookId: bookId ?? this.bookId,
      sectionId: sectionId ?? this.sectionId,
      markdownContent: markdownContent ?? this.markdownContent,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  List<Object?> get props => [bookId, sectionId, markdownContent, timestamp];
}
