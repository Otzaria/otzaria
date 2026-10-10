import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/bookmarks/view/book_bookmarks_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// The top bar of a commentators tab, for text and PDF books: the side pane
/// toggles, the navigation between sections, and the tab's actions.
///
/// The screens differ in how they navigate and in their text display
/// button, so those come from the screen, as do the tooltips that name the
/// larger navigation unit (a heading in PDF books, a chapter in text books).
class CommentatorsTabTopBar extends StatelessWidget {
  const CommentatorsTabTopBar({
    super.key,
    required this.title,
    required this.prevMajorTooltip,
    required this.nextMajorTooltip,
    required this.navPaneOpen,
    required this.navPanePinned,
    required this.onToggleNavPane,
    required this.onTogglePin,
    required this.onPrevMajor,
    required this.onPrevMinor,
    required this.onNextMinor,
    required this.onNextMajor,
    required this.textDisplayAction,
    required this.onPrint,
    required this.onSearch,
    required this.allExpanded,
    required this.onToggleAllExpanded,
    required this.onAddBookmark,
    required this.book,
    this.titleMaxLines,
  });

  final String title;
  final int? titleMaxLines;
  final String prevMajorTooltip;
  final String nextMajorTooltip;
  final bool navPaneOpen;
  final bool navPanePinned;
  final VoidCallback onToggleNavPane;
  final VoidCallback onTogglePin;
  final VoidCallback onPrevMajor;
  final VoidCallback onPrevMinor;
  final VoidCallback onNextMinor;
  final VoidCallback onNextMajor;
  final ActionButtonData textDisplayAction;
  final VoidCallback onPrint;
  final VoidCallback onSearch;
  final ValueListenable<bool> allExpanded;
  final VoidCallback onToggleAllExpanded;
  final VoidCallback onAddBookmark;

  /// The book whose bookmarks the bookmarks action lists.
  final Book book;

  static String _expandAllTooltip(bool allExpanded) =>
      allExpanded ? 'כווץ את כל המפרשים' : 'הרחב את כל המפרשים';

  static IconData _expandAllIcon(bool allExpanded) => allExpanded
      ? FluentIcons.arrow_collapse_all_24_regular
      : FluentIcons.arrow_expand_all_24_regular;

  ActionButtonData _iconAction({
    required String tooltip,
    required IconData icon,
    required bool compact,
    required VoidCallback onPressed,
    ToolbarActionId? actionId,
  }) => ActionButtonData(
    widget: BarButton.icon(
      tooltip: tooltip,
      icon: icon,
      compact: compact,
      onPressed: onPressed,
    ),
    icon: icon,
    tooltip: tooltip,
    actionId: actionId,
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsBloc>();
    final compact = settings.state.compactMenuMode;
    void onZoomIn() => settings.add(const AdjustCommentatorsFontSize(2));
    void onZoomOut() => settings.add(const AdjustCommentatorsFontSize(-2));
    void onShowBookmarks() => showBookBookmarksDialog(context, book);
    return AppTopBar(
      minCenterWidth: ReaderNavCenter.minTitleWidth,
      leadingItems: [
        AppTopBarItem(
          widget: NavPanelToggleButton(
            isOpen: navPaneOpen,
            onToggle: onToggleNavPane,
          ),
        ),
        if (navPaneOpen || navPanePinned)
          AppTopBarItem(
            widget: NavPanelPinButton(
              isPinned: navPanePinned,
              onToggle: onTogglePin,
            ),
          ),
      ],
      center: ReaderNavCenter(
        title: Text(
          title,
          style: AppTopBar.titleStyle(context),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: titleMaxLines,
        ),
        prevMajorTooltip: prevMajorTooltip,
        prevMinorTooltip: 'הקטע הקודם',
        nextMinorTooltip: 'הקטע הבא',
        nextMajorTooltip: nextMajorTooltip,
        onPrevMajor: onPrevMajor,
        onPrevMinor: onPrevMinor,
        onNextMinor: onNextMinor,
        onNextMajor: onNextMajor,
      ),
      trailingItems: [
        AppTopBarItem(
          flexible: true,
          widget: ResponsiveActionBar(
            overflowMenuOffset: const Offset(0, 8),
            actions: [
              textDisplayAction,
              _iconAction(
                tooltip: 'הדפסה',
                icon: FluentIcons.print_24_regular,
                compact: compact,
                actionId: ToolbarActionId.print,
                onPressed: onPrint,
              ),
              _iconAction(
                tooltip: 'חיפוש',
                icon: OtzariaIcons.search_24_regular,
                compact: compact,
                actionId: ToolbarActionId.search,
                onPressed: onSearch,
              ),
              ActionButtonData(
                widget: ValueListenableBuilder<bool>(
                  valueListenable: allExpanded,
                  builder: (context, expanded, _) => BarButton.icon(
                    tooltip: _expandAllTooltip(expanded),
                    icon: _expandAllIcon(expanded),
                    compact: compact,
                    onPressed: onToggleAllExpanded,
                  ),
                ),
                icon: _expandAllIcon(allExpanded.value),
                tooltip: _expandAllTooltip(allExpanded.value),
                actionId: ToolbarActionId.expandAll,
                onPressed: onToggleAllExpanded,
              ),
              _iconAction(
                tooltip: 'הוסף סימניה',
                icon: FluentIcons.bookmark_add_24_regular,
                compact: compact,
                actionId: ToolbarActionId.bookmarkAdd,
                onPressed: onAddBookmark,
              ),
              _iconAction(
                tooltip: 'הגדל את גודל הטקסט',
                icon: FluentIcons.zoom_in_24_regular,
                compact: compact,
                actionId: ToolbarActionId.zoomIn,
                onPressed: onZoomIn,
              ),
              _iconAction(
                tooltip: 'הקטן את גודל הטקסט',
                icon: FluentIcons.zoom_out_24_regular,
                compact: compact,
                actionId: ToolbarActionId.zoomOut,
                onPressed: onZoomOut,
              ),
            ],
            alwaysInMenu: [
              _iconAction(
                tooltip: 'סימניות בספר זה',
                icon: FluentIcons.bookmark_multiple_24_regular,
                compact: compact,
                onPressed: onShowBookmarks,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
