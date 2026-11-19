import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/models/library.dart' show normalizeBookTitle;
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

typedef LocatedUserLinkBook = ({
  String title,
  bool isUserBook,
  int? categoryId,
  int totalLines,
  bool isDependentOnly,
});

/// מאתר ספר לקישורי native. כותרת שקיימת במסד האישי וברשמי היא דו-משמעית.
typedef UserLinkBookLocator =
    Future<LocatedUserLinkBook?> Function(
      String title,
    );

/// המימוש האמיתי של [UserLinkBookLocator].
Future<LocatedUserLinkBook?> locateUserLinkBook(String title) =>
    _locateIn(_repositoryFor, title);

class AmbiguousUserLinkBookException implements Exception {
  final String title;

  const AmbiguousUserLinkBookException(this.title);
}

class UnavailableUserLinkCatalogException implements Exception {
  const UnavailableUserLinkCatalogException();
}

@visibleForTesting
Future<LocatedUserLinkBook?> locateUserLinkBookInRepositories(
  String title, {
  required SeforimRepository? userRepository,
  required SeforimRepository? officialRepository,
}) => _locateIn(
  (isUserBook) async => isUserBook ? userRepository : officialRepository,
  title,
);

/// כותרות המסד לפי [normalizeBookTitle], נבנות פעם אחת לכל מאתר ולא לכל החטאה.
typedef _LooseTitles =
    Map<SeforimRepository, Future<Map<String, List<String>>>>;

Future<Map<String, List<String>>> _looseTitlesOf(SeforimRepository repo) async {
  final byKey = <String, List<String>>{};
  try {
    for (final row in await repo.database.bookDao.selectAllLocalBooksSlim()) {
      final title = row['title'] as String;
      (byKey[normalizeBookTitle(title)] ??= []).add(title);
    }
  } on Exception catch (e) {
    // כמו לפני הגיבוי: ספר שלא נמצא בהתאמה מדויקת פשוט אינו נמצא.
    debugPrint('⚠️ [UserLinkBookLocator] $e');
  }
  return byKey;
}

Future<LocatedUserLinkBook?> _locateIn(
  Future<SeforimRepository?> Function(bool isUserBook) repositoryFor,
  String title, [
  _LooseTitles? looseTitles,
]) async {
  final userRepository = await repositoryFor(true);
  final userBook = userRepository == null
      ? null
      : await _bookByTitle(userRepository, title, null);
  final SeforimRepository? officialRepository;
  Book? officialBook;
  try {
    officialRepository = await repositoryFor(false);
    officialBook = officialRepository == null
        ? null
        : await _bookByTitle(officialRepository, title, null);
  } on Exception {
    throw const UnavailableUserLinkCatalogException();
  }
  if (userBook != null && officialBook != null) {
    throw AmbiguousUserLinkBookException(title);
  }
  var isUserBook = userBook != null;
  var book = userBook ?? officialBook;
  if (book == null) {
    // שם קובץ ב-Windows אינו יכול להכיל ", ולכן `ריף שבת` מכוון ל-`רי"ף שבת`.
    final key = normalizeBookTitle(title);
    final cache = looseTitles ?? {};
    final loose = [
      for (final (isUser, repo) in [
        (true, userRepository),
        (false, officialRepository),
      ])
        if (repo != null)
          for (final match
              in (await cache.putIfAbsent(
                    repo,
                    () => _looseTitlesOf(repo),
                  ))[key] ??
                  const <String>[])
            (isUser, repo, match),
    ];
    if (loose.length != 1) return null;
    final (isUser, repo, match) = loose.single;
    isUserBook = isUser;
    book = await _bookByTitle(repo, match, null);
    if (book == null) return null;
  }
  return (
    title: book.title,
    isUserBook: isUserBook,
    categoryId: book.categoryId,
    totalLines: book.totalLines,
    isDependentOnly: _isDependentOnly(book),
  );
}

// ספר תלוי יכול להיות מסומן גם כספר בסיס בפני עצמו.
bool _isDependentOnly(Book book) =>
    !book.isBaseBook && book.dependenceType?.trim().isNotEmpty == true;

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
  final locatedBooks = <String, Future<LocatedUserLinkBook?>>{};
  final _LooseTitles looseTitles = {};
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
      () => _locateIn(repositoryFor, title, looseTitles),
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
      <
        (String, String?),
        Future<({String slug, int totalLines, bool isDependentOnly})?>
      >{};

  bool get isEmpty => _libraries.isEmpty;

  /// הספר [title] במסד [slug], או — בלי slug — במסד הגלוי הראשון שמכיל אותו.
  Future<({String slug, int totalLines, bool isDependentOnly})?> locate(
    String title, {
    String? slug,
  }) => _located.putIfAbsent((title, slug), () async {
    for (final library in _libraries) {
      if (slug != null ? library.slug != slug : !library.visible) continue;
      try {
        final book = await _bookByTitle(library.repository, title, null);
        if (book != null) {
          return (
            slug: library.slug,
            totalLines: book.totalLines,
            isDependentOnly: _isDependentOnly(book),
          );
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
