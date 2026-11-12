import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פותר כתובת (ref) טקסטואלית — כמו "ב ע\"א" בגמרא או "רטו א" בשו"ע — לאינדקס
/// שורה (0-based) בספר היעד, כדי שקישור-משתמש יוכל להיפתח במקום הנכון.
/// מחזיר null אם הספר או הכתובת לא נמצאו.
typedef UserLinkRefResolver =
    Future<int?> Function({
      required String targetTitle,
      required int? targetCategoryId,
      required bool targetIsUserBook,
      required String ref,
    });

/// המימוש האמיתי: בוחר את המסד הנכון (רשמי/אישי), מאתר את הספר לפי כותרת
/// (+קטגוריה אם ידועה), וממיר את ה-ref לשורה דרך התאמת ה-TOC של הספר —
/// אותו מנגנון של איתור-מקורות ([SeforimRepository.getTocEntriesForReference]).
Future<int?> resolveUserLinkTargetLine({
  required String targetTitle,
  required int? targetCategoryId,
  required bool targetIsUserBook,
  required String ref,
}) async => _resolveTargetLine(
  repo: await _repositoryFor(targetIsUserBook),
  targetTitle: targetTitle,
  targetCategoryId: targetCategoryId,
  ref: ref,
);

Future<int?> _resolveTargetLine({
  required SeforimRepository? repo,
  required String targetTitle,
  required int? targetCategoryId,
  required String ref,
}) async {
  if (repo == null) return null;

  final book = await _bookByTitle(repo, targetTitle, targetCategoryId);
  final bookId = book?.id;
  if (bookId == null) return null;

  final tokens = normalizeForFindRefMatch(
    ref,
  ).split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;

  var matches = await repo.getTocEntriesForReference(
    bookId,
    book!.title,
    queryTokens: tokens,
  );
  if (matches.isEmpty) {
    matches = await repo.getAltTocEntriesForReference(
      bookId,
      book.title,
      queryTokens: tokens,
    );
  }
  if (matches.isEmpty) return null;
  return matches.first['segment'] as int?;
}

/// בודק אם ספר קיים במסד הנכון (אישי/רשמי) — לאימות ספר מקור רשמי בייבוא,
/// כדי לחסום קישור עם כותרת-מקור שגויה שתיצור קישור מת.
typedef UserLinkSourceChecker =
    Future<bool> Function({
      required String title,
      required int? categoryId,
      required bool isUserBook,
    });

/// המימוש האמיתי של [UserLinkSourceChecker].
Future<bool> userLinkSourceBookExists({
  required String title,
  required int? categoryId,
  required bool isUserBook,
}) async => _bookExists(await _repositoryFor(isUserBook), title, categoryId);

Future<bool> _bookExists(
  SeforimRepository? repo,
  String title,
  int? categoryId,
) async {
  if (repo == null) return false;
  return await _bookByTitle(repo, title, categoryId) != null;
}

/// שורת הספר בלבד: מחברים, נושאים ופרטי דפוס אינם נחוצים לפתירה, ועולים
/// ארבע שאילתות נוספות לכל כתובת בקובץ.
Future<Book?> _bookByTitle(
  SeforimRepository repo,
  String title,
  int? categoryId,
) {
  final books = repo.database.bookDao;
  return categoryId != null
      ? books.getBookByTitleAndCategory(title, categoryId)
      : books.getBookByTitle(title);
}

/// מאתר ספר לפי כותרת בשני המסדים — לקבצים בפורמט ה-native שאינם מציינים
/// אישי/רשמי. כותרת שקיימת בשניהם אינה מספיקה לזיהוי חד-משמעי.
typedef UserLinkBookLocator =
    Future<({bool isUserBook, int? categoryId, int totalLines})?> Function(
      String title,
    );

/// המימוש האמיתי של [UserLinkBookLocator].
Future<({bool isUserBook, int? categoryId, int totalLines})?>
locateUserLinkBook(String title) => _locateIn(_repositoryFor, title);

class AmbiguousUserLinkBookException implements Exception {
  final String title;

  const AmbiguousUserLinkBookException(this.title);
}

class UnavailableUserLinkCatalogException implements Exception {
  const UnavailableUserLinkCatalogException();
}

@visibleForTesting
Future<({bool isUserBook, int? categoryId, int totalLines})?>
locateUserLinkBookInRepositories(
  String title, {
  required SeforimRepository? userRepository,
  required SeforimRepository? officialRepository,
}) => _locateIn(
  (isUserBook) async => isUserBook ? userRepository : officialRepository,
  title,
);

Future<({bool isUserBook, int? categoryId, int totalLines})?> _locateIn(
  Future<SeforimRepository?> Function(bool isUserBook) repositoryFor,
  String title,
) async {
  final userRepository = await repositoryFor(true);
  final userBook = userRepository == null
      ? null
      : await _bookByTitle(userRepository, title, null);
  Book? officialBook;
  try {
    final officialRepository = await repositoryFor(false);
    officialBook = officialRepository == null
        ? null
        : await _bookByTitle(officialRepository, title, null);
  } on Exception {
    throw const UnavailableUserLinkCatalogException();
  }
  if (userBook != null && officialBook != null) {
    throw AmbiguousUserLinkBookException(title);
  }
  final book = userBook ?? officialBook;
  if (book == null) return null;
  return (
    isUserBook: userBook != null,
    categoryId: book.categoryId,
    totalLines: book.totalLines,
  );
}

/// שלושת הפותרים מול [userDb] *הנתון* ולא ההולדר הגלובלי (סריקת תיקייה).
/// [officialError] נזרק בכל פנייה לספרייה הרשמית, כמו כשל באתחולה.
({
  UserLinkRefResolver resolveRef,
  UserLinkSourceChecker sourceExists,
  UserLinkBookLocator locateBook,
})
userLinkResolversFor(
  MyDatabase userDb, {
  SeforimRepository? officialRepository,
  Exception? officialError,
}) {
  final userRepo = SeforimRepository(userDb);
  final locatedBooks =
      <String, Future<({bool isUserBook, int? categoryId, int totalLines})?>>{};
  Future<SeforimRepository?> repositoryFor(bool isUserBook) async {
    if (isUserBook) return userRepo;
    if (officialError != null) throw officialError;
    return officialRepository ?? await officialUserLinkRepository();
  }

  return (
    resolveRef:
        ({
          required targetTitle,
          required targetCategoryId,
          required targetIsUserBook,
          required ref,
        }) async => _resolveTargetLine(
          repo: await repositoryFor(targetIsUserBook),
          targetTitle: targetTitle,
          targetCategoryId: targetCategoryId,
          ref: ref,
        ),
    sourceExists:
        ({
          required title,
          required categoryId,
          required isUserBook,
        }) async =>
            _bookExists(await repositoryFor(isUserBook), title, categoryId),
    locateBook: (title) => locatedBooks.putIfAbsent(
      title,
      () => _locateIn(repositoryFor, title),
    ),
  );
}

/// המסד שבו נמצא ספר היעד — אישי (user_books.db) או רשמי (seforim.db).
Future<SeforimRepository?> _repositoryFor(bool isUserBook) async {
  if (isUserBook) {
    return UserBooksDatabaseHolder.instance.repositoryIfInitialized ??
        await UserBooksDatabaseHolder.instance.repository;
  }
  return officialUserLinkRepository();
}

/// seforim.db של התוכנה, או null כשאינו זמין.
Future<SeforimRepository?> officialUserLinkRepository() async {
  final provider = SqliteDataProvider.instance;
  if (!provider.isInitialized && !Settings.isInitialized) return null;
  if (!provider.isInitialized) await provider.initialize();
  return provider.repository;
}

/// מסד מצורף שהייבוא רשאי לחפש בו, כפי שנשלח ל-isolate (ערכים פשוטים בלבד).
typedef AttachedLinkLibrary = ({
  String slug,
  String path,
  bool immutable,
  bool visible,
});

/// ספרי המסדים המצורפים לפתירת צד של קישור או גרסה, לפי סדר העדיפות.
/// כל מסד נפתח מוקשח ולקריאה בלבד ([MyDatabase.untrusted]).
class AttachedLinkBooks {
  AttachedLinkBooks(this._libraries);

  /// [libraries] ממוינים לפי עדיפות; [visible] קובע אם נכללים בחיפוש בלי slug.
  factory AttachedLinkBooks.open(List<AttachedLinkLibrary> libraries) =>
      AttachedLinkBooks([
        for (final library in libraries)
          (
            slug: library.slug,
            visible: library.visible,
            repository: SeforimRepository(
              MyDatabase.untrusted(library.path, immutable: library.immutable),
            ),
          ),
      ]);

  static final AttachedLinkBooks none = AttachedLinkBooks(const []);

  final List<({String slug, bool visible, SeforimRepository repository})>
  _libraries;
  final _located =
      <(String, String?), Future<({String slug, int totalLines})?>>{};

  bool get isEmpty => _libraries.isEmpty;

  /// הספר [title] במסד [slug], או — בלי slug — במסד הגלוי הראשון שמכיל אותו.
  Future<({String slug, int totalLines})?> locate(
    String title, {
    String? slug,
  }) => _located.putIfAbsent((title, slug), () async {
    for (final library in _libraries) {
      if (slug != null ? library.slug != slug : !library.visible) continue;
      try {
        final book = await _bookByTitle(library.repository, title, null);
        if (book != null) {
          return (slug: library.slug, totalLines: book.totalLines);
        }
      } on Exception catch (e) {
        debugPrint('[AttachedLinkBooks] ${library.slug} unreadable: $e');
      }
    }
    return null;
  });

  /// השורה (0-based) של [ref] בספר [title] שבמסד [slug].
  Future<int?> resolveRef(String slug, String title, String ref) async {
    final library = _libraries.where((l) => l.slug == slug).firstOrNull;
    if (library == null) return null;
    return _resolveTargetLine(
      repo: library.repository,
      targetTitle: title,
      targetCategoryId: null,
      ref: ref,
    );
  }

  void close() {
    for (final library in _libraries) {
      library.repository.database.close();
    }
  }
}
