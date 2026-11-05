/// An exact selection in the displayed quote. These offsets never refer to
/// HTML and are never applied as a structured source correction.
class BookReportSelection {
  const BookReportSelection(this.start, this.end);
  final int start;
  final int end;

  static BookReportSelection? unique(String source, String selection) {
    if (selection.isEmpty) return null;
    final start = source.indexOf(selection);
    if (start < 0 || source.indexOf(selection, start + 1) >= 0) return null;
    final range = BookReportSelection(start, start + selection.length);
    return range.isValidFor(source) ? range : null;
  }

  bool isValidFor(String text) =>
      start >= 0 &&
      end > start &&
      end <= text.length &&
      !_splitsSurrogate(text, start) &&
      !_splitsSurrogate(text, end);

  String selectedText(String text) => text.substring(start, end);

  String contextText(String text) {
    final before = RegExp(r'\S+').allMatches(text.substring(0, start)).toList();
    final after = RegExp(
      r'\S+',
    ).allMatches(text.substring(end)).take(4).toList();
    final from = before.length > 4 ? before[before.length - 4].start : 0;
    final to = after.isEmpty ? end : end + after.last.end;
    // Put the exact range first so bounded display fields cannot discard it.
    // Very long source lines retain an explicitly positioned excerpt, rather
    // than labelling a truncated source as the full original.
    final location =
        'מיקום מסומן בציטוט המוצג: תווים $start–$end מתוך ${text.length} '
        '(UTF-16, התחלה 0, סוף לא כלול).';
    final excerpt = text.substring(from, to);
    if (text.length > 16000) {
      return '$location\nקטע סביב הבחירה (תווים $from–$to):\n$excerpt';
    }
    return '$location\n$excerpt\nהקטע המוצג המלא:\n$text';
  }

  static bool _splitsSurrogate(String text, int offset) =>
      offset > 0 &&
      offset < text.length &&
      text.codeUnitAt(offset - 1) >= 0xd800 &&
      text.codeUnitAt(offset - 1) <= 0xdbff &&
      text.codeUnitAt(offset) >= 0xdc00 &&
      text.codeUnitAt(offset) <= 0xdfff;
}
