import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/commentators_selection_panel.dart';

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
          onSelectionChanged: (commentators) {
            context.read<TextBookBloc>().add(UpdateCommentators(commentators));
          },
          onSelectionApplied: widget.onCommentatorSelected,
        );
      },
    );
  }
}
