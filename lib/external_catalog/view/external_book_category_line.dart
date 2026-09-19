import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'package:otzaria/models/books.dart';

/// שורת הקטגוריה שמוצגת לספר חיצוני, או `null` כשאין.
///
/// אצל ספק שאין לו שדה מחבר — ופרויקט השו"ת הוא כזה — זו השורה היחידה
/// שמסבירה מה נמצא, ולכן היא צריכה להיות בשמות שהמשתמש מכיר.
String? externalBookCategoryLine(ExternalLibraryBook book) {
  final provider = ExternalCatalogMapper.providerOf(
    externalLibraryId: book.externalLibraryId,
    link: book.link,
  );
  if (provider?.kind == ExternalProviderKind.responsa) {
    if (ResponsaCategoryMap.displayNameFor(book.heCategories)
        case final mapped?) {
      return mapped;
    }
  }
  final path = book.categoryPath?.trim();
  return (path == null || path.isEmpty) ? null : path.replaceAll('/', ' › ');
}
