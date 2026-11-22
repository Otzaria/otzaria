import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/search/utils/facet_helper.dart';

import 'semantic_availability.dart';

/// האם להציג את המצב בבורר; גם תצוגת הפיתוח מוגבלת למחשבים נתמכים.
bool isSemanticModeVisible(
  SemanticAvailability availability, {
  bool debug = kDebugMode,
}) =>
    availability.hiddenReason != SemanticHiddenReason.unsupportedPlatform &&
    (debug || availability.phase != SemanticAvailabilityPhase.hidden);

/// תצוגה מקדימה בפיתוח: יש הסכמה, אבל חסרים מנוע או נתונים.
bool isSemanticDebugPreview(
  SemanticAvailability availability, {
  bool debug = kDebugMode,
}) =>
    debug && availability.consentGranted && availability.isMissingEngineOrData;

/// האם אפשר לחפש: מנוע מוכן עם הסכמה, או תצוגה מקדימה בפיתוח.
bool canRunSemanticSearch(
  SemanticAvailability availability, {
  bool debug = kDebugMode,
}) =>
    isSemanticModeVisible(availability, debug: debug) &&
    (availability.isUsable ||
        isSemanticDebugPreview(availability, debug: debug));

/// האם ההיקף הוא כל הספרייה (ממדים כמו תקופה אינם מצמצמים לספרים).
bool isWholeLibraryScope(Iterable<String> selection) {
  final categories = FacetHelper.categoryFacetsOf(selection);
  return categories.isEmpty || categories.contains('/');
}

/// מפתחות של ספרים אישיים ושל מסדים מצורפים — וקטורים רק כשהסט מכסה אותם.
final RegExp _nonOfficialBookKey = RegExp(r'^(uid|db):');
final RegExp _bookKeySegment = RegExp(r'^(id|uid|ext|db):|\|');

/// מנרמל את ההיקף בלי להשמיט בחירה מפורשת ולהרחיב אותה לכל הספרייה.
List<String> semanticScopeFacets(Iterable<String> selection) {
  final facets = selection.toSet().toList();
  if (facets.contains('/')) {
    facets.removeWhere((f) => f != '/' && !FacetHelper.isDimensionFacet(f));
  } else if (FacetHelper.categoryFacetsOf(facets).isEmpty) {
    facets.add('/');
  }
  return facets..sort();
}

/// האם facet של ספר או קטגוריה נתמך, לפני נרמול של בחירת כל הספרייה.
/// [coveredBooks] — מפתחות הספרים שהסט מכסה (ראו [officialCategoryFilter]).
bool isSemanticScopeFacetSupported(
  String facet, {
  bool includeLexical = false,
  bool Function(String facet)? isOfficialCategory,
  Set<String> coveredBooks = const {},
}) {
  if (includeLexical || facet == '/' || FacetHelper.isDimensionFacet(facet)) {
    return true;
  }
  final segments = facet.split('/');
  final isBook = _bookKeySegment.hasMatch(segments.last);
  if (isBook && coveredBooks.contains(segments.last)) return true;
  if (segments.any(_nonOfficialBookKey.hasMatch)) return false;
  final categoryPath = isBook
      ? segments.sublist(0, segments.length - 1).join('/')
      : facet;
  final searchableCategory = isOfficialCategory?.call(categoryPath);
  if (searchableCategory != true &&
      BookDatabaseResolver.likelySource(categoryPath: facet) !=
          BookSource.official) {
    return false;
  }
  return categoryPath.isEmpty || (searchableCategory ?? true);
}

/// האם בקטגוריה של [facet] יש ספר רשמי או ספר שמפתחו ב-[coveredBooks];
/// `null` כשהספרייה לא נטענה.
bool Function(String facet)? officialCategoryFilter(
  Library? library, {
  Set<String> coveredBooks = const {},
}) {
  if (library == null) return null;
  return (facet) {
    // פסיק בשם תיקייה הוא מפריד ב-facet, ולכן משווים לנתיב ה-facet של התיקייה.
    Category? category = library;
    while (category != null && FacetHelper.categoryFacet(category) != facet) {
      category = category.subCategories.where((child) {
        final path = FacetHelper.categoryFacet(child);
        return facet == path || facet.startsWith('$path/');
      }).firstOrNull;
    }
    return category != null && _hasSearchableBook(category, coveredBooks);
  };
}

bool _hasSearchableBook(Category category, Set<String> coveredBooks) =>
    category.books.any(
      (book) =>
          book.source.isOfficial ||
          coveredBooks.contains(BookIdentity.keyOf(book)),
    ) ||
    category.subCategories.any(
      (child) => _hasSearchableBook(child, coveredBooks),
    );
