import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/settings/services/category_commentators_service.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';

/// מחלקה לניהול מפרשי ברירת המחדל ("מפרשים בסיסיים") של ספר.
///
/// המקור הבלעדי לנתונים הוא טבלאות `default_commentator` ו-`default_targum`
/// ב-seforim.db. ה-`position` ממיין כל טבלה בנפרד (אין מרחב position משותף
/// בין שתי הטבלאות) — הוא קובע את סדר ההקדמה ברשימה ואת סדר המיקומים בצורת
/// הדף בתוך כל סוג. היחס בין מפרשים לתרגומים קבוע: המפרשים תמיד קודמים
/// לתרגומים (ב-[getBaseCommentators] וגם במיפוי לחלוניות צורת הדף).
class DefaultCommentators {
  /// מחזיר את מפרשי ותרגומי ברירת המחדל של [book], ממוינים לפי `position`.
  ///
  /// נקרא מהמסד של הספר (seforim.db או מסד מצורף); לספר אישי — ריק.
  static Future<
    ({List<({String title, int position})> commentators, List<String> targums})
  >
  fetchDefaults(Book book) async {
    const empty = (
      commentators: <({String title, int position})>[],
      targums: <String>[],
    );

    final source = book.source;
    final repository = switch (source) {
      OfficialBookSource() => SqliteDataProvider.instance.repository,
      UserBookSource() => null,
      AttachedBookSource(:final slug) =>
        await AttachedLibraryRegistry.instance.repositoryFor(slug),
    };
    if (repository == null) return empty;

    final dbBook = book.categoryId != null
        ? await repository.getBookByTitleAndCategory(
            book.title,
            book.categoryId!,
          )
        : await repository.getBookByTitle(book.title);
    if (dbBook == null) return empty;

    final linkDao = repository.database.linkDao;
    final commentatorRows = await linkDao.selectDefaultCommentators(dbBook.id);
    final targumRows = await linkDao.selectDefaultTargums(dbBook.id);

    return (
      commentators: commentatorRows
          .map(
            (row) => (
              title: row['targetBookTitle'] as String,
              position: (row['position'] as num).toInt(),
            ),
          )
          .toList(),
      targums: targumRows
          .map((row) => row['targetBookTitle'] as String)
          .toList(),
    );
  }

  /// מחזיר את רשימת המפרשים הבסיסיים של [book] (מפרשים ואחריהם תרגומים),
  /// ממוינת לפי `position`. משמש להקדמת המפרשים הבסיסיים בתוך קבוצות הדורות.
  static Future<List<String>> getBaseCommentators(Book book) async {
    final data = await fetchDefaults(book);
    return [...data.commentators.map((c) => c.title), ...data.targums];
  }

  /// מחזיר את בחירת המפרשים ההתחלתית לפאנל/כרטסיית המפרשים של [book]:
  /// מפרשים קבועים שהמשתמש קבע לקטגוריה (אם יש), אחרת מפרשי ברירת המחדל
  /// מה-DB, אחרת כל המפרשים אם יש עד 4.
  /// כשאין ברירת מחדל ויש יותר מ-4 מפרשים — מחזיר רשימה ריקה (בחירה ידנית).
  /// [availableCommentators] = המפרשים הזמינים בפועל לספר.
  static Future<List<String>> getInitialSelection(
    Book book, {
    required List<String> availableCommentators,
    List<String>? baseCommentators,
  }) async {
    if (availableCommentators.isEmpty) return const [];

    final categorySelection = _resolveCategorySelection(
      book,
      availableCommentators,
    );
    if (categorySelection != null) return categorySelection;

    final base = baseCommentators ?? await getBaseCommentators(book);
    final resolved = <String>[];
    for (final name in base) {
      final match = findMatchingCommentator(name, availableCommentators);
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

  /// המפרשים הקבועים שהמשתמש קבע לקטגוריה של [book], כשמות מלאים מתוך
  /// הזמינים. null כשאין קביעה או כשאף שם לא נפתר בספר הזה (ואז נופלים
  /// לברירת המחדל מה-DB). רשימה ריקה שנקבעה במפורש מוחזרת כמות שהיא.
  static List<String>? _resolveCategorySelection(
    Book book,
    List<String> availableCommentators,
  ) {
    final baseNames = CategoryCommentatorsService.loadBaseNames(
      bookCategoriesSource(book),
    );
    if (baseNames == null) return null;
    if (baseNames.isEmpty) return const [];

    final resolved = <String>[];
    for (final name in baseNames) {
      final match = findMatchingCommentator(
        name,
        availableCommentators,
        commentedBookTitle: book.title,
      );
      if (match != null && !resolved.contains(match)) {
        resolved.add(match);
      }
    }
    return resolved.isEmpty ? null : resolved;
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
}
