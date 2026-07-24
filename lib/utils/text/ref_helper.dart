import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';

Future<String> refFromIndex(
  int index,
  Future<List<TocEntry>> tableOfContents,
) async {
  return refFromTocList(index, await tableOfContents);
}

/// הגרסה הסינכרונית של [refFromIndex]: מחשבת את הכתובת ההיררכית עבור שורה
/// [index] מתוך רשימת תוכן עניינים שכבר נטענה לזיכרון. נחוצה למקומות שצריכים
/// חישוב מיידי בלי `await` (למשל תווית יעד ברחיפה מעל פס הגלילה), והחישוב
/// עצמו הוא רקורסיה זולה על העץ עם עצירה מוקדמת.
String refFromTocList(int index, List<TocEntry> toc) {
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
      // ממקמים כל כותרת לפי הרמה האמיתית שלה (level-1). אם חסרות רמות-על
      // (למשל ספר שמתחיל ברמה 2 בלי כותרת-חלק ברמה 1), ממלאים את המקומות
      // החסרים במחרוזות ריקות במקום לדחוף את הכותרת לאינדקס 0 — אחרת
      // הכותרת הראשונה הייתה "נתקעת" באינדקס 0 ומזהמת כל כתובת אחריה.
      final targetIndex = entry.level - 1;
      while (texts.length <= targetIndex) {
        texts.add('');
      }
      texts[targetIndex] = entry.text;
      texts = texts.getRange(0, entry.level).toList();

      searchToc(entry.children, index);
    }
  }

  searchToc(toc, index);

  texts = texts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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

/// מחלץ מילים משמעותיות (>2 תווים) לפי סדר, ללא ניקוד/גרשיים/פיסוק.
/// כך "רמבם" (בשם הספר) תואם "רמב"ם" (בערך TOC), ו"חברותא על X" תואם "חברותא - X".
List<String> _significantWordList(String s) {
  return s
      .replaceAll(RegExp(r'\p{Mn}', unicode: true), '') // ניקוד וטעמים
      .replaceAll(RegExp('''['"״׳’”“`]'''), '') // גרשיים — השם נשמר בלעדיהם
      .replaceAll(RegExp(r'[-–־,.]'), ' ') // מפרידים
      .split(RegExp(r'\s+'))
      .map((w) => w.trim())
      .where((w) => w.length > 2)
      .toList();
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

  final bookWordList = _significantWordList(bookTitle);
  final bookWords = bookWordList.toSet();
  final refWordList = _significantWordList(ref);
  final refWords = refWordList.toSet();

  // אם כל מילות שם הספר כלולות בכותרת, שם הספר כבר מיוצג
  // (למשל "חברותא - בכורות" מכסה את "חברותא על בכורות")
  if (bookWords.isNotEmpty && refWords.containsAll(bookWords)) {
    return ref;
  }

  // כיוון הפוך: כותרת מקוצרת מהשם (כל מילותיה בשם + אותה מילה מובילה) —
  // השם המלא מייצג אותה, כמו "בית מאיר אורח חיים" מול "בית מאיר על שו"ע אורח חיים"
  if (refWordList.isNotEmpty &&
      bookWords.containsAll(refWords) &&
      refWordList.first == bookWordList.first) {
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
  return referenceFromPageNumber(pageNumber, outline, bookTitle);
}

/// הגרסה הסינכרונית של [refFromPageNumber]: מחשבת את הכתובת ההיררכית עבור
/// עמוד [pageNumber] מתוך ה-outline שכבר טעון לזיכרון. נחוצה לחישוב מיידי
/// בלי `await` (תווית יעד ברחיפה מעל פס הגלילה של ה-PDF).
String referenceFromPageNumber(
  int pageNumber,
  List<PdfOutlineNode>? outline, [
  String? bookTitle,
]) {
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
