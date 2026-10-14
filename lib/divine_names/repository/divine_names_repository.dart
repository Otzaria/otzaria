import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/models/book_source.dart';

/// מופעי שמות הקודש לפי ספר, ממטמון: הספר הנקרא וספרי המפרשים שבחלונית
/// שואלים על אותו ספר שוב ושוב, והטעינה היא שאילתה אחת לספר כולו.
class DivineNamesRepository {
  DivineNamesRepository._();

  static final DivineNamesRepository instance = DivineNamesRepository._();

  static const int _maxBooks = 32;
  final _cache = <String, Future<DivineNameSpans>>{};

  /// הטוען בפועל — מוחלף בבדיקות.
  @visibleForTesting
  Future<DivineNameSpans> Function(
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

  /// המופעים של [title]. ספר אישי, מהדורה חלופית ([versionTitle]) או ספר
  /// שאינו מוגש מהמסד ממוספרים אחרת — עבורם אין מופעים.
  Future<DivineNameSpans> spansFor(
    String title, {
    int? categoryId,
    BookSource source = BookSource.official,
    String? fileType,
    String? versionTitle,
  }) {
    if (source.isUser || versionTitle != null) {
      return Future.value(DivineNameSpans.empty);
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

  Future<DivineNameSpans> _load(
    String title,
    int? categoryId,
    BookSource source,
    String? fileType,
  ) async {
    if (source.isOfficial &&
        !await _isDatabaseBook(title, categoryId, fileType)) {
      return DivineNameSpans.empty;
    }
    final loader = debugLoader;
    if (loader != null) {
      return loader(title, categoryId: categoryId, source: source);
    }
    return DatabaseLibraryProvider.instance.getDivineNameSpans(
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
      debugPrint(
        '⚠️ DivineNamesRepository: provider lookup failed "$title": $e',
      );
      return false;
    }
  }

  /// מרוקן את המטמון — חובה כשמסד הספרייה מוחלף.
  void clear() => _cache.clear();
}
