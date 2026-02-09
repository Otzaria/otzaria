import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/strategies/strategies.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';

/// Scaffold for text book viewing that uses Strategy Pattern
/// to select the appropriate view mode.
///
/// This replaces the previous if/else chains with a cleaner
/// strategy-based approach that makes adding new view modes easier.
class TextBookScaffold extends StatelessWidget {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final ValueChanged<String?>? onSelectedTextChanged;
  final TextEditingValue searchTextController;
  final TextBookTab tab;
  final int? initialSidebarTabIndex;
  final Key? pageShapeKey; // מפתח עבור PageShapeScreen
  final GlobalKey? pageShapePrintBoundaryKey; // מפתח עבור צילום למסמך הדפסה

  const TextBookScaffold({
    super.key,
    required this.content,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    this.onSelectedTextChanged,
    required this.searchTextController,
    required this.tab,
    this.initialSidebarTabIndex,
    this.pageShapeKey,
    this.pageShapePrintBoundaryKey,
  });

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      builder: (context, state) {
        // Select the appropriate strategy based on current state
        final strategy = _selectStrategy(state);

        // Create configuration for the strategy
        final config = TextBookViewConfig(
          content: content,
          openBookCallback: openBookCallback,
          openLeftPaneTab: openLeftPaneTab,
          onSelectedTextChanged: onSelectedTextChanged,
          searchTextController: searchTextController,
          tab: tab,
          initialSidebarTabIndex: initialSidebarTabIndex,
          pageShapeKey: pageShapeKey,
          pageShapePrintBoundaryKey: pageShapePrintBoundaryKey,
        );

        // Build the view using the selected strategy
        return strategy.buildView(context, config);
      },
    );
  }

  /// Selects the appropriate view strategy based on the current state
  TextBookViewStrategy _selectStrategy(dynamic state) {
    // Check for page shape view first (highest priority)
    if (state.showPageShapeView) {
      return PageShapeStrategyImpl();
    }

    // Check for split view (commentaries on side)
    if (state.showSplitView) {
      return SplitViewStrategyImpl();
    }

    // Default to combined view (commentaries below)
    return CombinedViewStrategyImpl();
  }
}
