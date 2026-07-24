import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
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
}) async {
  final repo = await _repositoryFor(targetIsUserBook);
  if (repo == null) return null;

  final book = targetCategoryId != null
      ? await repo.getBookByTitleAndCategory(targetTitle, targetCategoryId)
      : await repo.getBookByTitle(targetTitle);
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
}) async {
  final repo = await _repositoryFor(isUserBook);
  if (repo == null) return false;
  final book = categoryId != null
      ? await repo.getBookByTitleAndCategory(title, categoryId)
      : await repo.getBookByTitle(title);
  return book != null;
}

/// מאתר ספר לפי כותרת בשני המסדים — לקבצים בפורמט ה-native שאינם מציינים
/// אישי/רשמי. אישי נבדק ראשון (עקרון preferUserBooks). null אם לא נמצא.
typedef UserLinkBookLocator =
    Future<({bool isUserBook, int? categoryId, int totalLines})?> Function(
      String title,
    );

/// המימוש האמיתי של [UserLinkBookLocator].
Future<({bool isUserBook, int? categoryId, int totalLines})?>
locateUserLinkBook(String title) async {
  for (final isUserBook in const [true, false]) {
    final repo = await _repositoryFor(isUserBook);
    final book = await repo?.getBookByTitle(title);
    if (book != null) {
      return (
        isUserBook: isUserBook,
        categoryId: book.categoryId,
        totalLines: book.totalLines,
      );
    }
  }
  return null;
}

/// המסד שבו נמצא ספר היעד — אישי (user_books.db) או רשמי (seforim.db).
Future<SeforimRepository?> _repositoryFor(bool isUserBook) async {
  if (isUserBook) {
    return UserBooksDatabaseHolder.instance.repositoryIfInitialized ??
        await UserBooksDatabaseHolder.instance.repository;
  }
  final provider = SqliteDataProvider.instance;
  if (!provider.isInitialized) await provider.initialize();
  return provider.repository;
}
