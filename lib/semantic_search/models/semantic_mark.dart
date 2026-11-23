import 'package:equatable/equatable.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticVote;

/// סימון של המשתמש על שורה, רלוונטית או לא. המנוע מסדר לפיו את התוצאות,
/// גם בחיפוש שנערך מחדש. [title] ו-[reference] להצגה בלבד.
class SemanticMark extends Equatable {
  const SemanticMark({
    required this.filePath,
    required this.id,
    required this.relevant,
    required this.title,
    required this.reference,
  });

  factory SemanticMark.of(SemanticResultItem item, {required bool relevant}) =>
      SemanticMark(
        filePath: item.filePath,
        id: item.id,
        relevant: relevant,
        title: item.title,
        reference: item.reference,
      );

  final String filePath;
  final BigInt id;
  final bool relevant;
  final String title;
  final String reference;

  /// האם [item] היא השורה המסומנת.
  bool isOf(SemanticResultItem item) =>
      filePath == item.filePath && id == item.id;

  /// אותה שורה, בכל כיוון סימון.
  bool sameLine(SemanticMark other) =>
      filePath == other.filePath && id == other.id;

  SemanticVote get vote =>
      SemanticVote(filePath: filePath, id: id, relevant: relevant);

  @override
  List<Object?> get props => [filePath, id, relevant];
}
