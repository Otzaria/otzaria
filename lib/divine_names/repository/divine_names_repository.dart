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
    final loader = debugLoader;
    if (loader == null &&
        source.isOfficial &&
        LibraryProviderManager.instance.getProviderForBook(
              title,
              categoryId: categoryId,
              fileType: fileType,
            )
            is! DatabaseLibraryProvider) {
      return Future.value(DivineNameSpans.empty);
    }
    final key = '${source.wireKey}|$categoryId|$title';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final future = loader != null
        ? loader(title, categoryId: categoryId, source: source)
        : DatabaseLibraryProvider.instance.getDivineNameSpans(
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
