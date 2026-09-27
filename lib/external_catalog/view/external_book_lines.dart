import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'package:otzaria/models/books.dart';

/// שורות המשנה שמוצגות לספר מספרייה חיצונית, בכרטיס ובשורת הרשימה.
///
/// הסדר בתצוגה הוא מחבר, מקור וקטגוריה — מהמסוים לכללי.

/// שם הספרייה שממנה הגיע הספר, או `null` לספר מקומי.
///
/// אותו ערך שמוצג בדיאלוג פרטי הספר תחת "מקור הספר". בלעדיו שתי שורות
/// המשנה — מחבר וקטגוריה — נראות בדיוק כמו של ספר מותקן, והמשתמש אינו
/// יודע שלחיצה תפתח תוכנה אחרת או דפדפן. האייקון לבדו אינו מספיק:
/// הוא 14 פיקסלים, ובשלושה ספקים הוא אינו מזוהה בלי הסבר.
String? externalBookSourceLine(Book book) =>
    ExternalCatalogMapper.providerOfBook(book)?.displayName;

/// שורת הקטגוריה שמוצגת לספר חיצוני, או `null` כשאין.
///
/// אצל פרויקט השו"ת מוצגת הקטגוריה **באוצריא** ולא המדף בבר אילן:
/// `שו״ת` ולא `ספרי שאלות ותשובות (שו"ת) › ... - אחרונים › תורת
/// יקותיאל`. זה השם שהמשתמש מכיר, ושם הוא ימצא את הספר בעיון.
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
