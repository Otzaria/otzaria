// כלי עזר למיפוי ספרי קטלוגים חיצוניים.
enum ExternalCatalogType { otzar, hebrew }

class ExternalCatalogMapper {
  /// קובע את סוג הקטלוג לפי קישור/מזהה חיצוני/נתיב קובץ.
  static ExternalCatalogType? catalogFromLinkOrId({
    String? link,
    String? externalLibraryId,
    String? filePath,
  }) {
    final linkValue = link?.toLowerCase() ?? '';
    final externalValue = externalLibraryId?.toLowerCase() ?? '';
    final fileValue = filePath?.toLowerCase() ?? '';

    if (linkValue.contains('hebrewbooks') ||
        externalValue.contains('hebrewbooks') ||
        fileValue.contains('hebrewbooks')) {
      return ExternalCatalogType.hebrew;
    }
    if (linkValue.contains('otzar') ||
        linkValue.contains('otzaria') ||
        externalValue.contains('otzar') ||
        externalValue.contains('otzaria') ||
        fileValue.contains('otzar') ||
        fileValue.contains('otzaria')) {
      return ExternalCatalogType.otzar;
    }
    if (linkValue.contains('hb:') ||
        linkValue.contains('hebrew:') ||
        externalValue.contains('hb:') ||
        externalValue.contains('hebrew:') ||
        fileValue.contains('hb:') ||
        fileValue.contains('hebrew:')) {
      return ExternalCatalogType.hebrew;
    }
    if (linkValue.contains('otz:') ||
        linkValue.contains('otzar:') ||
        linkValue.contains('oh:') ||
        externalValue.contains('otz:') ||
        externalValue.contains('otzar:') ||
        externalValue.contains('oh:') ||
        fileValue.contains('otz:') ||
        fileValue.contains('otzar:') ||
        fileValue.contains('oh:')) {
      return ExternalCatalogType.otzar;
    }
    return null;
  }
}
