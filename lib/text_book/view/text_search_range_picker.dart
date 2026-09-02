import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/models/text_search_range.dart';
import 'package:otzaria/widgets/dialogs/selection_dialog.dart';

/// בחירת הכותרת שסוגרת את הטווח; `entry` ריק — ענף ההתחלה בלבד.
class _RangeEnd {
  final TocEntry? entry;
  const _RangeEnd(this.entry);
}

/// שני דיאלוגי בחירה עוקבים — כותרת ההתחלה ואז כותרת הסיום — ומחזיר את
/// הטווח שנבחר, או `null` אם המשתמש ביטל באחד מהם.
Future<TextSearchRange?> pickTextSearchRange({
  required BuildContext context,
  required List<TocEntry> toc,
}) async {
  final headings = searchRangeHeadings(toc);
  if (headings.isEmpty) return null;

  final start = await showSelectionDialog<TocEntry>(
    context: context,
    title: 'תחילת הטווח',
    searchHint: 'איתור כותרת...',
    items: [
      for (final heading in headings)
        SelectionItem(label: heading.fullText, value: heading),
    ],
  );
  if (start == null || !context.mounted) return null;

  final following = headings.where((h) => h.index > start.index).toList();
  var end = const _RangeEnd(null);
  if (following.isNotEmpty) {
    final chosen = await showSelectionDialog<_RangeEnd>(
      context: context,
      title: 'סוף הטווח',
      searchHint: 'איתור כותרת...',
      items: [
        SelectionItem(label: '"${start.text}" בלבד', value: end),
        for (final heading in following)
          SelectionItem(label: heading.fullText, value: _RangeEnd(heading)),
      ],
    );
    if (chosen == null) return null;
    end = chosen;
  }

  return TextSearchRange.fromToc(toc: toc, start: start, end: end.entry);
}
