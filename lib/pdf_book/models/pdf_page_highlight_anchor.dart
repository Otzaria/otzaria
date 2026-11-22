/// בחירה שנשמרת בטאב בלי להחזיק טקסט/גיאומטריה של עמוד שלם.
class PdfPageHighlightAnchor {
  const PdfPageHighlightAnchor({
    required this.pageNumber,
    required this.start,
    required this.end,
    required this.query,
  });

  final int pageNumber;
  final int start;
  final int end;
  final String query;
}
