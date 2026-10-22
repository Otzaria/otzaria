import 'package:flutter/widgets.dart';
import 'package:otzaria/book_common/selection/commentary_copy_guard.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';
import 'package:otzaria/book_common/utils/commentary_plugin_menu_entries.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/marker/services/marker_selection.dart';
import 'package:otzaria/marker/view/reader/marker_reader_menu.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// שורת הצבעים של המרקר בתפריט של קטע מפרש, לבחירה בתוך הקטע הזה בלבד, או
/// הפעולות על סימון שנלחץ בו. קטע של כמה שורות (קישור לטווח) מסומן לפי
/// השורות שלו, כשהן כבר נטענו.
///
/// [selectedText] — הבחירה באזור המפרשים, עם מעברי השורה שלה. [selectedLink]
/// — הקטע שהבחירה בו, כשידוע; [itemKeys] ו-[linkKey] מאתרים את הקטעים
/// במסך, כדי שבחירה שחוצה כמה קטעים לא תסומן כאילו היא בקטע אחד.
List<AppContextMenuEntry> buildCommentaryLinkMarkerEntries({
  required BuildContext context,
  required Link link,
  required String? selectedText,
  required Link? selectedLink,
  required Map<String, GlobalKey> itemKeys,
  required String Function(Link link) linkKey,
  required TextDisplayProfile displayProfile,
  required double fontSize,
  required Offset tapPosition,
}) {
  final content = link.loadedContent;
  if (content == null || content.isEmpty) return const [];
  final Map<int, String> known;
  if (link.index2End == null) {
    known = {link.index2 - 1: content};
  } else {
    final lines = link.loadedContentLines;
    if (lines == null || lines.isEmpty) return const [];
    known = {for (final line in lines) line.lineIndex: line.content};
  }
  final first = known.keys.reduce((a, b) => a < b ? a : b);
  final last = known.keys.reduce((a, b) => a > b ? a : b);
  final key = linkKey(link);
  String? selected;
  int? startColumn;
  final text = selectedText?.trim();
  if (text != null && text.isNotEmpty) {
    final itemKey = itemKeys[key];
    if (selectionSpansMultipleItems(itemKeys) ||
        linkKey(selectedLink ?? link) != key ||
        itemKey == null) {
      return const [];
    }
    // הטקסט מאזור הבחירה; היסטי המעקב אינם מדויקים, ומשמשים רק כרמז למופע
    // הנכון כשהמילים חוזרות בקטע. בקטע של כמה שורות הם נמדדים מתחילת הקטע
    // ולא מתחילת השורה, ולכן אינם רמז.
    final tracked = known.length == 1
        ? CommentarySelectionTracker.selectionIn(itemKey)
        : null;
    selected = text;
    startColumn = tracked == null
        ? null
        : (tracked.start < tracked.end ? tracked.start : tracked.end);
  }
  final target = commentaryTargetForLink(link);
  final book = target.book;
  if (book is! TextBook) return const [];
  final lines = markerKnownLines(known);
  List<AppContextMenuEntry> entriesAt(int section) =>
      buildCommentaryMarkerEntries(
        context: context,
        root: context.findRenderObject(),
        book: book,
        ref: target.currentRef,
        protection: () => BookProtectionRepository.instance.forLink(link),
        lines: lines,
        paragraphIndex: section,
        selectedText: selected,
        anchor: (
          lineStart: selected == null ? section : first,
          lineEnd: selected == null ? section : last,
          startColumn: startColumn,
          pointerColumn: null,
        ),
        settings: () =>
            RenderSettings.fromProfile(displayProfile, fontSize: fontSize),
        tapPosition: tapPosition,
      );
  if (selected != null) return entriesAt(first);
  // לחיצה בלי בחירה: הסימון שנלחץ, בשורה הראשונה שיש בה כזה.
  for (var section = first; section <= last; section++) {
    if (!known.containsKey(section)) continue;
    final entries = entriesAt(section);
    if (entries.isNotEmpty) return entries;
  }
  return const [];
}

/// מוסיף את פריטי המרקר לתפריט של מפרש לפני המפריד הראשון — ליד פעולות
/// ההעתקה, כמו בתפריט של הספר, ולא בתחתית התפריט.
List<AppContextMenuEntry> withMarkerEntries(
  List<AppContextMenuEntry> menu,
  List<AppContextMenuEntry> marker,
) {
  if (marker.isEmpty) return menu;
  final divider = menu.indexWhere((entry) => entry.isDivider);
  return [
    ...menu.take(divider < 0 ? menu.length : divider),
    ...marker,
    ...menu.skip(divider < 0 ? menu.length : divider),
  ];
}
