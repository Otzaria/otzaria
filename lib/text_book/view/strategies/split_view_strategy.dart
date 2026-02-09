import 'package:flutter/material.dart';
import 'package:otzaria/text_book/view/strategies/text_book_view_strategy.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';

/// Strategy implementation for split view mode
///
/// Shows the main text with commentary panel on the side
class SplitViewStrategyImpl extends TextBookViewStrategy {
  @override
  String get displayName => 'מפרשים בצד';

  @override
  Widget buildView(BuildContext context, TextBookViewConfig config) {
    return SplitedViewScreen(
      content: config.content,
      openBookCallback: config.openBookCallback,
      searchTextController: config.searchTextController,
      openLeftPaneTab: config.openLeftPaneTab,
      onSelectedTextChanged: config.onSelectedTextChanged,
      tab: config.tab,
      initialTabIndex: config.initialSidebarTabIndex,
      showSplitView: true, // Split view - panel on the side
    );
  }
}
