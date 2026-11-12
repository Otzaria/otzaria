import 'package:flutter/material.dart';
import 'package:otzaria/text_book/view/strategies/text_book_view_strategy.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';

/// תצוגה מפוצלת (מפרשים בצד) או משולבת (מפרשים מתחת לטקסט) — אותו
/// [SplitedViewScreen], וההבדל ביניהן הוא [showSplitView] בלבד.
class SplitViewStrategyImpl extends TextBookViewStrategy {
  final bool showSplitView;

  SplitViewStrategyImpl({required this.showSplitView});

  @override
  Widget buildView(BuildContext context, TextBookViewConfig config) {
    return SplitedViewScreen(
      key: config.splitViewKey,
      content: config.content,
      openBookCallback: config.openBookCallback,
      searchTextController: config.searchTextController,
      openLeftPaneTab: config.openLeftPaneTab,
      onSelectedTextChanged: config.onSelectedTextChanged,
      tab: config.tab,
      initialTabIndex: config.initialSidebarTabIndex,
      showSplitView: showSplitView,
      onSidebarTabChanged: config.onSidebarTabChanged,
    );
  }
}
