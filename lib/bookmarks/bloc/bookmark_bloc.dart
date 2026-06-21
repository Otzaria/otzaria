import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';

class BookmarkBloc extends Cubit<BookmarkState> {
  final BookmarkRepository _repository;

  BookmarkBloc(this._repository) : super(BookmarkState.initial()) {
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    try {
      final bookmarks = await _repository.loadBookmarks();
      if (!isClosed) {
        emit(state.copyWith(bookmarks: bookmarks));
      }
    } catch (e, stackTrace) {
      debugPrint('שגיאה בטעינת סימניות: $e\n$stackTrace');
    }
  }

  /// שמירה ברקע עם דיווח שגיאה למשתמש — בלי await כדי לא לחסום את ה-UI,
  /// אבל עם טיפול בכישלון כך שסימניה שלא נשמרה לדיסק לא תיעלם בשקט.
  void _persistBookmarks(List<Bookmark> bookmarks) {
    _repository.saveBookmarks(bookmarks).catchError((Object e) {
      debugPrint('שגיאה בשמירת סימניות: $e');
      UiSnack.showError('שגיאה בשמירת הסימניות');
    });
  }

  bool addBookmark(
      {required String ref,
      required Book book,
      required int index,
      List<String>? commentatorsToShow,
      BookmarkTargetKind targetKind = BookmarkTargetKind.book}) {
    final bookmark = Bookmark(
        ref: ref,
        book: book,
        index: index,
        commentatorsToShow: commentatorsToShow ?? [],
        targetKind: targetKind,
        createdAt: DateTime.now());
    // כפילות נמדדת לפי זיהוי הספר + המיקום (index), כדי לאפשר מספר סימניות
    // באותו ספר במיקומים שונים. ref לבדו לא מספיק - ב-PDF כל הסימניות באותו
    // פרק יקבלו ref זהה (כותרת הפרק), וב-TextBook מספר מיקומים באותו סעיף.
    // משתמשים בזהות חזקה לספר (id/path/category) ולא בכותרת בלבד, כדי
    // ששתי מהדורות שונות עם אותה כותרת לא ייחשבו לאותו ספר.
    final newIdentity = bookIdentity(bookmark.book);
    if (state.bookmarks.any((b) =>
        b.index == bookmark.index &&
        bookIdentity(b.book) == newIdentity &&
        b.targetKind == bookmark.targetKind)) {
      return false;
    }

    final newBookmarks = [...state.bookmarks, bookmark];
    _persistBookmarks(newBookmarks);
    emit(state.copyWith(bookmarks: newBookmarks));
    return true;
  }

  void removeBookmark(int index) {
    final newBookmarks = [...state.bookmarks]..removeAt(index);
    _persistBookmarks(newBookmarks);
    emit(state.copyWith(bookmarks: newBookmarks));
  }

  void clearBookmarks() {
    _repository.clearBookmarks().catchError((Object e) {
      debugPrint('שגיאה במחיקת סימניות: $e');
      UiSnack.showError('שגיאה במחיקת הסימניות');
    });
    emit(state.copyWith(bookmarks: []));
  }

  /// מוחק את כל הסימניות של ספר ספציפי (לפי זהות חזקה - id/path/category),
  /// משאיר סימניות של ספרים אחרים על כנן.
  ///
  /// מחזיר true אם נמחקה לפחות סימניה אחת, false אם לא היו סימניות תואמות.
  /// מאפשר ל-UI להימנע מהודעת הצלחה מטעה כשלא בוצעה מחיקה בפועל.
  bool clearBookmarksForBook(Book book) {
    final targetIdentity = bookIdentity(book);
    final remaining = state.bookmarks
        .where((b) => bookIdentity(b.book) != targetIdentity)
        .toList();
    if (remaining.length == state.bookmarks.length) return false;
    _persistBookmarks(remaining);
    emit(state.copyWith(bookmarks: remaining));
    return true;
  }
}
