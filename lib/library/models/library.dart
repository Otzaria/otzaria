/* a representation of the library , every entry could be a category or a book, and a category can
contain other categories and books */

import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// Represents a category in the library.
///
/// A category in the library can contain other categories and books.
/// It has a [title], [subCategories], [books], and a [parent] category.
/// The [title] is a string representing the name of the category.
/// The [subCategories] is a list of categories that are contained in this category.
/// The [books] is a list of books that are contained in this category.
/// The [parent] is a pointer to the parent category. the top level category's parent is the library itself
///
/// The [description], [shortDescription], and [order] properties contain
/// additional information supplied by the active library provider.
class Category {
  String title;

  /// A full description of the category.
  String description;

  /// A short description of the category.
  String shortDescription;

  /// The display order of the category.
  /// Defaults to 999 if no order is specified for this category.
  int order;

  /// returns the path of this category e.g תנך/ראשונים/רשי/תורה
  String get path {
    if (title == 'ספריית אוצריא') {
      return '/';
    }
    String path = title;
    Category? parent = this.parent;
    while (parent != null && parent.title != 'ספריית אוצריא') {
      path = '${parent.title}/$path';
      parent = parent.parent;
    }
    return '/$path';
  }

  ///the list of sub categories that are contained in this category
  List<Category> subCategories;

  /// the list of books that are contained in this category
  List<Book> books;

  /// A pointer to the parent category, or null if this is a top level category.
  Category? parent;

  ///returns all the books in this category and its subcategories
  List<Book> getAllBooks() => _collect([], (c) => c.books);

  /// האם הקטגוריה מכילה ספר כלשהו, ישירות או בתת-קטגוריה.
  /// עוצר בספר הראשון שנמצא — זול מ-[getAllBooks] לבדיקת ריקנות בלבד.
  bool get hasBooks {
    if (books.isNotEmpty) return true;
    for (final category in subCategories) {
      if (category.hasBooks) return true;
    }
    return false;
  }

  /// מקור התיקייה כשאין בה (גם בתתי-התיקיות) אף ספר רשמי: מסד מצורף כשכל
  /// ספריה ממסדים מצורפים, אחרת [BookSource.user]. null לתיקייה רשמית,
  /// מעורבת או ריקה.
  BookSource? get personalSource {
    var hasUser = false;
    BookSource? attached;
    bool onlyPersonal(Category category) {
      for (final book in category.books) {
        final source = book.source;
        if (source.isOfficial) return false;
        if (source.isAttached) {
          attached ??= source;
        } else {
          hasUser = true;
        }
      }
      return category.subCategories.every(onlyPersonal);
    }

    if (!onlyPersonal(this)) return null;
    return hasUser ? BookSource.user : attached;
  }

  List<Category> getAllCategories() => _collect([], (c) => c.subCategories);

  // רשימה אחת לכל העץ — addAll של תת-רשימות מעתיק כל פריט פעם בכל רמה.
  List<T> _collect<T>(List<T> into, List<T> Function(Category) itemsOf) {
    into.addAll(itemsOf(this));
    for (final category in subCategories) {
      category._collect(into, itemsOf);
    }
    return into;
  }

  /// Initialize a new [Category] instance.
  ///
  /// The [title] is the name of the category, [subCategories] are the categories
  /// that are contained in this category, [books] are the books that are contained
  /// in this category, and [parent] is the parent category.
  Category({
    required this.title,
    required this.description,
    required this.shortDescription,
    required this.order,
    required this.subCategories,
    required this.books,
    required this.parent,
  });
}

/// Represents a library of categories and books.
///
/// A library is a top level category that contains other categories.
/// It has a [title], a list of [subCategories], and a list of [books].
/// The [parent] of a library is the library itself.
class Library extends Category {
  /// Initialize a new [Library] instance.
  ///
  /// The [categories] parameter is a list of categories that are contained in
  /// this library.
  Library({required List<Category> categories})
    : super(
        title: 'ספריית אוצריא',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: categories,
        books: [],
        parent: null,
      ) {
    parent = this;
  }

  /// ספרים שאינם בעץ (גרסאות משניות של ספר) אבל מאונדקסים ונפתחים מתוצאות
  /// חיפוש כספרים בפני עצמם.
  List<Book> offTreeBooks = const [];

  /// כל הספרים שנכנסים לאינדקס החיפוש: ספרי העץ ואחריהם [offTreeBooks].
  List<Book> getIndexableBooks() => [...getAllBooks(), ...offTreeBooks];

  /// מחפש ספר נלווה (Companion Book) כמו גרסת PDF לגרסת טקסט או להיפך.
  /// החיפוש מתבצע תחילה תחת אותה קטגוריה בה נמצא הספר המקורי.
  /// אם לא נמצא - נופל לחיפוש גלובלי עם מניעת התנגשויות (ירושלמי <-> בבלי כדוגמה).
  Book? getCompanionBook(Book book, Type companionType) {
    final normalizedTitle = _normalizeTitle(book.title);

    // 1. חיפוש באותה קטגוריה בדיוק:
    if (book.category != null) {
      final companions = book.category!.books
          .where(
            (b) =>
                _normalizeTitle(b.title) == normalizedTitle &&
                b.runtimeType == companionType,
          )
          .toList();

      // מועמד יחיד מאותו מקור מכריע; אחרת שני מועמדים = זהות לא ודאית
      // ומוותרים במקום לנחש.
      final sameSource = companions
          .where((c) => _isSameBookSource(book, c))
          .toList();
      if (sameSource.length == 1) return sameSource.first;
      if (companions.length > 1) return null;
      if (companions.isNotEmpty) return companions.first;
    }

    // 2. חיפוש גלובלי (מאפשר התאמה לפי נרמול הכותרת כפי שמקובל):
    final candidates = getCompanionBooks(book, companionType);

    // מהדורה ממקור אחר משמשת רק כשאין אחת מאותו מקור — אחרת מהדורה אישית
    // שנוספה בשם זהה גונבת את הבחירה, ומיפוי העמודים שלה נכשל ופותח בעמוד 1.
    return candidates.where((c) => _isSameBookSource(book, c)).firstOrNull ??
        candidates.firstOrNull;
  }

  /// כל מהדורות ה-[companionType] בספרייה שכותרתן זהה ל-[book], אחרי סינון
  /// ההתנגשויות. יותר מאחת = כפילות שם, שבה זהות המלווה אינה חד-משמעית.
  List<Book> getCompanionBooks(Book book, Type companionType) {
    final normalizedTitle = _normalizeTitle(book.title);
    return getAllBooks()
        .where(
          (b) =>
              b.runtimeType == companionType &&
              _normalizeTitle(b.title) == normalizedTitle &&
              !_isCrossTraditionConflict(book, b),
        )
        .toList();
  }

  /// מסכתות בבלי וירושלמי חולקות שמות — ואינן מלוות זו את זו.
  bool _isCrossTraditionConflict(Book book, Book candidate) {
    String categoryOf(Book b) =>
        b.categoryPath ?? b.heCategories ?? (b is FileBook ? b.path : '');
    final bookCat = categoryOf(book);
    final candCat = categoryOf(candidate);

    if (bookCat.contains('ירושלמי') && candCat.contains('בבלי')) return true;
    if (bookCat.contains('בבלי') && candCat.contains('ירושלמי')) return true;
    return false;
  }

  /// האם [candidate] בא מאותו מקור ספרים כמו [book] — ספריית אוצריא, הספרים
  /// האישיים, או אותו קטלוג חיצוני. שם זהה ממקור אחר אינו אותו ספר.
  bool _isSameBookSource(Book book, Book candidate) =>
      candidate.source == book.source &&
      _bookSourceKey(candidate) == _bookSourceKey(book);

  /// מסכת PDF מצורפת נושאת מזהה חיצוני אך מגיעה מספריית אוצריא עצמה.
  String? _bookSourceKey(Book book) =>
      DatabaseConstants.isBundledLibrarySource(book.externalLibraryId)
      ? null
      : book.externalLibraryId;

  String _normalizeTitle(String title) => normalizeBookTitle(title);
}

/// מנרמל כותרת ספר להשוואה: רווחים עודפים, גרשיים וסוגריים משולשים.
String normalizeBookTitle(String title) {
  if (_isNormalizedBookTitle(title)) return title;
  return title
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '')
      .replaceAll('<', '')
      .replaceAll('>', '');
}

/// איתור ספר נלווה בלי מלווה מנרמל כל כותרת בספרייה, ורובן כבר נקיות.
/// כל רווח שאינו רווח יחיד פנימי, כולל רווחי Unicode, נשלח למסלול המלא.
bool _isNormalizedBookTitle(String title) {
  final last = title.length - 1;
  for (var i = 0; i <= last; i++) {
    final c = title.codeUnitAt(i);
    if (c == 0x20) {
      if (i == 0 || i == last || title.codeUnitAt(i - 1) == 0x20) return false;
    } else if (c < 0x20 ||
        c == 0x22 || // "
        c == 0x27 || // '
        c == 0x3C ||
        c == 0x3E ||
        c == 0x05F3 || // ׳
        c == 0x05F4 || // ״
        c == 0x85 ||
        c == 0xA0 ||
        c == 0x1680 ||
        (c >= 0x2000 && c <= 0x3000) ||
        c == 0xFEFF) {
      return false;
    }
  }
  return true;
}
