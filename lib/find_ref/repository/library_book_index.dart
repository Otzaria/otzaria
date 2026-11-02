import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_visibility.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// מפתח את עץ הספרייה במעבר אחד, כדי שפתרון ספרי המפרשים לא יסרוק את כל
/// העץ מחדש לכל מפרש. קטע בספר יסוד מגיע לעשרות מפרשים, וכל שורה נראית
/// מבקשת את שלה.
///
/// המפות נבנות בסדר ה-DFS של [findOfficialTextBookById] ושל
/// [_findBookInLibraryByTitle], עם `putIfAbsent`, ולכן כשכמה ספרים חולקים
/// מזהה או כותרת נבחר אותו ספר שהסריקות היו בוחרות.
class LibraryBookIndex {
  LibraryBookIndex(this.library, {FindRefVisibility? visibility})
    : visibility = visibility ?? FindRefVisibility.empty() {
    _collect(library);
  }

  final Category library;
  final FindRefVisibility visibility;
  final Map<int, TextBook> _officialTextBookById = {};
  final Map<String, TextBook> _textBookByTitle = {};
  final Map<String, Book> _bookByTitle = {};

  // בלי סינון הסתרה: ספר מוסתר שנמצא לפי מזהה חוסם, ואינו נופל לכותרת.
  final Map<int, TextBook> _anyOfficialTextBookById = {};
  final Map<(BookSource, int), Book> _bookBySourceAndId = {};
  final Map<String, PdfBook> _pdfBookByPath = {};
  final Map<String, Book> _visibleOfficialByTitle = {};
  final Map<String, TextBook> _visibleOfficialTextByTitle = {};

  void _collect(Category category) {
    for (final book in category.books) {
      final id = book.id;
      if (id != null) {
        if (book is TextBook && book.source.isOfficial) {
          _anyOfficialTextBookById.putIfAbsent(id, () => book);
        }
        _bookBySourceAndId.putIfAbsent((book.source, id), () => book);
      }
      if (book is PdfBook && book.path.isNotEmpty) {
        _pdfBookByPath.putIfAbsent(book.path, () => book);
      }
      if (!visibility.allowsBook(book)) continue;
      if (book.source.isOfficial) {
        _visibleOfficialByTitle.putIfAbsent(book.title, () => book);
        if (book is TextBook) {
          _visibleOfficialTextByTitle.putIfAbsent(book.title, () => book);
        }
      }
      if (book is TextBook) {
        if (book.source.isOfficial && id != null) {
          _officialTextBookById.putIfAbsent(id, () => book);
        }
        _textBookByTitle.putIfAbsent(book.title, () => book);
      }
      _bookByTitle.putIfAbsent(book.title, () => book);
    }
    for (final subCategory in category.subCategories) {
      _collect(subCategory);
    }
  }

  /// מאתר את ה-`Book` הנכון לפי [bookId] אם נמסר, ולפי [title] אם לא. הסיבה:
  /// שני ספרים יכולים לחלוק כותרת זהה (למשל גרסאות שונות של פירוש), וה-link
  /// משאילתת המפרשים יודע בדיוק לאיזה ספר ללכת — פתרון רק לפי title היה
  /// פותח את הראשון שנמצא בעץ.
  Book? resolveCommentatorBook(String title, {required int? bookId}) {
    if (bookId != null && bookId > 0) {
      final byId = _officialTextBookById[bookId];
      if (byId != null) return byId;
    }
    // fallback ל-title (תאימות לאחור עם DB שלא מחזיר targetBookId).
    return _textBookByTitle[title] ?? _bookByTitle[title];
  }

  /// כמו [findOfficialTextBookById] על [library], בלי סריקה.
  TextBook? officialTextBookById(int bookId) =>
      _anyOfficialTextBookById[bookId];

  /// ה-PdfBook שבעץ לקובץ [path] — עם המזהה והמקור שלו, לזהות טאב והיסטוריה.
  PdfBook? pdfBookByPath(String path) => _pdfBookByPath[path];

  /// כמו [resolveFindRefBookInLibrary] על [library], בלי סריקה. [visibility]
  /// של האינדקס חייב להיות זה שהסריקה הייתה מקבלת.
  Book? resolveFindRefBook(
    String title, {
    required int? bookId,
    required BookSource source,
    bool preferTextBook = false,
  }) {
    if (bookId != null) {
      final byId = source.isOfficial
          ? _anyOfficialTextBookById[bookId]
          : _bookBySourceAndId[(source, bookId)];
      if (byId != null) return visibility.allowsBook(byId) ? byId : null;
      if (!source.isOfficial) return null;
    }
    return (preferTextBook ? _visibleOfficialTextByTitle[title] : null) ??
        _visibleOfficialByTitle[title];
  }
}

/// הספר בעל [bookId] במסד של [source] (אישי או מצורף), מכל סוג.
@visibleForTesting
Book? findBookBySourceAndId(Category category, int bookId, BookSource source) {
  for (final b in category.books) {
    if (b.source == source && b.id == bookId) return b;
  }
  for (final subCat in category.subCategories) {
    final found = findBookBySourceAndId(subCat, bookId, source);
    if (found != null) return found;
  }
  return null;
}

/// מאתר ספר טקסט רשמי לפי [bookId] מה-DB הראשי.
/// מזהי seforim.db אינם ייחודיים מול user_books.db ומול ייצוגי PDF בעץ —
/// ולכן ספרים אישיים וספרים שאינם TextBook מדולגים ולא מסתירים את היעד.
@visibleForTesting
TextBook? findOfficialTextBookById(Category category, int bookId) {
  for (final b in category.books) {
    if (b is TextBook && b.source.isOfficial && b.id == bookId) return b;
  }
  for (final subCat in category.subCategories) {
    final found = findOfficialTextBookById(subCat, bookId);
    if (found != null) return found;
  }
  return null;
}

Book? _findBookInLibraryByTitle(
  Category category,
  String title, {
  bool preferTextBook = false,
  required FindRefVisibility visibility,
}) {
  // עוברים פעמיים אם preferTextBook: ראשונה — רק TextBook; שנייה — כל סוג.
  for (final passOnlyText in preferTextBook ? [true, false] : [false]) {
    final result = _findBookInLibraryByTitlePass(
      category,
      title,
      onlyTextBook: passOnlyText,
      visibility: visibility,
    );
    if (result != null) return result;
  }
  return null;
}

Book? _findBookInLibraryByTitlePass(
  Category category,
  String title, {
  required bool onlyTextBook,
  required FindRefVisibility visibility,
}) {
  for (final b in category.books) {
    if (b.title != title) continue;
    if (onlyTextBook && b is! TextBook) continue;
    if (!b.source.isOfficial || !visibility.allowsBook(b)) continue;
    return b;
  }
  for (final subCat in category.subCategories) {
    final found = _findBookInLibraryByTitlePass(
      subCat,
      title,
      onlyTextBook: onlyTextBook,
      visibility: visibility,
    );
    if (found != null) return found;
  }
  return null;
}

@visibleForTesting
Book? resolveFindRefBookInLibrary(
  Category category,
  String title, {
  required int? bookId,
  required BookSource source,
  required FindRefVisibility visibility,
  bool preferTextBook = false,
}) {
  if (bookId != null) {
    final byId = source.isOfficial
        ? findOfficialTextBookById(category, bookId)
        : findBookBySourceAndId(category, bookId, source);
    if (byId != null) return visibility.allowsBook(byId) ? byId : null;
    if (!source.isOfficial) return null;
  }
  return _findBookInLibraryByTitle(
    category,
    title,
    preferTextBook: preferTextBook,
    visibility: visibility,
  );
}

/// האינדקס של הספרייה הנוכחית לפי בחירת ההסתרה הנוכחית. נבנה מחדש כשרענון
/// ספרייה יוצר מופע `Category` חדש (`DataRepository.library`) או כשההסתרה משתנה.
class FindRefBookIndexCache {
  LibraryBookIndex? _index;

  /// נבנה מחדש בטעינה הבאה, למשל כשההסתרה השתנתה.
  void clear() => _index = null;

  /// טוען את הספרייה; שגיאת טעינה עוברת לקורא.
  Future<LibraryBookIndex> load() async =>
      indexFor(await DataRepository.instance.library);

  /// כמו [load], ו-null כשהספרייה לא נטענה.
  Future<LibraryBookIndex?> tryLoad() async {
    Library library;
    try {
      library = await DataRepository.instance.library;
    } catch (e) {
      debugPrint('Error loading library: $e');
      return null;
    }
    return indexFor(library);
  }

  LibraryBookIndex indexFor(Library library) {
    final selection = const HiddenLibraryStore().load();
    final existing = _index;
    if (existing != null &&
        identical(existing.library, library) &&
        existing.visibility.selection == selection) {
      return existing;
    }
    return _index = LibraryBookIndex(
      library,
      visibility: FindRefVisibility(selection, library),
    );
  }

  /// האם מפרש שנבחר מתפריט עדיין גלוי לפי האינדקס האחרון.
  bool allowsCommentator(String title, int? bookId) =>
      _index?.visibility.allowsCommentator(title, bookId) ?? false;
}
