import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath;
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// כותרת תת-התפריט "מפרשים" בתפריט ההקשר של גוף הספר.
const String kParagraphCommentatorsMenuLabel = 'מפרשים על פסקה זו';

/// מטמון את מפרשי הפסקה ואת שאר קישוריה, שנטענו בשאילת טווח.
///
/// [changes] מאפשר לתת־התפריט הפתוח להתעדכן כשהשאילתה מסתיימת.
class ParagraphCommentatorsCache {
  final Map<(Object, int), List<String>> _values = {};
  final Map<(Object, int), List<Link>> _referenceLinks = {};
  final Set<(Object, int)> _pending = {};
  final StreamController<Object?> _changes = StreamController.broadcast();

  Stream<Object?> get changes => _changes.stream;

  List<String>? value(TextBook book, int paragraphIndex) =>
      _values[_key(book, paragraphIndex)];

  /// קישורי הפסקה שאינם מפרשים — לתת-התפריט "קישורים".
  List<Link>? referenceLinks(TextBook book, int paragraphIndex) =>
      _referenceLinks[_key(book, paragraphIndex)];

  bool isLoading(TextBook book, int paragraphIndex) =>
      _pending.contains(_key(book, paragraphIndex));

  Future<void> prefetch({
    required TextBookRepository repository,
    required TextBook book,
    required int paragraphIndex,
  }) async {
    final key = _key(book, paragraphIndex);
    if (_values.containsKey(key) || !_pending.add(key)) return;
    try {
      final links = await repository.getBookLinksInRange(
        book,
        startIndex: paragraphIndex,
        endIndex: paragraphIndex,
        targetBookTitles: null,
      );
      final referenceLinks = [
        for (final link in links)
          if (!LinkTypes.isDependentTextLink(link.connectionType)) link,
      ];
      // המיון בתפריט סינכרוני — הדורות חייבים להיות במטמון לפני ההודעה.
      await CommentaryService.preloadErasForLinks(
        referenceLinks,
      ).catchError((_) {});
      _values[key] = {
        for (final link in links)
          if (LinkTypes.isDependentTextLink(link.connectionType))
            getTitleFromPath(link.path2),
      }.toList();
      _referenceLinks[key] = referenceLinks;
    } finally {
      _pending.remove(key);
      if (!_changes.isClosed) _changes.add(key);
    }
  }

  (Object, int) _key(TextBook book, int paragraphIndex) => (
    (
      book.id,
      book.title,
      book.source.wireKey,
      book.categoryId,
      book.fileType,
      book.versionTitle,
    ),
    paragraphIndex,
  );

  void dispose() => _changes.close();
}

/// המפרשים מתוך [availableCommentators] שיש להם תוכן על הפסקה [paragraphIndex].
/// [queriedCommentators] מגיע משאילתת הטווח; [linksByLine] מצרף קישורים
/// מקומיים, לרבות ספרי משתמש. הערות inline מצרפות את [kNotesCommentatorTitle].
List<String> paragraphCommentators({
  required List<String> availableCommentators,
  required List<String> content,
  required int paragraphIndex,
  required Map<int, List<Link>> linksByLine,
  List<String>? queriedCommentators,
}) {
  final onParagraph = queriedCommentators?.toSet() ?? <String>{};
  for (final link in linksByLine[paragraphIndex + 1] ?? const <Link>[]) {
    if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
    onParagraph.add(getTitleFromPath(link.path2));
  }
  if (inline_notes.notesForLines(content, [paragraphIndex]).isNotEmpty) {
    onParagraph.add(kNotesCommentatorTitle);
  }
  return availableCommentators.where(onParagraph.contains).toList();
}

/// קישורי תת-התפריט "קישורים": [linksByLine] (חלון הטעינה) מאוחד עם
/// [queriedLinks] (שאילתת הפסקה), בלי מפרשים וקישורים פנימיים, לפי דורות.
List<Link> paragraphReferenceLinks({
  required Map<int, List<Link>> linksByLine,
  required int paragraphIndex,
  List<Link>? queriedLinks,
}) {
  final seen =
      <(int, String, int, BookSource, int?, int?, String?, int?, String)>{};
  final links = [
    for (final link in [
      ...?linksByLine[paragraphIndex + 1],
      ...?queriedLinks,
    ])
      if (!LinkTypes.isDependentTextLink(link.connectionType) &&
          link.start == null &&
          link.end == null &&
          seen.add((
            link.index1,
            link.path2,
            link.index2,
            link.targetSource,
            link.targetBookId,
            link.targetCategoryId,
            link.targetFileType,
            link.index2End,
            link.connectionType,
          )))
        link,
  ];
  return CommentaryService.sortLinksByEraSync(links);
}

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

/// בונה את פריטי תת-התפריט "מפרשים על פסקה זו" בתפריט ההקשר של גוף הספר.
///
/// משותף לתצוגה המשולבת/מפוצלת ולצורת הדף, כדי ששלושתן יציגו את אותם פריטים
/// ואותה התנהגות. [availableCommentators] הם מפרשי הפסקה בלבד (ראו
/// [paragraphCommentators]); הקבוצות מסוננות לפיהם.
///
/// [onOpenPane] ו-[onSelectMultiple] אינם מוצגים כשהם `null`. כשאין מפרשים
/// לפסקה מוחזר רק פריט "טוען…" מושבת בזמן [linksLoading], ואחריו
/// רשימה ריקה — כך הפריט האב מתאפר (issue #1413).
List<AppContextMenuEntry> buildCommentatorsContextMenuChildren({
  required List<String> activeCommentators,
  required List<String> availableCommentators,
  required List<CommentatorGroup> commentatorGroups,
  required CommentatorsSelectionChanged onCommentatorsChanged,
  VoidCallback? onOpenPane,
  VoidCallback? onSelectMultiple,
  bool linksLoading = false,
}) {
  final activeSet = activeCommentators.toSet();
  final availableSet = availableCommentators.toSet();
  final allActive = activeSet.containsAll(availableCommentators);

  List<AppContextMenuEntry> buildGroup(CommentatorGroup group) {
    final commentators = group.commentators.where(availableSet.contains);
    if (commentators.isEmpty) return const <AppContextMenuEntry>[];
    final groupActive = commentators.every(activeSet.contains);
    return [
      AppContextMenuEntry(
        label: 'הצג את כל ${group.title}',
        isSelected: groupActive,
        onTap: () {
          final updated = List<String>.from(activeCommentators);
          if (groupActive) {
            updated.removeWhere(commentators.contains);
          } else {
            for (final title in commentators) {
              if (!updated.contains(title)) updated.add(title);
            }
          }
          onCommentatorsChanged(updated, isAdding: !groupActive);
        },
      ),
      ...commentators.map((title) {
        final isActive = activeSet.contains(title);
        return AppContextMenuEntry(
          label: title,
          isSelected: isActive,
          onTap: () {
            // מפרש פעיל אינו מוסר מכאן — לחיצה עליו רק פותחת את החלונית.
            // הסרה שקטה גרמה ללולאת הוסף/הסר בכל ניסיון חוזר (issue #904).
            final updated = List<String>.from(activeCommentators);
            if (!isActive) updated.add(title);
            onCommentatorsChanged(updated, isAdding: true);
          },
        );
      }),
    ];
  }

  if (availableCommentators.isEmpty) {
    return linksLoading
        ? const [AppContextMenuEntry(label: 'טוען מפרשים…', enabled: false)]
        : const <AppContextMenuEntry>[];
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
      label: 'הצג את כל המפרשים על פסקה זו',
      isSelected: allActive,
      onTap: () => onCommentatorsChanged(
        allActive ? <String>[] : List<String>.from(availableCommentators),
        isAdding: !allActive,
      ),
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

  return entries;
}
