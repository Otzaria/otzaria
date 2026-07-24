/// Pure, I/O-free matching and interpolation logic for the PDF↔text page map.
/// Extracted so it can be unit-tested without any Flutter or file-system setup.
library;

/// Holds matched anchor pairs and interpolates between them.
class PageMap {
  /// Sorted PDF page numbers (1-based).
  final List<int> pdfPages;

  /// Sorted text indices (0-based), parallel to [pdfPages].
  final List<int> textIndices;

  PageMap(this.pdfPages, this.textIndices);

  /// A single anchor is not reliable enough for cross-navigation.
  bool get hasReliableAnchors =>
      pdfPages.length >= 2 && textIndices.length >= 2;

  /// Converts a PDF page to a text index via binary search + linear interpolation.
  int? pdfToText(int page) {
    if (pdfPages.isEmpty) return null;
    final i = _lowerBound(pdfPages, page);
    if (i == 0) return textIndices.first;
    if (i >= pdfPages.length) return textIndices.last;
    final pA = pdfPages[i - 1], pB = pdfPages[i];
    final tA = textIndices[i - 1], tB = textIndices[i];
    if (pB == pA) return tA;
    return tA + ((page - pA) * (tB - tA) / (pB - pA)).round();
  }

  /// Converts a text index to a PDF page via binary search + linear interpolation.
  int? textToPdf(int index) {
    if (textIndices.isEmpty) return null;
    final i = _lowerBound(textIndices, index);
    if (i == 0) return pdfPages.first;
    if (i >= textIndices.length) return pdfPages.last;
    final tA = textIndices[i - 1], tB = textIndices[i];
    final pA = pdfPages[i - 1], pB = pdfPages[i];
    if (tB == tA) return pA;
    return pA + ((index - tA) * (pB - pA) / (tB - tA)).round();
  }

  int _lowerBound(List<int> a, int x) {
    var lo = 0, hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Normalizes a ref string for comparison (collapses whitespace, strips
/// characters that differ only in punctuation style, lowercases).
String normalizeRef(String s) {
  return s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s/.-]', unicode: true), '')
      .toLowerCase()
      .trim();
}

/// Builds a [PageMap] from pre-collected anchor lists.
///
/// Matching strategy (most-specific first):
/// 1. Full normalized path match (e.g. "ברכות/ב." == "ברכות/ב.")
/// 2. Suffix-path fallback: for each PDF anchor, try progressively shorter
///    suffixes of its path and accept the first suffix that maps to exactly
///    **one** text index (unambiguous). This handles the common case where the
///    PDF outline has extra top-level nodes not present in the text TOC, e.g.:
///      PDF  "תלמוד בבלי/ברכות/ב."
///      Text "ברכות/ב."   ← matched via 2-component suffix
///    Ambiguous leaves ("הקדמה", "א", "ב" appearing in many tractates) are
///    safely skipped because they map to more than one text index.
PageMap buildPageMapFromAnchors(
  List<({int page, String ref})> anchorsPdf,
  List<({int index, String ref})> anchorsText,
) {
  final mapTextByRef = <String, int>{};
  final mapTextBySuffix = <String, List<int>>{};

  for (final a in anchorsText) {
    mapTextByRef[a.ref] = a.index;
    final parts = a.ref.split('/');
    for (var i = 0; i < parts.length; i++) {
      final suffix = parts.sublist(i).join('/');
      (mapTextBySuffix[suffix] ??= []).add(a.index);
    }
  }

  final pdfPages = <int>[];
  final textIndices = <int>[];

  for (final p in anchorsPdf) {
    int? idx = mapTextByRef[p.ref];

    if (idx == null) {
      final pdfParts = p.ref.split('/');
      for (var i = 0; i < pdfParts.length && idx == null; i++) {
        final suffix = pdfParts.sublist(i).join('/');
        final matches = mapTextBySuffix[suffix];
        if (matches != null && matches.length == 1) {
          idx = matches.first;
        }
      }
    }

    if (idx != null &&
        !pdfPages.contains(p.page) &&
        !textIndices.contains(idx)) {
      pdfPages.add(p.page);
      textIndices.add(idx);
    }
  }

  // Sort by PDF page number so interpolation works correctly.
  final zipped = List.generate(
    pdfPages.length,
    (i) => (page: pdfPages[i], idx: textIndices[i]),
  );
  zipped.sort((a, b) => a.page.compareTo(b.page));

  return PageMap(
    zipped.map((e) => e.page).toList(),
    zipped.map((e) => e.idx).toList(),
  );
}
