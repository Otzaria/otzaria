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

  /// מחזיר קישור מתאים מתוך filePath או externalLibraryId אם הם URL.
  static String? resolveLink({
    String? filePath,
    String? externalLibraryId,
  }) {
    final fromExternalId = _linkFromExternalLibraryId(externalLibraryId);
    if (fromExternalId != null) return fromExternalId;
    return null;
  }

  static String? _linkFromExternalLibraryId(String? externalLibraryId) {
    if (externalLibraryId == null) return null;
    final trimmed = externalLibraryId.trim();
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('oh:')) {
      final id = trimmed.substring(3).trim();
      if (id.isEmpty) return null;
      return 'https://tablet.otzar.org/book/book.php?book=$id';
    }

    if (lower.startsWith('hb:')) {
      final id = trimmed.substring(3).trim();
      if (id.isEmpty) return null;
      return 'https://hebrewbooks.org/$id';
    }

    return null;
  }
}
