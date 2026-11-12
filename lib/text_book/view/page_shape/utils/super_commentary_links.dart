import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// מפרש-על (שער הציון על משנה ברורה) כטור עצמאי בצורת הדף: אין לו קישורים
/// מהספר הראשי, ולכן קישורי הסנכרון שלו מורכבים דרך המפרש שעליו הוא מפרש.

/// מפרשי-העל מתוך סיכום קישורי המפרש [parentTargets]: יעדים תלויי-טקסט
/// שאינם הספר הראשי ואינם מפרשים ישירים שלו.
Set<String> superCommentatorTitles({
  required Iterable<LinkTargetSummary> parentTargets,
  required String mainBookTitle,
  required Iterable<String> directCommentators,
}) {
  final direct = directCommentators.toSet();
  return {
    for (final target in parentTargets)
      if (LinkTypes.isDependentTextLink(target.connectionType) &&
          target.targetTitle != mainBookTitle &&
          !direct.contains(target.targetTitle))
        target.targetTitle,
  };
}

/// מפת מפרש-על ← המפרש שעליו הוא מפרש, לפי סדר [parents]: מפרש-על של כמה
/// מפרשים משויך לראשון שבהם.
Map<String, String> superCommentatorParents(
  List<String> parents,
  Map<String, Set<String>> superTitlesByParent,
) {
  final result = <String, String>{};
  for (final parent in parents) {
    for (final title in superTitlesByParent[parent] ?? const <String>{}) {
      result.putIfAbsent(title, () => parent);
    }
  }
  return result;
}

/// מרכיב קישורי ראשי←מפרש-על: לכל קישור ראשי←[parentTitle] (index2 = שורת
/// המפרש) נלקחים קישורי המפרש←[superTitle] שיוצאים מאותה שורה. ממוין ובלי כפילויות.
List<Link> composeSuperCommentaryLinks({
  required Iterable<Link> mainToParent,
  required Iterable<Link> parentToSuper,
  required String parentTitle,
  required String superTitle,
}) {
  final superByParentLine = <int, List<Link>>{};
  for (final link in parentToSuper) {
    if (!_isDependentLinkTo(link, superTitle)) continue;
    for (
      var line = link.index1;
      line <= (link.index1End ?? link.index1);
      line++
    ) {
      superByParentLine.putIfAbsent(line, () => []).add(link);
    }
  }

  final seen = <(int, int)>{};
  final composed = <Link>[];
  for (final mainLink in mainToParent) {
    if (!_isDependentLinkTo(mainLink, parentTitle)) continue;
    final last = mainLink.index2End ?? mainLink.index2;
    for (var line = mainLink.index2; line <= last; line++) {
      for (final superLink in superByParentLine[line] ?? const <Link>[]) {
        if (!seen.add((mainLink.index1, superLink.index2))) continue;
        composed.add(
          Link(
            heRef: superLink.heRef,
            index1: mainLink.index1,
            index1End: mainLink.index1End,
            path2: superLink.path2,
            index2: superLink.index2,
            index2End: superLink.index2End,
            heRefEnd: superLink.heRefEnd,
            connectionType: superLink.connectionType,
            targetCategoryId: superLink.targetCategoryId,
            targetBookId: superLink.targetBookId,
            targetFileType: superLink.targetFileType,
            targetSource: superLink.targetSource,
          ),
        );
      }
    }
  }
  composed.sort(
    (a, b) => a.index1 != b.index1
        ? a.index1.compareTo(b.index1)
        : a.index2.compareTo(b.index2),
  );
  return composed;
}

bool _isDependentLinkTo(Link link, String title) =>
    utils.getTitleFromPath(link.path2) == title &&
    LinkTypes.isDependentTextLink(link.connectionType);

/// שליפת קישורי טווח שורות (0-based, כולל) של ספר אל ספר יעד אחד.
typedef SuperCommentaryRangeFetcher =
    Future<List<Link>> Function({
      required String bookTitle,
      required int categoryId,
      required BookSource source,
      required int startLine,
      required int endLine,
      required String targetTitle,
    });

/// טוען בחלונות סביב שורת הראשי את קישורי טור מפרש-העל — שתי שאילתות לכל
/// חלון (ראשי←מפרש, ואז מפרש←מפרש-על בטווח השורות שעלה), דרך ה-worker.
class SuperCommentaryLinkLoader {
  SuperCommentaryLinkLoader({
    required this.mainTitle,
    required this.mainCategoryId,
    required this.mainSource,
    required this.parentTitle,
    required this.superTitle,
    required this.fetch,
    this.windowLines = 150,
    this.reloadThresholdLines = 50,
  });

  final String mainTitle;
  final int mainCategoryId;
  final BookSource mainSource;
  final String parentTitle;
  final String superTitle;
  final SuperCommentaryRangeFetcher fetch;
  final int windowLines;
  final int reloadThresholdLines;

  final List<({int start, int end})> _loaded = [];
  final Map<(int, int), Link> _byKey = {};
  List<Link> _links = const [];
  Future<bool>? _inFlight;

  /// הקישורים המורכבים שנטענו עד כה, ממוינים לפי שורת הראשי.
  List<Link> get links => _links;

  // בקצות הספר אין מה לטעון מעבר, ולכן שולי הביטחון שם מוותרים.
  bool _covers(int mainIndex, int lastLine) => _loaded.any(
    (range) =>
        mainIndex >=
            (range.start == 0 ? 0 : range.start + reloadThresholdLines) &&
        mainIndex <=
            (range.end >= lastLine
                ? range.end
                : range.end - reloadThresholdLines),
  );

  /// מוודא שחלון סביב [mainIndex] (0-based) מתוך [totalLines] שורות הראשי
  /// טעון. מחזיר true כשנוספו קישורים.
  Future<bool> ensureLoaded(int mainIndex, int totalLines) async {
    final pending = _inFlight;
    if (pending != null) {
      await pending;
    }
    final lastLine = totalLines - 1;
    if (lastLine < 0 || _covers(mainIndex, lastLine)) return false;
    final end = mainIndex + windowLines;
    final future = _load(
      mainIndex - windowLines < 0 ? 0 : mainIndex - windowLines,
      end > lastLine ? lastLine : end,
    );
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  Future<bool> _load(int start, int end) async {
    final mainLinks = (await fetch(
      bookTitle: mainTitle,
      categoryId: mainCategoryId,
      source: mainSource,
      startLine: start,
      endLine: end,
      targetTitle: parentTitle,
    )).where((link) => _isDependentLinkTo(link, parentTitle)).toList();
    _loaded.add((start: start, end: end));
    final parentCategoryId = mainLinks
        .map((link) => link.targetCategoryId)
        .whereType<int>()
        .firstOrNull;
    if (mainLinks.isEmpty || parentCategoryId == null) return false;

    var first = mainLinks.first.index2;
    var last = first;
    for (final link in mainLinks) {
      if (link.index2 < first) first = link.index2;
      final linkLast = link.index2End ?? link.index2;
      if (linkLast > last) last = linkLast;
    }
    final parentLinks = await fetch(
      bookTitle: parentTitle,
      categoryId: parentCategoryId,
      source: mainLinks.first.targetSource,
      startLine: first - 1,
      endLine: last - 1,
      targetTitle: superTitle,
    );
    final composed = composeSuperCommentaryLinks(
      mainToParent: mainLinks,
      parentToSuper: parentLinks,
      parentTitle: parentTitle,
      superTitle: superTitle,
    );
    var added = false;
    for (final link in composed) {
      if (_byKey.putIfAbsent((link.index1, link.index2), () => link) == link) {
        added = true;
      }
    }
    if (added) {
      _links = _byKey.values.toList()
        ..sort(
          (a, b) => a.index1 != b.index1
              ? a.index1.compareTo(b.index1)
              : a.index2.compareTo(b.index2),
        );
    }
    return added;
  }
}
