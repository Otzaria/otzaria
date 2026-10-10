import 'package:flutter/widgets.dart';
import 'package:otzaria/library/services/parallel_editions_service.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// The toolbar button that opens a parallel edition of the book. The first
/// edition is the main action; with more than one, a split menu lists them
/// all.
///
/// The built-in companion edition differs per reader: [companionIcon],
/// [companionTooltip] when it is the main action, and [companionMenuSuffix]
/// after its title in the menu.
ActionButtonData buildParallelEditionsAction({
  required List<ParallelEdition> editions,
  required bool compact,
  required IconData companionIcon,
  required String companionTooltip,
  required String companionMenuSuffix,
  required void Function(ParallelEdition edition) onOpen,
}) {
  final primary = editions.first;
  final tooltip = primary.isCompanion ? companionTooltip : 'פתח מהדורה מקבילה';
  if (editions.length == 1) {
    return ActionButtonData(
      widget: BarButton.icon(
        tooltip: tooltip,
        icon: companionIcon,
        compact: compact,
        onPressed: () => onOpen(primary),
      ),
      icon: companionIcon,
      tooltip: tooltip,
      actionId: ToolbarActionId.parallelEdition,
      onPressed: () => onOpen(primary),
    );
  }
  return ActionButtonData.split(
    icon: companionIcon,
    tooltip: tooltip,
    compact: compact,
    actionId: ToolbarActionId.parallelEdition,
    onPressed: () => onOpen(primary),
    menuItems: [
      for (final edition in editions)
        ActionButtonData(
          widget: const SizedBox.shrink(),
          icon: edition.isCompanion
              ? companionIcon
              : OtzariaIcons.book_24_regular,
          tooltip: edition.isCompanion
              ? '${edition.book.title} — $companionMenuSuffix'
              : edition.label ?? edition.book.title,
          onPressed: () => onOpen(edition),
        ),
    ],
  );
}
