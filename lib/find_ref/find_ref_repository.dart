import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/db_reference_result.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/utils/text_manipulation.dart';

class FindRefRepository {
  final DataRepository dataRepository;

  FindRefRepository({required this.dataRepository});

  Future<List<DbReferenceResult>> findRefs(String ref) async {
    final cleanedQuery = _normalizeForMatch(ref);
    if (cleanedQuery.length < 2) {
      return const [];
    }

    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[FindRef] Database not initialized');
      return const [];
    }

    // Single query search in TOC
    final results = await repository.searchReferences(cleanedQuery, limit: 20);

    debugPrint('[FindRef] Found ${results.length} results');

    return results.map((row) {
      final fileType = _safeGet<String>(row, 'fileType', 'txt');
      return DbReferenceResult(
        title: _safeGet<String>(row, 'title', ''),
        reference: _safeGet<String>(row, 'reference', ''),
        segment: _safeGet<int>(row, 'segment', 0),
        isPdf: fileType == 'pdf',
        filePath: _safeGet<String>(row, 'filePath', ''),
      );
    }).toList();
  }

  T _safeGet<T>(Map<String, dynamic> map, String key, T defaultValue) {
    final value = map[key];
    return value is T ? value : defaultValue;
  }

  String _normalizeForMatch(String input) {
    var cleaned = removeTeamim(removeVolwels(input));
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s]'), ' ');
    cleaned = cleaned.toLowerCase();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
