import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/models/books.dart';

/// כל שינוי עובר דרך `mutate*` על הרשימה הטרייה, כדי לשמר כתיבות מחלונות אחרים.
class BookmarkBloc extends Cubit<BookmarkState> {
  final BookmarkRepository _repository;
  StreamSubscription<void>? _bookmarksChanged;
  StreamSubscription<void>? _groupsChanged;

  // פענוח ברקע עלול להשלים אחרי כתיבה או טעינה חדשה יותר.
  int _bookmarksGeneration = 0;
  int _groupsGeneration = 0;

  BookmarkBloc(this._repository) : super(BookmarkState.initial()) {
    _loadBookmarks();
    // חלון אחר כתב — העותק שבזיכרון התיישן.
    _bookmarksChanged = _repository.remoteChanges.listen(
      (_) => unawaited(_reloadBookmarks()),
    );
    _groupsChanged = _repository.groupsRemoteChanges.listen(
      (_) => unawaited(_reloadGroups()),
    );
  }

  @override
  Future<void> close() {
    _bookmarksChanged?.cancel();
    _groupsChanged?.cancel();
    return super.close();
  }

  Future<void> _loadBookmarks() async {
    await _reloadBookmarks();
    if (!isClosed) await _reloadGroups();
  }

  Future<void> _reloadBookmarks() async {
    final generation = ++_bookmarksGeneration;
    try {
      final bookmarks = await _repository.loadBookmarks();
      if (!isClosed && generation == _bookmarksGeneration) {
        emit(state.copyWith(bookmarks: bookmarks));
      }
    } catch (e, stackTrace) {
      debugPrint('שגיאה בטעינת סימניות: $e\n$stackTrace');
    }
  }

  Future<void> _reloadGroups() async {
    final generation = ++_groupsGeneration;
    try {
      final groups = await _repository.loadGroups();
      if (!isClosed && generation == _groupsGeneration) {
        emit(state.copyWith(groups: groups));
      }
    } catch (e, stackTrace) {
      debugPrint('שגיאה בטעינת סימניות מרוכזות: $e\n$stackTrace');
    }
  }

  /// מציג מיד את [optimistic] ומחיל את [apply] על הרשימה הטרייה.
  /// בכשל חוזר למה שבאמת שמור, כדי לא להציג סימנייה שלא נשמרה.
  Future<bool> _applyBookmarks(
    List<Bookmark> Function(List<Bookmark> current) apply, {
    required List<Bookmark> optimistic,
  }) async {
    _bookmarksGeneration++;
    emit(state.copyWith(bookmarks: optimistic));
    try {
      final saved = await _repository.mutateBookmarks(apply);
      _bookmarksGeneration++;
      if (!isClosed) emit(state.copyWith(bookmarks: saved));
      return true;
    } catch (e) {
      debugPrint('שגיאה בשמירת סימניות: $e');
      UiSnack.showError(NotesMessages.bookmarkSaveError);
      await _reloadBookmarks();
      return false;
    }
  }

  Future<bool> _applyGroups(
    List<BookmarkGroup> Function(List<BookmarkGroup> current) apply, {
    required List<BookmarkGroup> optimistic,
  }) async {
    _groupsGeneration++;
    emit(state.copyWith(groups: optimistic));
    try {
      final saved = await _repository.mutateGroups(apply);
      _groupsGeneration++;
      if (!isClosed) emit(state.copyWith(groups: saved));
      return true;
    } catch (e) {
      debugPrint('שגיאה בשמירת סימניות מרוכזות: $e');
      UiSnack.showError(NotesMessages.bookmarkSaveError);
      await _reloadGroups();
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
    //
    // ⚠️ נבדק פעמיים: כאן מול ה-state כדי להחזיר תשובה סינכרונית לקורא,
    // ושוב בתוך `apply` מול הרשימה הטרייה — כי חלון אחר יכול היה להוסיף
    // בדיוק את אותה סימנייה מאז שנטענה.
    final identity = bookmark.bookmarkIdentity;
    if (state.bookmarks.any((b) => b.bookmarkIdentity == identity)) {
      return null;
    }

    return _applyBookmarks(
      (current) => current.any((b) => b.bookmarkIdentity == identity)
          ? current
          : [...current, bookmark],
      optimistic: [...state.bookmarks, bookmark],
    );
  }

  /// מעדכן את טקסט התיאור המוצג של סימניה. [label] ריק מאפס לברירת המחדל
  /// (הצגת המיקום).
  void updateBookmarkLabel(int index, String? label) {
    if (index < 0 || index >= state.bookmarks.length) return;
    final trimmed = label?.trim();
    final hasLabel = trimmed != null && trimmed.isNotEmpty;
    final identity = state.bookmarks[index].bookmarkIdentity;

    List<Bookmark> relabel(List<Bookmark> current) => [
      for (final b in current)
        if (b.bookmarkIdentity == identity)
          b.copyWith(label: hasLabel ? trimmed : null, clearLabel: !hasLabel)
        else
          b,
    ];

    unawaited(
      _applyBookmarks(relabel, optimistic: relabel(state.bookmarks)),
    );
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
    // ⚠️ האינדקס מתורגם לזהות **כאן**, מול ה-state שממנו ה-UI חישב אותו.
    // מחיקה לפי אינדקס אצל הבעלים הייתה מוחקת סימנייה אחרת אם חלון אחר
    // הוסיף בינתיים.
    final identity = state.bookmarks[index].bookmarkIdentity;
    return _applyBookmarks(
      (current) =>
          current.where((b) => b.bookmarkIdentity != identity).toList(),
      optimistic: [...state.bookmarks]..removeAt(index),
    );
  }

  void clearBookmarks() {
    _bookmarksGeneration++;
    // דריסה מכוונת: "מחק את כל הסימניות" פירושו הכול.
    _repository
        .clearBookmarks()
        .then((_) {
          _bookmarksGeneration++;
          if (!isClosed) emit(state.copyWith(bookmarks: []));
        })
        .catchError((Object e) {
          debugPrint('שגיאה במחיקת סימניות: $e');
          UiSnack.showError(NotesMessages.bookmarkClearError);
        });
    emit(state.copyWith(bookmarks: []));
  }

  /// סף החפיפה לזיהוי "אותה קבוצה" בשמירה חוזרת — רוב הספרים משותפים
  /// (החיתוך ביחס לקבוצה הגדולה מבין השתיים).
  static const double _groupOverlapThreshold = 0.6;

  /// מחזיר את הקבוצה הקיימת הדומה ביותר לקבוצת ספרים בעלת הזהויות
  /// [identities], או null אם אף קבוצה אינה חופפת ברוב ספריה.
  BookmarkGroup? findSimilarGroup(Set<String> identities) {
    BookmarkGroup? best;
    var bestOverlap = 0.0;
    for (final group in state.groups) {
      final overlap = group.overlapWith(identities);
      if (overlap >= _groupOverlapThreshold && overlap > bestOverlap) {
        best = group;
        bestOverlap = overlap;
      }
    }
    return best;
  }

  void addGroup(BookmarkGroup group) {
    unawaited(
      _applyGroups(
        (current) => current.any((g) => g.id == group.id)
            ? current
            : [...current, group],
        optimistic: [...state.groups, group],
      ),
    );
  }

  /// מחליף קבוצה קיימת בתוכן חדש תוך שמירת המזהה שלה.
  /// מחזיר false אם [id] לא נמצא.
  bool replaceGroup(String id, BookmarkGroup replacement) {
    if (!state.groups.any((g) => g.id == id)) return false;

    List<BookmarkGroup> replaced(List<BookmarkGroup> current) => [
      for (final g in current)
        if (g.id == id)
          g.copyWith(name: replacement.name, items: replacement.items)
        else
          g,
    ];

    unawaited(_applyGroups(replaced, optimistic: replaced(state.groups)));
    return true;
  }

  bool removeGroup(String id) {
    if (!state.groups.any((g) => g.id == id)) return false;
    unawaited(
      _applyGroups(
        (current) => current.where((g) => g.id != id).toList(),
        optimistic: state.groups.where((g) => g.id != id).toList(),
      ),
    );
    return true;
  }

  void renameGroup(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (!state.groups.any((g) => g.id == id)) return;

    List<BookmarkGroup> renamed(List<BookmarkGroup> current) => [
      for (final g in current)
        if (g.id == id) g.copyWith(name: trimmed) else g,
    ];

    unawaited(_applyGroups(renamed, optimistic: renamed(state.groups)));
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
    unawaited(
      _applyBookmarks(
        (current) => current
            .where((b) => bookIdentity(b.book) != targetIdentity)
            .toList(),
        optimistic: remaining,
      ),
    );
    return true;
  }
}
