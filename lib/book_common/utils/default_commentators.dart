import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart'
    show kExternalTargetOfficial;
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
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
  /// נקרא מהמסד של הספר (seforim.db או מסד מצורף); לספר אישי — ריק. אחריהם
  /// באים מפרשים ממסדים מצורפים אחרים (`external_default_commentator`).
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
      OfficialBookSource() =>
        _needsReopen ? await _reopenedRepository() : _provider.repository,
      UserBookSource() => null,
      AttachedBookSource(:final slug) =>
        await AttachedLibraryRegistry.instance.repositoryFor(slug),
    };
    if (repository == null) return empty;

    final dbBook = await BookDatabaseResolver.findBookInRepository(
      repository,
      book.title,
      categoryId: book.categoryId,
    );
    if (dbBook == null) return empty;

    final linkDao = repository.database.linkDao;
    final commentatorRows = await linkDao.selectDefaultCommentators(dbBook.id);
    final targumRows = await linkDao.selectDefaultTargums(dbBook.id);

    final commentators = [
      for (final row in commentatorRows)
        (
          title: row['targetBookTitle'] as String,
          position: (row['position'] as num).toInt(),
        ),
    ];
    final targums = [
      for (final row in targumRows) row['targetBookTitle'] as String,
    ];
    if (AttachedLibraryRegistry.instance.visibleLibraries.isEmpty) {
      return (commentators: commentators, targums: targums);
    }
    final external = await _externalDefaults(book);
    var next = commentators.fold(-1, (m, c) => c.position > m ? c.position : m);
    for (final title in external.commentators) {
      if (commentators.any((c) => c.title == title)) continue;
      commentators.add((title: title, position: ++next));
    }
    for (final title in external.targums) {
      if (!targums.contains(title)) targums.add(title);
    }
    return (commentators: commentators, targums: targums);
  }

  /// מפרשים ותרגומים שמסדים מצורפים אחרים מציעים ל-[book], לפי עדיפות המסד
  /// ואז `position`. נכלל רק ספר שמקושר בפועל ל-[book] ומוצג ברשימת מפרשיו.
  static Future<({List<String> commentators, List<String> targums})>
  _externalDefaults(Book book) async {
    final commentators = <String>[];
    final targums = <String>[];
    final ownSlug = switch (book.source) {
      AttachedBookSource(:final slug) => slug,
      _ => null,
    };
    final linked = await ExternalLinkRepository.instance.commentatorSources(
      title: book.title,
      categoryId: book.categoryId,
      source: book.source,
    );
    final registry = AttachedLibraryRegistry.instance;
    for (final library in registry.visibleLibraries) {
      final source = BookSource.attached(library.slug);
      if (library.slug == ownSlug || !linked.containsValue(source)) continue;
      final repository = await registry.repositoryFor(library.slug);
      if (repository == null) continue;
      final rows = await repository.database.linkDao
          .selectExternalDefaultCommentators(book.title);
      for (final row in rows) {
        final title = row['commentatorTitle'] as String;
        if (linked[title] != source) continue;
        if (!_targetsBook(row['targetSource'] as String?, ownSlug)) continue;
        switch (row['kind']) {
          case 'commentator':
            commentators.add(title);
          case 'targum':
            targums.add(title);
        }
      }
    }
    return (commentators: commentators, targums: targums);
  }

  /// `targetSource`: NULL — כל מקור; 'official' — הספרייה הרשמית; אחרת
  /// library_id של המסד שבו הספר.
  static bool _targetsBook(String? targetSource, String? ownSlug) {
    final value = targetSource?.trim() ?? '';
    if (value.isEmpty) return true;
    if (value.toLowerCase() == kExternalTargetOfficial) return ownSlug == null;
    return AttachedLibraryProbe.sanitizeSlug(value) == ownSlug;
  }

  static SqliteDataProvider get _provider => SqliteDataProvider.instance;

  /// חיבור שמעולם לא נפתח שייך לאתחול האפליקציה.
  static bool get _needsReopen =>
      !_provider.isInitialized && _provider.canReopenAfterClose;

  static Future<SeforimRepository?> _reopenedRepository() async {
    await _provider.initialize();
    return _provider.repository;
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
