import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// מחלקה לניהול מפרשי ברירת המחדל ("מפרשים בסיסיים") של ספר.
///
/// המקור הבלעדי לנתונים הוא טבלאות `default_commentator` ו-`default_targum`
/// ב-seforim.db. ה-`position` ממיין כל טבלה בנפרד (אין מרחב position משותף
/// בין שתי הטבלאות) — הוא קובע את סדר ההקדמה ברשימה ואת סדר המיקומים בצורת
/// הדף בתוך כל סוג. היחס בין מפרשים לתרגומים קבוע: המפרשים תמיד קודמים
/// לתרגומים (ב-[getBaseCommentators] וב-[getDefaults] כאחד).
class DefaultCommentators {
  /// מחזיר את מפרשי ותרגומי ברירת המחדל של [book], ממוינים לפי `position`.
  ///
  /// ספרים אישיים אינם נכללים ב-seforim.db ולכן מחזירים רשימות ריקות.
  static Future<
      ({
        List<({String title, int position})> commentators,
        List<String> targums
      })> _fetchDefaults(Book book) async {
    const empty =
        (commentators: <({String title, int position})>[], targums: <String>[]);

    if (book.isUserBook) return empty;

    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) return empty;

    final dbBook = book.categoryId != null
        ? await repository.getBookByTitleAndCategory(
            book.title, book.categoryId!)
        : await repository.getBookByTitle(book.title);
    if (dbBook == null) return empty;

    final linkDao = repository.database.linkDao;
    final commentatorRows = await linkDao.selectDefaultCommentators(dbBook.id);
    final targumRows = await linkDao.selectDefaultTargums(dbBook.id);

    return (
      commentators: commentatorRows
          .map((row) => (
                title: row['targetBookTitle'] as String,
                position: (row['position'] as num).toInt(),
              ))
          .toList(),
      targums:
          targumRows.map((row) => row['targetBookTitle'] as String).toList(),
    );
  }

  /// מחזיר את רשימת המפרשים הבסיסיים של [book] (מפרשים ואחריהם תרגומים),
  /// ממוינת לפי `position`. משמש להקדמת המפרשים הבסיסיים בתוך קבוצות הדורות.
  static Future<List<String>> getBaseCommentators(Book book) async {
    final data = await _fetchDefaults(book);
    return [...data.commentators.map((c) => c.title), ...data.targums];
  }

  /// מחזיר את בחירת המפרשים ההתחלתית לפאנל/כרטסיית המפרשים של [book]:
  /// מפרשי ברירת המחדל המוגדרים (אם יש), אחרת כל המפרשים אם יש עד 4.
  /// כשאין ברירת מחדל ויש יותר מ-4 מפרשים — מחזיר רשימה ריקה (בחירה ידנית).
  /// [availableCommentators] = המפרשים הזמינים בפועל לספר.
  static Future<List<String>> getInitialSelection(
    Book book, {
    required List<String> availableCommentators,
    List<String>? baseCommentators,
  }) async {
    if (availableCommentators.isEmpty) return const [];

    final base = baseCommentators ?? await getBaseCommentators(book);
    final resolved = <String>[];
    for (final name in base) {
      final match = _findMatchingCommentator(name, availableCommentators);
      if (match != null && !resolved.contains(match)) {
        resolved.add(match);
      }
    }
    if (resolved.isNotEmpty) return resolved;

    if (availableCommentators.length <= 4) {
      return List<String>.from(availableCommentators);
    }
    return const [];
  }

  /// מחליט את בחירת המפרשים האוטומטית לפתיחה, בהתחשב בבחירה שמורה פר-ספר.
  /// בחירה שמורה (גם ריקה) היא מקור-האמת ולכן מבטלת אוטו-בחירה — מחזיר null.
  /// אחרת מחזיר את מפרשי ברירת המחדל ([getInitialSelection]), או null אם אין.
  static Future<List<String>?> resolveAutoSelection(
    Book book, {
    required List<String> availableCommentators,
    required List<String>? savedSelection,
  }) async {
    if (savedSelection != null) return null;
    final defaults = await getInitialSelection(
      book,
      availableCommentators: availableCommentators,
    );
    return defaults.isEmpty ? null : defaults;
  }

  /// מחזיר מפרשי ברירת מחדל למיקומי צורת הדף (right/left/bottom/bottomRight),
  /// ממופים לפי ה-`position` של כל מפרש (פירוט המיפוי ב-[mapToPageShape]).
  /// [availableCommentators] משמש להתאמת השם המלא הזמין בספר הנוכחי.
  static Future<Map<String, String?>> getDefaults(
    TextBook book, {
    List<String>? availableCommentators,
  }) async {
    final data = await _fetchDefaults(book);
    final defaults = mapToPageShape(data.commentators, data.targums);

    if (availableCommentators != null && availableCommentators.isNotEmpty) {
      return _resolveCommentatorNamesFromAvailable(
          defaults, availableCommentators);
    }

    return defaults;
  }

  /// ממפה מפרשים (לפי `position` מהטבלה) ותרגומים ל-4 מיקומי צורת הדף:
  /// position 0→ימין, 1→שמאל, 2→תחתון, 3→תחתון-ימני. position חסר (slot ריק
  /// מכוון, ראה ה-sentinel "-" ב-seed) → המיקום נשאר ריק. התרגומים ממולאים
  /// במיקומים שאחרי ה-position המקסימלי של המפרשים.
  @visibleForTesting
  static Map<String, String?> mapToPageShape(
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

    return {
      'right': slots[0],
      'left': slots[1],
      'bottom': slots[2],
      'bottomRight': slots[3],
    };
  }

  static Map<String, String?> _resolveCommentatorNamesFromAvailable(
      Map<String, String?> defaults, List<String> availableCommentators) {
    return {
      'right':
          _findMatchingCommentator(defaults['right'], availableCommentators),
      'left': _findMatchingCommentator(defaults['left'], availableCommentators),
      'bottom':
          _findMatchingCommentator(defaults['bottom'], availableCommentators),
      'bottomRight': _findMatchingCommentator(
          defaults['bottomRight'], availableCommentators),
    };
  }

  /// מחפש מפרש שמתאים לשם הנתון מתוך הזמינים בפועל בספר.
  /// מחזיר את השם המלא אם נמצא, או null אם לא.
  static String? _findMatchingCommentator(
      String? name, List<String> available) {
    if (name == null) return null;

    // 1. התאמה מדויקת
    String? match = available.firstWhereOrNull((item) => item == name);
    if (match != null) return match;

    // 2. התאמה של התחלה
    match = available.firstWhereOrNull((item) => item.startsWith(name));
    if (match != null) return match;

    // 3. התאמה של הכלה
    match = available.firstWhereOrNull((item) => item.contains(name));
    if (match != null) return match;

    // 4. התאמה הפוכה - השם בהגדרות מכיל את השם הזמין
    match = available.firstWhereOrNull((item) => name.contains(item));
    return match;
  }
}
