import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';

/// פריט ברשימת המפרשים השטוחה: כותרת קבוצה (כש-[link] הוא null) או קטע מפרש
/// בודד. [showDivider] — הפריט האחרון של הקבוצה (המפריד מצויר אחריו).
class CommentaryFlatItem {
  final LinkGroup group;
  final Link? link;
  final Link? previousVisibleLink;
  final bool showDivider;

  const CommentaryFlatItem({
    required this.group,
    this.link,
    this.previousVisibleLink,
    required this.showDivider,
  });
}

/// בונה את פריטי הרשימה השטוחה: פריט כותרת לכל קבוצה, ופריט לכל קטע רק
/// בקבוצה מורחבת — כך הרשימה נבנית בעצלנות (issue #844). [headerIndexOut]
/// ו-[linkIndexOut] מקבלים את מיפוי האינדקסים לגלילה.
/// כשניתן [isLinkVisible], נשמר גם הקישור המוצג הקודם באותה קבוצה.
List<CommentaryFlatItem> buildCommentaryFlatItems({
  required List<LinkGroup> groups,
  required bool Function(String bookTitle) isGroupExpanded,
  required String Function(Link link) linkKey,
  required Map<String, int> headerIndexOut,
  required Map<String, int> linkIndexOut,
  bool Function(String key)? isLinkVisible,
}) {
  final items = <CommentaryFlatItem>[];
  for (final group in groups) {
    final expanded = isGroupExpanded(group.bookTitle);
    headerIndexOut[group.bookTitle] = items.length;
    items.add(CommentaryFlatItem(group: group, showDivider: !expanded));
    if (!expanded) continue;
    final indexPrevious = isLinkVisible != null && group.links.length > 1;
    final previousByLink = indexPrevious ? <Link, Link?>{} : null;
    Link? previousVisible;
    for (int i = 0; i < group.links.length; i++) {
      final link = group.links[i];
      final key = linkKey(link);
      linkIndexOut[key] = items.length;
      // כפילות של אותו קישור משתמשת בקודם של המופע הראשון.
      final previous = previousByLink?.putIfAbsent(link, () => previousVisible);
      if (indexPrevious && isLinkVisible(key)) previousVisible = link;
      items.add(
        CommentaryFlatItem(
          group: group,
          link: link,
          previousVisibleLink: previous,
          showDivider: i == group.links.length - 1,
        ),
      );
    }
  }
  return items;
}

/// כותרת הקבוצה שהפריט [flatIndex] שייך לה, לפי מיפוי הכותרות
/// [headerIndexes] (כותרת → אינדקס ברשימה השטוחה) — הכותרת הקרובה ביותר מעליו.
String? groupTitleAtFlatIndex(Map<String, int> headerIndexes, int flatIndex) {
  String? title;
  int best = -1;
  headerIndexes.forEach((groupTitle, index) {
    if (index <= flatIndex && index > best) {
      best = index;
      title = groupTitle;
    }
  });
  return title;
}
