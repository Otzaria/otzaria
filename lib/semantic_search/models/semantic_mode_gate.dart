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

/// מפתחות של ספרים אישיים ושל מסדים מצורפים — אין להם וקטורים.
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

/// האם יש בבחירה ספר או קטגוריה שדורשים בדיקת כיסוי.
bool needsSemanticScopeCoverage(Iterable<String> selection) => selection.any(
  (facet) => facet != '/' && !FacetHelper.isDimensionFacet(facet),
);

/// האם facet של ספר או קטגוריה נתמך, לפני נרמול של בחירת כל הספרייה.
bool isSemanticScopeFacetSupported(
  String facet, {
  bool includeLexical = false,
  bool Function(String facet)? isOfficialCategory,
  bool Function(String facet)? isCoveredFacet,
}) {
  if (includeLexical || facet == '/' || FacetHelper.isDimensionFacet(facet)) {
    return true;
  }
  if (isCoveredFacet != null) return isCoveredFacet(facet);
  if (BookDatabaseResolver.likelySource(categoryPath: facet) !=
      BookSource.official) {
    return false;
  }
  final segments = facet.split('/');
  if (segments.any(_nonOfficialBookKey.hasMatch)) return false;
  final categoryPath = _bookKeySegment.hasMatch(segments.last)
      ? segments.sublist(0, segments.length - 1).join('/')
      : facet;
  return categoryPath.isEmpty ||
      (isOfficialCategory?.call(categoryPath) ?? true);
}

/// האם בקטגוריה של [facet] יש ספר מהספרייה הרשמית; `null` כשהספרייה לא נטענה.
bool Function(String facet)? officialCategoryFilter(Library? library) {
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
    return category != null && _hasOfficialBook(category);
  };
}

bool _hasOfficialBook(Category category) =>
    category.books.any((book) => book.source.isOfficial) ||
    category.subCategories.any(_hasOfficialBook);

final Expando<(Set<String>, Set<String>)> _coveredFacetsCache = Expando();

/// האם ל-facet של ספר יש וקטורים, או שבקטגוריה יש ספר כזה; `null` כשהספרייה
/// או הספרים המכוסים ([coveredFilePaths], לפי filePath באינדקס) לא ידועים.
bool Function(String facet)? coveredFacetFilter(
  Library? library,
  Set<String>? coveredFilePaths,
) {
  if (library == null || coveredFilePaths == null) return null;
  final cached = _coveredFacetsCache[library];
  final facets = cached != null && identical(cached.$1, coveredFilePaths)
      ? cached.$2
      : _coveredFacets(library, coveredFilePaths);
  _coveredFacetsCache[library] = (coveredFilePaths, facets);
  return facets.contains;
}

Set<String> _coveredFacets(Library library, Set<String> coveredFilePaths) {
  final facets = <String>{};
  bool visit(Category category) {
    var covered = false;
    for (final book in category.books) {
      if (coveredFilePaths.contains(BookIdentity.indexedFilePath(book))) {
        facets.add(
          FacetHelper.buildBookFacet(
            FacetHelper.resolveCategoryPath(book),
            book,
          ),
        );
        covered = true;
      }
    }
    for (final child in category.subCategories) {
      if (visit(child)) covered = true;
    }
    if (covered) facets.add(FacetHelper.categoryFacet(category));
    return covered;
  }

  visit(library);
  return facets;
}
