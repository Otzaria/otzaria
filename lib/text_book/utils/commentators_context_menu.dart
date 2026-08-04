import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// סדר הקבוצות בתת-התפריט "מפרשים" — לפי דורות, כמו בחלונית בחירת המפרשים.
const List<String> _kGroupOrder = <String>[
  'תורה שבכתב',
  'חז"ל',
  'ראשונים',
  'אחרונים',
  'מחברי זמננו',
  'שאר מפרשים',
];

/// פריט "פתח את חלונית המפרשים" יוצג כשיש מפרשים נבחרים, המפרשים אינם מוצגים
/// inline מתחת לטקסט, וטאב המפרשים אינו כבר פעיל בחלונית הצד.
bool shouldShowOpenCommentatorsPaneEntry({
  required bool hasSelectedCommentators,
  required bool showCommentaryAsExpansionTiles,
  required bool isCommentatorsTabActive,
}) {
  return hasSelectedCommentators &&
      !showCommentaryAsExpansionTiles &&
      !isCommentatorsTabActive;
}

/// פריט "בחר מפרשים מרובים" יוצג כשיש callback לפתיחת חלונית הסינון וטאב
/// המפרשים אינו פעיל בחלונית הצד.
///
/// בניגוד ל-[shouldShowOpenCommentatorsPaneEntry], הפריט הזה לא תלוי
/// ב-`hasSelectedCommentators` — מטרתו לאפשר בחירה גם כשהבחירה ריקה.
bool shouldShowSelectCommentatorsEntry({
  required bool hasOpenCommentatorsPaneWithFilterCallback,
  required bool isCommentatorsTabActive,
}) {
  return hasOpenCommentatorsPaneWithFilterCallback && !isCommentatorsTabActive;
}

/// נקרא כשבחירת המפרשים משתנה מתוך תת-התפריט.
///
/// [commentators] - הבחירה המעודכנת המלאה.
/// [isAdding] - האם הפעולה הוסיפה מפרשים (ולכן כדאי לפתוח את החלונית).
typedef CommentatorsSelectionChanged =
    void Function(List<String> commentators, {required bool isAdding});

/// בונה את פריטי תת-התפריט "מפרשים" בתפריט ההקשר של גוף הספר.
///
/// משותף לתצוגה המשולבת/מפוצלת ולצורת הדף, כדי ששלושתן יציגו את אותם פריטים
/// ואותה התנהגות.
///
/// [onOpenPane] ו-[onSelectMultiple] אינם מוצגים כשהם `null`.
List<AppContextMenuEntry> buildCommentatorsContextMenuChildren({
  required List<String> activeCommentators,
  required List<String> availableCommentators,
  required List<CommentatorGroup> commentatorGroups,
  required CommentatorsSelectionChanged onCommentatorsChanged,
  VoidCallback? onOpenPane,
  VoidCallback? onSelectMultiple,
}) {
  final activeSet = activeCommentators.toSet();
  final allActive = activeSet.containsAll(availableCommentators);

  List<AppContextMenuEntry> buildGroup(CommentatorGroup group) {
    if (group.commentators.isEmpty) return const <AppContextMenuEntry>[];
    final groupActive = group.commentators.every(activeSet.contains);
    return [
      AppContextMenuEntry(
        label: 'הצג את כל ${group.title}',
        isSelected: groupActive,
        onTap: () {
          final updated = List<String>.from(activeCommentators);
          if (groupActive) {
            updated.removeWhere(group.commentators.contains);
          } else {
            for (final title in group.commentators) {
              if (!updated.contains(title)) updated.add(title);
            }
          }
          onCommentatorsChanged(updated, isAdding: !groupActive);
        },
      ),
      ...group.commentators.map((title) {
        final isActive = activeSet.contains(title);
        return AppContextMenuEntry(
          label: title,
          isSelected: isActive,
          onTap: () {
            final updated = List<String>.from(activeCommentators);
            if (isActive) {
              updated.remove(title);
            } else {
              updated.add(title);
            }
            onCommentatorsChanged(updated, isAdding: !isActive);
          },
        );
      }),
    ];
  }

  final entries = <AppContextMenuEntry>[
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
    if (onOpenPane != null || onSelectMultiple != null)
      const AppContextMenuEntry.divider(),
    AppContextMenuEntry(
      label: 'הצג את כל המפרשים',
      isSelected: allActive,
      onTap: () => onCommentatorsChanged(
        allActive ? <String>[] : List<String>.from(availableCommentators),
        isAdding: !allActive,
      ),
    ),
  ];

  for (final title in _kGroupOrder) {
    final group = buildGroup(
      CommentatorGroup.groupByTitle(commentatorGroups, title),
    );
    if (group.isEmpty) continue;
    entries.add(const AppContextMenuEntry.divider());
    entries.addAll(group);
  }

  return entries;
}
