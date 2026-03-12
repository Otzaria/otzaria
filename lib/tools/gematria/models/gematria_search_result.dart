// lib/tools/gematria/models/gematria_search_result.dart
//
// מודל תוצאת חיפוש לתצוגה במסך — עוטף SearchResult בשדות תצוגה.
// הוצא מ-gematria_search_screen.dart לקובץ עצמאי לפי עקרון SRP.

import 'package:otzaria/tools/gematria/models/search_result.dart';

class GematriaSearchResult {
  final String bookTitle;
  final String internalPath;
  final String preview;
  final SearchResult data;

  const GematriaSearchResult({
    required this.bookTitle,
    required this.internalPath,
    this.preview = '',
    required this.data,
  });
}
