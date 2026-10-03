import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';

/// Default commentators of a book mapped to the page shape panels.
class PageShapeDefaultCommentators {
  static const _pageShapePanelKeys = ['left', 'right', 'bottom', 'bottomRight'];

  /// מחזיר את ברירת המחדל המלאה לצורת הדף: בחירת מפרשים וגם נראות חלוניות.
  ///
  /// חלונית מוסתרת רק כשיש "חור" מכוון בתוך מיקומי ברירת המחדל של הספר עצמו
  /// (לדוגמה position 0 ואז 2). חלוניות שמעבר למיקום האחרון נשארות ברירת מחדל.
  static Future<
    ({
      Map<String, String?> commentators,
      Map<String, bool> visibility,
    })
  >
  getPageShapeDefaults(
    TextBook book, {
    List<String>? availableCommentators,
  }) async {
    final data = await DefaultCommentators.fetchDefaults(book);
    final defaults = mapToPageShapeDefaults(data.commentators, data.targums);
    var commentators = defaults.commentators;

    if (availableCommentators != null && availableCommentators.isNotEmpty) {
      commentators = _resolveCommentatorNamesFromAvailable(
        commentators,
        availableCommentators,
      );
    }

    return (commentators: commentators, visibility: defaults.visibility);
  }

  /// ממפה מפרשים (לפי `position` מהטבלה) ותרגומים ל-4 מיקומי צורת הדף:
  /// position 0→ימין, 1→שמאל, 2→תחתון, 3→תחתון נוסף. position חסר (slot ריק
  /// מכוון, ראה ה-sentinel "-" ב-seed) → המיקום נשאר ריק. התרגומים ממולאים
  /// במיקומים שאחרי ה-position המקסימלי של המפרשים.
  @visibleForTesting
  static Map<String, String?> mapToPageShape(
    List<({String title, int position})> commentators,
    List<String> targums,
  ) => mapToPageShapeDefaults(commentators, targums).commentators;

  @visibleForTesting
  static ({
    Map<String, String?> commentators,
    Map<String, bool> visibility,
  })
  mapToPageShapeDefaults(
    List<({String title, int position})> commentators,
    List<String> targums,
  ) {
    final slots = <String?>[null, null, null, null];
    var maxPosition = -1;
    for (final c in commentators) {
      if (c.position >= 0 && c.position < slots.length) {
        slots[c.position] = c.title;
      }
      if (c.position > maxPosition) maxPosition = c.position;
    }

    var targumSlot = maxPosition + 1;
    for (final targum in targums) {
      if (targumSlot >= slots.length) break;
      slots[targumSlot] = targum;
      targumSlot++;
    }

    // מפתחות הפאנלים הפוכים לצד הפיזי (Row שיורש RTL): 'left' מוצג בימין ולהפך.
    final mappedCommentators = <String, String?>{};
    final mappedVisibility = <String, bool>{};
    for (var i = 0; i < _pageShapePanelKeys.length; i++) {
      final key = _pageShapePanelKeys[i];
      mappedCommentators[key] = slots[i];
      mappedVisibility[key] = !(i <= maxPosition && slots[i] == null);
    }

    return (commentators: mappedCommentators, visibility: mappedVisibility);
  }

  static Map<String, String?> _resolveCommentatorNamesFromAvailable(
    Map<String, String?> defaults,
    List<String> availableCommentators,
  ) {
    return {
      'right': findMatchingCommentator(
        defaults['right'],
        availableCommentators,
      ),
      'left': findMatchingCommentator(defaults['left'], availableCommentators),
      'bottom': findMatchingCommentator(
        defaults['bottom'],
        availableCommentators,
      ),
      'bottomRight': findMatchingCommentator(
        defaults['bottomRight'],
        availableCommentators,
      ),
    };
  }
}
