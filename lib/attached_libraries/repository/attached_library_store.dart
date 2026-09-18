import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// שמירת רשימת המסדים המצורפים ותיקיות המסדים בהגדרות — במפתחות נפרדים
/// מאלה של התיקיות המותאמות אישית.
class AttachedLibraryStore {
  const AttachedLibraryStore();

  List<AttachedLibrary> loadLibraries() => loadLibrariesOrNull() ?? [];

  /// null כשהערך השמור פגום — "לא ידוע", ולא "אין מסדים": ניקוי יתומים אינו
  /// רשאי למחוק על סמך רשימה ריקה שנולדה מכשל פענוח.
  List<AttachedLibrary>? loadLibrariesOrNull() {
    final decoded = _tryDecodeList(
      Settings.getValue<String>(SettingsRepository.keyAttachedLibraries),
    );
    if (decoded == null) return null;
    final libraries = <AttachedLibrary>[];
    for (final item in decoded) {
      try {
        libraries.add(
          AttachedLibrary.fromJson(Map<String, dynamic>.from(item as Map)),
        );
      } catch (e) {
        // רשומה פגומה אחת אינה מאבדת את שאר המסדים.
        debugPrint('[AttachedLibraryStore] skipping corrupt entry: $e');
      }
    }
    return libraries;
  }

  Future<void> saveLibraries(List<AttachedLibrary> libraries) =>
      Settings.setValue<String>(
        SettingsRepository.keyAttachedLibraries,
        jsonEncode([for (final library in libraries) library.toJson()]),
      );

  List<String> loadFolders() => [
    for (final item in _decodeList(
      Settings.getValue<String>(SettingsRepository.keyAttachedLibraryFolders),
    ))
      if (item is String && item.isNotEmpty) item,
  ];

  Future<void> saveFolders(List<String> folders) => Settings.setValue<String>(
    SettingsRepository.keyAttachedLibraryFolders,
    jsonEncode(folders),
  );

  static List<Object?> _decodeList(String? raw) =>
      _tryDecodeList(raw) ?? const [];

  static List<Object?>? _tryDecodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (e) {
      debugPrint('[AttachedLibraryStore] JSON parse failed: $e');
      return null;
    }
  }
}
