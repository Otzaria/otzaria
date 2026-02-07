import 'package:equatable/equatable.dart';

/// Represents a stable identifier for a text section that persists across content changes
class SectionIdentifier extends Equatable {
  /// Stable GUID or TOC-based identifier that doesn't change when content is modified
  final String sectionId;

  /// Current position index in the content list (may change when content is reordered)
  final int sectionIndex;

  /// Hash of normalized content for change detection and matching
  final String contentHash;

  const SectionIdentifier({
    required this.sectionId,
    required this.sectionIndex,
    required this.contentHash,
  });

  /// Creates a section identifier from content and index
  factory SectionIdentifier.fromContent({
    required String content,
    required int index,
    String? existingSectionId,
  }) {
    final normalizedContent = _normalizeContent(content);
    final contentHash = _generateHash(normalizedContent);
    final sectionId =
        existingSectionId ?? _generateSectionId(index, contentHash);

    return SectionIdentifier(
      sectionId: sectionId,
      sectionIndex: index,
      contentHash: contentHash,
    );
  }

  /// Normalizes content by removing nikud, extra spaces, and HTML tags for consistent hashing
  static String _normalizeContent(String content) {
    return content
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '') // Remove Hebrew nikud
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Generates a hash from normalized content
  static String _generateHash(String content) {
    return content.hashCode.toRadixString(16).padLeft(8, '0');
  }

  /// Public wrapper for normalizing content
  static String normalizeContent(String content) => _normalizeContent(content);

  /// Public wrapper for generating hash
  static String generateHash(String content) => _generateHash(content);

  /// Generates a stable section ID based on index and content hash
  static String _generateSectionId(int index, String contentHash) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'sec_${index}_${contentHash}_${timestamp.toRadixString(16)}';
  }

  /// Creates a copy with updated values
  SectionIdentifier copyWith({
    String? sectionId,
    int? sectionIndex,
    String? contentHash,
  }) {
    return SectionIdentifier(
      sectionId: sectionId ?? this.sectionId,
      sectionIndex: sectionIndex ?? this.sectionIndex,
      contentHash: contentHash ?? this.contentHash,
    );
  }

  @override
  List<Object?> get props => [sectionId, sectionIndex, contentHash];

  @override
  String toString() =>
      'SectionIdentifier(id: $sectionId, index: $sectionIndex, hash: $contentHash)';
}
