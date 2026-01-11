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
      final fileType = row['fileType'] as String? ?? 'txt';
      return DbReferenceResult(
        title: row['title'] as String? ?? '',
        reference: row['reference'] as String? ?? '',
        segment: row['segment'] as int? ?? 0,
        isPdf: fileType == 'pdf',
        filePath: row['filePath'] as String? ?? '',
      );
    }).toList();
  }

  String _normalizeForMatch(String input) {
    var cleaned = removeTeamim(removeVolwels(input));
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s]'), ' ');
    cleaned = cleaned.toLowerCase();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
