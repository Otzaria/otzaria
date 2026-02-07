import '../models/text_override.dart';
import '../models/text_draft.dart';

/// Abstract repository for managing text overrides and drafts
abstract class OverridesRepository {
  /// Reads an override for the specified book and section
  Future<TextOverride?> readOverride(String bookId, String sectionId);

  /// Writes an override for the specified book and section
  Future<void> writeOverride(
      String bookId, String sectionId, String markdown, String sourceHash);

  /// Reads a draft for the specified book and section
  Future<TextDraft?> readDraft(String bookId, String sectionId);

  /// Writes a draft for the specified book and section
  Future<void> writeDraft(String bookId, String sectionId, String markdown);

  /// Deletes a draft for the specified book and section
  Future<void> deleteDraft(String bookId, String sectionId);

  /// Checks if there's a newer draft than the saved override
  Future<bool> hasNewerDraftThanOverride(String bookId, String sectionId);

  /// Checks if the specified book has a links file (commentary links)
  Future<bool> hasLinksFile(String bookId);

  /// Lists all overrides for a book
  Future<List<String>> listOverrides(String bookId);

  /// Lists all drafts for a book
  Future<List<String>> listDrafts(String bookId);

  /// Cleans up old drafts based on age and size limits
  Future<void> cleanupOldDrafts();

  /// Gets the total size of all drafts in MB
  Future<double> getTotalDraftsSizeMB();

  /// Deletes an override
  Future<void> deleteOverride(String bookId, String sectionId);
}
