import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/text_book/models/book_notes.dart';

/// הערות השוליים (`line_note`) לפי ספר, ממטמון: הספר הנקרא, ההדפסה והחלונית
/// שואלים על אותו ספר שוב ושוב, והטעינה היא שאילתה אחת לספר כולו.
class BookNotesRepository {
  BookNotesRepository._();

  static final BookNotesRepository instance = BookNotesRepository._();

  static const int _maxBooks = 32;
  final _cache = <String, Future<BookNotes>>{};

  /// הטוען בפועל — מוחלף בבדיקות.
  @visibleForTesting
  Future<BookNotes> Function(
    String title, {
    int? categoryId,
    required BookSource source,
  })?
  debugLoader;

  /// ההערות של [title]. ספר אישי וספר שאינו מוגש מהמסד שומרים את ההערות
  /// בשורה עצמה; הטבלה מכסה רק שורות בסיס, ולכן מהדורה חלופית
  /// ([versionTitle]) נשארת במסלול ה-inline.
  Future<BookNotes> notesFor(
    String title, {
    int? categoryId,
    BookSource source = BookSource.official,
    String? fileType,
    String? versionTitle,
  }) {
    if (source.isUser || versionTitle != null) {
      return Future.value(BookNotes.empty);
    }
    final loader = debugLoader;
    if (loader == null &&
        source.isOfficial &&
        LibraryProviderManager.instance.getProviderForBook(
              title,
              categoryId: categoryId,
              fileType: fileType,
            )
            is! DatabaseLibraryProvider) {
      return Future.value(BookNotes.empty);
    }
    final key = '${source.wireKey}|$categoryId|$title';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final future = loader != null
        ? loader(title, categoryId: categoryId, source: source)
        : DatabaseLibraryProvider.instance.getBookNotes(
            title,
            categoryId: categoryId,
            source: source,
          );
    _cache[key] = future;
    if (_cache.length > _maxBooks) _cache.remove(_cache.keys.first);
    return future;
  }

  /// מרוקן את המטמון — חובה כשמסד הספרייה מוחלף.
  void clear() => _cache.clear();
}
