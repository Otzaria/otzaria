import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/models/books.dart';

/// שכבת תאימות דקה מעל [ExternalProviderRegistry] לקוראים הקיימים.
class ExternalCatalogMapper {
  ExternalCatalogMapper._();

  /// המזהה החיצוני קודם לקישור: ספר היברובוקס שהורד הופך ל-`PdfBook` עם
  /// `hb:123`, ונתיב הקובץ שלו עלול להכיל `otzaria` ולהטעות.
  static ExternalProviderDescriptor? providerOf({
    String? link,
    String? externalLibraryId,
  }) {
    final parsed = ExternalProviderRegistry.parse(externalLibraryId);
    if (parsed != null) return parsed.provider;
    return ExternalProviderRegistry.fromLink(link);
  }

  /// הספק של [book], או `null` לספר מקומי.
  static ExternalProviderDescriptor? providerOfBook(Book book) => providerOf(
    externalLibraryId: book.externalLibraryId,
    link: book is ExternalLibraryBook ? book.link : null,
  );

  /// מפענח `externalLibraryId` לספק ולערך.
  static ExternalBookRef? parse(String? externalLibraryId) =>
      ExternalProviderRegistry.parse(externalLibraryId);

  /// רק ממזהה תקין או מקישור של ספק מוכר, לא מהספרות הראשונות שבכל
  /// מחרוזת: `"ספר 3 חלקים"` אינו `3`.
  static int? extractExternalId({String? externalLibraryId, String? link}) {
    final parsed = ExternalProviderRegistry.parse(externalLibraryId);
    if (parsed != null) return parsed.numericValue;
    return _idFromKnownLink(link);
  }

  /// מחזיר קישור לאתר הספק מתוך `externalLibraryId`, או `null` לספק
  /// שאין לו נוכחות ברשת.
  static String? resolveLink({String? filePath, String? externalLibraryId}) {
    final parsed = ExternalProviderRegistry.parse(externalLibraryId);
    if (parsed == null) return null;
    return parsed.provider.webLinkFor(parsed.value);
  }

  static int? _idFromKnownLink(String? link) {
    final provider = ExternalProviderRegistry.fromLink(link);
    if (provider == null) return null;
    final match = RegExp(r'(\d+)').firstMatch(link!);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
