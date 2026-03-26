import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/core/ui_snack.dart';

// Cache של outlines — מפתח: title של הספר
final Map<String, List<PdfOutlineNode>> _outlineCache = {};

// Lock למניעת טעינות מקביליות
final Map<String, Future<List<PdfOutlineNode>>> _loadingOutlines = {};

typedef EntryTextGetter<T> = String Function(T entry);
typedef ChildrenGetter<T> = Future<List<T>> Function(T entry);

/// חיפוש רשומה בעץ outline/toc לפי טקסט
Future<T?> findEntryInTree<T>(
  Future<List<T>> rootEntries,
  String daf,
  EntryTextGetter<T> getText,
  ChildrenGetter<T> getChildren,
) async {
  final entries = await rootEntries;
  for (var entry in entries) {
    if (getText(entry).contains(daf)) return entry;
    final T? result =
        await findEntryInTree(getChildren(entry), daf, getText, getChildren);
    if (result != null) return result;
  }
  return null;
}

/// פותח את הדף היומי מהתלמוד הבבלי (או קטגוריה מותאמת)
void openDafYomiBook(
  BuildContext context,
  String tractate,
  String daf, {
  String categoryName = 'תלמוד בבלי',
}) async {
  _openDafYomiBookInCategory(context, tractate, daf, categoryName);
}

void _openDafYomiBookInCategory(
  BuildContext context,
  String tractate,
  String daf,
  String categoryName,
) async {
  final libraryBlocState = BlocProvider.of<LibraryBloc>(context).state;
  final library = libraryBlocState.library;
  if (library == null) return;

  Category? talmudCategory;
  for (var category in library.getAllCategories()) {
    if (category.title == categoryName) {
      talmudCategory = category;
      break;
    }
  }

  if (talmudCategory == null) {
    final allBooks = library.getAllBooks();
    Book? book;
    for (var bookInLibrary in allBooks) {
      if (bookInLibrary.title == tractate ||
          bookInLibrary.title.contains(tractate) ||
          tractate.contains(bookInLibrary.title)) {
        if (bookInLibrary.category?.title == categoryName) {
          book = bookInLibrary;
          break;
        }
      }
    }
    if (book == null) {
      UiSnack.showError('לא נמצאה קטגוריה: $categoryName');
      return;
    } else {
      await _openBook(context, book, daf);
      return;
    }
  }

  Book? book;
  Book? textBookFallback;
  final allBooksInCategory = talmudCategory.getAllBooks();

  for (var bookInCategory in allBooksInCategory) {
    if (bookInCategory.title == tractate ||
        bookInCategory.title.contains(tractate) ||
        tractate.contains(bookInCategory.title)) {
      if (bookInCategory is PdfBook) {
        book = bookInCategory;
        break;
      } else {
        textBookFallback ??= bookInCategory;
      }
    }
  }

  book ??= textBookFallback;

  if (book != null) {
    await _openBook(context, book, daf);
  } else {
    final availableBooks =
        allBooksInCategory.map((b) => b.title).take(5).join(', ');
    UiSnack.showError(
        'לא נמצא ספר: $tractate ב$categoryName\nספרים זמינים: $availableBooks...');
  }
}

Future<void> _openBook(BuildContext context, Book book, String daf) async {
  final index = await findReference(book, 'דף ${daf.trim()}') ?? 0;
  if (!context.mounted) return;
  openBook(context, book, index, '', ignoreHistory: true);
}

/// מוצא את האינדקס של הפניה בספר (PDF או טקסט)
Future<int?> findReference(Book book, String ref) async {
  if (book is TextBook) {
    final tocEntry = await _findDafInToc(book, ref);
    return tocEntry?.index;
  } else if (book is PdfBook) {
    final outline = await getDafYomiOutline(book, ref);
    final pageNum = outline?.dest?.pageNumber;
    return pageNum;
  }
  return null;
}

Future<TocEntry?> _findDafInToc(TextBook book, String daf) async {
  final toc = await book.tableOfContents;
  return await findEntryInTree(
    Future.value(toc),
    daf,
    (entry) => entry.text,
    (entry) => Future.value(entry.children),
  );
}

/// מוצא את ה-outline של הדף היומי ב-PDF (עם cache)
Future<PdfOutlineNode?> getDafYomiOutline(PdfBook book, String daf) async {
  List<PdfOutlineNode> outlines = const [];
  try {
    if (_outlineCache.containsKey(book.title)) {
      outlines = _outlineCache[book.title]!;
    } else if (_loadingOutlines.containsKey(book.title)) {
      outlines = await _loadingOutlines[book.title]!;
    } else {
      final loadFuture = _loadOutlineFromFile(book);
      _loadingOutlines[book.title] = loadFuture;
      try {
        outlines = await loadFuture;
        _outlineCache[book.title] = outlines;
      } finally {
        _loadingOutlines.remove(book.title);
      }
    }
  } catch (e, stackTrace) {
    debugPrint('❌ getDafYomiOutline error: $e\n$stackTrace');
    _loadingOutlines.remove(book.title);
    return null;
  }

  return findEntryInTree(
    Future.value(outlines),
    daf,
    (entry) => entry.title,
    (entry) => Future.value(entry.children),
  );
}

Future<List<PdfOutlineNode>> _loadOutlineFromFile(PdfBook book) async {
  final document = await PdfDocument.openFile(book.path);
  return document.loadOutline();
}

/// פותח ספר PDF לפי שם וסימן
Future<void> openPdfBookFromRef(
    String bookname, String ref, BuildContext context) async {
  await _openBookFromRefHelper(bookname, ref, context, PdfBook);
}

/// פותח ספר טקסט לפי שם וסימן
Future<void> openTextBookFromRef(
    String bookname, String ref, BuildContext context) async {
  await _openBookFromRefHelper(bookname, ref, context, TextBook);
}

Future<void> _openBookFromRefHelper(
  String bookname,
  String ref,
  BuildContext context,
  Type bookType,
) async {
  final libraryBlocState = BlocProvider.of<LibraryBloc>(context).state;
  final book = libraryBlocState.library?.findBookByTitle(bookname, bookType);

  if (book != null) {
    final index = await findReference(book, ref);
    if (!context.mounted) return;
    if (index != null) {
      openBook(context, book, index, '', ignoreHistory: true);
    } else {
      UiSnack.showError(UiSnack.sectionNotFound);
    }
  } else {
    UiSnack.showError(UiSnack.bookNotFound);
  }
}
