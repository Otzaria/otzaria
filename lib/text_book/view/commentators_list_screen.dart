import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';

class CommentatorsListView extends StatefulWidget {
  final VoidCallback? onCommentatorSelected;

  const CommentatorsListView({
    super.key,
    this.onCommentatorSelected,
  });

  @override
  State<CommentatorsListView> createState() => CommentatorsListViewState();
}

class CommentatorsListViewState extends State<CommentatorsListView> {
  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      loadingWidget: const Center(),
      builder: (context, state) {
        return CommentatorsSelectionPanel(
          groups: state.commentatorGroups,
          selectedCommentators: state.activeCommentators,
          bookTitle: state.book.title,
          rareCommentators: state.rareCommentators,
          lineRelevantCommentators: _lineRelevantCommentators(state),
          onSelectionChanged: (commentators) {
            context.read<TextBookBloc>().add(UpdateCommentators(commentators));
          },
        );
      },
    );
  }

  /// אינדקסי השורות הנוכחיים (בחירה מרובה אם יש, אחרת הנראות) שלפיהם מחליטים
  /// אילו מפרשים נדירים כן להציג ברשימה.
  Set<String> _lineRelevantCommentators(TextBookLoaded state) {
    if (state.rareCommentators.isEmpty) return const {};
    final indexes = state.selectedIndices.isNotEmpty
        ? state.selectedIndices
        : (state.visibleIndices.isNotEmpty
              ? state.visibleIndices
              : (state.selectedIndex != null
                    ? [state.selectedIndex!]
                    : const <int>[]));
    return lineRelevantRareCommentators(
      rareCommentators: state.rareCommentators,
      currentIndexes: indexes,
      linksByLine: state.linksByLine,
    );
  }
}
