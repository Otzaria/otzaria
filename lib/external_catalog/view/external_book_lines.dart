import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'package:otzaria/models/books.dart';

/// בלעדיה ספר חיצוני נראה כמו ספר מותקן, והאייקון הזעיר לבדו אינו מסביר
/// שלחיצה תפתח תוכנה אחרת.
String? externalBookSourceLine(Book book) =>
    ExternalCatalogMapper.providerOfBook(book)?.displayName;

/// אצל פרויקט השו"ת - הקטגוריה באוצריא ולא המדף בבר אילן, כי שם המשתמש
/// ימצא את הספר בעיון.
String? externalBookCategoryLine(Book book) {
  final provider = ExternalCatalogMapper.providerOfBook(book);
  if (provider?.kind == ExternalProviderKind.responsa) {
    final categories = book is ExternalLibraryBook ? book.heCategories : null;
    if (ResponsaCategoryMap.displayNameFor(categories) case final mapped?) {
      return mapped;
    }
  }
  final path = book.categoryPath?.trim();
  return (path == null || path.isEmpty) ? null : path.replaceAll('/', ' › ');
}
