/* a representation of the library , every entry could be a category or a book, and a category can
contain other categories and books */

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
  List<Book> getAllBooks() {
    List<Book> books = [];
    books.addAll(this.books);
    for (Category category in subCategories) {
      books.addAll(category.getAllBooks());
    }
    return books;
  }

  /// האם הקטגוריה מכילה ספר כלשהו, ישירות או בתת-קטגוריה.
  /// עוצר בספר הראשון שנמצא — זול מ-[getAllBooks] לבדיקת ריקנות בלבד.
  bool get hasBooks {
    if (books.isNotEmpty) return true;
    for (final category in subCategories) {
      if (category.hasBooks) return true;
    }
    return false;
  }

  List<Category> getAllCategories() {
    List<Category> categories = [];
    categories.addAll(subCategories);
    for (Category category in subCategories) {
      categories.addAll(category.getAllCategories());
    }
    return categories;
  }

  List<dynamic> getAllBooksAndCategories() {
    List<dynamic> booksAndCategories = [];
    booksAndCategories.addAll(getAllBooks());
    booksAndCategories.addAll(getAllCategories());
    return booksAndCategories;
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

  /// מחפש TextBook לפי כותרת ו-categoryId.
  ///
  /// מחפש התאמה מדויקת לפי categoryId (אם סופק), עם fallback לפי שם בלבד.
  /// שימושי כשצריך למצוא TextBook שמתאים לספר PDF עם אותו שם.
  TextBook? findTextBookByTitleAndCategory(
    String title, {
    int? categoryId,
  }) {
    TextBook? result;
    for (final candidate in getAllBooks()) {
      if (candidate is! TextBook) continue;
      if (candidate.title != title) continue;
      if (categoryId != null && candidate.categoryId != categoryId) {
        continue;
      }
      result = candidate;
      break;
    }
    return result ?? findBookByTitle(title, TextBook) as TextBook?;
  }

  /// Finds a book by its title in the library.
  ///
  /// Searches through all books in the library and its subcategories
  /// for a book with the specified title.
  ///
  /// Returns the first matching [Book] or null if no book is found.
  Book? findBookByTitle(String title, Type? type) {
    List<Book> allBooks = getAllBooks();
    try {
      if (type == null) {
        return allBooks.firstWhere((book) => book.title == title);
      }
      return allBooks.firstWhere(
        (book) => book.title == title && book.runtimeType == type,
      );
    } catch (e) {
      return null;
    }
  }

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
      candidate.isUserBook == book.isUserBook &&
      candidate.externalLibraryId == book.externalLibraryId;

  /// מחפש ספר לפי כותרת עם חיפוש גמיש יותר.
  ///
  /// אם לא נמצא התאמה מדויקת, מנסה למצוא ספר עם כותרת דומה:
  /// - מסיר רווחים מיותרים
  /// - מתעלם מהבדלי גרשיים וסימני פיסוק
  /// - מחפש התאמה חלקית
  ///
  /// [title] - כותרת הספר לחיפוש
  /// [type] - סוג הספר (למשל PdfBook, TextBook)
  /// מחזיר את הספר הראשון שנמצא או null
  Book? findBookByTitleFlexible(String title, Type? type) {
    List<Book> allBooks = getAllBooks();

    // ניסיון ראשון: חיפוש מדויק
    try {
      if (type == null) {
        return allBooks.firstWhere((book) => book.title == title);
      }
      return allBooks.firstWhere(
        (book) => book.title == title && book.runtimeType == type,
      );
    } catch (e) {
      // לא נמצא - ממשיכים לחיפוש גמיש
    }

    // נרמול הכותרת לחיפוש
    String normalizedTitle = _normalizeTitle(title);

    // חיפוש עם נרמול
    List<Book> candidates = allBooks.where((book) {
      if (type != null && book.runtimeType != type) return false;
      return _normalizeTitle(book.title) == normalizedTitle;
    }).toList();

    if (candidates.isNotEmpty) {
      return candidates.first;
    }

    // חיפוש חלקי - הכלה כמילה שלמה בלבד (מונע "רות" בתוך "טהרות")
    candidates = allBooks.where((book) {
      if (type != null && book.runtimeType != type) return false;
      String bookNormalized = _normalizeTitle(book.title);
      return _containsAsWholeWord(bookNormalized, normalizedTitle) ||
          _containsAsWholeWord(normalizedTitle, bookNormalized);
    }).toList();

    return candidates.isNotEmpty ? candidates.first : null;
  }

  /// בודק אם [needle] מוכל ב-[haystack] כרצף מילים שלם (גבול מילה ברווחים).
  bool _containsAsWholeWord(String haystack, String needle) {
    if (needle.isEmpty) return false;
    return ' $haystack '.contains(' $needle ');
  }

  String _normalizeTitle(String title) => normalizeBookTitle(title);
}

/// מנרמל כותרת ספר להשוואה: רווחים עודפים, גרשיים וסוגריים משולשים.
String normalizeBookTitle(String title) {
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
