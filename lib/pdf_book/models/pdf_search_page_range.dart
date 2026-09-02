/// טווח עמודים (1-based, כולל) שאליו מוגבל החיפוש בתוך ספר PDF.
class PdfSearchPageRange {
  final int firstPage;
  final int lastPage;

  const PdfSearchPageRange(this.firstPage, this.lastPage);

  bool contains(int page) => page >= firstPage && page <= lastPage;

  String get label =>
      firstPage == lastPage ? 'עמוד $firstPage' : 'עמודים $firstPage–$lastPage';

  /// מנרמל קלט חופשי משדות "מעמוד"/"עד עמוד": שני שדות ריקים — אין טווח;
  /// שדה ריק — קצה הספר; סדר הפוך מתוקן; הערכים נחתכים ל-1..[totalPages].
  static PdfSearchPageRange? parse({
    required String from,
    required String to,
    required int totalPages,
  }) {
    final first = int.tryParse(from.trim());
    final last = int.tryParse(to.trim());
    if (first == null && last == null) return null;
    if (totalPages < 1) return null;

    var start = (first ?? 1).clamp(1, totalPages);
    var end = (last ?? totalPages).clamp(1, totalPages);
    if (end < start) {
      final swapped = start;
      start = end;
      end = swapped;
    }
    if (start == 1 && end == totalPages) return null;
    return PdfSearchPageRange(start, end);
  }
}
