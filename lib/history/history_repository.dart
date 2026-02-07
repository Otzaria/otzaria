import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/repository/base_list_repository.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/ref_helper.dart';

class HistoryRepository extends BaseListRepository<Bookmark> {
  HistoryRepository()
      : super(
          boxName: 'history',
          key: 'history',
          fromJson: (json) => Bookmark.fromJson(json),
          toJson: (bookmark) => bookmark.toJson(),
        );

  Future<List<Bookmark>> loadHistory() async => load();

  Future<void> saveHistory(List<Bookmark> history) async => save(history);

  Future<void> clearHistory() async => clear();

  Future<void> addHistoryItem(Bookmark bookmark) async => addItem(bookmark);

  Future<void> removeHistoryItem(int index) async => removeAt(index);

  Future<void> addHistoryFromTab(OpenedTab tab) async {
    if (tab is PdfBookTab) {
      int index = tab.pdfViewerController.pageNumber ?? 1;
      addHistoryItem(Bookmark(
        ref: '${tab.title} עמוד $index',
        book: tab.book,
        index: index,
      ));
    }
    if (tab is TextBookTab) {
      final state = tab.bloc.state;
      if (state is TextBookLoaded) {
        final index = state.positionsListener.itemPositions.value.first.index;
        String ref = await refFromIndex(index, tab.book.tableOfContents);
        // הוספת שם הספר לכותרת
        ref = addBookTitleToRef(ref, tab.book.title);
        addHistoryItem(Bookmark(
          ref: ref,
          book: tab.book,
          index: index,
        ));
      }
    }
  }
}
