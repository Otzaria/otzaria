import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath;

/// מאתר את הגבלת המו"ל והבאנר של ספר מתוך המסד שלו.
///
/// רק הספרייה הרשמית ומסדים מצורפים נבדקים; ספר אישי — אין הגבלה. מזהי ספרים
/// חופפים בין מסדים, ולכן כל חיפוש נעשה במסד של מקור הספר בלבד. האיתור כולו
/// בזיכרון, מתוך הטבלאות שנטענו פעם אחת לכל מסד.
class BookProtectionRepository {
  BookProtectionRepository._();

  static final BookProtectionRepository instance = BookProtectionRepository._();

  /// מחליף את איתור המסד לפי מקור — לבדיקות בלבד.
  @visibleForTesting
  Future<SeforimRepository?> Function(BookSource source)? debugRepositoryFor;

  @visibleForTesting
  void debugReset() => debugRepositoryFor = null;

  /// ההגבלה של [book]. גרסה חלופית (versionTitle) חולקת את כותרת הספר הראשי.
  Future<BookProtection> forBook(Book book) {
    if (book is! TextBook) return Future.value(BookProtection.none);
    if (book.source.isOfficial && !book.isOfficialLibraryBook) {
      return Future.value(BookProtection.none);
    }
    return forTitle(
      book.title,
      source: book.source,
      categoryId: book.categoryId,
    );
  }

  /// ההגבלה של ספר היעד של [link] (מפרש, קישור).
  Future<BookProtection> forLink(Link link) async {
    final source = link.targetSource;
    final bookId = link.targetBookId;
    if (bookId == null) {
      return forTitle(
        getTitleFromPath(link.path2),
        source: source,
        categoryId: link.targetCategoryId,
      );
    }
    final tables = await _tablesFor(source);
    if (tables == null) return BookProtection.none;
    return _fromTables(tables, bookId);
  }

  /// ההגבלה של הספר [title] במסד של [source]. עם [categoryId] נדרשת התאמה
  /// מדויקת — ספר בשם זהה בקטגוריה אחרת הוא ספר אחר.
  Future<BookProtection> forTitle(
    String title, {
    BookSource source = BookSource.official,
    int? categoryId,
  }) async {
    if (title.trim().isEmpty) return BookProtection.none;
    final tables = await _tablesFor(source);
    final candidates = tables?.booksByTitle[title];
    if (tables == null || candidates == null) return BookProtection.none;
    for (final candidate in candidates) {
      if (categoryId == null || candidate.categoryId == categoryId) {
        return _fromTables(tables, candidate.id);
      }
    }
    return BookProtection.none;
  }

  /// ההגבלה המחמירה מבין [titles] (למשל מפרשים שנכללים בהדפסה).
  Future<BookProtection> strictestForTitles(
    Iterable<String> titles, {
    BookSource source = BookSource.official,
  }) async {
    var result = BookProtection.none;
    for (final title in titles.toSet()) {
      result = result.strictest(await forTitle(title, source: source));
    }
    return BookProtection(level: result.level);
  }

  /// ההגבלה המחמירה מבין ספרי היעד של [links].
  Future<BookProtection> strictestForLinks(Iterable<Link> links) async {
    var result = BookProtection.none;
    final seen = <String>{};
    for (final link in links) {
      final key =
          '${link.targetSource.wireKey}|${link.targetBookId}|${link.path2}';
      if (!seen.add(key)) continue;
      result = result.strictest(await forLink(link));
    }
    return BookProtection(level: result.level);
  }

  Future<BookProtectionTables?> _tablesFor(BookSource source) async {
    if (source.isUser) return null;
    try {
      final repository = await _repositoryFor(source);
      return await repository?.getBookProtectionTables();
    } catch (error) {
      debugPrint('BookProtection tables failed for $source: $error');
      return null;
    }
  }

  static BookProtection _fromTables(BookProtectionTables tables, int bookId) {
    final level = tables.levels[bookId] ?? 0;
    final banner = tables.banners[bookId];
    if (level == 0 && banner == null) return BookProtection.none;
    return BookProtection(level: level, bannerText: banner);
  }

  Future<SeforimRepository?> _repositoryFor(BookSource source) async {
    final override = debugRepositoryFor;
    if (override != null) return override(source);
    switch (source) {
      case OfficialBookSource():
        final provider = SqliteDataProvider.instance;
        if (!provider.isInitialized) await provider.initialize();
        return provider.repository;
      case UserBookSource():
        return null;
      case AttachedBookSource(:final slug):
        return AttachedLibraryRegistry.instance.repositoryFor(slug);
    }
  }
}
