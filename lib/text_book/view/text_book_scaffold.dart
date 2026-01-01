import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';

class TextBookScaffold extends StatelessWidget {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int) openLeftPaneTab;
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
        if (state.showPageShapeView) {
          final page = PageShapeScreen(
            key: pageShapeKey,
            openBookCallback: openBookCallback,
          );

          final boundaryKey = pageShapePrintBoundaryKey;
          if (boundaryKey == null) return page;

          return RepaintBoundary(
            key: boundaryKey,
            child: page,
          );
        }

        // תמיד משתמשים ב-SplitedViewScreen, הוא יחליט אם להציג split או לא
        return SplitedViewScreen(
          content: content,
          openBookCallback: openBookCallback,
          searchTextController: searchTextController,
          openLeftPaneTab: openLeftPaneTab,
          tab: tab,
          initialTabIndex: initialSidebarTabIndex,
          showSplitView: state.showSplitView,
        );
      },
    );
  }
}
