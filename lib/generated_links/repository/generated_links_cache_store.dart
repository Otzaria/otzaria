import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/generated_links/models/generated_links_cache.dart';
import 'package:path/path.dart' as p;

/// שומר וטוען קבצי cache של קישורים שנוצרו מקומית.
///
/// כל ספר מיוצג בקובץ JSON נפרד בשם {bookId}.json.
/// כתיבה מתבצעת אטומית: כותבים ל-{bookId}.json.tmp ואז מבצעים rename.
class GeneratedLinksCacheStore {
  final String _cacheDir;

  GeneratedLinksCacheStore({required String basePath}) : _cacheDir = basePath;

  String get directoryPath => _cacheDir;

  /// יוצר instance חדש ומוודא שתיקיית ה-cache קיימת.
  static Future<GeneratedLinksCacheStore> create() async {
    final dir = await AppPaths.getGeneratedLinksCachePath();
    await Directory(dir).create(recursive: true);
    return GeneratedLinksCacheStore(basePath: dir);
  }

  String _cachePath(int bookId) => p.join(_cacheDir, '$bookId.json');
  String _tmpPath(int bookId) => p.join(_cacheDir, '$bookId.json.tmp');

  /// טוען cache של ספר. מחזיר null אם הקובץ לא קיים או פסול.
  Future<GeneratedLinksCache?> load(int bookId) async {
    final file = File(_cachePath(bookId));
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final cache = GeneratedLinksCache.fromJson(json);

      if (cache.schemaVersion > GeneratedLinksCache.currentSchemaVersion) {
        debugPrint(
            'GeneratedLinksCacheStore: schema version ${cache.schemaVersion} '
            '> current ${GeneratedLinksCache.currentSchemaVersion}, ignoring cache for $bookId');
        return null;
      }

      return cache;
    } catch (e, st) {
      debugPrint(
          'GeneratedLinksCacheStore: failed to load cache for $bookId: $e\n$st');
      return null;
    }
  }

  /// שומר cache בכתיבה אטומית (tmp + rename).
  Future<void> save(GeneratedLinksCache cache) async {
    final tmpFile = File(_tmpPath(cache.sourceBookId));
    final finalFile = File(_cachePath(cache.sourceBookId));

    try {
      await tmpFile.writeAsString(jsonEncode(cache.toJson()), flush: true);
      await tmpFile.rename(finalFile.path);
    } catch (e, st) {
      debugPrint('GeneratedLinksCacheStore: failed to save cache for '
          '${cache.sourceBookId}: $e\n$st');
      if (await tmpFile.exists()) {
        await tmpFile.delete().catchError((Object _) => tmpFile);
      }
      rethrow;
    }
  }

  /// מוחק cache של ספר (קובץ סופי + קובץ זמני אם קיים).
  Future<void> delete(int bookId) async {
    for (final path in [_cachePath(bookId), _tmpPath(bookId)]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// מחזיר רשימת ה-IDs של ספרים שיש להם קובץ cache.
  Future<List<int>> listCachedBookIds() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return [];

    final ids = <int>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      final id = int.tryParse(name);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// מנקה קבצי .tmp שנותרו מכתיבות שהופסקו באמצע.
  Future<void> cleanupStaleTemporaryFiles() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json.tmp')) {
        await entity.delete().catchError((Object _) => entity);
      }
    }
  }
}
