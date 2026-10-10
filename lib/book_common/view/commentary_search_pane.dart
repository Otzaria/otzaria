import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/widgets/commentary/commentary_search_results_list.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// The search tab of a commentators tab, for text and PDF books. The
/// commentary list that runs the search reports its result count, current
/// result and snippets through the notifiers, and moves between results
/// through the callbacks.
class CommentarySearchPane extends StatelessWidget {
  const CommentarySearchPane({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.totalResults,
    required this.currentResult,
    required this.snippets,
    required this.onPrevious,
    required this.onNext,
    required this.onSnippetTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueListenable<int> totalResults;
  final ValueListenable<int> currentResult;
  final ValueListenable<List<CommentarySearchSnippet>> snippets;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onSnippetTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasQuery = value.text.isNotEmpty;
        return ValueListenableBuilder<int>(
          valueListenable: totalResults,
          builder: (context, total, _) => ValueListenableBuilder<int>(
            valueListenable: currentResult,
            builder: (context, current, _) => SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              hintText: hintText,
              isNoResults: hasQuery && total == 0,
              resetSearchCallback: controller.clear,
              resultCountString: hasQuery && total > 0
                  ? 'תוצאה ${current + 1} מתוך $total'
                  : null,
              resultToolbar: hasQuery && total > 0
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OtzariaSearchAction.prevResult(
                          onPressed: current > 0 ? onPrevious : null,
                        ),
                        OtzariaSearchAction.nextResult(
                          onPressed: current < total - 1 ? onNext : null,
                        ),
                      ],
                    )
                  : null,
              resultsWidget:
                  ValueListenableBuilder<List<CommentarySearchSnippet>>(
                    valueListenable: snippets,
                    builder: (context, snippets, _) =>
                        CommentarySearchResultsList(
                          query: value.text,
                          snippets: snippets,
                          currentIdx: current,
                          onSnippetTap: onSnippetTap,
                        ),
                  ),
            ),
          ),
        );
      },
    );
  }
}
