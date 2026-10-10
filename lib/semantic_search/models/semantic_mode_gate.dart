import 'package:flutter/foundation.dart' show kDebugMode;
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

/// ההיקף שנשלח למנוע: הבחירה בלי ספרים אישיים ומצורפים, שאין להם וקטורים.
/// [isOfficialCategory] מסנן קטגוריות שכל ספריהן ממסדים מצורפים שמוזגו לעץ.
List<String> semanticScopeFacets(
  Iterable<String> selection, {
  bool Function(String facet)? isOfficialCategory,
}) {
  final facets = [
    for (final facet in selection.toSet())
      if (FacetHelper.isDimensionFacet(facet) ||
          isSemanticScopeFacetSupported(
            facet,
            isOfficialCategory: isOfficialCategory,
          ))
        facet,
  ];
  if (facets.contains('/')) {
    facets.removeWhere((f) => f != '/' && !FacetHelper.isDimensionFacet(f));
  } else if (FacetHelper.categoryFacetsOf(facets).isEmpty) {
    facets.add('/');
  }
  return facets..sort();
}

/// האם facet של ספר או קטגוריה נתמך, לפני נרמול של בחירת כל הספרייה.
bool isSemanticScopeFacetSupported(
  String facet, {
  bool Function(String facet)? isOfficialCategory,
}) {
  if (facet == '/') return true;
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
    Category? category = library;
    for (final title in facet.split('/').where((part) => part.isNotEmpty)) {
      category = category?.subCategories
          .where((child) => child.title == title)
          .firstOrNull;
    }
    return category != null && _hasOfficialBook(category);
  };
}

bool _hasOfficialBook(Category category) =>
    category.books.any((book) => book.source.isOfficial) ||
    category.subCategories.any(_hasOfficialBook);
