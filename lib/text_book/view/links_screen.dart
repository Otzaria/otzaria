// a widget that takes an html strings array, finds all the headings, and displays it in a listview. on pressed the scrollcontroller scrolls to the index of the heading.

import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/links.dart';

class LinksViewer extends StatefulWidget {
  final Function(OpenedTab tab) openTabcallback;
  final void Function() closeLeftPanelCallback;
  final void Function() openInSidebarCallback;
  final bool isSplitViewOpen; // האם החלונית פתוחה
  final List<Link> links;

  const LinksViewer({
    super.key,
    required this.openTabcallback,
    required this.closeLeftPanelCallback,
    required this.openInSidebarCallback,
    required this.isSplitViewOpen,
    required this.links,
  });

  @override
  State<LinksViewer> createState() => _LinksViewerState();
}

class _LinksViewerState extends State<LinksViewer>
    with AutomaticKeepAliveClientMixin<LinksViewer> {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final links = widget.links;

    return ListView.builder(
      itemCount: links.length + 1, // +1 עבור הלחצן
      itemBuilder: (context, index) {
        // הלחצן "פתח/סגור חלונית צד" בתחילת הרשימה
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: widget.openInSidebarCallback,
              icon: Icon(widget.isSplitViewOpen
                  ? FluentIcons.chevron_right_24_regular
                  : FluentIcons.chevron_left_24_regular),
              label: Text(
                  widget.isSplitViewOpen ? 'סגור חלונית צד' : 'פתח בחלונית צד'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
              ),
            ),
          );
        }

        // קישורים רגילים
        final linkIndex = index - 1;
        return ListTile(
          key: ValueKey('${links[linkIndex].path2}_${links[linkIndex].index2}'),
          title: Text(links[linkIndex].heRef),
          onTap: () {
            void open() => widget.openTabcallback(
                  TextBookTab(
                    book: TextBook(
                        title: utils.getTitleFromPath(links[linkIndex].path2)),
                    index: links[linkIndex].index2 - 1,
                    openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ??
                            false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
                  ),
                );

            if (MediaQuery.of(context).size.width < 600) {
              widget.closeLeftPanelCallback();
              WidgetsBinding.instance.addPostFrameCallback((_) => open());
            } else {
              open();
            }
          },
        );
      },
    );
  }

  @override
  get wantKeepAlive => true;
}
