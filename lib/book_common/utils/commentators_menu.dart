import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// מציג פתיחת חלונית כשיש בחירה, בלי מפרשים inline או טאב מפרשים פעיל.
bool shouldShowOpenCommentatorsPaneEntry({
  required bool hasSelectedCommentators,
  required bool showCommentaryAsExpansionTiles,
  required bool isCommentatorsTabActive,
}) {
  return hasSelectedCommentators &&
      !showCommentaryAsExpansionTiles &&
      !isCommentatorsTabActive;
}

/// מאפשר בחירה מרובה גם כשהבחירה ריקה, אם טאב המפרשים אינו פעיל.
bool shouldShowSelectCommentatorsEntry({
  required bool hasOpenCommentatorsPaneWithFilterCallback,
  required bool isCommentatorsTabActive,
}) {
  return hasOpenCommentatorsPaneWithFilterCallback && !isCommentatorsTabActive;
}

/// מוסר את הבחירה המלאה; [isAdding] מציין שכדאי לפתוח את חלונית המפרשים.
typedef CommentatorsSelectionChanged =
    void Function(List<String> commentators, {required bool isAdding});

/// בונה תפריט למפרשי הפסקה או העמוד; הקבוצות מסוננות למפרשים הזמינים.
/// [getActiveCommentators] נקרא גם בלחיצה, כדי לשמר בחירה שנטענה אחרי הפתיחה.
List<AppContextMenuEntry> buildCommentatorsContextMenuChildren({
  required Iterable<String> Function() getActiveCommentators,
  required List<String> availableCommentators,
  required List<CommentatorGroup> commentatorGroups,
  required CommentatorsSelectionChanged onCommentatorsChanged,
  VoidCallback? onOpenPane,
  VoidCallback? onSelectMultiple,
  bool linksLoading = false,
  String showAllLabel = 'הצג את כל המפרשים על פסקה זו',
  bool keepPaneEntriesWithoutCommentators = false,
}) {
  final activeSet = getActiveCommentators().toSet();
  final availableSet = availableCommentators.toSet();
  final allActive = activeSet.containsAll(availableCommentators);

  AppContextMenuEntry buildItem(String title) {
    final isActive = activeSet.contains(title);
    return AppContextMenuEntry(
      label: title,
      isSelected: isActive,
      onTap: () {
        // לחיצה על מפרש פעיל רק פותחת את החלונית; הסרה נעשית בחלונית הסינון.
        final updated = getActiveCommentators().toSet()..add(title);
        onCommentatorsChanged(updated.toList(), isAdding: true);
      },
    );
  }

  List<AppContextMenuEntry> buildGroup(CommentatorGroup group) {
    final commentators = group.commentators
        .where(availableSet.contains)
        .toSet();
    if (commentators.isEmpty) return const <AppContextMenuEntry>[];
    final groupActive = commentators.every(activeSet.contains);
    return [
      AppContextMenuEntry(
        label: 'הצג את כל ${group.title}',
        isSelected: groupActive,
        onTap: () {
          final updated = getActiveCommentators().toSet();
          final isRemoving = updated.containsAll(commentators);
          if (isRemoving) {
            updated.removeAll(commentators);
          } else {
            updated.addAll(commentators);
          }
          onCommentatorsChanged(updated.toList(), isAdding: !isRemoving);
        },
      ),
      ...commentators.map(buildItem),
    ];
  }

  final paneEntries = <AppContextMenuEntry>[
    if (onOpenPane != null)
      AppContextMenuEntry(
        label: 'פתח את חלונית המפרשים',
        icon: FluentIcons.panel_right_24_regular,
        isHighlighted: true,
        onTap: onOpenPane,
      ),
    if (onSelectMultiple != null)
      AppContextMenuEntry(
        label: 'בחר מפרשים מרובים',
        icon: FluentIcons.filter_24_regular,
        isHighlighted: true,
        onTap: onSelectMultiple,
      ),
  ];

  if (availableCommentators.isEmpty) {
    if (linksLoading) {
      return const [AppContextMenuEntry(label: 'טוען מפרשים…', enabled: false)];
    }
    return keepPaneEntriesWithoutCommentators
        ? paneEntries
        : const <AppContextMenuEntry>[];
  }

  final entries = <AppContextMenuEntry>[
    ...paneEntries,
    if (paneEntries.isNotEmpty) const AppContextMenuEntry.divider(),
    AppContextMenuEntry(
      label: showAllLabel,
      isSelected: allActive,
      // בחירות מפסקאות או עמודים אחרים נשמרות.
      onTap: () {
        final updated = getActiveCommentators().toSet();
        final isRemoving = updated.containsAll(availableSet);
        if (isRemoving) {
          updated.removeAll(availableSet);
        } else {
          updated.addAll(availableSet);
        }
        onCommentatorsChanged(updated.toList(), isAdding: !isRemoving);
      },
    ),
  ];

  // הקבוצות מגיעות מה-BLoC כשהן כבר ממוינות לפי דורות; מפריד מתווסף רק לפני
  // קבוצה שיש בה מפרשים, כדי שקבוצה ריקה באמצע לא תדביק שתי קבוצות זו לזו.
  for (final group in commentatorGroups) {
    final items = buildGroup(group);
    if (items.isEmpty) continue;
    entries.add(const AppContextMenuEntry.divider());
    entries.addAll(items);
  }

  // מפרשים ללא קבוצה מוצגים גם בזמן שהקבוצות עדיין נטענות.
  final grouped = {
    for (final group in commentatorGroups) ...group.commentators,
  };
  final ungrouped = availableCommentators.where((c) => !grouped.contains(c));
  if (ungrouped.isNotEmpty) {
    entries.add(const AppContextMenuEntry.divider());
    entries.addAll(ungrouped.map(buildItem));
  }

  return entries;
}

/// מציג פתיחת חלונית קישורים כשיש קישורים והטאב אינו פעיל.
bool shouldShowOpenLinksPaneEntry({
  required bool hasLinks,
  required bool isLinksTabActive,
}) {
  return hasLinks && !isLinksTabActive;
}
