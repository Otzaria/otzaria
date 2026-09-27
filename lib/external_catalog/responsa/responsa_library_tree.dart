import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// תיקיות וירטואליות מחוץ לעץ הספרייה: מה שב-`getAllBooks()` נשלח לאינדוקס,
/// וספרי בר אילן אין להם טקסט מקומי. לכן מוצגות רק בשכבת התצוגה.
class ResponsaLibraryTree {
  /// שם התיקייה שנוספת בתוך קטגוריית היעד.
  static const String folderTitle = 'פרויקט השו"ת בר אילן';

  /// המפתח מנורמל: די בתו גרשיים אחר (`שו"ת` מול `שו״ת`) כדי שהתיקייה
  /// תיעלם בשקט.
  final Map<String, Category> byCategoryPath;

  /// תיקיות עליונות — רק עבור ספרים שלא שויכו.
  final List<Category> topLevel;

  const ResponsaLibraryTree({
    required this.byCategoryPath,
    required this.topLevel,
  });

  static const ResponsaLibraryTree empty = ResponsaLibraryTree(
    byCategoryPath: {},
    topLevel: [],
  );

  bool get isEmpty => byCategoryPath.isEmpty && topLevel.isEmpty;

  /// התיקייה שיש להציג בתוך [categoryPath], או `null`.
  Category? folderFor(String categoryPath) =>
      byCategoryPath[pathKey(categoryPath)];

  /// מפתח ההשוואה של נתיב קטגוריה — רכיב-רכיב, בכתיב מנורמל.
  static String pathKey(String categoryPath) => categoryPath
      .split('/')
      .map(ResponsaHebrew.spellingKey)
      .where((part) => part.isNotEmpty)
      .join('/');

  /// `heCategories` של כל ספר ב-[books] הוא נתיב הקטגוריה שלו בבר אילן.
  static ResponsaLibraryTree build(Iterable<Book> books) {
    // path של קטגוריית היעד -> שורש התיקייה הווירטואלית
    final roots = <String, Category>{};
    final unmapped = <String, Category>{};

    // אינדקס במקום חיפוש לינארי ב-`subCategories`: מדף מגיע לאלפי תיקיות,
    // וסריקה לכל ספר היא מיליוני השוואות בתוך `setState`.
    final children = <Category, Map<String, Category>>{};

    // גם תיקיות הבת נושאות את מזהה הספק, כדי שבכל עומק יהיה ברור שהתוכן
    // ייפתח בתוכנה אחרת.
    Category folder(String title, Category? parent, int order) => Category(
      title: title,
      description: '',
      shortDescription: '',
      order: order,
      subCategories: [],
      books: [],
      parent: parent,
      externalProviderId: ExternalProviderRegistry.responsa.id,
    );

    // ~8,400 ספרים על ~96 מדפים: כמעט כל נתיב כבר נפתר, ופתרון עולה regex.
    final resolved = <String, ({List<String> target, int levels})?>{};

    for (final book in books) {
      final source = book.heCategories;
      final match = resolved.putIfAbsent(
        source ?? '',
        () => ResponsaCategoryMap.resolve(source),
      );
      final targetPath = match == null
          ? null
          : pathKey('/${match.target.join('/')}');

      final Category root;
      if (targetPath == null) {
        root = unmapped.putIfAbsent(
          folderTitle,
          () => folder(folderTitle, null, 999),
        );
      } else {
        root = roots.putIfAbsent(
          targetPath,
          () => folder(folderTitle, null, 999),
        );
      }

      // רק הרמות שמתחת לנקודת השיוך הופכות לתיקיות; מה שנצרך כבר מיוצג
      // בקטגוריית היעד.
      final parts = (source ?? '')
          .split(ResponsaCategoryMap.pathSeparator)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final consumed = match?.levels ?? 0;
      var current = root;
      for (final part in parts.skip(consumed)) {
        current = children.putIfAbsent(current, () => {}).putIfAbsent(part, () {
          final created = folder(
            part,
            current,
            current.subCategories.length,
          );
          current.subCategories.add(created);
          return created;
        });
      }
      current.books.add(book);
    }

    return ResponsaLibraryTree(
      byCategoryPath: roots,
      topLevel: unmapped.values.toList(),
    );
  }
}
