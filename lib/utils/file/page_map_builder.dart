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
///
/// Dashes are folded to ASCII `-` first: stripping a maqaf or en-dash instead
/// would glue "דף כב־א" into "דף כבא" and read it as daf 23.
String normalizeRef(String s) {
  return s
      .replaceAll(RegExp(r'[־‐-―]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s/.-]', unicode: true), '')
      .toLowerCase()
      .trim();
}

/// ערכי אותיות הגימטריה (כולל אותיות סופיות).
const _hebrewNumeralValues = <String, int>{
  'א': 1,
  'ב': 2,
  'ג': 3,
  'ד': 4,
  'ה': 5,
  'ו': 6,
  'ז': 7,
  'ח': 8,
  'ט': 9,
  'י': 10,
  'כ': 20,
  'ך': 20,
  'ל': 30,
  'מ': 40,
  'ם': 40,
  'נ': 50,
  'ן': 50,
  'ס': 60,
  'ע': 70,
  'פ': 80,
  'ף': 80,
  'צ': 90,
  'ץ': 90,
  'ק': 100,
  'ר': 200,
  'ש': 300,
  'ת': 400,
};

/// ערך הגימטריה של [letters], או null אם אינו מספר עברי תקין.
///
/// תקינות = ערכי האותיות אינם עולים, כמו בכתיב גימטריה ("כב"). זה דוחה את רוב
/// המילים, אך לא את כולן ("תמיד"=454) — ולכן [canonicalDafKey] דורש בנוסף
/// קידומת "דף" או סימן עמוד.
int? hebrewNumeralValue(String letters) {
  if (letters.isEmpty || letters.length > 4) return null;
  var sum = 0;
  var previous = 400;
  for (final ch in letters.split('')) {
    final value = _hebrewNumeralValues[ch];
    if (value == null || value > previous) return null;
    sum += value;
    previous = value;
  }
  return sum;
}

/// A "דף" label: the literal prefix, a numeral, and an optional amud marker.
final _dafLabelPattern = RegExp(
  r'^דף\s+([א-ת]{1,4})\s*(?:-\s*)?(\.|ע?[אב]|עמוד\s*[אב])?$',
);

/// Canonical key for a Talmud daf from a **normalized** ([normalizeRef]) label —
/// "22a"/"22b", or null when the label is not a daf.
///
/// Unifies spellings of the same daf: "דף כב.", "דף כב ע\"א", "דף כב - א" → "22a".
/// [normalizeRef] strips the colon, so a missing marker means amud bet.
///
/// The literal "דף" prefix is required: without it, chapter/siman labels
/// ("א.", "ב.") and words whose gematria is valid ("תמיד.") would be read as
/// dafim and produce a plausible-looking but wrong map.
String? canonicalDafKey(String ref) {
  final match = _dafLabelPattern.firstMatch(ref.trim());
  if (match == null) return null;
  final number = hebrewNumeralValue(match.group(1)!);
  if (number == null) return null;
  final marker = match.group(2);
  final isAmudAlef = marker == '.' || (marker != null && marker.endsWith('א'));
  return '$number${isAmudAlef ? 'a' : 'b'}';
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
/// 3. Canonical daf fallback ([canonicalDafKey]) — bridges editions that spell
///    the same daf differently ("דף כב." בצד אחד, "דף כב - א" בשני), שאחרת
///    נותנות אפס התאמות. רץ כמעבר שני ורק כששלבים 1-2 לא הפיקו מיפוי שמיש,
///    כדי שספר שההתאמה בו כבר עובדת לא ייגע בהיוריסטיקה הזאת.
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

  int? matchByPath(String ref) {
    final exact = mapTextByRef[ref];
    if (exact != null) return exact;
    final parts = ref.split('/');
    for (var i = 0; i < parts.length; i++) {
      final matches = mapTextBySuffix[parts.sublist(i).join('/')];
      if (matches != null && matches.length == 1) {
        return matches.first;
      }
    }
    return null;
  }

  final byPath = _zipAnchors(anchorsPdf, matchByPath);
  if (byPath.hasReliableAnchors) {
    return byPath;
  }

  final mapTextByDaf = <String, List<int>>{};
  for (final a in anchorsText) {
    final daf = canonicalDafKey(a.ref.split('/').last);
    if (daf != null) {
      (mapTextByDaf[daf] ??= []).add(a.index);
    }
  }
  if (mapTextByDaf.isEmpty) {
    return byPath;
  }

  final withDaf = _zipAnchors(anchorsPdf, (ref) {
    final path = matchByPath(ref);
    if (path != null) return path;
    final daf = canonicalDafKey(ref.split('/').last);
    final matches = daf == null ? null : mapTextByDaf[daf];
    return matches != null && matches.length == 1 ? matches.first : null;
  });
  return withDaf.hasReliableAnchors ? withDaf : byPath;
}

/// מזווג עוגני PDF לאינדקסי טקסט לפי [resolve], בלי כפילויות בשני הצדדים,
/// וממוין לפי עמוד ה-PDF כדי שהאינטרפולציה תעבוד.
PageMap _zipAnchors(
  List<({int page, String ref})> anchorsPdf,
  int? Function(String ref) resolve,
) {
  final usedPages = <int>{};
  final usedIndices = <int>{};
  final matched = <({int page, int idx})>[];

  for (final p in anchorsPdf) {
    final idx = resolve(p.ref);
    if (idx == null || !usedPages.add(p.page)) continue;
    if (!usedIndices.add(idx)) {
      usedPages.remove(p.page);
      continue;
    }
    matched.add((page: p.page, idx: idx));
  }

  matched.sort((a, b) => a.page.compareTo(b.page));
  return PageMap(
    matched.map((e) => e.page).toList(),
    matched.map((e) => e.idx).toList(),
  );
}
