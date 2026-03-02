import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for backing up and restoring app data
class BackupService {
  static final Logger _logger = Logger('BackupService');
  static const String backupFolderName = 'backups';

  /// Get the backup directory path
  static Future<String> getBackupDirectory() async {
    final libraryPath = await AppPaths.getLibraryPath();
    final backupPath = p.join(libraryPath, backupFolderName);
    final dir = Directory(backupPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return backupPath;
  }

  /// Create a backup with specified options
  static Future<String> createBackup({
    required bool includeSettings,
    required bool includeBookmarks,
    required bool includeHistory,
    required bool includeNotes,
    required bool includeWorkspaces,
    required bool includeShamorZachor,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupDir = await getBackupDirectory();
      final backupFileName = 'otzaria_backup_$timestamp.json';
      final backupPath = p.join(backupDir, backupFileName);

      _logger.info('Creating backup at: $backupPath');
      _logger.info('Backup directory: $backupDir');

      final backupData = <String, dynamic>{
        'version': '1.0',
        'timestamp': timestamp,
        'includes': {
          'settings': includeSettings,
          'bookmarks': includeBookmarks,
          'history': includeHistory,
          'notes': includeNotes,
          'workspaces': includeWorkspaces,
          'shamorZachor': includeShamorZachor,
        },
      };

      // Backup settings
      if (includeSettings) {
        backupData['settings'] = await _backupSettings();
      }

      // Backup bookmarks
      if (includeBookmarks) {
        backupData['bookmarks'] = await _backupBookmarks();
      }

      // Backup history
      if (includeHistory) {
        backupData['history'] = await _backupHistory();
      }

      // Backup notes
      if (includeNotes) {
        backupData['notes'] = await _backupNotes();
      }

      // Backup workspaces
      if (includeWorkspaces) {
        final workspacesData = await _backupWorkspaces();
        backupData['workspaces'] = workspacesData['workspaces'];
        backupData['currentWorkspace'] = workspacesData['currentWorkspace'];
      }

      // Backup Shamor Zachor
      if (includeShamorZachor) {
        backupData['shamorZachor'] = await _backupShamorZachor();
      }

      // Write backup file
      final file = File(backupPath);
      _logger.info('Writing backup data (${backupData.length} keys)...');

      final jsonString = json.encode(backupData);
      _logger.info('JSON size: ${jsonString.length} characters');

      await file.writeAsString(jsonString);
      _logger.info('Backup file written successfully');

      // Verify file was created
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      _logger.info('File exists: $exists, Size: $size bytes');

      return backupPath;
    } catch (e, stackTrace) {
      _logger.severe('Error creating backup: $e');
      _logger.severe('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Backup all settings
  static Future<Map<String, dynamic>> _backupSettings() async {
    final settingsKeys = [
      SettingsRepository.keyDarkMode,
      SettingsRepository.keySwatchColor,
      SettingsRepository.keyFontSize,
      SettingsRepository.keyFontFamily,
      SettingsRepository.keyShowOtzarHachochma,
      SettingsRepository.keyShowHebrewBooks,
      SettingsRepository.keyShowExternalBooks,
      SettingsRepository.keyShowTeamim,
      SettingsRepository.keyUseFastSearch,
      SettingsRepository.keyReplaceHolyNames,
      SettingsRepository.keyAutoUpdateIndex,
      SettingsRepository.keyDefaultNikud,
      SettingsRepository.keyRemoveNikudFromTanach,
      SettingsRepository.keyDefaultSidebarOpen,
      SettingsRepository.keyPinSidebar,
      SettingsRepository.keySidebarWidth,
      SettingsRepository.keyFacetFilteringWidth,
      SettingsRepository.keyCalendarType,
      SettingsRepository.keySelectedCity,
      SettingsRepository.keyCalendarEvents,
      SettingsRepository.keyCopyWithHeaders,
      SettingsRepository.keyCopyHeaderFormat,
      SettingsRepository.keyLibraryPath,
      SettingsRepository.keyHebrewBooksPath,
      SettingsRepository.keyDevChannel,
      SettingsRepository.keyAutoSync,
      SettingsRepository.keyOfflineMode,
      SettingsRepository.keyPersonalNotesCollapsedByDefault,
    ];

    final settings = <String, dynamic>{};
    for (final key in settingsKeys) {
      final value = Settings.getValue(key);
      if (value != null) {
        settings[key] = value;
      }
    }
    return settings;
  }

  /// Backup bookmarks
  static Future<List<Map<String, dynamic>>> _backupBookmarks() async {
    final repo = BookmarkRepository();
    final bookmarks = await repo.loadBookmarks();
    return bookmarks.map((b) => b.toJson()).toList();
  }

  /// Backup history
  static Future<List<Map<String, dynamic>>> _backupHistory() async {
    final repo = HistoryRepository();
    final history = await repo.loadHistory();
    return history.map((h) => h.toJson()).toList();
  }

  /// Backup notes from SQLite database
  static Future<List<Map<String, dynamic>>> _backupNotes() async {
    final database = PersonalNotesDatabase.instance;
    final booksWithNotes = await database.listBooksWithNotes();

    final List<Map<String, dynamic>> result = [];

    for (final bookInfo in booksWithNotes) {
      try {
        final notes = await database.loadNotes(bookInfo.bookId);
        if (notes.isEmpty) continue;

        result.add({
          'bookId': bookInfo.bookId,
          'notes': notes.map((note) => _noteToBackupJson(note)).toList(),
        });
      } catch (e) {
        _logger.warning(
            'Skipping notes for book ${bookInfo.bookId} due to error: $e');
      }
    }

    return result;
  }

  /// Convert PersonalNote to backup JSON format
  static Map<String, dynamic> _noteToBackupJson(PersonalNote note) {
    return {
      'id': note.id,
      'bookId': note.bookId,
      'lineNumber': note.lineNumber,
      'displayTitle': note.displayTitle,
      'lastKnownLineNumber': note.lastKnownLineNumber,
      'status': note.status.name,
      'content': note.content,
      'contentPlain': note.contentPlain,
      'contentFormat': note.contentFormat.name,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    };
  }

  /// Backup workspaces
  static Future<Map<String, dynamic>> _backupWorkspaces() async {
    final repo = WorkspaceRepository();
    final (workspaces, currentWorkspace) = repo.loadWorkspaces();
    return {
      'workspaces': workspaces.map((w) => w.toJson()).toList(),
      'currentWorkspace': currentWorkspace,
    };
  }

  /// Backup Shamor Zachor data - backs up ALL keys starting with 'sz:'
  static Future<Map<String, dynamic>> _backupShamorZachor() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final shamorZachorData = <String, dynamic>{};

    // Backup all keys that start with 'sz:' prefix
    for (final key in allKeys) {
      if (key.startsWith('sz:')) {
        final value = prefs.get(key);
        if (value != null) {
          shamorZachorData[key] = value;
        }
      }
    }

    return shamorZachorData;
  }

  /// Restore from backup file
  static Future<void> restoreFromBackup(String backupPath) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('קובץ הגיבוי לא נמצא');
    }

    final content = await file.readAsString();
    final backupData = json.decode(content) as Map<String, dynamic>;

    // Validate backup version
    final version = backupData['version'] as String?;
    if (version != '1.0') {
      throw Exception('גרסת גיבוי לא נתמכת');
    }

    final includes = backupData['includes'] as Map<String, dynamic>;

    // Restore settings
    if (includes['settings'] == true && backupData.containsKey('settings')) {
      await _restoreSettings(backupData['settings'] as Map<String, dynamic>);
    }

    // Restore bookmarks
    if ((includes['bookmarks'] == true ||
            includes['bookmarksAndHistory'] == true) &&
        backupData.containsKey('bookmarks')) {
      await _restoreBookmarks(
        (backupData['bookmarks'] as List).cast<Map<String, dynamic>>(),
      );
    }

    // Restore history
    if ((includes['history'] == true ||
            includes['bookmarksAndHistory'] == true) &&
        backupData.containsKey('history')) {
      await _restoreHistory(
        (backupData['history'] as List).cast<Map<String, dynamic>>(),
      );
    }

    // Restore notes
    if (includes['notes'] == true && backupData.containsKey('notes')) {
      await _restoreNotes(
        (backupData['notes'] as List).cast<Map<String, dynamic>>(),
      );
    }

    // Restore workspaces
    if (includes['workspaces'] == true &&
        backupData.containsKey('workspaces')) {
      await _restoreWorkspaces(
        (backupData['workspaces'] as List).cast<Map<String, dynamic>>(),
        backupData['currentWorkspace'] as int? ?? 0,
      );
    }

    // Restore Shamor Zachor
    if (includes['shamorZachor'] == true &&
        backupData.containsKey('shamorZachor')) {
      await _restoreShamorZachor(
        backupData['shamorZachor'] as Map<String, dynamic>,
      );
    }
  }

  /// Restore settings
  static Future<void> _restoreSettings(Map<String, dynamic> settings) async {
    for (final entry in settings.entries) {
      await Settings.setValue(entry.key, entry.value);
    }
  }

  /// Restore bookmarks
  static Future<void> _restoreBookmarks(
    List<Map<String, dynamic>> bookmarksData,
  ) async {
    final repo = BookmarkRepository();
    final bookmarks =
        bookmarksData.map((data) => Bookmark.fromJson(data)).toList();
    await repo.saveBookmarks(bookmarks);
  }

  /// Restore history
  static Future<void> _restoreHistory(
    List<Map<String, dynamic>> historyData,
  ) async {
    final repo = HistoryRepository();
    final history = historyData.map((data) => Bookmark.fromJson(data)).toList();
    await repo.saveHistory(history);
  }

  /// Restore notes to SQLite database
  static Future<void> _restoreNotes(
    List<Map<String, dynamic>> notesData,
  ) async {
    final database = PersonalNotesDatabase.instance;

    for (final entry in notesData) {
      try {
        final bookId = (entry['bookId'] as String?)?.trim();
        if (bookId == null || bookId.isEmpty) {
          continue;
        }

        // Handle new format (SQLite backup)
        if (entry.containsKey('notes')) {
          final notesList = entry['notes'] as List<dynamic>;
          for (final noteData in notesList) {
            try {
              final note =
                  _noteFromBackupJson(noteData as Map<String, dynamic>);
              await database.insertNote(note);
            } catch (e) {
              _logger.warning('Failed to restore single note from backup: $e');
            }
          }
        }
        // Handle legacy format (file-based backup) for backward compatibility
        else if (entry.containsKey('annotations')) {
          await _restoreLegacyNotes(entry, database);
        }
      } catch (e) {
        _logger.warning('Failed to restore note entry: $e');
      }
    }
  }

  /// Convert backup JSON to PersonalNote
  static PersonalNote _noteFromBackupJson(Map<String, dynamic> json) {
    return PersonalNote(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      lineNumber: json['lineNumber'] as int?,
      displayTitle: json['displayTitle'] as String?,
      lastKnownLineNumber: json['lastKnownLineNumber'] as int?,
      status: PersonalNoteStatus.values.byName(json['status'] as String),
      content: json['content'] as String,
      contentPlain:
          (json['contentPlain'] as String?) ?? (json['content'] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
        json['contentFormat'] as String? ??
            PersonalNoteContentFormat.plain.name,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Restore notes from legacy file-based backup format
  static Future<void> _restoreLegacyNotes(
    Map<String, dynamic> entry,
    PersonalNotesDatabase database,
  ) async {
    final bookId = entry['bookId'] as String;
    final annotations = entry['annotations'] as Map<String, dynamic>;
    final notesList = annotations['notes'] as List<dynamic>? ?? [];

    // Parse the text file content to extract note contents
    final textContent = entry['text'] as String? ?? '';
    final noteContents = _parseLegacyNoteContents(textContent);

    for (final noteData in notesList) {
      try {
        final map = noteData as Map<String, dynamic>;
        final noteId = map['id'] as String;

        // Get content from parsed text file, or empty string if not found
        final content = noteContents[noteId] ?? '';

        final note = PersonalNote(
          id: noteId,
          bookId: bookId,
          lineNumber: map['line'] as int?,
          displayTitle: map['display_title'] as String?,
          lastKnownLineNumber: map['last_known_line'] as int?,
          status: PersonalNoteStatus.values.byName(map['status'] as String),
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
          createdAt: DateTime.parse(map['created_at'] as String),
          updatedAt: DateTime.parse(map['updated_at'] as String),
        );

        await database.insertNote(note);
      } catch (e) {
        _logger.warning('Failed to restore legacy note: $e');
      }
    }
  }

  /// Parse legacy TXT file format to extract note contents by ID
  static Map<String, String> _parseLegacyNoteContents(String textContent) {
    final contents = <String, String>{};
    if (textContent.isEmpty) return contents;

    const noteHeaderPrefix = '### NOTE ';
    const noteFooter = '### END NOTE';

    final lines = textContent.split('\n');
    var index = 0;

    while (index < lines.length) {
      final line = lines[index];
      if (line.startsWith(noteHeaderPrefix)) {
        final id = line.substring(noteHeaderPrefix.length).trim();
        index++;
        final buffer = StringBuffer();

        while (index < lines.length && lines[index] != noteFooter) {
          buffer.writeln(lines[index]);
          index++;
        }

        contents[id] = buffer.toString().trimRight();

        if (index < lines.length && lines[index] == noteFooter) {
          index++;
        }
        // Skip blank separator line
        if (index < lines.length && lines[index].trim().isEmpty) {
          index++;
        }
      } else {
        index++;
      }
    }

    return contents;
  }

  /// Restore workspaces
  static Future<void> _restoreWorkspaces(
    List<Map<String, dynamic>> workspacesData,
    int currentWorkspace,
  ) async {
    final repo = WorkspaceRepository();
    final workspaces =
        workspacesData.map((data) => Workspace.fromJson(data)).toList();
    // Get the workspace ID from the index, or use the first workspace's ID
    final currentId =
        (currentWorkspace >= 0 && currentWorkspace < workspaces.length)
            ? workspaces[currentWorkspace].id
            : (workspaces.isNotEmpty ? workspaces.first.id : null);
    repo.saveWorkspaces(workspaces, currentId);
  }

  /// Restore Shamor Zachor data - restores ALL backed up keys
  static Future<void> _restoreShamorZachor(
    Map<String, dynamic> shamorZachorData,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Restore all backed up keys
    for (final entry in shamorZachorData.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value == null) continue;

      // Set the value based on its type
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }
  }

  /// Check if automatic backup is needed
  static Future<bool> shouldPerformAutoBackup() async {
    final frequency =
        Settings.getValue<String>('key-auto-backup-frequency') ?? 'none';
    if (frequency == 'none') return false;

    final lastBackup = Settings.getValue<String>('key-last-auto-backup');
    if (lastBackup == null) return true;

    final lastBackupDate = DateTime.parse(lastBackup);
    final now = DateTime.now();

    switch (frequency) {
      case 'weekly':
        return now.difference(lastBackupDate).inDays >= 7;
      case 'monthly':
        return now.difference(lastBackupDate).inDays >= 30;
      default:
        return false;
    }
  }

  /// Perform automatic backup
  static Future<void> performAutoBackup() async {
    final includeSettings =
        Settings.getValue<bool>('key-backup-settings') ?? true;
    final includeBookmarks =
        Settings.getValue<bool>('key-backup-bookmarks') ?? true;
    final includeHistory =
        Settings.getValue<bool>('key-backup-history') ?? true;
    final includeNotes = Settings.getValue<bool>('key-backup-notes') ?? true;
    final includeWorkspaces =
        Settings.getValue<bool>('key-backup-workspaces') ?? true;
    final includeShamorZachor =
        Settings.getValue<bool>('key-backup-shamor-zachor') ?? true;

    await createBackup(
      includeSettings: includeSettings,
      includeBookmarks: includeBookmarks,
      includeHistory: includeHistory,
      includeNotes: includeNotes,
      includeWorkspaces: includeWorkspaces,
      includeShamorZachor: includeShamorZachor,
    );

    await Settings.setValue(
        'key-last-auto-backup', DateTime.now().toIso8601String());
  }

  /// Get list of available backups
  static Future<List<FileSystemEntity>> getAvailableBackups() async {
    final backupDir = await getBackupDirectory();
    final dir = Directory(backupDir);
    if (!await dir.exists()) return [];

    final files = await dir.list().toList();
    return files.where((f) => f is File && f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // Sort by date (newest first)
  }
}
