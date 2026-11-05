import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

/// הספרים והקטגוריות שהמשתמש הסתיר מהממשק (issue #1448).
///
/// ההסתרה אינה משנה את מסד הספרים ואת העץ שב-`DataRepository`;
/// ספר מוסתר מוסר גם מאינדקס החיפוש.
@immutable
class HiddenLibrarySelection {
  /// מפתחות ספרים, בפורמט של [PerBookSettings.bookKey]. אותו מפתח שכבר משמש
  /// להגדרות פר-ספר, ולכן הוא יציב מול שינוי מזהי המסד בעדכון ספרייה.
  final Set<String> bookKeys;

  /// נתיבי קטגוריות, בפורמט של [Category.path] (למשל `/תנ"ך/תורה`).
  final Set<String> categoryPaths;

  const HiddenLibrarySelection({
    this.bookKeys = const {},
    this.categoryPaths = const {},
  });

  bool get isEmpty => bookKeys.isEmpty && categoryPaths.isEmpty;

  bool isBookHidden(Book book) =>
      bookKeys.contains(PerBookSettings.bookKey(book));

  /// בודק גם קטגוריות אב בלי להסתמך על categoryPath, שעשוי להיות חסר.
  bool excludesFromIndex(
    Book book, {
    Set<Book> categoryHiddenBooks = const {},
  }) {
    if (isBookHidden(book) || categoryHiddenBooks.contains(book)) return true;
    if (categoryPaths.isEmpty) return false;
    var category = book.category;
    while (category != null) {
      if (isCategoryHidden(category)) return true;
      final parent = category.parent;
      category = identical(parent, category) ? null : parent;
    }
    return false;
  }

  /// העץ הוא מקור האמת לשיוך קטגוריה גם כש-Book.category חסר.
  Set<Book> booksHiddenByCategory(Library library) {
    if (categoryPaths.isEmpty) return const <Book>{};
    final hiddenBooks = <Book>{};
    void visit(Category category, bool ancestorHidden) {
      final hidden = ancestorHidden || isCategoryHidden(category);
      if (hidden) hiddenBooks.addAll(category.books);
      for (final child in category.subCategories) {
        visit(child, hidden);
      }
    }

    visit(library, false);
    return hiddenBooks;
  }

  bool isCategoryHidden(Category category) =>
      categoryPaths.contains(category.path);

  HiddenLibrarySelection copyWith({
    Set<String>? bookKeys,
    Set<String>? categoryPaths,
  }) => HiddenLibrarySelection(
    bookKeys: bookKeys ?? this.bookKeys,
    categoryPaths: categoryPaths ?? this.categoryPaths,
  );

  @override
  bool operator ==(Object other) =>
      other is HiddenLibrarySelection &&
      setEquals(other.bookKeys, bookKeys) &&
      setEquals(other.categoryPaths, categoryPaths);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(bookKeys),
    Object.hashAllUnordered(categoryPaths),
  );
}

HiddenLibrarySelection applyHiddenSelectionChange(
  HiddenLibrarySelection current,
  HiddenLibrarySelection base,
  HiddenLibrarySelection requested,
) => HiddenLibrarySelection(
  bookKeys: {
    ...current.bookKeys,
    ...requested.bookKeys.difference(base.bookKeys),
  }..removeAll(base.bookKeys.difference(requested.bookKeys)),
  categoryPaths: {
    ...current.categoryPaths,
    ...requested.categoryPaths.difference(base.categoryPaths),
  }..removeAll(base.categoryPaths.difference(requested.categoryPaths)),
);

/// מסדר כתיבות הסתרה באותו isolate כך ששתי בחירות לא ידרסו זו את זו.
class HiddenLibraryUpdateQueue {
  HiddenLibraryUpdateQueue();

  static final instance = HiddenLibraryUpdateQueue();
  final Queue<Future<void> Function()> _pending = Queue();
  bool _running = false;

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pending.add(() async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _runNext();
      }
    });
    if (!_running) _runNext();
    return completer.future;
  }

  void _runNext() {
    if (_pending.isEmpty) {
      _running = false;
      return;
    }
    _running = true;
    unawaited(_pending.removeFirst()());
  }
}

({List<Book> newlyHidden, List<Book> newlyVisible}) hiddenIndexDelta(
  Library library,
  HiddenLibrarySelection before,
  HiddenLibrarySelection after,
) {
  final beforeCategories = before.booksHiddenByCategory(library);
  final afterCategories = after.booksHiddenByCategory(library);
  final newlyHidden = <Book>[];
  final newlyVisible = <Book>[];
  for (final book in library.getIndexableBooks()) {
    final wasHidden = before.excludesFromIndex(
      book,
      categoryHiddenBooks: beforeCategories,
    );
    final isHidden = after.excludesFromIndex(
      book,
      categoryHiddenBooks: afterCategories,
    );
    if (!wasHidden && isHidden) newlyHidden.add(book);
    if (wasHidden && !isHidden) newlyVisible.add(book);
  }
  return (newlyHidden: newlyHidden, newlyVisible: newlyVisible);
}
