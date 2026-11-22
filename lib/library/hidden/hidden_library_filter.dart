import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';

/// מחזיר עותק של [library] בלי הספרים והקטגוריות שב-[hidden]. [Library.offTreeBooks]
/// עוברים כמות שהם: העותק מגיע גם לאינדוקס, ו-booksForIndexing מוציא את המוסתרים.
///
/// העותק נבנה מחדש ואינו חולק אובייקטי קטגוריה עם המקור: העץ המקורי משותף
/// עם גשר התוספים ועם קוד התחזוקה, וההסתרה היא של הממשק בלבד (issue #1448).
/// הספרים עצמם אינם משוכפלים — הם חסרי מצב מבחינת העץ, ושכפולם היה מנתק
/// השוואות זהות שמסכים אחרים נשענים עליהן.
Library filterHiddenFromLibrary(
  Library library,
  HiddenLibrarySelection hidden,
) {
  if (hidden.isEmpty) return library;

  final filtered = Library(
    categories: library.subCategories
        .map((category) => _filterCategory(category, hidden))
        .whereType<Category>()
        .toList(),
  );
  for (final category in filtered.subCategories) {
    category.parent = filtered;
  }
  filtered.offTreeBooks = library.offTreeBooks;
  return filtered;
}

/// `null` = הקטגוריה עצמה מוסתרת ויורדת מהעץ עם כל מה שתחתיה.
///
/// קטגוריה שהתרוקנה מהסתרת כל ספריה נשארת: הסתרת ספר אינה אמורה להעלים
/// מדף שלם, והמשתמש יסתיר את הקטגוריה במפורש אם זה מה שהוא רוצה.
Category? _filterCategory(Category category, HiddenLibrarySelection hidden) {
  if (hidden.isCategoryHidden(category)) return null;

  final copy = Category(
    title: category.title,
    description: category.description,
    shortDescription: category.shortDescription,
    order: category.order,
    subCategories: [],
    books: category.books.where((book) => !hidden.isBookHidden(book)).toList(),
    parent: category.parent,
  );

  for (final sub in category.subCategories) {
    final filteredSub = _filterCategory(sub, hidden);
    if (filteredSub == null) continue;
    filteredSub.parent = copy;
    copy.subCategories.add(filteredSub);
  }

  return copy;
}
