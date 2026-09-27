import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/models/books.dart';

/// כלי עזר למיפוי ספרי קטלוגים חיצוניים.
///
/// כל הזיהוי כאן נשען על [ExternalProviderRegistry]; המחלקה הזו היא
/// שכבת תאימות דקה לקוראים הקיימים.
class ExternalCatalogMapper {
  ExternalCatalogMapper._();

  /// קובע את הספק לפי מזהה חיצוני, ובהיעדרו לפי קישור.
  ///
  /// הסדר חשוב: `externalLibraryId` הוא המקור האמין. ספר היברובוקס
  /// שהורד מקומית מומר ל-`PdfBook` ושומר `hb:123` — נתיב הקובץ שלו
  /// עלול להכיל את המחרוזת `otzaria` ולהטעות.
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

  /// מחלץ את המזהה המספרי של הספר אצל הספק.
  ///
  /// רק מתוך מזהה חיצוני תקין או מתוך קישור של ספק מוכר — ולא על ידי
  /// שליפת הספרות הראשונות מכל מחרוזת. `"ספר 3 חלקים"` אינו `3`.
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
