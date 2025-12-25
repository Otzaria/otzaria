import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';

class TextBookScaffold extends StatelessWidget {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int) openLeftPaneTab;
  final TextEditingValue searchTextController;
  final TextBookTab tab;
  final int? initialSidebarTabIndex;
  final Key? pageShapeKey; // מפתח עבור PageShapeScreen

  const TextBookScaffold({
    super.key,
    required this.content,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    required this.searchTextController,
    required this.tab,
    this.initialSidebarTabIndex,
    this.pageShapeKey,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.showPageShapeView) {
          return PageShapeScreen(
            key: pageShapeKey,
            openBookCallback: openBookCallback,
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
