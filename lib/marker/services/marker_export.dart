import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/personal_notes/utils/note_print_html.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

/// תאריך עברי ולצדו הלועזי, כמו בתוסף המרקר.
String markerDateLabel(DateTime date) {
  final local = date.toLocal();
  return '${getHebrewDateFormattedAsString(local)} · '
      '${local.day}.${local.month}.${local.year}';
}

/// בלוקי הדפסה לרשימת סימונים, למסך ההדפסה ולייצוא לוורד: כותרת לכל ספר,
/// ותחתיה כל סימון על רקע בצבע שלו, עם מראה המקום, ההערה והתגיות. הסדר הוא
/// סדר הרשימה: הספרים לפי הסימון הראשון של כל אחד, והסימונים כפי שמוינו.
List<PrintBlock> markerPrintBlocks(
  List<MarkerHighlight> highlights, {
  MarkerPalette? palette,
}) {
  final byBook = <String, List<MarkerHighlight>>{};
  for (final mark in highlights) {
    byBook.putIfAbsent(mark.bookTitle, () => []).add(mark);
  }
  final sorted = [for (final marks in byBook.values) ...marks];
  final blocks = <PrintBlock>[
    PrintBlock(
      kind: PrintBlockKind.text,
      text: escapePrintHtml(
        '${_count(sorted.length)} · ${markerDateLabel(DateTime.now())}',
      ),
    ),
  ];
  String? book;
  for (final mark in sorted) {
    if (mark.bookTitle != book) {
      book = mark.bookTitle;
      blocks.add(
        PrintBlock(
          kind: PrintBlockKind.heading,
          headingLevel: 1,
          text: escapePrintHtml(mark.bookTitle),
        ),
      );
    }
    final color = palette?.colorById(mark.colorId);
    final argb = color?.argb ?? MarkerColor.argbOf(mark.colorHex);
    blocks.add(
      PrintBlock(
        kind: PrintBlockKind.text,
        text: escapePrintHtml(mark.text),
        accent: PrintAccent(argb, PrintAccentStyle.filled),
      ),
    );
    final ref = mark.ref?.trim();
    final details = [
      if (ref != null && ref.isNotEmpty) ref,
      ?color?.label,
      markerDateLabel(mark.createdAt),
      if (mark.favorite) 'מועדף',
      if (mark.tags.isNotEmpty) 'תגיות: ${mark.tags.join(', ')}',
    ];
    blocks.add(
      PrintBlock(
        kind: PrintBlockKind.text,
        text: escapePrintHtml(details.join(' · ')),
        accent: PrintAccent(argb, PrintAccentStyle.detail),
      ),
    );
    if (mark.hasNote) {
      final note = mark.note!;
      for (final paragraph in noteHtmlParagraphs(
        content: note.content,
        contentPlain: note.plain,
        format: note.format,
      )) {
        if (paragraph.trim().isEmpty) continue;
        blocks.add(
          PrintBlock(
            kind: PrintBlockKind.text,
            text: paragraph,
            accent: PrintAccent(argb, PrintAccentStyle.body),
          ),
        );
      }
    }
  }
  return blocks;
}

String _count(int count) => count == 1 ? 'סימון אחד' : '$count סימונים';
