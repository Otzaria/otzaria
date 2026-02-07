import 'package:equatable/equatable.dart';

/// Represents a user's local override of a text section
class TextOverride extends Equatable {
  /// Book identifier
  final String bookId;

  /// Stable section identifier
  final String sectionId;

  /// Markdown content of the override
  final String markdownContent;

  /// When this override was last modified
  final DateTime lastModified;

  /// Hash of the original source content when this override was created
  final String sourceHashOnOpen;

  /// Application schema version for migration purposes
  final String appSchemaVersion;

  /// Original content for reference (optional)
  final String? originalContent;

  const TextOverride({
    required this.bookId,
    required this.sectionId,
    required this.markdownContent,
    required this.lastModified,
    required this.sourceHashOnOpen,
    required this.appSchemaVersion,
    this.originalContent,
  });

  /// Creates an override from markdown content and metadata
  factory TextOverride.create({
    required String bookId,
    required String sectionId,
    required String markdownContent,
    required String sourceHash,
    String? originalContent,
  }) {
    return TextOverride(
      bookId: bookId,
      sectionId: sectionId,
      markdownContent: markdownContent,
      lastModified: DateTime.now(),
      sourceHashOnOpen: sourceHash,
      appSchemaVersion: '1.0',
      originalContent: originalContent,
    );
  }

  /// Creates an override from file content with frontmatter
  factory TextOverride.fromFileContent({
    required String bookId,
    required String sectionId,
    required String fileContent,
  }) {
    final parts = fileContent.split('---');
    if (parts.length < 3) {
      // No frontmatter, treat entire content as markdown
      return TextOverride.create(
        bookId: bookId,
        sectionId: sectionId,
        markdownContent: fileContent,
        sourceHash: '',
      );
    }

    // Parse frontmatter
    final frontmatter = parts[1];
    final markdownContent = parts.sublist(2).join('---');

    String sourceHash = '';
    String appSchemaVersion = '1.0';
    DateTime lastModified = DateTime.now();

    for (final line in frontmatter.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('sourceHashOnOpen:')) {
        sourceHash = trimmed.split(':')[1].trim().replaceAll('"', '');
      } else if (trimmed.startsWith('appSchemaVersion:')) {
        appSchemaVersion = trimmed.split(':')[1].trim().replaceAll('"', '');
      } else if (trimmed.startsWith('lastModified:')) {
        final dateStr = trimmed.split(':')[1].trim().replaceAll('"', '');
        lastModified = DateTime.tryParse(dateStr) ?? DateTime.now();
      }
    }

    return TextOverride(
      bookId: bookId,
      sectionId: sectionId,
      markdownContent: markdownContent,
      lastModified: lastModified,
      sourceHashOnOpen: sourceHash,
      appSchemaVersion: appSchemaVersion,
    );
  }

  /// Converts the override to file content with frontmatter
  String toFileContent() {
    final frontmatter = '''---
sourceHashOnOpen: "$sourceHashOnOpen"
appSchemaVersion: "$appSchemaVersion"
lastModified: "${lastModified.toIso8601String()}"
---''';

    return '$frontmatter\n$markdownContent';
  }

  /// Creates a copy with updated values
  TextOverride copyWith({
    String? bookId,
    String? sectionId,
    String? markdownContent,
    DateTime? lastModified,
    String? sourceHashOnOpen,
    String? appSchemaVersion,
    String? originalContent,
  }) {
    return TextOverride(
      bookId: bookId ?? this.bookId,
      sectionId: sectionId ?? this.sectionId,
      markdownContent: markdownContent ?? this.markdownContent,
      lastModified: lastModified ?? this.lastModified,
      sourceHashOnOpen: sourceHashOnOpen ?? this.sourceHashOnOpen,
      appSchemaVersion: appSchemaVersion ?? this.appSchemaVersion,
      originalContent: originalContent ?? this.originalContent,
    );
  }

  @override
  List<Object?> get props => [
        bookId,
        sectionId,
        markdownContent,
        lastModified,
        sourceHashOnOpen,
        appSchemaVersion,
        originalContent,
      ];
}
