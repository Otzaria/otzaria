/* this is a representation of the tabs that could be open in the app.
a tab is either a pdf book or a text book, or a full text search window*/

import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

abstract class OpenedTab {
  String title;
  bool isPinned;
  final String? dedupeKey;
  OpenedTab(this.title, {this.isPinned = false, this.dedupeKey});

  /// Called when the tab is being disposed.
  /// Override this method to perform cleanup.
  void dispose() {}

  /// Returns a fresh independent copy of this tab.
  /// Subclasses that manage their own state (e.g. BLoC, controllers) must
  /// override this so that [OpenedTab.from] produces a real clone and not
  /// a shared-object alias.
  OpenedTab clone() => this;

  factory OpenedTab.from(OpenedTab tab) {
    if (tab is TextBookTab) {
      bool? splitedView;
      bool? showPageShapeView;
      List<String>? commentators = tab.commentators;
      // ערכי ברירת מחדל לוקחים את ה‑pinpoint שאיתו נבנה הטאב המקורי. אם
      // ה‑bloc כבר נטען, נעדיף את הערכים המעודכנים מה‑state — כדי לתפוס שינויים
      // (למשל ניקוי ה‑pinpoint עם חיפוש ידני חדש).
      String? pinpointText = tab.pinpointHighlight;
      int? pinpointSectionIndex = tab.pinpointHighlightSectionIndex;
      final state = tab.bloc.state;
      if (state is TextBookLoaded) {
        splitedView = state.showSplitView;
        showPageShapeView = state.showPageShapeView;
        commentators = state.activeCommentators;
        pinpointText = state.pinpointHighlightText;
        pinpointSectionIndex = state.pinpointHighlightIndex;
      } else if (state is TextBookInitial) {
        // טאב ששמור בשולחן עבודה לא-פעיל מעולם לא נטען — בלי הענף הזה
        // צורת הדף והתצוגה המפוצלת מתאפסות בכל החלפת שולחן עבודה.
        splitedView = state.splitedView;
        showPageShapeView = state.showPageShapeView;
      }
      return TextBookTab(
        index: tab.index,
        book: tab.book,
        searchText: tab.searchText,
        commentators: commentators,
        openLeftPane: state.showLeftPane,
        splitedView: splitedView,
        showPageShapeView: showPageShapeView,
        isPinned: tab.isPinned,
        dedupeKey: tab.dedupeKey,
        pinpointHighlight: pinpointText,
        pinpointHighlightSectionIndex: pinpointSectionIndex,
      );
    } else if (tab is PdfBookTab) {
      return PdfBookTab(
        book: tab.book,
        pageNumber: tab.pageNumber,
        openLeftPane: tab.showLeftPane.value,
        isPinned: tab.isPinned,
        dedupeKey: tab.dedupeKey,
        requiresStableLayout: tab.requiresStableLayout,
      );
    } else if (tab is CombinedTab) {
      return CombinedTab(
        rightTab: OpenedTab.from(tab.rightTab),
        leftTab: OpenedTab.from(tab.leftTab),
        splitRatio: tab.splitRatio,
        isPinned: tab.isPinned,
      );
    } else if (tab is SearchingTab) {
      return SearchingTab.clone(tab);
    }
    return tab.clone();
  }

  factory OpenedTab.fromBook(
    Book book,
    int index, {
    String searchText = '',
    String highlightText = '',
    int? permanentHighlightLine,
    List<String>? commentators,
    bool openLeftPane = false,
    bool isPinned = false,
    bool? showPageShapeView,
    bool requiresStableLayout = false,
    String? pinpointHighlight,
    int? pinpointHighlightSectionIndex,
    String? dedupeKey,
  }) {
    if (book is PdfBook) {
      return PdfBookTab(
        book: book,
        pageNumber: index,
        openLeftPane: openLeftPane,
        searchText: searchText,
        isPinned: isPinned,
        requiresStableLayout: requiresStableLayout,
        dedupeKey: dedupeKey,
      );
    } else if (book is DocxBook || book is EpubBook) {
      // DOCX/EPUB רצים דרך זרימת TextBook — העטיפה דרך toTextBook
      // משמרת id/categoryId/externalLibraryId שדרושים ל-LibraryProviderManager.
      return TextBookTab(
        book: book is DocxBook
            ? book.toTextBook()
            : (book as EpubBook).toTextBook(),
        index: index,
        searchText: searchText,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
        dedupeKey: dedupeKey,
      );
    } else if (book is TextBook) {
      return TextBookTab(
        book: book,
        index: index,
        searchText: searchText,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
        dedupeKey: dedupeKey,
      );
    }
    throw UnsupportedError("Unsupported book type: ${book.runtimeType}");
  }

  /// טיפוס לא מוכר זורק ולא נופל בשקט ל-[SearchingTab]: נפילה כזו יצרה טאב
  /// רפאים בשם הכלי/הספר בכל ירידת גרסה, וההצפה נשמרה חזרה לדיסק. הקוראים
  /// (`TabsRepository.loadTabs`, `Workspace.decodeTab`) מדלגים על טאב שנכשל.
  factory OpenedTab.fromJson(Map<String, dynamic> json) {
    String type = json['type'];
    if (type == 'TextBookTab') {
      return TextBookTab.fromJson(json);
    } else if (type == 'PdfBookTab') {
      return PdfBookTab.fromJson(json);
    } else if (type == 'CombinedTab') {
      return decodeCombinedTab(json);
    } else if (type == 'SearchingTabWindow' || type == 'SearchingTab') {
      return SearchingTab.fromJson(json);
    }
    throw FormatException('Unknown tab type: $type');
  }
  Map<String, dynamic> toJson();
}
