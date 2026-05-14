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

  factory OpenedTab.from(OpenedTab tab) {
    if (tab is TextBookTab) {
      bool? splitedView;
      bool? showPageShapeView;
      // ערכי ברירת מחדל לוקחים את ה‑pinpoint שאיתו נבנה הטאב המקורי. אם
      // ה‑bloc כבר נטען, נעדיף את הערכים המעודכנים מה‑state — כדי לתפוס שינויים
      // (למשל ניקוי ה‑pinpoint עם חיפוש ידני חדש).
      String? pinpointText = tab.pinpointHighlight;
      int? pinpointSectionIndex = tab.pinpointHighlightSectionIndex;
      final state = tab.bloc.state;
      if (state is TextBookLoaded) {
        splitedView = state.showSplitView;
        showPageShapeView = state.showPageShapeView;
        pinpointText = state.pinpointHighlightText;
        pinpointSectionIndex = state.pinpointHighlightIndex;
      }
      return TextBookTab(
        index: tab.index,
        book: tab.book,
        searchText: tab.searchText,
        commentators: tab.commentators,
        openLeftPane: state is TextBookLoaded ? state.showLeftPane : false,
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
    return tab;
  }

  factory OpenedTab.fromBook(Book book, int index,
      {String searchText = '',
      List<String>? commentators,
      bool openLeftPane = false,
      bool isPinned = false,
      bool? showPageShapeView,
      bool requiresStableLayout = false,
      String? pinpointHighlight,
      int? pinpointHighlightSectionIndex}) {
    if (book is PdfBook) {
      return PdfBookTab(
        book: book,
        pageNumber: index,
        openLeftPane: openLeftPane,
        searchText: searchText,
        isPinned: isPinned,
        requiresStableLayout: requiresStableLayout,
      );
    } else if (book is DocxBook) {
      // DOCX is rendered through the text book flow (converted to HTML-ish text).
      // We wrap it as a TextBook so existing TextBookBloc/Repository can load it.
      final textBook = TextBook(
        title: book.title,
        category: book.category,
        author: book.author,
        heCategories: book.heCategories,
        heEra: book.heEra,
        compDateStringHe: book.compDateStringHe,
        compPlaceStringHe: book.compPlaceStringHe,
        pubDateStringHe: book.pubDateStringHe,
        pubPlaceStringHe: book.pubPlaceStringHe,
        heShortDesc: book.heShortDesc,
        heDesc: book.heDesc,
        pubDate: book.pubDate,
        pubPlace: book.pubPlace,
        order: book.order,
        topics: book.topics,
        // Prefer filePath if present; otherwise fall back to the actual file path.
        filePath: book.filePath ?? book.path,
        fileType: book.fileType ?? 'docx',
        categoryPath: book.categoryPath,
        extraTitles: book.extraTitles,
        isUserBook: book.isUserBook,
      );
      return TextBookTab(
        book: textBook,
        index: index,
        searchText: searchText,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
      );
    } else if (book is TextBook) {
      return TextBookTab(
        book: book,
        index: index,
        searchText: searchText,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
      );
    }
    throw UnsupportedError("Unsupported book type: ${book.runtimeType}");
  }

  factory OpenedTab.fromJson(Map<String, dynamic> json) {
    String type = json['type'];
    if (type == 'TextBookTab') {
      return TextBookTab.fromJson(json);
    } else if (type == 'PdfBookTab') {
      return PdfBookTab.fromJson(json);
    } else if (type == 'CombinedTab') {
      return CombinedTab.fromJson(json);
    }
    return SearchingTab.fromJson(json);
  }
  Map<String, dynamic> toJson();
}
