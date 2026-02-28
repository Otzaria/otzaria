import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';

import 'overrides_repository.dart';
import '../models/text_override.dart';
import '../models/text_draft.dart';
import '../models/editor_settings.dart';

/// Local file system implementation of OverridesRepository
class LocalOverridesRepository implements OverridesRepository {
  static const String _overridesDir = 'user_overrides';
  static const String _draftsSubdir = 'drafts';
  static const String _recoverySubdir = 'recovery';
  static const String _overrideExtension = '.md';
  static const String _draftExtension = '.tmp';

  final EditorSettings _settings;
  final Completer<String> _basePathCompleter = Completer<String>();
  late final Future<String> _basePath;

  // Mutex for file operations to prevent race conditions
  final Map<String, Completer<void>> _fileLocks = {};

  LocalOverridesRepository({EditorSettings? settings})
      : _settings = settings ?? const EditorSettings() {
    _basePath = _basePathCompleter.future;
    _initializeBasePath();
  }

  Future<void> _initializeBasePath() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final basePath = path.join(appDocDir.path, _overridesDir);
      await Directory(basePath).create(recursive: true);
      _basePathCompleter.complete(basePath);
    } catch (e) {
      _basePathCompleter.completeError(e);
    }
  }

  /// Acquires a lock for file operations on a specific file
  Future<void> _acquireFileLock(String filePath) async {
    while (_fileLocks.containsKey(filePath)) {
      await _fileLocks[filePath]!.future;
    }
    _fileLocks[filePath] = Completer<void>();
  }

  /// Releases a lock for file operations on a specific file
  void _releaseFileLock(String filePath) {
    final completer = _fileLocks.remove(filePath);
    completer?.complete();
  }

  /// Gets the directory path for a book's overrides
  Future<String> _getBookDir(String bookId) async {
    final basePath = await _basePath;
    return path.join(basePath, _sanitizeBookId(bookId));
  }

  /// Gets the directory path for a book's drafts
  Future<String> _getDraftsDir(String bookId) async {
    final bookDir = await _getBookDir(bookId);
    return path.join(bookDir, _draftsSubdir);
  }

  /// Gets the directory path for recovery files
  Future<String> _getRecoveryDir(String bookId) async {
    final bookDir = await _getBookDir(bookId);
    return path.join(bookDir, _recoverySubdir);
  }

  /// Sanitizes book ID for use as directory name
  String _sanitizeBookId(String bookId) {
    return bookId.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// Sanitizes section ID for use as filename
  String _sanitizeSectionId(String sectionId) {
    return sectionId.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// Validates that a path is within the allowed directory
  bool _isPathSafe(String filePath, String allowedBasePath) {
    final normalizedPath = path.normalize(filePath);
    final normalizedBase = path.normalize(allowedBasePath);
    return normalizedPath.startsWith(normalizedBase);
  }

  /// Performs atomic write operation (write to temp file, then rename)
  Future<void> _atomicWrite(String filePath, String content) async {
    final tempPath = '$filePath.tmp.${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Ensure directory exists
      await Directory(path.dirname(filePath)).create(recursive: true);

      // Write to temporary file
      final tempFile = File(tempPath);
      await tempFile.writeAsString(content, encoding: utf8);

      // Atomic rename
      await tempFile.rename(filePath);
    } catch (e) {
      // Clean up temp file if it exists
      try {
        await File(tempPath).delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Performs atomic write with retry and recovery
  Future<void> _atomicWriteWithRetry(
      String filePath, String content, String bookId, String sectionId) async {
    const maxRetries = 3;
    const baseDelay = Duration(milliseconds: 100);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await _atomicWrite(filePath, content);
        return;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          // Final attempt failed, save to recovery directory
          await _saveToRecovery(bookId, sectionId, content, e.toString());
          rethrow;
        }

        // Exponential backoff
        final delay =
            Duration(milliseconds: baseDelay.inMilliseconds * (1 << attempt));
        await Future.delayed(delay);
      }
    }
  }

  /// Saves content to recovery directory when normal save fails
  Future<void> _saveToRecovery(
      String bookId, String sectionId, String content, String error) async {
    try {
      final recoveryDir = await _getRecoveryDir(bookId);
      await Directory(recoveryDir).create(recursive: true);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final recoveryFile = path.join(
          recoveryDir, '${_sanitizeSectionId(sectionId)}_$timestamp.md');

      final recoveryContent =
          '''<!-- Recovery file created due to save failure -->
<!-- Error: $error -->
<!-- Original section: $sectionId -->
<!-- Timestamp: ${DateTime.now().toIso8601String()} -->

$content''';

      await File(recoveryFile).writeAsString(recoveryContent, encoding: utf8);
    } catch (_) {
      // If recovery also fails, there's not much we can do
    }
  }

  @override
  Future<TextOverride?> readOverride(String bookId, String sectionId) async {
    try {
      final bookDir = await _getBookDir(bookId);
      final filePath = path.join(
          bookDir, '${_sanitizeSectionId(sectionId)}$_overrideExtension');

      if (!_isPathSafe(filePath, await _basePath)) {
        throw ArgumentError('Invalid file path: $filePath');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString(encoding: utf8);
      return TextOverride.fromFileContent(
        bookId: bookId,
        sectionId: sectionId,
        fileContent: content,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeOverride(String bookId, String sectionId, String markdown,
      String sourceHash) async {
    final filePath = path.join(
      await _getBookDir(bookId),
      '${_sanitizeSectionId(sectionId)}$_overrideExtension',
    );

    if (!_isPathSafe(filePath, await _basePath)) {
      throw ArgumentError('Invalid file path: $filePath');
    }

    await _acquireFileLock(filePath);
    try {
      final override = TextOverride.create(
        bookId: bookId,
        sectionId: sectionId,
        markdownContent: markdown,
        sourceHash: sourceHash,
      );

      await _atomicWriteWithRetry(
          filePath, override.toFileContent(), bookId, sectionId);

      // Delete corresponding draft after successful save
      await deleteDraft(bookId, sectionId);
    } finally {
      _releaseFileLock(filePath);
    }
  }

  @override
  Future<TextDraft?> readDraft(String bookId, String sectionId) async {
    try {
      final draftsDir = await _getDraftsDir(bookId);
      final filePath = path.join(
          draftsDir, '${_sanitizeSectionId(sectionId)}$_draftExtension');

      if (!_isPathSafe(filePath, await _basePath)) {
        throw ArgumentError('Invalid file path: $filePath');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString(encoding: utf8);
      final stat = await file.stat();

      return TextDraft.fromFileContent(
        bookId: bookId,
        sectionId: sectionId,
        fileContent: content,
        fileTimestamp: stat.modified,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeDraft(
      String bookId, String sectionId, String markdown) async {
    final draftsDir = await _getDraftsDir(bookId);
    final filePath = path.join(
        draftsDir, '${_sanitizeSectionId(sectionId)}$_draftExtension');

    if (!_isPathSafe(filePath, await _basePath)) {
      throw ArgumentError('Invalid file path: $filePath');
    }

    await _acquireFileLock(filePath);
    try {
      final draft = TextDraft.create(
        bookId: bookId,
        sectionId: sectionId,
        markdownContent: markdown,
      );

      await _atomicWrite(filePath, draft.toFileContent());
    } finally {
      _releaseFileLock(filePath);
    }
  }

  @override
  Future<void> deleteDraft(String bookId, String sectionId) async {
    try {
      final draftsDir = await _getDraftsDir(bookId);
      final filePath = path.join(
          draftsDir, '${_sanitizeSectionId(sectionId)}$_draftExtension');

      if (!_isPathSafe(filePath, await _basePath)) {
        return;
      }

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore errors when deleting drafts
    }
  }

  @override
  Future<bool> hasNewerDraftThanOverride(
      String bookId, String sectionId) async {
    try {
      final draft = await readDraft(bookId, sectionId);
      if (draft == null) return false;

      final override = await readOverride(bookId, sectionId);
      if (override == null) return true;

      return draft.timestamp.isAfter(override.lastModified);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> hasLinksFile(String bookId) async {
    try {
      // Check if there's a links file for this book
      // This would typically be in the book's directory with a .links extension
      final libraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
      final bookPath = path.join(libraryPath, 'אוצריא');

      // Look for links file - this is a simplified check
      // In practice, you'd need to check the actual book structure
      final linksFile = File(path.join(bookPath, '$bookId.links'));
      return await linksFile.exists();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<String>> listOverrides(String bookId) async {
    try {
      final bookDir = Directory(await _getBookDir(bookId));
      if (!await bookDir.exists()) return [];

      final files = await bookDir
          .list()
          .where((entity) =>
              entity is File && entity.path.endsWith(_overrideExtension))
          .cast<File>()
          .toList();

      return files
          .map((file) => path.basenameWithoutExtension(file.path))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<String>> listDrafts(String bookId) async {
    try {
      final draftsDir = Directory(await _getDraftsDir(bookId));
      if (!await draftsDir.exists()) return [];

      final files = await draftsDir
          .list()
          .where((entity) =>
              entity is File && entity.path.endsWith(_draftExtension))
          .cast<File>()
          .toList();

      return files
          .map((file) => path.basenameWithoutExtension(file.path))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> cleanupOldDrafts() async {
    try {
      final basePath = await _basePath;
      final baseDir = Directory(basePath);

      if (!await baseDir.exists()) return;

      final cutoffDate =
          DateTime.now().subtract(Duration(days: _settings.draftCleanupDays));
      double totalSizeMB = 0;
      final List<FileSystemEntity> allDrafts = [];

      // Collect all draft files
      await for (final bookDir in baseDir.list(followLinks: false)) {
        if (bookDir is Directory) {
          final draftsDir = Directory(path.join(bookDir.path, _draftsSubdir));
          if (await draftsDir.exists()) {
            await for (final draftFile in draftsDir.list(followLinks: false)) {
              if (draftFile is File &&
                  draftFile.path.endsWith(_draftExtension)) {
                allDrafts.add(draftFile);
                final stat = await draftFile.stat();
                totalSizeMB += stat.size / (1024 * 1024);
              }
            }
          }
        }
      }

      // Sort by modification time (oldest first)
      allDrafts.sort((a, b) {
        final aStat = File(a.path).statSync();
        final bStat = File(b.path).statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      // Delete old drafts and enforce quota
      for (final draft in allDrafts) {
        final file = File(draft.path);
        final stat = await file.stat();
        final shouldDelete = stat.modified.isBefore(cutoffDate) ||
            totalSizeMB > _settings.globalDraftsQuotaMB;

        if (shouldDelete) {
          try {
            await file.delete();
            totalSizeMB -= stat.size / (1024 * 1024);
          } catch (e) {
            // Continue with other files if one fails
          }
        }
      }
    } catch (e) {
      // Cleanup is best-effort, don't throw errors
    }
  }

  @override
  Future<double> getTotalDraftsSizeMB() async {
    try {
      final basePath = await _basePath;
      final baseDir = Directory(basePath);

      if (!await baseDir.exists()) return 0.0;

      double totalSizeMB = 0;

      await for (final bookDir in baseDir.list(followLinks: false)) {
        if (bookDir is Directory) {
          final draftsDir = Directory(path.join(bookDir.path, _draftsSubdir));
          if (await draftsDir.exists()) {
            await for (final draftFile in draftsDir.list(followLinks: false)) {
              if (draftFile is File &&
                  draftFile.path.endsWith(_draftExtension)) {
                final stat = await draftFile.stat();
                totalSizeMB += stat.size / (1024 * 1024);
              }
            }
          }
        }
      }

      return totalSizeMB;
    } catch (e) {
      return 0.0;
    }
  }

  @override
  Future<void> deleteOverride(String bookId, String sectionId) async {
    try {
      final bookDir = await _getBookDir(bookId);
      final filePath = path.join(
          bookDir, '${_sanitizeSectionId(sectionId)}$_overrideExtension');

      if (!_isPathSafe(filePath, await _basePath)) {
        return;
      }

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore errors when deleting overrides
    }
  }
}
