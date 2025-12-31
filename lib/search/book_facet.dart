import 'package:flutter/foundation.dart';
import 'package:otzaria/data/repository/data_repository.dart';

class BookFacet {
  BookFacet._();

  static String topicsToPath(String topics) {
    final t = topics.trim();
    if (t.isEmpty) return '';
    return '/${t.replaceAll(', ', '/')}';
  }

  static String buildFacetPath({required String title, required String topics}) {
    final cleanTitle = title.trim();
    final topicsPath = topicsToPath(topics);
    return topicsPath.isEmpty ? '/$cleanTitle' : '$topicsPath/$cleanTitle';
  }

  static Future<String> resolveTopics({
    required String title,
    required String initialTopics,
    required Type? type,
  }) async {
    final t = initialTopics.trim();
    if (t.isNotEmpty) return t;

    try {
      final library = await DataRepository.instance.library;
      final book = library.findBookByTitle(title, type);
      return book?.topics ?? '';
    } catch (e) {
      debugPrint('📚 BookFacet.resolveTopics error: $e');
      return '';
    }
  }
}
