import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// תיקיות וירטואליות שמציגות את ספרי בר אילן בתוך קטגוריות אוצריא.
///
/// **הן אינן חלק מעץ הספרייה.** הספרייה האמיתית מוזנת למנוע האינדוקס,
/// ל-`dropOrphanedIndexEntries` ולעוד כמה צרכנים שעוברים על
/// `getAllBooks()`; הוספת 8,465 ספרים חיצוניים שאין להם טקסט מקומי
/// הייתה שולחת את כולם לאינדוקס. לכן העץ הזה נבנה בנפרד ומוצג רק
/// בשכבת התצוגה, כשההגדרה דולקת.
///
/// המבנה: תחת קטגוריית היעד באוצריא נוספת תיקייה אחת בשם
/// [folderTitle], ובתוכה נשמר מבנה התיקיות של בר אילן מתחת לנקודת
/// השיוך. כך `שו״ת` באוצריא אינו מוצף באלף ספרים, והמשתמש רואה בבירור
/// מה מגיע מבר אילן ומה מותקן אצלו.
class ResponsaLibraryTree {
  /// שם התיקייה שנוספת בתוך קטגוריית היעד.
  static const String folderTitle = 'פרויקט השו"ת בר אילן';

  /// מיפוי מנתיב קטגוריית היעד, **מנורמל**, אל התיקייה הווירטואלית.
  ///
  /// מנורמל ולא גולמי: `Category.path` נבנה מכותרות הספרייה המותקנת,
  /// ודי בתו גרשיים אחר (`שו"ת` מול `שו״ת`) כדי שההשוואה תיכשל — ואז
  /// התיקייה פשוט אינה מופיעה, בלי שגיאה ובלי סימן.
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

  /// בונה את העץ מרשימת הספרים של הקטלוג.
  ///
  /// [books] הם כל ספרי בר אילן; `heCategories` של כל אחד הוא נתיב
  /// הקטגוריה שלו בבר אילן.
  static ResponsaLibraryTree build(Iterable<Book> books) {
    // path של קטגוריית היעד -> שורש התיקייה הווירטואלית
    final roots = <String, Category>{};
    final unmapped = <String, Category>{};

    // תיקייה -> תיקיות הבת שלה לפי שם. חיפוש לינארי ב-`subCategories`
    // הוא O(אחים), ומדף אחד מגיע לאלפי תיקיות — 8,400 ספרים × סריקה
    // כזו הם מיליוני השוואות מחרוזות בתוך `setState`.
    final children = <Category, Map<String, Category>>{};

    // כל תיקייה בעץ הזה נושאת את מזהה הספק, כולל תיקיות הבת: המשתמש
    // יורד לתוך `שו"ת אחרונים` ומשם ל-`תורת יקותיאל`, וגם שם צריך
    // להיות ברור שכל מה שבפנים ייפתח בתוכנה אחרת.
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

    // 8,400 ספרים מתחלקים על פני ~96 מדפים, ולכן כמעט כל קריאה חוזרת
    // על נתיב שכבר נפתר — ופתרון הוא ארבעה מעברי regex.
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

      // מתחת לתיקייה נשמר מבנה בר אילן שמתחת לנקודת השיוך: `ספרות חז"ל
      // > מדרשי אגדה` שויך כולו, ואילו `ספרי הלכה ומנהג > ... - אחרונים`
      // שויך ברמה אחת, והרמה השנייה נשארת כתיקייה.
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
