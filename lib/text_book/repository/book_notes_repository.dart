import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/text_book/models/book_notes.dart';

/// הערות השוליים (`line_note`) לפי ספר, ממטמון: הספר, ההדפסה והחלונית שואלים
/// על אותו ספר שוב ושוב, והטעינה היא שאילתה אחת לספר כולו.
class BookNotesRepository {
  BookNotesRepository._();

  static final BookNotesRepository instance = BookNotesRepository._();

  static const int _maxBooks = 32;
  final _cache = <String, Future<BookNotes>>{};

  /// הטוען מהמסד — מוחלף בבדיקות.
  @visibleForTesting
  Future<BookNotes> Function(
    String title, {
    int? categoryId,
    required BookSource source,
  })?
  debugLoader;

  /// האם הספר מוגש מהמסד — מוחלף בבדיקות. בלעדיו, [debugLoader] לבדו מדלג
  /// על הבדיקה.
  @visibleForTesting
  Future<bool> Function(String title, {int? categoryId, String? fileType})?
  debugIsDatabaseBook;

  /// ההערות של [title]. ספר אישי וספר מקובץ שומרים את ההערות בשורה; הטבלה
  /// מכסה רק שורות בסיס, ולכן גם מהדורה ([versionTitle]) נשארת בשורה.
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
    final key = '${source.wireKey}|$categoryId|$title';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final future = _load(title, categoryId, source, fileType);
    _cache[key] = future;
    if (_cache.length > _maxBooks) _cache.remove(_cache.keys.first);
    return future;
  }

  Future<BookNotes> _load(
    String title,
    int? categoryId,
    BookSource source,
    String? fileType,
  ) async {
    if (source.isOfficial &&
        !await _isDatabaseBook(title, categoryId, fileType)) {
      return BookNotes.empty;
    }
    final loader = debugLoader;
    if (loader != null) {
      return loader(title, categoryId: categoryId, source: source);
    }
    return DatabaseLibraryProvider.instance.getBookNotes(
      title,
      categoryId: categoryId,
      source: source,
    );
  }

  // שאלה סינכרונית על המיפוי נכשלת בטאב משוחזר בעלייה, לפני שהקטלוג נבנה.
  Future<bool> _isDatabaseBook(
    String title,
    int? categoryId,
    String? fileType,
  ) async {
    final check = debugIsDatabaseBook;
    if (check != null) {
      return check(title, categoryId: categoryId, fileType: fileType);
    }
    if (debugLoader != null) return true;
    try {
      final provider = await LibraryProviderManager.instance
          .resolveProviderForBook(
            title,
            categoryId: categoryId,
            fileType: fileType,
          );
      return provider is DatabaseLibraryProvider;
    } catch (e) {
      debugPrint('⚠️ BookNotesRepository: provider lookup failed "$title": $e');
      return false;
    }
  }

  /// מרוקן את המטמון — חובה כשמסד הספרייה מוחלף.
  void clear() => _cache.clear();
}
