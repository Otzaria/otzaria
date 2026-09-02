import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/models/text_search_range.dart';
import 'package:otzaria/widgets/dialogs/selection_dialog.dart';

/// תווית האפשרות שמחזירה את החיפוש לכל הספר.
const String kSearchWholeBookLabel = 'כל הספר — ביטול הגבלת הטווח';

/// בחירת כותרת בדיאלוג; `entry` ריק — "כל הספר" (בהתחלה) או "ענף ההתחלה
/// בלבד" (בסיום).
class _HeadingChoice {
  final TocEntry? entry;
  const _HeadingChoice(this.entry);
}

/// שני דיאלוגי בחירה עוקבים — כותרת ההתחלה ואז כותרת הסיום. מחזיר
/// `(range: null)` כשנבחר "כל הספר", ו-`null` אם המשתמש ביטל באחד מהם.
/// [hasActiveRange] מוסיף לדיאלוג הראשון את האפשרות לחזור לכל הספר.
Future<({TextSearchRange? range})?> pickTextSearchRange({
  required BuildContext context,
  required List<TocEntry> toc,
  bool hasActiveRange = false,
}) async {
  final headings = searchRangeHeadings(toc);
  if (headings.isEmpty) return null;

  const wholeBook = _HeadingChoice(null);
  final start = await showSelectionDialog<_HeadingChoice>(
    context: context,
    title: 'תחילת הטווח',
    searchHint: 'איתור כותרת...',
    items: [
      if (hasActiveRange)
        const SelectionItem(label: kSearchWholeBookLabel, value: wholeBook),
      for (final heading in headings)
        SelectionItem(label: heading.fullText, value: _HeadingChoice(heading)),
    ],
  );
  if (start == null || !context.mounted) return null;
  final startEntry = start.entry;
  if (startEntry == null) return (range: null);

  final following = headings.where((h) => h.index > startEntry.index).toList();
  var end = const _HeadingChoice(null);
  if (following.isNotEmpty) {
    final chosen = await showSelectionDialog<_HeadingChoice>(
      context: context,
      title: 'סוף הטווח',
      searchHint: 'איתור כותרת...',
      items: [
        SelectionItem(label: '"${startEntry.text}" בלבד', value: end),
        for (final heading in following)
          SelectionItem(
            label: heading.fullText,
            value: _HeadingChoice(heading),
          ),
      ],
    );
    if (chosen == null) return null;
    end = chosen;
  }

  return (
    range: TextSearchRange.fromToc(
      toc: toc,
      start: startEntry,
      end: end.entry,
    ),
  );
}
