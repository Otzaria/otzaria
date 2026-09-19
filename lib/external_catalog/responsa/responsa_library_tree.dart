import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
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

  /// היעד לספרים שנתיב הקטגוריה שלהם אינו משויך — קטגוריה עליונה משלהם.
  ///
  /// מהדורה חדשה עשויה להוסיף קטגוריית שורש שאינה בטבלת השיוך. הספרים
  /// שלה ייראו במקום אחד ברור במקום להיעלם בשקט.
  static const List<String> unmappedTarget = [folderTitle];

  /// מיפוי מ-[Category.path] של קטגוריית היעד אל התיקייה הווירטואלית.
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
  Category? folderFor(String categoryPath) => byCategoryPath[categoryPath];

  /// בונה את העץ מרשימת הספרים של הקטלוג.
  ///
  /// [books] הם כל ספרי בר אילן; `heCategories` של כל אחד הוא נתיב
  /// הקטגוריה שלו בבר אילן.
  static ResponsaLibraryTree build(Iterable<Book> books) {
    // path של קטגוריית היעד -> שורש התיקייה הווירטואלית
    final roots = <String, Category>{};
    final unmapped = <String, Category>{};

    Category folder(String title, Category? parent, int order) => Category(
      title: title,
      description: '',
      shortDescription: '',
      order: order,
      subCategories: [],
      books: [],
      parent: parent,
    );

    for (final book in books) {
      final source = book.heCategories;
      final match = ResponsaCategoryMap.resolve(source);
      final targetPath = match == null ? null : '/${match.target.join('/')}';

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
        current = current.subCategories.firstWhere(
          (child) => child.title == part,
          orElse: () {
            final created = folder(part, current, current.subCategories.length);
            current.subCategories.add(created);
            return created;
          },
        );
      }
      current.books.add(book);
    }

    return ResponsaLibraryTree(
      byCategoryPath: roots,
      topLevel: unmapped.values.toList(),
    );
  }
}
