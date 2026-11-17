import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

/// [activeLibraryPath] נדרש מחוץ ל-isolate הראשי, שם אין גישה להגדרות.
String resolveMovedFileBookPath(String filePath, {String? activeLibraryPath}) {
  if (File(filePath).existsSync()) return filePath;
  for (final candidate in _movedPathCandidates(filePath, activeLibraryPath)) {
    if (File(candidate).existsSync()) return candidate;
  }
  return filePath;
}

/// כמו [resolveMovedFileBookPath], בלי לחסום את ה-isolate: בכונן רשת או
/// בכונן שנרדם בדיקת קובץ אחת נמשכת שניות.
Future<String> resolveMovedFileBookPathAsync(String filePath) async {
  if (await File(filePath).exists()) return filePath;
  for (final candidate in _movedPathCandidates(filePath, null)) {
    if (await File(candidate).exists()) return candidate;
  }
  return filePath;
}

Set<String> _movedPathCandidates(String filePath, String? activeLibraryPath) {
  final libraryPath =
      activeLibraryPath ??
      Settings.getValue<String>(SettingsRepository.keyLibraryPath) ??
      '';
  final candidates = <String>{};
  if (libraryPath.isEmpty) return candidates;

  final segments = p.split(p.normalize(filePath));

  void addCandidateFromSegment(String segment) {
    final index = segments.lastIndexWhere(
      (part) => part.toLowerCase() == segment.toLowerCase(),
    );
    if (index < 0 || index + 1 >= segments.length) return;
    candidates.add(p.joinAll([libraryPath, ...segments.skip(index + 1)]));
  }

  addCandidateFromSegment(p.basename(libraryPath));
  addCandidateFromSegment(DatabaseConstants.talmudBavliFolderName);
  return candidates;
}
