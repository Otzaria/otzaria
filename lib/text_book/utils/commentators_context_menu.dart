import 'dart:async';

import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath;

/// כותרת תת-התפריט "מפרשים" בתפריט ההקשר של גוף הספר.
const String kParagraphCommentatorsMenuLabel = 'מפרשים על פסקה זו';

/// מטמון את מפרשי הפסקה ואת שאר קישוריה, שנטענו בשאילת טווח.
///
/// [changes] מאפשר לתת־התפריט הפתוח להתעדכן כשהשאילתה מסתיימת.
class ParagraphCommentatorsCache {
  final Map<(Object, int), List<String>> _values = {};
  final Map<(Object, int), List<Link>> _referenceLinks = {};
  final Set<(Object, int)> _pending = {};
  final StreamController<Object?> _changes = StreamController.broadcast();

  Stream<Object?> get changes => _changes.stream;

  List<String>? value(TextBook book, int paragraphIndex) =>
      _values[_key(book, paragraphIndex)];

  /// קישורי הפסקה שאינם מפרשים — לתת-התפריט "קישורים".
  List<Link>? referenceLinks(TextBook book, int paragraphIndex) =>
      _referenceLinks[_key(book, paragraphIndex)];

  bool isLoading(TextBook book, int paragraphIndex) =>
      _pending.contains(_key(book, paragraphIndex));

  Future<void> prefetch({
    required TextBookRepository repository,
    required TextBook book,
    required int paragraphIndex,
  }) async {
    final key = _key(book, paragraphIndex);
    if (_values.containsKey(key) || !_pending.add(key)) return;
    try {
      final links = await repository.getBookLinksInRange(
        book,
        startIndex: paragraphIndex,
        endIndex: paragraphIndex,
        targetBookTitles: null,
      );
      final referenceLinks = [
        for (final link in links)
          if (!LinkTypes.isDependentTextLink(link.connectionType)) link,
      ];
      // המיון בתפריט סינכרוני — הדורות חייבים להיות במטמון לפני ההודעה.
      await CommentaryService.preloadErasForLinks(
        referenceLinks,
      ).catchError((_) {});
      _values[key] = {
        for (final link in links)
          if (LinkTypes.isDependentTextLink(link.connectionType))
            getTitleFromPath(link.path2),
      }.toList();
      _referenceLinks[key] = referenceLinks;
    } finally {
      _pending.remove(key);
      if (!_changes.isClosed) _changes.add(key);
    }
  }

  (Object, int) _key(TextBook book, int paragraphIndex) => (
    (
      book.id,
      book.title,
      book.source.wireKey,
      book.categoryId,
      book.fileType,
      book.versionTitle,
    ),
    paragraphIndex,
  );

  void dispose() => _changes.close();
}

/// המפרשים מתוך [availableCommentators] שיש להם תוכן על הפסקה [paragraphIndex].
/// [queriedCommentators] מגיע משאילתת הטווח; [linksByLine] מצרף קישורים
/// מקומיים, לרבות ספרי משתמש. הערות inline מצרפות את [kNotesCommentatorTitle].
List<String> paragraphCommentators({
  required List<String> availableCommentators,
  required List<String> content,
  required int paragraphIndex,
  required Map<int, List<Link>> linksByLine,
  List<String>? queriedCommentators,
}) {
  final onParagraph = queriedCommentators?.toSet() ?? <String>{};
  for (final link in linksByLine[paragraphIndex + 1] ?? const <Link>[]) {
    if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
    onParagraph.add(getTitleFromPath(link.path2));
  }
  if (inline_notes.notesForLines(content, [paragraphIndex]).isNotEmpty) {
    onParagraph.add(kNotesCommentatorTitle);
  }
  return availableCommentators.where(onParagraph.contains).toList();
}

/// קישורי תת-התפריט "קישורים": [linksByLine] (חלון הטעינה) מאוחד עם
/// [queriedLinks] (שאילתת הפסקה), בלי מפרשים וקישורים פנימיים, לפי דורות.
List<Link> paragraphReferenceLinks({
  required Map<int, List<Link>> linksByLine,
  required int paragraphIndex,
  List<Link>? queriedLinks,
}) {
  final seen =
      <(int, String, int, BookSource, int?, int?, String?, int?, String)>{};
  final links = [
    for (final link in [
      ...?linksByLine[paragraphIndex + 1],
      ...?queriedLinks,
    ])
      if (!LinkTypes.isDependentTextLink(link.connectionType) &&
          link.start == null &&
          link.end == null &&
          seen.add((
            link.index1,
            link.path2,
            link.index2,
            link.targetSource,
            link.targetBookId,
            link.targetCategoryId,
            link.targetFileType,
            link.index2End,
            link.connectionType,
          )))
        link,
  ];
  return CommentaryService.sortLinksByEraSync(links);
}
