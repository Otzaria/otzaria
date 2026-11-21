import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/models/book_source.dart';

/// כינויי הספר של [item] לחיפוש ברשימות ההיסטוריה והסימניות.
/// null — מטמון הכינויים עוד לא נטען, והרשימה תנסה שוב.
List<String>? bookmarkSearchAliases(dynamic item) {
  final bookmark = item as Bookmark;
  if (bookmark.isSearch) return const [];
  final id = bookmark.book.id;
  final cache = AcronymsCache.instance;
  final source = bookmark.book.source;
  if (id == null) {
    // אין כינויים מילוליים לחכות להם — רק הנגזרים מהכותרת.
  } else if (source is AttachedBookSource) {
    if (cache.attachedAcronymsOf(source.slug) == null) return null;
  } else if (!cache.isLoaded) {
    return null;
  }
  return cache.aliasesFor(source, id, bookmark.book.title);
}

/// חיפושים שמורים מכילים שאילתה, ולא שם ספר שניתן לשנות את כתיבו.
String? bookmarkSearchTitle(dynamic item) {
  final bookmark = item as Bookmark;
  return bookmark.isSearch ? null : bookmark.book.title;
}
