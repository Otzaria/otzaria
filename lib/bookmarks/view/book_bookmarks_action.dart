import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// Shows the bookmarks of [book] only.
Future<void> showBookBookmarksDialog(BuildContext context, Book book) =>
    showDialog<void>(
      context: context,
      builder: (_) => BookmarksDialog(bookFilter: book),
    );

/// The toolbar button that shows the bookmarks of [book]. [tourKey] marks it
/// for the reader tour.
ActionButtonData buildBookBookmarksAction(
  BuildContext context, {
  required Book book,
  required bool compact,
  Key? tourKey,
}) {
  const tooltip = 'סימניות בספר זה';
  void onPressed() => showBookBookmarksDialog(context, book);
  return ActionButtonData(
    widget: BarButton.icon(
      key: tourKey,
      tooltip: tooltip,
      icon: FluentIcons.bookmark_multiple_24_regular,
      compact: compact,
      onPressed: onPressed,
    ),
    icon: FluentIcons.bookmark_multiple_24_regular,
    tooltip: tooltip,
    onPressed: onPressed,
  );
}
