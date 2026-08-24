import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
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

  /// שומר ומדווח שגיאה למשתמש. מחזיר האם השמירה לדיסק הצליחה, כדי שקורא
  /// שצריך תשובה אמיתית (הגשר לתוספים) יוכל להמתין; מסלול ה-UI לא ממתין.
  Future<bool> _persistBookmarks(List<Bookmark> bookmarks) async {
    try {
      await _repository.saveBookmarks(bookmarks);
      return true;
    } catch (e) {
      debugPrint('שגיאה בשמירת סימניות: $e');
      UiSnack.showError(NotesMessages.bookmarkSaveError);
      return false;
    }
  }

  /// מוסיף סימניה וממתין לשמירה לדיסק. מחזיר true רק אם הסימניה גם נוספה
  /// וגם נשמרה — לשימוש הגשר, שאסור לו לדווח הצלחה על כתיבה שנכשלה.
  Future<bool> addBookmarkAndSave({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) async {
    final save = _addBookmark(
      ref: ref,
      book: book,
      index: index,
      commentatorsToShow: commentatorsToShow,
      targetKind: targetKind,
      label: label,
    );
    if (save == null) return false;
    return save;
  }

  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) {
    final save = _addBookmark(
      ref: ref,
      book: book,
      index: index,
      commentatorsToShow: commentatorsToShow,
      targetKind: targetKind,
      label: label,
    );
    if (save == null) return false;
    unawaited(save);
    return true;
  }

  /// מחזיר את Future השמירה, או null אם הסימניה לא נוספה (כפילות).
  Future<bool>? _addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) {
    final bookmark = Bookmark(
      ref: ref,
      book: book,
      index: index,
      commentatorsToShow: commentatorsToShow ?? [],
      targetKind: targetKind,
      label: label,
      createdAt: DateTime.now(),
    );
    // כפילות נמדדת לפי זיהוי הספר + המיקום (index), כדי לאפשר מספר סימניות
    // באותו ספר במיקומים שונים. ref לבדו לא מספיק - ב-PDF כל הסימניות באותו
    // פרק יקבלו ref זהה (כותרת הפרק), וב-TextBook מספר מיקומים באותו סעיף.
    // משתמשים בזהות חזקה לספר (id/path/category) ולא בכותרת בלבד, כדי
    // ששתי מהדורות שונות עם אותה כותרת לא ייחשבו לאותו ספר.
    final newIdentity = bookIdentity(bookmark.book);
    if (state.bookmarks.any(
      (b) =>
          b.index == bookmark.index &&
          bookIdentity(b.book) == newIdentity &&
          b.targetKind == bookmark.targetKind,
    )) {
      return null;
    }

    final newBookmarks = [...state.bookmarks, bookmark];
    final save = _persistBookmarks(newBookmarks);
    emit(state.copyWith(bookmarks: newBookmarks));
    return save;
  }

  /// מעדכן את טקסט התיאור המוצג של סימניה. [label] ריק מאפס לברירת המחדל
  /// (הצגת המיקום).
  void updateBookmarkLabel(int index, String? label) {
    if (index < 0 || index >= state.bookmarks.length) return;
    final trimmed = label?.trim();
    final hasLabel = trimmed != null && trimmed.isNotEmpty;
    final updated = [...state.bookmarks];
    updated[index] = updated[index].copyWith(
      label: hasLabel ? trimmed : null,
      clearLabel: !hasLabel,
    );
    unawaited(_persistBookmarks(updated));
    emit(state.copyWith(bookmarks: updated));
  }

  /// מחזיר false אם [index] מחוץ לתחום ולכן לא נמחקה סימניה.
  bool removeBookmark(int index) {
    final save = _removeBookmark(index);
    if (save == null) return false;
    unawaited(save);
    return true;
  }

  /// מסיר סימניה וממתין לשמירה לדיסק — המסלול של הגשר לתוספים.
  Future<bool> removeBookmarkAndSave(int index) async {
    final save = _removeBookmark(index);
    if (save == null) return false;
    return save;
  }

  Future<bool>? _removeBookmark(int index) {
    if (index < 0 || index >= state.bookmarks.length) return null;
    final newBookmarks = [...state.bookmarks]..removeAt(index);
    final save = _persistBookmarks(newBookmarks);
    emit(state.copyWith(bookmarks: newBookmarks));
    return save;
  }

  void clearBookmarks() {
    _repository.clearBookmarks().catchError((Object e) {
      debugPrint('שגיאה במחיקת סימניות: $e');
      UiSnack.showError(NotesMessages.bookmarkClearError);
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
    unawaited(_persistBookmarks(remaining));
    emit(state.copyWith(bookmarks: remaining));
    return true;
  }
}
