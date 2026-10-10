import 'dart:math';

import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';

Future<String> refFromIndex(
  int index,
  Future<List<TocEntry>> tableOfContents,
) async {
  return refFromTocList(index, await tableOfContents);
}

/// הכתובת ההיררכית של שורה [index] ב-[book], בשאילתה אחת על ה-DB במקום
/// טעינת עץ הכותרות כולו — ההפרש מורגש בספרים עם עשרות אלפי כותרות.
///
/// מחזירה `null` לספר שאינו ב-DB או לשורה שאין לה מיפוי כותרת, ואז על הקורא
/// ליפול חזרה ל-[refFromIndex].
Future<String?> refFromDbLine(TextBook book, int index) async {
  final bookId = book.id;
  if (bookId == null) return null;
  try {
    final repository = switch (book.source) {
      OfficialBookSource() => SqliteDataProvider.instance.repository,
      UserBookSource() => await UserBooksDatabaseHolder.instance.repository,
      AttachedBookSource(:final slug) =>
        await AttachedLibraryRegistry.instance.repositoryFor(slug),
    };
    if (repository == null) return null;
    final dbPath = SqliteDataProvider.instance.dbPath;
    if (book.source.isOfficial && dbPath.isNotEmpty) {
      try {
        return await DbReadWorker.batched('breadcrumb', {
              'dbPath': dbPath,
              'bookId': bookId,
              'lineIndex': index,
            })
            as String?;
      } catch (_) {
        return null;
      }
    }
    return await repository.getLineBreadcrumb(bookId, index);
  } catch (_) {
    return null;
  }
}

/// כתובת השורה המלאה מה-DB, עד רמת הפסוק/ההלכה; `null` לספר
/// שאינו ב-DB או לשורה בלי `heRef` (כותרות, ספרי קבצים).
Future<String?> heRefFromDbLine(TextBook book, int index) async {
  final bookId = book.id;
  if (bookId == null) return null;
  try {
    final repository = switch (book.source) {
      OfficialBookSource() => SqliteDataProvider.instance.repository,
      UserBookSource() => await UserBooksDatabaseHolder.instance.repository,
      AttachedBookSource(:final slug) =>
        await AttachedLibraryRegistry.instance.repositoryFor(slug),
    };
    return await repository?.getLineHeRef(bookId, index);
  } catch (_) {
    return null;
  }
}

/// הגרסה הסינכרונית של [refFromIndex]: מחשבת את הכתובת ההיררכית עבור שורה
/// [index] מתוך רשימת תוכן עניינים שכבר נטענה לזיכרון. נחוצה למקומות שצריכים
/// חישוב מיידי בלי `await` (למשל תווית יעד ברחיפה מעל פס הגלילה), והחישוב
/// עצמו נעשה במבנה עזר שנבנה פעם אחת לכל עץ, כי היא נקראת בכל גלילה.
String refFromTocList(int index, List<TocEntry> toc) =>
    (_tocRefLookups[toc] ??= _TocRefLookup(toc)).refAt(index);

final _tocRefLookups = Expando<_TocRefLookup>();

/// הכתובת היא שרשרת הכותרות שנסרקו, כל אחת הקודמת שרמתה נמוכה מזו שאחריה.
/// כותרת נסרקת כשהמפתח שלה (מקסימום האינדקסים של אחיה הקודמים ואבותיה) <= השורה.
class _TocRefLookup {
  final _entries = <TocEntry>[];
  final _ranks = <int>[];
  final _sortedKeys = <int>[];
  final _roots = <int>[];
  final _left = <int>[0];
  final _right = <int>[0];
  final _lastPos = <int>[-1];
  late final int _levelCount;

  _TocRefLookup(List<TocEntry> toc) {
    final keys = <int>[];
    final pending = <({Iterator<TocEntry> entries, int? key})>[
      (entries: toc.iterator, key: null),
    ];
    while (pending.isNotEmpty) {
      final frame = pending.removeLast();
      if (!frame.entries.moveNext()) continue;
      final entry = frame.entries.current;
      final key = frame.key == null
          ? entry.index
          : max(frame.key!, entry.index);
      pending.add((entries: frame.entries, key: key));
      if (entry.level > 0) {
        _entries.add(entry);
        keys.add(key);
      }
      if (entry.children.isNotEmpty) {
        pending.add((entries: entry.children.iterator, key: key));
      }
    }

    final levels = _entries.map((entry) => entry.level).toSet().toList()
      ..sort();
    _levelCount = levels.length;
    final ranks = {for (var i = 0; i < levels.length; i++) levels[i]: i};
    _ranks.addAll(_entries.map((entry) => ranks[entry.level]!));
    final positions = List.generate(_entries.length, (i) => i)
      ..sort((a, b) => keys[a].compareTo(keys[b]));
    var root = 0, firstNewNode = 1;
    for (final pos in positions) {
      if (_sortedKeys.isEmpty || _sortedKeys.last != keys[pos]) {
        firstNewNode = _lastPos.length;
      }
      root = _insert(root, 0, _levelCount, _ranks[pos], pos, firstNewNode);
      if (_sortedKeys.isNotEmpty && _sortedKeys.last == keys[pos]) {
        _roots[_roots.length - 1] = root;
      } else {
        _sortedKeys.add(keys[pos]);
        _roots.add(root);
      }
    }
  }

  // כל גרסה שומרת את הכותרת האחרונה בכל רמה עבור סף שורה אחד.
  int _insert(int node, int lo, int hi, int rank, int pos, int firstNewNode) {
    if (hi - lo == 1 && _lastPos[node] >= pos) return node;
    var left = _left[node], right = _right[node];
    if (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (rank < mid) {
        left = _insert(left, lo, mid, rank, pos, firstNewNode);
      } else {
        right = _insert(right, mid, hi, rank, pos, firstNewNode);
      }
      if (left == _left[node] &&
          right == _right[node] &&
          _lastPos[node] == max(_lastPos[left], _lastPos[right])) {
        return node;
      }
    }
    final lastPos = hi - lo == 1 ? pos : max(_lastPos[left], _lastPos[right]);
    // עד לפרסום גרסה חדשה אפשר לעדכן את צמתיה בלי להעתיק שוב את אותו מסלול.
    if (node >= firstNewNode) {
      _left[node] = left;
      _right[node] = right;
      _lastPos[node] = lastPos;
      return node;
    }
    _left.add(left);
    _right.add(right);
    _lastPos.add(lastPos);
    return _lastPos.length - 1;
  }

  int _lastBelow(int node, int lo, int hi, int bound) {
    if (node == 0 || lo >= bound) return -1;
    if (hi <= bound) return _lastPos[node];
    final mid = (lo + hi) >> 1;
    return max(
      _lastBelow(_left[node], lo, mid, bound),
      _lastBelow(_right[node], mid, hi, bound),
    );
  }

  String refAt(int index) {
    final lo = _countAtMost(_sortedKeys, index);
    if (lo == 0) return '';
    final root = _roots[lo - 1];
    final parts = <String>[];
    var pos = _lastPos[root];
    while (pos >= 0) {
      parts.add(_entries[pos].text.trim());
      pos = _lastBelow(root, 0, _levelCount, _ranks[pos]);
    }
    return parts.reversed.where((part) => part.isNotEmpty).join(', ');
  }
}

int _countAtMost(List<int> sorted, int value) {
  var lo = 0, hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    sorted[mid] <= value ? lo = mid + 1 : hi = mid;
  }
  return lo;
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
      bookTitle: bookTitle,
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
    if (dedupedParts.isNotEmpty &&
        dedupedParts.last == part &&
        _looksLikeHeadingSegment(part)) {
      continue;
    }
    dedupedParts.add(part);
  }

  return dedupedParts.join(', ');
}

/// רכיב שנראה ככותרת TOC (מילים/טקסט ארוך) ולא כערך מיקום גימטרי קצר.
/// "פרק א, פרק א" הוא כפל כותרות שיש לאחד; "א, א" הוא פרק א פסוק א — שתי
/// רמות לגיטימיות שאסור למזג.
bool _looksLikeHeadingSegment(String part) =>
    part.contains(' ') || part.length > 3;

String _chooseMoreSpecificReference({
  required String resolvedDisplay,
  required String fallbackDisplay,
  required String bookTitle,
}) {
  // כתובת השורה (fallback) יורדת לרמה עמוקה מזו של ה-TOC כשה-TOC נעצר בפרק —
  // "משנה אבות א, ג" מול "משנה אבות, פרק א". הניקוד לבדו העדיף את הקצרה.
  if (bookTitle.isNotEmpty &&
      resolvedDisplay.startsWith(bookTitle) &&
      fallbackDisplay.startsWith(bookTitle) &&
      _addressDepth(fallbackDisplay, bookTitle) >
          _addressDepth(resolvedDisplay, bookTitle)) {
    return fallbackDisplay;
  }

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

/// מספר רמות המיקום שאחרי שם הספר: "משנה אבות א, ג" → 2, "משנה אבות, פרק א" → 1.
int _addressDepth(String display, String bookTitle) {
  return display
      .substring(bookTitle.length)
      .split(',')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .length;
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

/// הכתובת ההיררכית של עמוד [pageNumber] מתוך ה-outline שבזיכרון.
/// סינכרונית וזולה — אין צורך לדחות אותה ל-debounce או ל-isolate.
String referenceFromPageNumber(
  int pageNumber,
  List<PdfOutlineNode>? outline, [
  String? bookTitle,
]) {
  if (outline == null) return "";

  List<String> texts = [];

  void searchOutline(List<PdfOutlineNode> entries, {int level = 0}) {
    for (final entry in entries) {
      final entryPage = entry.dest?.pageNumber;
      if (entryPage == null) continue;
      if (entryPage > pageNumber) return;
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

/// האינדקס הגדול ביותר מבין הכותרות שהאינדקס שלהן ושל כל אבותיהן <=
/// [targetIndex], או null. נקראת בכל גלילה, ולכן במבנה עזר שנבנה פעם אחת לכל עץ.
int? closestTocEntryIndex(List<TocEntry> entries, int targetIndex) {
  final (:keys, :best) = _closestTocLookups[entries] ??= _closestTocLookup(
    entries,
  );
  final count = _countAtMost(keys, targetIndex);
  return count == 0 ? null : best[count - 1];
}

final _closestTocLookups = Expando<({List<int> keys, List<int> best})>();

/// מפתח כותרת = מקסימום האינדקסים שלה ושל אבותיה; ממוין, עם מקסימום מצטבר.
({List<int> keys, List<int> best}) _closestTocLookup(List<TocEntry> toc) {
  final pairs = <(int, int)>[];
  final pending = [for (final entry in toc) (entry, entry.index)];
  while (pending.isNotEmpty) {
    final (entry, key) = pending.removeLast();
    pairs.add((key, entry.index));
    for (final child in entry.children) {
      pending.add((child, max(key, child.index)));
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  final best = <int>[];
  for (final (_, index) in pairs) {
    best.add(max(index, best.lastOrNull ?? index));
  }
  return (keys: [for (final (key, _) in pairs) key], best: best);
}

/// הקטע שתחת הכותרת הקרובה ל-[line] (מעליה או בה): מהכותרת ועד הכותרת הבאה
/// באותה רמה או גבוהה ממנה. `end` null = עד סוף הספר; null כשאין כותרת מעל.
({int start, int? end, String title})? tocSectionAt(
  List<TocEntry> entries,
  int line,
) {
  final flat = flattenToc(entries);
  int? closestPos;
  for (var i = 0; i < flat.length; i++) {
    if (flat[i].index <= line &&
        (closestPos == null || flat[i].index >= flat[closestPos].index)) {
      closestPos = i;
    }
  }
  if (closestPos == null) return null;
  final heading = flat[closestPos];
  int? end;
  for (var i = closestPos + 1; i < flat.length; i++) {
    if (flat[i].level <= heading.level && flat[i].index > heading.index) {
      end = flat[i].index;
      break;
    }
  }
  return (start: heading.index, end: end, title: heading.text);
}
