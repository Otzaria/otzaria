import 'package:equatable/equatable.dart';

class CommentatorGroup extends Equatable {
  final String title;
  final List<String> commentators;

  const CommentatorGroup({
    required this.title,
    required this.commentators,
  });

  CommentatorGroup copyWith({
    String? title,
    List<String>? commentators,
  }) {
    return CommentatorGroup(
      title: title ?? this.title,
      commentators: commentators ?? this.commentators,
    );
  }

  @override
  List<Object?> get props => [title, commentators];

  /// Helper method to find commentator group by title
  static CommentatorGroup groupByTitle(
          List<CommentatorGroup> groups, String title) =>
      groups.firstWhere((g) => g.title == title,
          orElse: () => const CommentatorGroup(title: '', commentators: []));
}
