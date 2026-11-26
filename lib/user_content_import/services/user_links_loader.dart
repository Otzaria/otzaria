import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// טוען קישורי-משתמש (מ-user_books.db) ככ-[Link] עבור ספר שנקרא, בשני
/// הכיוונים:
/// - forward: ספר-המשתמש מקושר ליעד (כשקוראים את ספר-המשתמש עצמו).
/// - inverse: ספר-משתמש אחר מצביע אל הספר הזה (כשקוראים רשמי/אישי שעליו
///   נכתב מפרש-משתמש) — כך מפרש-משתמש מופיע גם בספר הרשמי.
///
/// מחזיר רשימה ריקה אם user_books.db לא פתוח (בלי לכפות פתיחתו). ספר ממסד
/// מצורף מזוהה לפי slug וכותרת, בלי קטגוריה (מזהיה פנימיים למסד).
Future<List<Link>> loadUserLinksForBook({
  required String bookTitle,
  required int? bookCategoryId,
  required BookSource source,
  required int startLineIndex,
  required int endLineIndex,
  List<String>? targetBookTitles,
}) async {
  final dbPath = UserBooksDatabaseHolder.instance.openDbPath;
  if (dbPath == null) return const [];
  final isUserBook = source.isUser;
  final db = source.attachedSlug;
  final categoryId = db == null ? bookCategoryId : null;

  final links = await _readUserContent(
    dbPath,
    (ucr) async {
      Future<(List<Link>, List<Link>)> load({
        int? from,
        int? to,
        Set<int>? starts,
      }) async {
        final forward = await ucr.forwardUserLinks(
          bookTitle,
          sourceIsUserBook: isUserBook,
          sourceDb: db,
          sourceCategoryId: categoryId,
          startLineIndex: from,
          endLineIndex: to,
          startLines: starts,
        );
        final inverse = await ucr.inverseUserLinks(
          bookTitle,
          targetIsUserBook: isUserBook,
          targetDb: db,
          targetCategoryId: categoryId,
          startLineIndex: from,
          endLineIndex: to,
          startLines: starts,
        );
        return (
          [
            for (final r in forward)
              if (r.targetLineIndex != null) _forwardLink(r),
          ],
          [
            for (final r in inverse)
              if (r.targetLineIndex != null) _inverseLink(r),
          ],
        );
      }

      final (forward, inverse) = await load(
        from: startLineIndex,
        to: endLineIndex,
      );
      final window = [...forward, ...inverse];
      final earlierStarts = {
        for (final link in window)
          if (link.index1 <= startLineIndex) link.index1 - 1,
      };
      if (earlierStarts.isEmpty) return dedupeUserLinks(window);

      // גם רשומה הפוכה או קצרה יכולה להיות מחוץ לחלון, באותה שורת התחלה.
      final shown = window.map(_pairKey).toSet();
      final (earlierForward, earlierInverse) = await load(
        starts: earlierStarts,
      );
      return dedupeUserLinks([
            ...earlierForward.where((link) => shown.contains(_pairKey(link))),
            ...forward.where((link) => link.index1 > startLineIndex),
            ...earlierInverse.where((link) => shown.contains(_pairKey(link))),
            ...inverse.where((link) => link.index1 > startLineIndex),
          ])
          .where((link) => (link.index1End ?? link.index1) > startLineIndex)
          .toList();
    },
    ifSkipped: const <Link>[],
  );
  return _applyCommentatorFilter(links, targetBookTitles);
}

Link _forwardLink(UserLinkRecord r) => Link(
  heRef: r.targetRef ?? r.targetTitle,
  index1: r.sourceLineIndex + 1,
  index1End: _oneBased(r.sourceLineIndexEnd),
  path2: r.targetTitle,
  index2: r.targetLineIndex! + 1,
  connectionType: r.connectionType,
  targetCategoryId: r.targetCategoryId,
  targetSource: r.targetOrigin,
  anchorStart: r.anchorStart,
  anchorEnd: r.anchorEnd,
  // אופסטי user_link נמדדו על HTML גולמי, בניגוד לעוגנים במסד הרשמי.
  anchorOffsetsAreRaw: true,
  anchorLabel: r.anchorLabel,
  heRefEnd: r.targetRefEnd,
  index2End: _oneBased(r.targetLineIndexEnd),
);

Link _inverseLink(UserLinkRecord r) => Link(
  heRef: r.sourceTitle,
  index1: r.targetLineIndex! + 1,
  index1End: _oneBased(r.targetLineIndexEnd),
  path2: r.sourceTitle,
  index2: r.sourceLineIndex + 1,
  connectionType: LinkTypes.inverse(r.connectionType),
  targetSource: r.sourceOrigin,
  targetCategoryId: r.sourceCategoryId,
  index2End: _oneBased(r.sourceLineIndexEnd),
);

int? _oneBased(int? index) => index == null ? null : index + 1;

/// כותרות מפרשי-המשתמש של ספר — להזנת רשימת המפרשים לבחירה (שאחרת נבנית
/// רק מ-seforim.db ואינה מכירה קישורי-משתמש). ריק אם user_books.db לא פתוח.
Future<List<String>> loadUserCommentatorTitles({
  required String bookTitle,
  required int? bookCategoryId,
  required BookSource source,
}) async {
  final dbPath = UserBooksDatabaseHolder.instance.openDbPath;
  if (dbPath == null) return const [];
  final isUserBook = source.isUser;
  final db = source.attachedSlug;
  return _readUserContent(
    dbPath,
    (ucr) => ucr.userCommentatorTitles(
      bookTitle,
      sourceIsUserBook: isUserBook,
      sourceDb: db,
      sourceCategoryId: db == null ? bookCategoryId : null,
    ),
    ifSkipped: const [],
  );
}

/// קורא את user_books.db בחיבור read-only משלו ב-isolate: כתיבה מקבילה
/// (סנכרון הרקע) נועלת את המסד, והמתנה לה על ה-UI isolate תוקעת את הממשק.
Future<T> _readUserContent<T>(
  String dbPath,
  Future<T> Function(UserContentRepository ucr) read, {
  required T ifSkipped,
}) async {
  var result = ifSkipped;
  await UserBooksDatabaseHolder.instance.trackRead(() async {
    result = await _readUserContentInIsolate(dbPath, read);
  });
  return result;
}

Future<T> _readUserContentInIsolate<T>(
  String dbPath,
  Future<T> Function(UserContentRepository ucr) read,
) async {
  await QueryLoader.initialize();
  final queryCache = QueryLoader.cacheSnapshot;
  return Isolate.run(() async {
    QueryLoader.seedCache(queryCache);
    final db = MyDatabase.withPath(dbPath, readOnly: true);
    try {
      final connection = await db.database;
      connection.execute('PRAGMA busy_timeout=5000');
      // קדימה, הפוך והשלמת הרשומות נקראים מאותה תמונת מצב.
      connection.execute('BEGIN');
      return await read(UserContentRepository(db));
    } finally {
      db.close();
    }
  });
}

typedef _UserLinkPair = (int, String, int, String, BookSource, int?);

_UserLinkPair _pairKey(Link link) => (
  link.index1,
  link.path2,
  link.index2,
  link.connectionType,
  link.targetSource,
  link.targetCategoryId,
);

/// ממזג קישורים כפי שהם נראים בספר הנקרא. עוגנים מקומיים שונים נשמרים.
@visibleForTesting
List<Link> dedupeUserLinks(List<Link> links) {
  final groups = <(_UserLinkPair, int?), List<Link>>{};
  final anchored = <_UserLinkPair>{};
  for (final link in links) {
    final key = _pairKey(link);
    final anchor = link.anchorStart;
    (groups[(key, anchor)] ??= []).add(link);
    if (anchor != null) anchored.add(key);
  }
  return [
    for (final entry in groups.entries)
      if (entry.key.$2 != null || !anchored.contains(entry.key.$1))
        _mergeDisplayLink(
          entry.value,
          plain: entry.key.$2 == null ? null : groups[(entry.key.$1, null)],
        ),
  ];
}

Link _mergeDisplayLink(List<Link> links, {List<Link>? plain}) {
  if (links.length == 1 && plain == null) return links.first;
  var best = links.first;
  for (final link in links.skip(1)) {
    if (_linkDetails(link) > _linkDetails(best)) best = link;
  }

  var sourceEnd = best.index1End;
  var reference = best.heRef.isEmpty ? best.path2 : best.heRef;
  var anchorEnd = best.anchorEnd;
  var anchorLabel = best.anchorLabel;
  Link? targetRange = best.index2End == null ? null : best;
  for (final link in links) {
    anchorEnd ??= link.anchorEnd;
    anchorLabel ??= link.anchorLabel;
  }
  for (final group in [links, ?plain]) {
    for (final link in group) {
      final end = link.index1End;
      if (end != null && (sourceEnd == null || end > sourceEnd)) {
        sourceEnd = end;
      }
      if (reference == best.path2 && link.heRef.isNotEmpty) {
        reference = link.heRef;
      }
      if (best.index2End == null &&
          link.index2End != null &&
          (targetRange == null ||
              _linkDetails(link) > _linkDetails(targetRange))) {
        targetRange = link;
      }
    }
  }
  // הטווח ביעד והכתובת שבקצהו צריכים להגיע מאותה רשומה.
  final rangeReference = targetRange?.heRef;
  return Link(
    heRef:
        rangeReference == null ||
            rangeReference.isEmpty ||
            rangeReference == best.path2
        ? reference
        : rangeReference,
    index1: best.index1,
    index1End: sourceEnd,
    path2: best.path2,
    index2: best.index2,
    connectionType: best.connectionType,
    targetCategoryId: best.targetCategoryId,
    targetBookId: best.targetBookId,
    targetFileType: best.targetFileType,
    targetSource: best.targetSource,
    start: best.start,
    end: best.end,
    anchorStart: best.anchorStart,
    anchorEnd: anchorEnd,
    anchorOffsetsAreRaw: best.anchorOffsetsAreRaw,
    anchorLabel: anchorLabel,
    linkedAnchorStart: best.linkedAnchorStart,
    linkedAnchorEnd: best.linkedAnchorEnd,
    anchorSpans: best.anchorSpans,
    heRefEnd: targetRange == null ? best.heRefEnd : targetRange.heRefEnd,
    index2End: targetRange?.index2End,
    baseProvenance: best.baseProvenance,
  );
}

int _linkDetails(Link link) =>
    (link.heRef.isNotEmpty && link.heRef != link.path2 ? 1 : 0) +
    (link.anchorEnd == null ? 0 : 1) +
    (link.anchorLabel == null ? 0 : 1) +
    (link.index1End == null ? 0 : 1) +
    (link.index2End == null ? 0 : 1) +
    (link.heRefEnd == null ? 0 : 1);

/// מסנן קישורי-מפרש לפי המפרשים הנבחרים (כמו הסינון ב-getLinksForBookRange):
/// קישור תלוי-טקסט נכלל רק אם כותרת היעד נבחרה; קישורי הפניה תמיד עוברים.
List<Link> _applyCommentatorFilter(
  List<Link> links,
  List<String>? targetBookTitles,
) {
  if (targetBookTitles == null) return links;
  final selected = targetBookTitles.toSet();
  return links.where((link) {
    if (!LinkTypes.isDependentTextLink(link.connectionType)) return true;
    return selected.contains(utils.getTitleFromPath(link.path2));
  }).toList();
}
