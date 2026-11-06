/// Pure, I/O-free matching and interpolation logic for the PDF↔text page map.
/// Extracted so it can be unit-tested without any Flutter or file-system setup.
library;

import 'package:otzaria/utils/text/numeral_formats.dart';

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
  int? pdfToText(int page) => _interpolate(pdfPages, textIndices, page);

  /// Converts a text index to a PDF page via binary search + linear interpolation.
  int? textToPdf(int index) => _interpolate(textIndices, pdfPages, index);

  static int? _interpolate(List<int> from, List<int> to, int x) {
    if (from.isEmpty) return null;
    final i = _lowerBound(from, x);
    if (i == 0) return to.first;
    if (i >= from.length) return to.last;
    final fromA = from[i - 1], fromB = from[i];
    final toA = to[i - 1], toB = to[i];
    if (fromB == fromA) return toA;
    return toA + ((x - fromA) * (toB - toA) / (fromB - fromA)).round();
  }

  static int _lowerBound(List<int> a, int x) {
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
  final collapsed = s
      .replaceAll(RegExp(r'[־‐-―]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ');
  return stripNonRefChars(collapsed).toLowerCase().trim();
}

final _nonRefChars = RegExp(r'[^\p{L}\p{N}\s/.-]', unicode: true);

/// מסיר מ-[s] את מה שאינו אות, ספרה, רווח או `/.-`, כמו [_nonRefChars].
/// ה-regex היוניקודי איטי (פי 7), ולכן עברית ו-ASCII מסווגים כאן והשאר עובר אליו.
String stripNonRefChars(String s) {
  final kept = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if ((c >= 0x30 && c <= 0x39) ||
        ((c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A) ||
        (c >= 0x09 && c <= 0x0D) ||
        c == 0x20 ||
        (c >= 0x2D && c <= 0x2F) ||
        (c >= 0x5D0 && c <= 0x5EA) ||
        (c >= 0x5EF && c <= 0x5F2)) {
      kept.writeCharCode(c);
    } else if (!(c < 0x80 ||
        (c >= 0x591 && c <= 0x5C7) ||
        c == 0x5F3 ||
        c == 0x5F4)) {
      if (i == 0) return s.replaceAll(_nonRefChars, '');
      kept.write(s.substring(i).replaceAll(_nonRefChars, ''));
      break;
    }
  }
  return kept.toString();
}

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
    final value = hebrewLetterValues[ch];
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
