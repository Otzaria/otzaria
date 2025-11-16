import 'package:search_engine/search_engine.dart';

/// תוצאה עם ניקוד למיון
class ScoredResult {
  final ReferenceSearchResult result;
  final String type; // "ספר", "ספר_חלקי", "כותרת2", "כותרת3"
  final int level; // 0 = ספר, 2 = H2, 3 = H3
  final double score; // ניקוד כולל

  ScoredResult({
    required this.result,
    required this.type,
    required this.level,
    required this.score,
  });

  @override
  String toString() {
    return 'ScoredResult(type=$type, level=$level, score=$score, title="${result.title}", ref="${result.reference}")';
  }
}
