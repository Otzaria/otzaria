import 'dart:io';

import 'package:logging/logging.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_storage.dart';

/// Migrates personal notes from the old file-based storage (TXT + JSON)
/// to the new SQLite database.
class FileToDbMigrator {
  static final Logger _logger = Logger('FileToDbMigrator');

  /// Run migration from file storage to SQLite database.
  /// This should be called once during app initialization.
  ///
  /// - Migrates notes that don't exist in the database (by ID)
  /// - Deletes old file storage after successful migration
  static Future<void> runMigration() async {
    try {
      final migrator = FileToDbMigrator();
      final summary = await migrator.migrate();

      if (summary.hasMigratedNotes) {
        _logger.info('Personal notes migration: ${summary.summaryText}');
      }

      // Only cleanup old files if ALL notes were migrated successfully
      // If any book failed, keep the old files to prevent data loss
      if (summary.success && !summary.hasFailures) {
        await migrator.cleanupOldFiles();
      } else if (summary.hasFailures) {
        _logger.warning(
            'Keeping old note files because ${summary.failedBooks.length} books failed to migrate: '
            '${summary.failedBooks.keys.join(", ")}');
      }
    } catch (e, s) {
      _logger.severe('Personal notes migration failed', e, s);
    }
  }

  final PersonalNotesStorage _fileStorage;
  final PersonalNotesDatabase _database;

  FileToDbMigrator({
    PersonalNotesStorage? fileStorage,
    PersonalNotesDatabase? database,
  })  : _fileStorage = fileStorage ?? PersonalNotesStorage.instance,
        _database = database ?? PersonalNotesDatabase.instance;

  /// Migrate all notes from file storage to database.
  /// Returns a summary of the migration.
  ///
  /// Uses batch insert for better performance.
  /// Notes with duplicate IDs are automatically skipped.
  Future<MigrationSummary> migrate() async {
    final summary = MigrationSummary();

    try {
      // Get all books that have notes in file storage
      final storedBooks = await _fileStorage.listStoredBooks();

      if (storedBooks.isEmpty) {
        summary.success = true;
        return summary;
      }

      summary.totalBooks = storedBooks.length;

      for (final bookInfo in storedBooks) {
        try {
          // Read notes from file storage
          final notes = await _fileStorage.readNotes(bookInfo.bookId);

          if (notes.isEmpty) {
            continue;
          }

          // Use batch insert - duplicates are automatically skipped
          final insertedCount = await _database.batchInsertNotes(notes);

          if (insertedCount > 0) {
            summary.migratedBooks.add(bookInfo.bookId);
            summary.migratedNotesCount += insertedCount;
          }
        } catch (e) {
          summary.failedBooks[bookInfo.bookId] = e.toString();
        }
      }

      summary.success = true;
    } catch (e) {
      summary.success = false;
      summary.error = e.toString();
    }

    return summary;
  }

  /// Delete old file storage after successful migration.
  /// WARNING: This will permanently delete the TXT and JSON files!
  Future<void> cleanupOldFiles() async {
    try {
      final dirPath = await _fileStorage.notesDirectoryPath();
      final dir = Directory(dirPath);

      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, s) {
      _logger.warning('Failed to cleanup old note files', e, s);
      // Continue anyway - cleanup failure is not critical
    }
  }
}

/// Summary of the migration process
class MigrationSummary {
  bool success = false;
  String? error;
  int totalBooks = 0;
  int migratedNotesCount = 0;
  List<String> migratedBooks = [];
  Map<String, String> failedBooks = {};

  bool get hasFailures => failedBooks.isNotEmpty;

  /// Returns true if any notes were migrated
  bool get hasMigratedNotes => migratedNotesCount > 0;

  String get summaryText {
    if (!success && error != null) {
      return 'Migration failed: $error';
    }

    final parts = <String>[];

    if (migratedNotesCount > 0) {
      parts.add(
          'Migrated $migratedNotesCount notes from ${migratedBooks.length} books');
    }

    if (failedBooks.isNotEmpty) {
      parts.add('Failed to migrate ${failedBooks.length} books');
    }

    if (parts.isEmpty) {
      return 'No notes to migrate';
    }

    return parts.join('. ');
  }
}
