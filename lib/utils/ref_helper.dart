import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';

Future<String> refFromIndex(
    int index, Future<List<TocEntry>> tableOfContents) async {
  List<TocEntry> toc = await tableOfContents;
  List<String> texts = [];

  void searchToc(List<TocEntry> entries, int index) {
    for (final TocEntry entry in entries) {
      if (entry.index > index) {
        return;
      }
      // Guard against invalid level values, but still search children
      if (entry.level <= 0) {
        searchToc(entry.children, index);
        continue;
      }
      if (entry.level > texts.length) {
        texts.add(entry.text);
      } else {
        final targetIndex = entry.level - 1;
        // Guard against negative index
        if (targetIndex >= 0 && targetIndex < texts.length) {
          texts[targetIndex] = entry.text;
          texts = texts.getRange(0, entry.level).toList();
        }
      }

      searchToc(entry.children, index);
    }
  }

  searchToc(toc, index);

  texts = texts.map((e) => e.trim()).toList();
  return texts.join(', ');
}

/// מחזירה כתובת תצוגה מלאה ואחידה עבור ספר יעד.
///
/// אם קיימת כתובת מחושבת מתוך ה-TOC היא מועדפת, אחרת נעשה שימוש
/// בכתובת הגיבוי הקיימת. שם הספר יתווסף רק אם הוא עדיין לא חלק מהכתובת.
String formatDisplayReference({
  required String bookTitle,
  String? resolvedRef,
  String? fallbackRef,
}) {
  final normalizedResolved = _normalizeReferenceForDisplay(resolvedRef ?? '');
  final normalizedFallback = _normalizeReferenceForDisplay(fallbackRef ?? '');

  if (normalizedResolved.isNotEmpty) {
    final resolvedDisplay = addBookTitleToRef(normalizedResolved, bookTitle);
    if (normalizedFallback.isEmpty) {
      return resolvedDisplay;
    }

    final fallbackDisplay = addBookTitleToRef(normalizedFallback, bookTitle);
    return _chooseMoreSpecificReference(
      resolvedDisplay: resolvedDisplay,
      fallbackDisplay: fallbackDisplay,
    );
  }

  if (normalizedFallback.isNotEmpty) {
    return addBookTitleToRef(normalizedFallback, bookTitle);
  }

  return bookTitle;
}

String _normalizeReferenceForDisplay(String ref) {
  final parts = ref
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);

  final dedupedParts = <String>[];
  for (final part in parts) {
    if (dedupedParts.isNotEmpty && dedupedParts.last == part) {
      continue;
    }
    dedupedParts.add(part);
  }

  return dedupedParts.join(', ');
}

String _chooseMoreSpecificReference({
  required String resolvedDisplay,
  required String fallbackDisplay,
}) {
  final resolvedScore = _referenceSpecificityScore(resolvedDisplay);
  final fallbackScore = _referenceSpecificityScore(fallbackDisplay);

  if (fallbackScore > resolvedScore) {
    return fallbackDisplay;
  }

  if (fallbackScore == resolvedScore &&
      fallbackDisplay.length > resolvedDisplay.length &&
      _referencesAreRelated(resolvedDisplay, fallbackDisplay)) {
    return fallbackDisplay;
  }

  return resolvedDisplay;
}

int _referenceSpecificityScore(String ref) {
  const markers = [
    'פרק',
    'פסוק',
    'דף',
    'עמוד',
    'סימן',
    'סעיף',
    'הלכה',
    'פסקה',
    'משנה',
    'מאמר',
    'קטן',
  ];

  var score = 0;
  for (final marker in markers) {
    if (ref.contains(marker)) {
      score += 2;
    }
  }

  score += ','.allMatches(ref).length;
  score += RegExp(r'[א-ת0-9]+').allMatches(ref).length ~/ 3;
  return score;
}

bool _referencesAreRelated(String resolvedDisplay, String fallbackDisplay) {
  return fallbackDisplay.startsWith(resolvedDisplay) ||
      fallbackDisplay.contains(resolvedDisplay) ||
      resolvedDisplay.contains(fallbackDisplay);
}

/// מוסיף את שם הספר לכותרת אם הוא לא מופיע
/// ומטפל במקרים מיוחדים כמו כותרת ריקה או פסיק מיותר
String addBookTitleToRef(String ref, String bookTitle) {
  // אם הכותרת כבר מתחילה בשם הספר, לא צריך להוסיף
  if (ref.startsWith(bookTitle)) {
    return ref;
  }

  // אם הכותרת ריקה, נחזיר רק את שם הספר
  if (ref.trim().isEmpty) {
    return bookTitle;
  }

  // אחרת, נוסיף את שם הספר עם פסיק
  return '$bookTitle, $ref';
}

Future<String> refFromPageNumber(
  int pageNumber,
  List<PdfOutlineNode>? outline, [
  String? bookTitle,
]) async {
  if (outline == null) return "";

  List<String> texts = [];

  void searchOutline(List<PdfOutlineNode> entries, {int level = 0}) {
    for (final entry in entries) {
      if (entry.dest?.pageNumber == null ||
          entry.dest!.pageNumber > pageNumber) {
        return;
      }
      if (level + 1 > texts.length) {
        texts.add(entry.title);
      } else {
        texts[level] = entry.title;
        texts = texts.getRange(0, level + 1).toList();
      }

      searchOutline(
        entry.children,
        level: level + 1,
      );
    }
  }

  searchOutline(outline);
  texts = texts.map((e) => e.trim()).toList();
  if (bookTitle != null && texts.isNotEmpty && texts.first == bookTitle) {
    texts = texts.sublist(1);
  }
  return texts.join(', ');
}

/// Returns the index of the last [TocEntry] whose [index] is less than or equal
/// to [targetIndex]. If no such entry exists, returns `null`.
int? closestTocEntryIndex(List<TocEntry> entries, int targetIndex) {
  TocEntry? closest;

  void search(List<TocEntry> toc) {
    for (final entry in toc) {
      if (entry.index <= targetIndex) {
        if (closest == null || entry.index > closest!.index) {
          closest = entry;
        }
        search(entry.children);
      }
    }
  }

  search(entries);
  return closest?.index;
}
