import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';

class FileSyncRepository {
  final String githubOwner;
  final String repositoryName;
  final String branch;
  bool isSyncing = false;
  int _currentProgress = 0;
  int _totalFiles = 0;

  FileSyncRepository({
    required this.githubOwner,
    required this.repositoryName,
    this.branch = 'main',
  });

  int get currentProgress => _currentProgress;
  int get totalFiles => _totalFiles;

  Future<String> get _localManifestPath async {
    return await AppPaths.getManifestPath();
  }

  Future<String> get _localDirectory async {
    return await AppPaths.getLibraryPath();
  }

  /// Normalizes file paths from the manifest to local paths.
  ///
  /// The manifest contains full paths from the GitHub repository structure,
  /// but we need to extract only the relevant local path.
  ///
  /// Handles three cases:
  /// 1. Paths containing 'אוצריא/' - extracts from 'אוצריא/' onwards
  ///    Example: 'otzaria-library/sefariaToOtzaria/sefaria_export/ספרים/אוצריא/תנך/תורה/בראשית.txt'
  ///    Returns: 'אוצריא/תנך/תורה/בראשית.txt'
  ///
  /// 2. Paths containing 'links/' - extracts from 'links/' onwards
  ///    Example: 'otzaria-library/sefariaToOtzaria/sefaria_export/links/בראשית_links.json'
  ///    Returns: 'links/בראשית_links.json'
  ///
  /// 3. Root files (metadata.json, files_manifest.json, etc.) - returns as-is
  ///    Example: 'metadata.json'
  ///    Returns: 'metadata.json'
  String _normalizeFilePath(String manifestPath) {
    // Case 1: Files in אוצריא directory
    const ozariaDir = 'אוצריא/';
    final ozariaIndex = manifestPath.indexOf(ozariaDir);
    if (ozariaIndex != -1) {
      return manifestPath.substring(ozariaIndex);
    }

    // Case 2: Link files
    const linksDir = 'links/';
    final linksIndex = manifestPath.indexOf(linksDir);
    if (linksIndex != -1) {
      return manifestPath.substring(linksIndex);
    }

    // Case 3: Root files (metadata.json, etc.)
    // Return as-is if no special directory found
    return manifestPath;
  }

  Future<Map<String, dynamic>> _getLocalManifest() async {
    final path = await _localManifestPath;
    final file = File(path);
    try {
      if (!await file.exists()) {
        // ---- תוספת חשובה ---- //
        // אם הקובץ הראשי לא קיים, בדוק אם נשאר גיבוי מתהליך שנכשל
        final oldFile = File('$path.old');
        if (await oldFile.exists()) {
          developer.log('Main manifest missing, restoring from .old backup...',
              name: 'FileSyncRepository');
          await oldFile.rename(path); // שחזר את הגיבוי
          // עכשיו הקובץ הראשי קיים, נמשיך כרגיל
        } else {
          return {}; // אם גם גיבוי אין, באמת אין מניפסט
        }
      }
      final content = await file.readAsString(encoding: utf8);
      return json.decode(content);
    } catch (e) {
      developer.log('Error reading local manifest',
          name: 'FileSyncRepository', error: e);
      // הלוגיקה שלך לגיבוי מ-.bak הייתה טובה, נתאים אותה ל-.old
      final oldFile = File('$path.old'); // השתמש ב-.old במקום .bak
      if (await oldFile.exists()) {
        try {
          developer.log(
              'Main manifest is corrupt, restoring from .old backup...',
              name: 'FileSyncRepository',
              error: e);
          final backupContent = await oldFile.readAsString(encoding: utf8);
          await oldFile.rename(path); // rename בטוח יותר מ-copy
          return json.decode(backupContent);
        } catch (_) {}
      }
      return {};
    }
  }

  Future<Map<String, dynamic>> _getRemoteManifest() async {
    // Using files_manifest.json which contains full paths from source directories
    // This allows direct file access without the need for merged folders
    // The _normalizeFilePath function extracts the correct local path from these full paths
    final url =
        'https://raw.githubusercontent.com/$githubOwner/$repositoryName/$branch/files_manifest.json';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Accept-Charset': 'utf-8',
        },
      );
      if (response.statusCode == 200) {
        // Explicitly decode as UTF-8
        return json.decode(utf8.decode(response.bodyBytes));
      }
      throw Exception('Failed to fetch remote manifest');
    } catch (e) {
      developer.log('Error fetching remote manifest',
          name: 'FileSyncRepository', error: e);
      rethrow;
    }
  }

  /// Downloads a file using streaming for large files to prevent memory issues
  /// and timeouts on slow networks.
  Future<void> downloadFile(String filePath) async {
    final url =
        'https://raw.githubusercontent.com/$githubOwner/$repositoryName/$branch/$filePath';

    final directory = await _localDirectory;
    final localFilePath = _normalizeFilePath(filePath);
    final file = File('$directory/$localFilePath');
    final tempFile = File('$directory/$localFilePath.tmp');

    try {
      // Create directories if they don't exist
      await tempFile.parent.create(recursive: true);

      // Use streaming download for better handling of large files
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers['Accept-Charset'] = 'utf-8';

        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 90),
          onTimeout: () {
            throw Exception('Connection timeout for $filePath');
          },
        );

        if (streamedResponse.statusCode != 200) {
          throw Exception('HTTP ${streamedResponse.statusCode} for $filePath');
        }

        // Get content length for progress tracking (may be null)
        final contentLength = streamedResponse.contentLength;

        // Stream directly to file - handles large files without memory issues
        final sink = tempFile.openWrite();
        int downloadedBytes = 0;

        try {
          await for (final chunk in streamedResponse.stream) {
            // Check if sync was cancelled
            if (!isSyncing) {
              await sink.close();
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
              throw Exception('Download cancelled for $filePath');
            }

            sink.add(chunk);
            downloadedBytes += chunk.length;

            // Log progress for large files (every 5MB)
            if (contentLength != null &&
                contentLength > 10 * 1024 * 1024 &&
                downloadedBytes % (5 * 1024 * 1024) < chunk.length) {
              final percent =
                  (downloadedBytes / contentLength * 100).toStringAsFixed(1);
              developer.log(
                'Downloading $filePath: $percent% (${(downloadedBytes / 1024 / 1024).toStringAsFixed(1)}MB)',
                name: 'FileSyncRepository',
              );
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        // Verify the temp file was written successfully
        if (!await tempFile.exists()) {
          throw Exception('Failed to write temporary file: $filePath');
        }

        final tempFileSize = await tempFile.length();
        if (tempFileSize == 0) {
          throw Exception('Downloaded file is empty: $filePath');
        }

        // For text files, convert encoding if needed
        if (filePath.endsWith('.txt') ||
            filePath.endsWith('.json') ||
            filePath.endsWith('.csv')) {
          // Read and re-write with proper UTF-8 encoding
          final bytes = await tempFile.readAsBytes();
          await tempFile.writeAsString(utf8.decode(bytes), encoding: utf8);
        }

        // Only now replace the original file (if exists)
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);

        developer.log(
          'Successfully downloaded: $filePath ($downloadedBytes bytes)',
          name: 'FileSyncRepository',
        );
      } finally {
        client.close();
      }
    } catch (e) {
      developer.log('Error downloading file $filePath',
          name: 'FileSyncRepository', error: e);
      // Clean up temp file if it exists
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _writeManifest(Map<String, dynamic> manifest) async {
    final path = await _localManifestPath;
    final file = File(path);
    final tempFile = File('$path.tmp');
    // נשתמש ב- .old כפי שהוצע, זה עקבי וברור
    final oldFile = File('$path.old');

    try {
      // 1. כותבים את המידע החדש לקובץ זמני.
      // אם שלב זה נכשל, שום דבר לא קרה לקובץ המקורי.
      await tempFile.writeAsString(
        json.encode(manifest),
        encoding: utf8,
      );

      // 2. אם הקובץ המקורי קיים, שנה את שמו לגיבוי.
      // זו פעולה אטומית ומהירה. אם היא נכשלת, לא קרה כלום.
      // אם היא מצליחה, המניפסט הישן בטוח בצד.
      if (await file.exists()) {
        await file.rename(oldFile.path);
      }

      // 3. שנה את שם הקובץ הזמני לשם הקובץ הסופי.
      // גם זו פעולה אטומית. אם היא נכשלת, המניפסט הישן עדיין קיים ב- .old
      // וניתן לשחזר אותו.
      await tempFile.rename(path);

      // 4. אם הגענו לכאן, הכל הצליח. אפשר למחוק בבטחה את הגיבוי.
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    } catch (e) {
      developer.log('Error writing manifest',
          name: 'FileSyncRepository', error: e);
      // במקרה של תקלה (למשל, אחרי ש-file.rename הצליח אבל tempFile.rename נכשל),
      // ננסה לשחזר את המצב לקדמותו כדי למנוע מצב ללא מניפסט.
      try {
        if (await oldFile.exists() && !(await file.exists())) {
          developer.log('Attempting to restore manifest from .old backup...',
              name: 'FileSyncRepository');
          await oldFile.rename(path);
        }
      } catch (restoreError) {
        developer.log('FATAL: Could not restore manifest from backup',
            name: 'FileSyncRepository', error: restoreError);
      }
      rethrow; // זרוק את השגיאה המקורית כדי שהפונקציה שקראה תדע שהעדכון נכשל.
    }
  }

  Future<void> _updateLocalManifestForFile(
      String filePath, Map<String, dynamic> fileInfo) async {
    try {
      Map<String, dynamic> localManifest = await _getLocalManifest();

      // Update the manifest for this specific file
      localManifest[filePath] = fileInfo;

      await _writeManifest(localManifest);
    } catch (e) {
      developer.log('Error updating local manifest for file $filePath',
          name: 'FileSyncRepository', error: e);
    }
  }

  Future<void> _removeFromLocal(String filePath) async {
    try {
      // Try to remove the actual file if it exists
      final directory = await _localDirectory;
      // Normalize the file path to get the local path
      final localFilePath = _normalizeFilePath(filePath);
      final file = File('$directory/$localFilePath');
      if (await file.exists()) {
        await file.delete();
      }

      //if successful, remove from manifest
      Map<String, dynamic> localManifest = await _getLocalManifest();

      // Remove the file from the manifest
      localManifest.remove(filePath);

      await _writeManifest(localManifest);
    } catch (e) {
      developer.log('Error removing file $filePath from local manifest',
          name: 'FileSyncRepository', error: e);
    }
  }

  Future<void> removeEmptyFolders() async {
    try {
      final baseDir = Directory(await _localDirectory);
      if (!await baseDir.exists()) return;

      // Bottom-up approach: process deeper directories first
      await _cleanEmptyDirectories(baseDir);
    } catch (e) {
      developer.log('Error removing empty folders',
          name: 'FileSyncRepository', error: e);
    }
  }

  Future<void> _cleanEmptyDirectories(Directory dir) async {
    if (!await dir.exists()) return;

    // First process all subdirectories
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        await _cleanEmptyDirectories(entity);
      }
    }

    // After cleaning subdirectories, check if this directory is now empty
    final contents = await dir.list().toList();
    final baseDir = await _localDirectory;
    if (contents.isEmpty && dir.path != baseDir) {
      await dir.delete();
      developer.log('Removed empty directory: ${dir.path}',
          name: 'FileSyncRepository');
    }
  }

  Future<List<String>> checkForUpdates() async {
    final localManifest = await _getLocalManifest();
    final remoteManifest = await _getRemoteManifest();

    final filesToUpdate = <String>[];

    remoteManifest.forEach((filePath, remoteInfo) {
      if (!localManifest.containsKey(filePath) ||
          localManifest[filePath]['hash'] != remoteInfo['hash']) {
        filesToUpdate.add(filePath);
      }
    });

    return filesToUpdate;
  }

  Future<int> syncFiles() async {
    if (isSyncing) {
      return 0;
    }
    isSyncing = true;
    int count = 0;
    _currentProgress = 0;

    try {
      final remoteManifest = await _getRemoteManifest();
      final localManifest = await _getLocalManifest();

      // Find files to update or add
      final filesToUpdate = await checkForUpdates();
      _totalFiles = filesToUpdate.length;

      // Download and update manifest for each file individually
      for (final filePath in filesToUpdate) {
        if (isSyncing == false) {
          return count;
        }

        // Download the file
        await downloadFile(filePath);

        // Verify the file was actually downloaded successfully
        final directory = await _localDirectory;
        final localFilePath = _normalizeFilePath(filePath);
        final file = File('$directory/$localFilePath');

        // Only update manifest if file exists and has content
        if (await file.exists()) {
          final fileSize = await file.length();
          if (fileSize > 0) {
            // File downloaded successfully, update manifest
            await _updateLocalManifestForFile(
                filePath, remoteManifest[filePath]);
            count++;
            developer.log('Successfully downloaded and registered: $filePath',
                name: 'FileSyncRepository');
          } else {
            developer.log('WARNING: Downloaded file is empty: $filePath',
                name: 'FileSyncRepository');
          }
        } else {
          developer.log('WARNING: File download failed: $filePath',
              name: 'FileSyncRepository');
        }

        _currentProgress = count;
      }

      // CRITICAL FIX: Only remove files if ALL downloads completed successfully
      // This prevents data loss due to network issues
      if (count == filesToUpdate.length) {
        developer.log(
            'All files downloaded successfully, checking for obsolete files...',
            name: 'FileSyncRepository');

        // Remove files that exist locally but not in remote
        for (final localFilePath in localManifest.keys.toList()) {
          if (isSyncing == false) {
            return count;
          }
          if (!remoteManifest.containsKey(localFilePath)) {
            developer.log('Removing obsolete file: $localFilePath',
                name: 'FileSyncRepository');
            await _removeFromLocal(localFilePath);
          }
        }
        // Clean up empty folders after sync
        await removeEmptyFolders();
      } else {
        developer.log(
            'WARNING: Not all files downloaded successfully ($count/${filesToUpdate.length}). '
            'Skipping file removal to prevent data loss.',
            name: 'FileSyncRepository');
      }
    } catch (e) {
      developer.log(
          'Error during sync, manifest preserved to prevent data loss',
          name: 'FileSyncRepository',
          error: e);
      isSyncing = false;
      rethrow;
    }

    isSyncing = false;
    return count;
  }

  Future<void> stopSyncing() async {
    isSyncing = false;
  }
}
