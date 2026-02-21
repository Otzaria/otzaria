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
  OpenedTab(this.title, {this.isPinned = false});

  /// Called when the tab is being disposed.
  /// Override this method to perform cleanup.
  void dispose() {}

  factory OpenedTab.from(OpenedTab tab) {
    if (tab is TextBookTab) {
      bool? splitedView;
      bool? showPageShapeView;
      final state = tab.bloc.state;
      if (state is TextBookLoaded) {
        splitedView = state.showSplitView;
        showPageShapeView = state.showPageShapeView;
      }
      return TextBookTab(
        index: tab.index,
        book: tab.book,
        searchText: tab.searchText,
        commentators: tab.commentators,
        splitedView: splitedView,
        showPageShapeView: showPageShapeView,
        isPinned: tab.isPinned,
      );
    } else if (tab is PdfBookTab) {
      return PdfBookTab(
        book: tab.book,
        pageNumber: tab.pageNumber,
        isPinned: tab.isPinned,
      );
    } else if (tab is CombinedTab) {
      return CombinedTab(
        rightTab: OpenedTab.from(tab.rightTab),
        leftTab: OpenedTab.from(tab.leftTab),
        splitRatio: tab.splitRatio,
        isPinned: tab.isPinned,
      );
    }
    return tab;
  }

  factory OpenedTab.fromBook(Book book, int index,
      {String searchText = '',
      List<String>? commentators,
      bool openLeftPane = false,
      bool isPinned = false}) {
    if (book is PdfBook) {
      return PdfBookTab(
        book: book,
        pageNumber: index,
        openLeftPane: openLeftPane,
        searchText: searchText,
        isPinned: isPinned,
      );
    } else if (book is TextBook) {
      return TextBookTab(
        book: book,
        index: index,
        searchText: searchText,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
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
