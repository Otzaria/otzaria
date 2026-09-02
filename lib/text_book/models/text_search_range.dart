import 'package:otzaria/models/books.dart';

/// טווח שורות לחיפוש בתוך ספר טקסט, הנגזר מכותרות תוכן העניינים: מכותרת
/// ההתחלה ועד סוף הענף של כותרת הסיום (או של ההתחלה עצמה כשאין סיום).
class TextSearchRange {
  final int startLine;

  /// השורה הראשונה שמחוץ לטווח; `null` — עד סוף הספר.
  final int? endLine;
  final String label;

  const TextSearchRange({
    required this.startLine,
    required this.endLine,
    required this.label,
  });

  bool contains(int line) =>
      line >= startLine && (endLine == null || line < endLine!);

  /// [end] ריק — הטווח הוא ענף [start] בלבד. סדר הפוך של הכותרות מתוקן.
  factory TextSearchRange.fromToc({
    required List<TocEntry> toc,
    required TocEntry start,
    TocEntry? end,
  }) {
    var first = start;
    var last = end ?? start;
    if (last.index < first.index) {
      final swapped = first;
      first = last;
      last = swapped;
    }
    final label = first.index == last.index
        ? first.fullText
        : '${first.fullText} — ${last.fullText}';
    return TextSearchRange(
      startLine: first.index,
      endLine: branchEndLine(toc, last),
      label: label,
    );
  }

  /// השורה הראשונה אחרי הענף של [entry] — הכותרת הבאה ברמה שווה או גבוהה
  /// יותר — או `null` כשהענף נמשך עד סוף הספר.
  static int? branchEndLine(List<TocEntry> toc, TocEntry entry) {
    for (final candidate in flattenToc(toc)) {
      if (candidate.index > entry.index && candidate.level <= entry.level) {
        return candidate.index;
      }
    }
    return null;
  }
}

/// הכותרות שמהן בוחרים טווח: כל העץ בסדר הספר, בלי שורש שם הספר.
List<TocEntry> searchRangeHeadings(List<TocEntry> toc) {
  final flat = flattenToc(toc);
  if (flat.isNotEmpty && flat.first.level <= 1 && flat.first.parent == null) {
    return flat.sublist(1);
  }
  return flat;
}
