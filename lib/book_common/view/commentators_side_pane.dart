import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// The side pane of a commentators tab, for text and PDF books: navigation,
/// the commentators selection and the search, each in its own tab.
class CommentatorsSidePane extends StatelessWidget {
  const CommentatorsSidePane({
    super.key,
    required this.controller,
    required this.navigation,
    required this.selection,
    required this.search,
  });

  final TabController controller;
  final Widget navigation;
  final Widget selection;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NavPanelTabHeader(
          controller: controller,
          tabs: const [
            (
              icon: OtzariaIcons.list_24_regular,
              iconFilled: OtzariaIcons.list_24_filled,
              label: 'ניווט',
            ),
            (
              icon: OtzariaIcons.apps_list_24_regular,
              iconFilled: OtzariaIcons.apps_list_24_filled,
              label: 'סינון מפרשים',
            ),
            (
              icon: FluentIcons.search_24_regular,
              iconFilled: FluentIcons.search_24_filled,
              label: 'חיפוש',
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              NavPanelSearchSlot(index: 0, child: navigation),
              NavPanelSearchSlot(index: 1, child: selection),
              NavPanelSearchSlot(index: 2, child: search),
            ],
          ),
        ),
      ],
    );
  }
}
